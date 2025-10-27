# scrape_rauchland_200g.py
# Ziel-Format je Zeile (JSONL):
# {"name":"Love 66","flavor":"Maracuja,Honigmelone,Wassermelone","manufacturer":{"name":"Adalya"}}
 
import argparse, json, re, time, os
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
    print("  .venv_scraper/bin/python scripts/scrape_rauchland.py --start 1 --end 2 --out tabak_200g_rauchland.jsonl")
    raise
 
BASE = "https://rauchland.de"
CATEGORY = f"{BASE}/Shisha-Tabak"
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
        # (e.g. /Shisha-Tabak_s2) which matches this site's known pagination pattern.
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
    """
    Collect product links from the category page following the user's rules:
    - Only search inside <div id="content">.
    - Iterate items with class "col-12" and extract anchors from those items.
    - Ignore any links under <ul class="flx-ac flx-jc blanklist flx-w">.
    - Return normalized product links (shallow hyphenated slugs).
    """
    soup = get_soup(list_url)
    links = []
    content = soup.select_one("div#content") or soup

    # remove ignored lists completely
    for ul in content.select("ul.flx-ac.flx-jc.blanklist.flx-w"):
        ul.decompose()

    # search within col-12 items (user requested)
    for item in content.select(".col-12"):
        # prefer anchor that wraps an image or has product-like classes
        a = item.select_one("a[href] img")
        if a:
            a = a.find_parent("a", href=True)
        else:
            a = item.select_one("a[href].product--title, a[href].product-link, a[href].product-name, a[href]")

        if not a:
            continue
        href = a.get("href")
        if not href:
            continue
        url = urljoin(list_url, href)
        if not url.startswith(BASE):
            continue

        # exclude anchors that point to in-page anchors or filters
        if urlparse(url).fragment:
            continue
        # exclude known non-product patterns (category slices shown as 'Shisha-Tabak::Brand' etc.)
        if "::" in url:
            continue

        path = urlparse(url).path
        # candidate: shallow path with at least one hyphen (typical product slug)
        if not (path.count("/") <= 2 and "-" in path):
            continue

        # exclude category/brand index, pods, vapes, accessories
        if re.search(r"(?:/Shisha-Tabak\b|/Tabak\b|/Tobacco\b|Pods?|Vapes?|Zubehoer|Zubehör|Kategorie)", path, flags=re.I):
            continue

        # anchor text should be non-empty and not purely numeric
        txt = norm(a.get_text())
        if not txt or re.fullmatch(r"\d+", txt):
            continue

        links.append(normalize_link(url))

    # Deduplicate preserving order
    seen = set()
    out = []
    for u in links:
        if u not in seen:
            seen.add(u)
            out.append(u)

    return sorted(out)

