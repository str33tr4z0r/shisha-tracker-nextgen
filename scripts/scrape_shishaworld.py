# scrape_shishaworld_200g.py
# Ziel-Format je Zeile (JSONL):
# {"name":"Love 66","flavor":"Maracuja,Honigmelone,Wassermelone","manufacturer":{"name":"Adalya"}}

import argparse, json, re, time
from urllib.parse import urljoin, urlparse
import requests
try:
    from bs4 import BeautifulSoup
except Exception:
    # Friendly error when user runs system python without venv.
    print("Missing dependency: 'bs4' (BeautifulSoup).")
    print("Create and use the project's virtualenv before running the script:")
    print("  python3 -m venv .venv_scraper")
    print("  .venv_scraper/bin/pip install -r scripts/requirements.txt")
    print("  .venv_scraper/bin/python scripts/scrape_shishaworld.py --start 1 --end 8 --out tabak_200g.jsonl")
    raise

BASE = "https://www.smoke2u.de"
CATEGORY = f"{BASE}/shisha-tabak/200g"
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36"}

def get_soup(url: str) -> BeautifulSoup:
    for attempt in range(3):
        r = requests.get(url, headers=UA, timeout=25)
        if r.status_code == 200:
            return BeautifulSoup(r.text, "html.parser")
        if r.status_code in (429, 503):
            time.sleep(1.5 * (attempt + 1)); continue
        r.raise_for_status()
    raise RuntimeError(f"Request failed: {url}")

def norm(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "")).strip()
 
def normalize_link(url: str) -> str:
    """Normalize product URLs for deduplication: strip query/fragments and trailing slash."""
    p = urlparse(url)
    clean = p._replace(query="", fragment="").geturl()
    return clean.rstrip("/")
 
def list_page_urls(start=1, end=30):
    """
    Yield category page URLs starting at `start` and following site's "next" links
    when available. This is more robust than only generating suffix URLs and
    tolerates small layout changes.

    Behavior:
    - If start <= 1: begin at CATEGORY (page 1).
    - If start > 1: begin at CATEGORY_s{start}.
    - Follow discovered "next" links up to `end` pages or until no next link is found.
    """
    start = int(start)
    end = int(end)

    if start <= 1:
        current = CATEGORY
        yield current
        page = 1
    else:
        current = f"{CATEGORY}_s{start}"
        yield current
        page = start

    seen = {normalize_link(current)}

    while page < end:
        try:
            soup = get_soup(current)
        except Exception:
            # stop following if the list page fails
            break

        # try common "next" selectors first
        next_el = soup.select_one(
            'a[rel="next"], a.next, .pagination a.next, .pager a.next, li.next a, a[aria-label="Next"], a[title*="Weiter" i]'
        )
 
        # fallback: find anchors whose visible text suggests "next"/"weiter"/»/›
        if not next_el:
            for a in soup.select("a[href]"):
                tx = norm(a.get_text()).lower()
                if re.search(r"\b(next|weiter|mehr)\b", tx, flags=re.I) or re.search(r"[»›]+", tx):
                    next_el = a
                    break
 
        # If we found a next element, use it. Otherwise, attempt a suffix-based guess
        # (e.g. /shisha-tabak/200g_s2) which matches this site's known pagination pattern.
        if next_el:
            href = next_el.get("href")
            if not href:
                break
            next_url = urljoin(current, href)
            next_norm = normalize_link(next_url)
            if next_norm in seen:
                break
        else:
            # try constructing the next suffix page if within requested range
            if page + 1 > end:
                break
            candidate = f"{CATEGORY}_s{page+1}"
            candidate_norm = normalize_link(candidate)
            if candidate_norm in seen:
                break
            next_url = candidate
            next_norm = candidate_norm
 
        seen.add(next_norm)
        yield next_url
 
        # advance
        current = next_url
        page += 1
 
def collect_product_links(list_url: str):
    soup = get_soup(list_url)
    links = set()
 
    # Prefer links inside the main product list container to avoid promos/landing pages.
    container = soup.select_one("#product-list, .product-list, .row.product-list, .layout-gallery")
    search_root = container or soup
 
    # Common selectors for product links inside the product list
    sels = [
        "a.product--title", "a.product--image", "a.product--info",
        ".product--box a[href]", ".product a[href]", "a[href]"
    ]
    for sel in sels:
        for a in search_root.select(sel):
            href = a.get("href")
            if not href:
                continue
            url = urljoin(list_url, href)
            path = urlparse(url).path
            # keep only product-like slugs (shallow path, hyphenated)
            if url.startswith(BASE) and path.count("/") <= 2 and "-" in path:
                links.add(normalize_link(url))
 
    # Fallback: if nothing found inside container, fall back to whole page but still restrict by path pattern
    if not links:
        for a in soup.select("a[href*='-']"):
            href = a.get("href")
            if not href:
                continue
            url = urljoin(list_url, href)
            path = urlparse(url).path
            if url.startswith(BASE) and path.count("/") <= 2 and "-" in path:
                links.add(normalize_link(url))
 
    # return sorted normalized links (full url without query/fragment)
    return sorted(links)