def is_target_weight_product(url: str, title_text: str, page_text: str) -> bool:
    """
    Weight checks disabled by user request — ignore any weight labels and accept all products.
    This function always returns True so the scraper does not filter products by grams.
    """
    return True

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
    for sel in ['[itemprop="brand"]','.product--manufacturer a','.product--supplier a','a[class*="brand"]', '.manufacturer a', '.hersteller a']:
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
    3) Als Fallback Phrasen wie 'schmeckt nach ...' parsen oder Beschreibungstext verwenden.
    4) Stoppe die Extraktion vor bekannten Labels (inkl. EINHEIT, Produkteigenschaft).
    Ergebnis: kommagetrennte Aromen ohne Leerzeichen nach Kommas, dedupliziert.
    """
    # gesamter Seitentext (für Fallbacks)
    txt = soup.get_text(" ", strip=True)

    # Erweiterte Stop-Labels — füge Grundtabak + Lieferumfang hinzu
    STOP_LABELS = r"(?:FSK|Nikotinstärke|Nikotin|Gewicht|Inhalt|Herkunftsland|Grundtabak|Lieferumfang|Tabakart|EAN|Artikelnummer|Marke|Hersteller|EINHEIT|Produkteigenschaft|Produkteigenschaften|Produktbeschreibung|Preis|Verpackung|Menge|Inhaltseinheit)"

    def _clean_boilerplate(raw: str) -> str:
        """Remove marketing boilerplate and sentences/reference labels that are not flavors."""
        if not raw:
            return raw
        # remove obvious inline EINHEIT leftovers
        raw = re.sub(r"\bEINHEIT\s*[:\s]*\d+\s*g\b", "", raw, flags=re.I)
        # remove labels like 'Grundtabak: ...' or 'Lieferumfang: ...' and anything after until stop label
        raw = re.split(r"\s*" + STOP_LABELS + r"\s*[:\s]?", raw, flags=re.I)[0]
        # remove sentences that mention the shop or generic marketing
        sentences = re.split(r"[.!\n\r]+", raw)
        good = []
        for s in sentences:
            s_strip = s.strip()
            if not s_strip:
                continue
            low = s_strip.lower()
            if "rauchland" in low or "shisha tabak" in low or "perfekten genuss" in low or "riesenauswahl" in low:
                continue
            good.append(s_strip)
        raw = " ".join(good)
        # remove stray occurrences of 'Shisha Tabak' within remaining text
        raw = re.sub(r"(?i)\bshisha\s+tabak\b", "", raw)
        return raw.strip()

    # 1) dt/dd pairs (typische Shopware Produktinfo)
    for dt in soup.select("dt"):
        if re.search(r"\b(Geschmack|Aroma)\b", dt.get_text(), flags=re.I):
            dd = dt.find_next_sibling("dd")
            if dd:
                raw = norm(dd.get_text())
                # stoppe bei Stop-Label in dd text
                raw = _clean_boilerplate(raw)
                if raw:
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
            raw = _clean_boilerplate(raw)
            if raw:
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

    # 4) Fallback: suche nach "schmeckt nach ..." oder nutze Produktbeschreibung
    if not raw or re.search(r"(nicht\s+verfügbar|nicht\s+angegeben|keine\s+angabe|n/?a\b)", raw, flags=re.I):
        m2 = re.search(r"schmeckt\s+nach\s*:?\s*(.+?)(?=\s*" + STOP_LABELS + r"\s*:|[.!\n\r]|$)", txt, flags=re.I)
        if m2:
            raw = m2.group(1)

    if not raw:
        # Versuch: kurze Beschreibung/Produkttext aus typischen Container
        desc_sel = soup.select_one(".product--description, .description, #description, .product-description, .short-description")
        if desc_sel:
            raw = norm(desc_sel.get_text(" ", strip=True))

    if not raw:
        return ""

    # bereinigen: entferne versehentliche EINHEIT- / Feldreste & marketing boilerplate
    raw = _clean_boilerplate(raw)
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

    # 4) Fallback: suche nach "schmeckt nach ..." oder nutze Produktbeschreibung
    if not raw or re.search(r"(nicht\s+verfügbar|nicht\s+angegeben|keine\s+angabe|n/?a\b)", raw, flags=re.I):
        m2 = re.search(r"schmeckt\s+nach\s*:?\s*(.+?)(?=\s*" + STOP_LABELS + r"\s*:|[.!\n\r]|$)", txt, flags=re.I)
        if m2:
            raw = m2.group(1)

    if not raw:
        # Versuch: kurze Beschreibung/Produkttext aus typischen Container
        desc_sel = soup.select_one(".product--description, .description, #description, .product-description, .short-description")
        if desc_sel:
            raw = norm(desc_sel.get_text(" ", strip=True))
            raw = re.split(r"\s*" + STOP_LABELS + r"\s*[:\s]?", raw, flags=re.I)[0]

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
    title_el = soup.select_one("h1, h1[itemprop='name'], .product--title, .product-name, .page-title")
    title = norm(title_el.get_text()) if title_el else ""
    page_text = soup.get_text(" ", strip=True)

    if not is_target_weight_product(url, title, page_text):
        raise ValueError("Nicht gewünschtes Gewicht (25g oder 200g)")

    manufacturer = extract_manufacturer(soup, title, url)
    name = extract_flavor_name(title, manufacturer)
    flavor = extract_flavor_components(soup)

    # Format: flavor ohne Leerzeichen nach Komma
    flavor = flavor.replace(", ", ",")
    return {"name": name, "flavor": flavor, "manufacturer": {"name": manufacturer or ""}}

# ---------------- Main ----------------

def main():
    ap = argparse.ArgumentParser(description="Scrape 200g Shisha-Tabak von rauchland.de im JSONL-Format.")
    ap.add_argument("--start", type=int, default=1, help="?p=Startseite (Standard 1)")
    ap.add_argument("--end", type=int, default=97, help="?p=Endseite (Standard 97)")
    ap.add_argument("--out", default="tabak_200g_rauchland.jsonl", help="Ausgabedatei (JSONL)")
    ap.add_argument("--delay", type=float, default=0.6, help="Delay zwischen Requests (Sek.)")
    ap.add_argument("--require-flavor", action="store_true", help="Nur Produkte mit gefülltem 'flavor' schreiben")
    ap.add_argument("--verbose", action="store_true", help="Verbose debug output")
    args = ap.parse_args()

    # don't globally dedupe links across pages; dedupe at write time via seen_keys.
    # Track links per page to allow parsing products that may appear on multiple paginated pages.
    seen_keys = set()   # (manufacturer.lower(), name.lower())

    # Preload existing dataset (skip duplicates already in repo list)
    existing_paths = [
        "scripts/tabak_200g.jsonl",  # historic 200g file in repository
        args.out                    # if user provided an output that already exists
    ]
    for p in existing_paths:
        try:
            if os.path.exists(p):
                with open(p, "r", encoding="utf-8") as ef:
                    for line in ef:
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            obj = json.loads(line)
                            m = (obj.get("manufacturer", {}).get("name", "") or "").lower()
                            n = (obj.get("name", "") or "").lower()
                            if m or n:
                                seen_keys.add((m, n))
                        except Exception:
                            continue
        except Exception:
            # ignore file-read errors, proceed with empty seen_keys
            pass

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