def is_200g_product(url: str, title_text: str, page_text: str) -> bool:
    # 1) URL- oder Titelindikatoren
    if "/200g" in url.lower() or "-200g" in url.lower():
        return True
    if re.search(r"\b200\s*g\b", title_text, flags=re.I):
        return True

    # 2) Explizites Feld EINHEIT: bevorzugen (wenn vorhanden, gilt nur wenn 200g)
    m_unit = re.search(r"EINHEIT\s*:\s*([^\n\r]+)", page_text, flags=re.I)
    if m_unit:
        unit = m_unit.group(1).strip()
        # Beispiele: "200 g", "200g", "200 Gramm"
        if re.search(r"\b200\s*g\b", unit, flags=re.I) or re.search(r"\b200\b", unit):
            return True
        return False

    # 3) Fallback auf "Gewicht: 200 g"
    if re.search(r"\bGewicht\s*:\s*200\s*g\b", page_text, flags=re.I):
        return True

    # 4) Ausschlüsse: andere eindeutige Grammaturen im Titel -> kein 200g
    if re.search(r"\b(20|25|50|65|100|125|150|180|250|500)\s*g\b", title_text, flags=re.I):
        return False

    # Streng: wenn nichts eindeutig ist, nicht als 200g behandeln
    return False

# ---------------- Hersteller & Felder ----------------

def extract_manufacturer_from_title(title_text: str) -> str:
    """
    Marke = alles vor 'Tabak'/'Tobacco' im Titel.
    Beispiele:
      'Nameless Tabak #808 P!NA & LADA - 200g' -> 'Nameless'
      'True Passion Tobacco Le Chill 200g'     -> 'True Passion'
    """
    t = norm(title_text)
    m = re.match(r"^(.*?)\s+(Tabak|Tobacco)\b", t, flags=re.I)
    if m:
        return norm(m.group(1))
    # Fallback: erstes Wort des Kopfsegments vor dem ersten Bindestrich
    head = t.split("-")[0].strip()
    first = head.split(" ")[0] if head else ""
    return first

def extract_manufacturer(soup: BeautifulSoup, title_text: str, url: str) -> str:
    # 1) bevorzugt aus dem Titel
    brand = extract_manufacturer_from_title(title_text)
    if brand:
        return brand

    # 2) strukturierte Felder (gezielt, kein generisches dt/dd)
    for sel in ['[itemprop="brand"]','.product--manufacturer a','.product--supplier a','a[class*="brand"]']:
        el = soup.select_one(sel)
        if el:
            t = norm(el.get_text())
            if t and t.lower() not in ("tabak","tobacco"):
                return t

    # 3) Breadcrumb als Fallback
    for a in soup.select(".breadcrumb a, .breadcrumbs a, nav.breadcrumb a, nav a"):
        t = norm(a.get_text())
        if re.search(r"(tabak|tobacco)", t, re.I):
            t = re.sub(r"(tabak|tobacco)", "", t, flags=re.I).strip(" -")
            if t:
                return t

    # 4) URL-Slug (Markensegment)
    path = urlparse(url).path.strip("/").split("/")
    if path:
        seg = path[0].replace("-tabak","").replace("-tobacco","")
        words = [w for w in seg.split("-") if w]
        if words:
            return words[0].capitalize()

    # letzter Notanker: erstes Wort im Titel
    return (norm(title_text).split(" ") or [""])[0]

def extract_flavor_components(soup: BeautifulSoup) -> str:
    """
    Extrahiere 'Geschmack' / 'Aroma' möglichst präzise.

    Strategie:
    1) Strukturierte Felder (dt/dd, th/td) bevorzugen.
    2) Falls nicht vorhanden, nach Elementtexten mit 'Geschmack:' / 'Aroma:' suchen.
    3) Als Fallback Phrasen wie 'schmeckt nach ...' parsen.
    4) Stoppe die Extraktion vor bekannten Labels (inkl. EINHEIT, Produkteigenschaft).
    Ergebnis: kommagetrennte Aromen ohne Leerzeichen nach Kommas, dedupliziert.
    """
    # gesamter Seitentext (für Fallbacks)
    txt = soup.get_text(" ", strip=True)

    STOP_LABELS = r"(?:FSK|Nikotinstärke|Nikotin|Gewicht|Inhalt|Herkunftsland|Tabakart|EAN|Artikelnummer|Marke|Hersteller|EINHEIT|Produkteigenschaft|Produkteigenschaften|Produktbeschreibung|Preis|Verpackung|Menge)"

    # 1) dt/dd pairs (typische Shopware Produktinfo)
    for dt in soup.select("dt"):
        if re.search(r"\b(Geschmack|Aroma)\b", dt.get_text(), flags=re.I):
            dd = dt.find_next_sibling("dd")
            if dd:
                raw = norm(dd.get_text())
                # stoppe bei Stop-Label in dd text
                raw = re.split(r"\s*" + STOP_LABELS + r"\s*[:\s]?", raw, flags=re.I)[0]
                if raw:
                    # Entferne mögliche Inline-Labels wie "EINHEIT: 200g" oder "Produkteigenschaft: ..."
                    raw = re.sub(r"\b(?:EINHEIT|Produkteigenschaft|Produkteigenschaften)\s*[:\s]*[^,.;\n\r]*", "", raw, flags=re.I)
                    parts = re.split(r",|/|\||\+|&| und ", raw, flags=re.I)
                    parts = [norm(p) for p in parts if norm(p)]
                    out, seen = [], set()
                    for p in parts:
                        p = re.sub(r"^(schmeckt\s+nach[:\s]*)", "", p, flags=re.I).strip()
                        key = p.lower()
                        if key and key not in seen:
                            seen.add(key); out.append(p)
                    return ",".join(out).replace(", ", ",")

    # 2) table rows th/td
    for row in soup.select("tr"):
        th = row.select_one("th")
        td = row.select_one("td")
        if th and td and re.search(r"\b(Geschmack|Aroma)\b", th.get_text(), flags=re.I):
            raw = norm(td.get_text())
            raw = re.split(r"\s*" + STOP_LABELS + r"\s*[:\s]?", raw, flags=re.I)[0]
            raw = re.sub(r"\b(?:EINHEIT|Produkteigenschaft|Produkteigenschaften)\s*[:\s]*[^,.;\n\r]*", "", raw, flags=re.I)
            parts = re.split(r",|/|\||\+|&| und ", raw, flags=re.I)
            parts = [norm(p) for p in parts if norm(p)]
            out, seen = [], set()
            for p in parts:
                p = re.sub(r"^(schmeckt\s+nach[:\s]*)", "", p, flags=re.I).strip()
                key = p.lower()
                if key and key not in seen:
                    seen.add(key); out.append(p)
            return ",".join(out).replace(", ", ",")

    # 3) direkte Label-Suche in Textknoten / Inline-Feldern, capture non-greedy bis STOP_LABELS
    m = re.search(r"(?:Geschmack|Aroma)\s*:\s*(.+?)(?=\s*" + STOP_LABELS + r"\s*:|$)", txt, flags=re.I)
    raw = m.group(1) if m else ""

    # 4) Fallback: suche nach "schmeckt nach ..."
    if not raw or re.search(r"(nicht\s+verfügbar|nicht\s+angegeben|keine\s+angabe|n/?a\b)", raw, flags=re.I):
        m2 = re.search(r"schmeckt\s+nach\s*:?\s*(.+?)(?=\s*" + STOP_LABELS + r"\s*:|[.!\n\r]|$)", txt, flags=re.I)
        if m2:
            raw = m2.group(1)

    if not raw:
        return ""

    # bereinigen: entferne versehentliche EINHEIT- / Feldreste
    raw = re.sub(r"\bEINHEIT\s*[:\s]*\d+\s*g\b", "", raw, flags=re.I)
    raw = re.sub(r"\b(?:EINHEIT|Produkteigenschaft|Produkteigenschaften)\s*[:\s]*[^,.;\n\r]*", "", raw, flags=re.I)
    raw = re.split(r"\s*" + STOP_LABELS + r"\s*[:\s]?", raw, flags=re.I)[0]

    parts = re.split(r",|/|\||\+|&| und ", raw, flags=re.I)
    parts = [norm(p) for p in parts if norm(p)]
    out, seen = [], set()
    for p in parts:
        p = re.sub(r"^(schmeckt\s+nach[:\s]*)", "", p, flags=re.I).strip()
        key = p.lower()
        if key and key not in seen:
            seen.add(key)
            out.append(p)
    return ",".join(out).replace(", ", ",")

def extract_flavor_name(title_text: str, manufacturer: str) -> str:
    """
    'name' = vollständiger Produktname (inkl. 'Tabak/Tobacco'),
    aber ohne Gewichtsangaben/Klammern und ohne trailing ' -'.
    """
    t = norm(title_text)
    t = re.sub(r"\b\d+\s*g\b", "", t, flags=re.I)
    t = re.sub(r"\b1\s*kg\b", "", t, flags=re.I)
    t = re.sub(r"\([^)]*\)", "", t)             # Klammern
    t = re.sub(r"\s{2,}", " ", t).strip()
    t = re.sub(r"\s-\s*$", "", t)               # trailing " -"
    return t

# ---------------- Produkt-Parsing ----------------

def parse_product(url: str):
    soup = get_soup(url)
    title_el = soup.select_one("h1, h1[itemprop='name'], .product--title")
    title = norm(title_el.get_text()) if title_el else ""
    page_text = soup.get_text(" ", strip=True)

    if not is_200g_product(url, title, page_text):
        raise ValueError("Nicht 200g")

    manufacturer = extract_manufacturer(soup, title, url)
    name = extract_flavor_name(title, manufacturer)
    flavor = extract_flavor_components(soup)

    # Format: flavor ohne Leerzeichen nach Komma
    flavor = flavor.replace(", ", ",")
    return {"name": name, "flavor": flavor, "manufacturer": {"name": manufacturer or ""}}

# ---------------- Main ----------------

def main():
    ap = argparse.ArgumentParser(description="Scrape 200g Shisha-Tabak von shisha-world.com im JSONL-Format.")
    ap.add_argument("--start", type=int, default=1, help="?p=Startseite (Standard 1)")
    ap.add_argument("--end", type=int, default=30, help="?p=Endseite (Standard 30)")
    ap.add_argument("--out", default="tabak_200g.jsonl", help="Ausgabedatei (JSONL)")
    ap.add_argument("--delay", type=float, default=0.6, help="Delay zwischen Requests (Sek.)")
    ap.add_argument("--require-flavor", action="store_true", help="Nur Produkte mit gefülltem 'flavor' schreiben")
    ap.add_argument("--verbose", action="store_true", help="Verbose debug output")
    args = ap.parse_args()
 
    # don't globally dedupe links across pages; dedupe at write time via seen_keys.
    # Track links per page to allow parsing products that may appear on multiple paginated pages.
    seen_keys = set()   # (manufacturer.lower(), name.lower())
    written = 0
 
    with open(args.out, "w", encoding="utf-8") as f:
        for list_url in list_page_urls(args.start, args.end):
            if args.verbose:
                print(f"[DEBUG] Fetching list page: {list_url}")
            try:
                product_links = collect_product_links(list_url)
            except Exception as e:
                print(f"[WARN] Kategorieseite {list_url}: {e}")
                continue
 
            if not product_links:
                # Seite liefert keine Produktlinks — überspringe, statt das ganze Scraping abzubrechen.
                print(f"[WARN] Keine Produkte auf {list_url} – überspringe Seite und fahre fort.")
                continue
 
            print(f"[INFO] {list_url} -> {len(product_links)} Links")
            if args.verbose:
                print(f"[DEBUG] First links: {product_links[:8]}")
 
            new_from_page = 0
            # per-page link set to avoid duplicate links on the same page
            seen_links_page = set()
            for link in product_links:
                if link in seen_links_page:
                    if args.verbose:
                        print(f"[DEBUG] already seen on page (skip): {link}")
                    continue
                seen_links_page.add(link)
                new_from_page += 1
                time.sleep(args.delay)
                try:
                    if args.verbose:
                        print(f"[DEBUG] parsing product: {link}")
                    item = parse_product(link)
                    if args.require_flavor and not item.get("flavor"):
                        print(f"[SKIP] {item['manufacturer']['name']} – {item['name']} (kein flavor)")
                        continue
                    key = (item["manufacturer"]["name"].lower(), item["name"].lower())
                    if key in seen_keys:
                        if args.verbose:
                            print(f"[DEBUG] duplicate product key (skip): {key}")
                        continue
                    seen_keys.add(key)
                    f.write(json.dumps(item, ensure_ascii=False) + "\n")
                    written += 1
                    print(f"[OK] {item['manufacturer']['name']} – {item['name']}")
                except ValueError as ve:
                    print(f"[SKIP] {link} -> {ve}")
                except Exception as e:
                    # include minimal traceback-like info for debugging
                    print(f"[FAIL] {link}: {type(e).__name__}: {e}")
 
            if args.verbose:
                print(f"[DEBUG] New links processed from this page: {new_from_page}")
                print(f"[DEBUG] Total unique keys so far: {len(seen_keys)}; written: {written}")
 
    print(f"\nGespeichert: {args.out} (Artikel: {written})")
 
if __name__ == "__main__":
    main()
