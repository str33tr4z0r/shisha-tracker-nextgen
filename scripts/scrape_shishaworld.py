# scrape_shishaworld_200g.py
# Ziel-Format je Zeile (JSONL):
# {"name":"Love 66","flavor":"Maracuja,Honigmelone,Wassermelone","manufacturer":{"name":"Adalya"}}

import argparse, json, re, time
from urllib.parse import urljoin, urlparse
import requests
from bs4 import BeautifulSoup

BASE = "https://www.shisha-world.com"
CATEGORY = f"{BASE}/shisha-tabak-200g"
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

def list_page_urls(start=1, end=30):
    # Shopware-Pagination: ?p=2, ?p=3, …
    for p in range(start, end + 1):
        yield f"{CATEGORY}?p={p}"

def collect_product_links(list_url: str):
    soup = get_soup(list_url)
    links = set()

    sels = [
        "a.product--title", "a.product--image", "a.product--info",
        ".product--box a[href]", ".product a[href]"
    ]
    for sel in sels:
        for a in soup.select(sel):
            href = a.get("href")
            if not href: 
                continue
            url = urljoin(list_url, href)
            path = urlparse(url).path
            if url.startswith(BASE) and path.count("/") <= 2 and "-" in path:
                links.add(url)

    if not links:
        for a in soup.select("a[href*='-']"):
            url = urljoin(list_url, a.get("href"))
            path = urlparse(url).path
            if url.startswith(BASE) and path.count("/") <= 2:
                links.add(url)

    return sorted(links)

def is_200g_product(url: str, title_text: str, page_text: str) -> bool:
    # Positive Indikatoren
    if "-200g" in url.lower():
        return True
    if re.search(r"\b200\s*g\b", title_text, flags=re.I):
        return True
    if re.search(r"\bGewicht\s*:\s*200\s*g\b", page_text, flags=re.I):
        return True
    # Ausschlüsse (falls andere Grammaturen auftauchen)
    if re.search(r"\b(20|25|50|65|100|125|150|180|250|500)\s*g\b", title_text, flags=re.I):
        return False
    return False  # streng: nur eindeutige 200g nehmen

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
    NUR der Wert hinter 'Aroma:' oder 'Geschmack:'.
    Stoppt vor FSK, Nikotin, Gewicht, EAN, Artikelnummer, Marke/Hersteller etc.
    Ausgabe ohne Leerzeichen nach Kommas.
    """
    txt = soup.get_text(" ", strip=True)
    m = re.search(r"(?:Aroma|Geschmack)\s*:\s*([^\n\r]+)", txt, flags=re.I)
    if not m:
        return ""
    raw = m.group(1)
    raw = re.split(
        r"\s*(?:FSK|Nikotinstärke|Nikotin|Gewicht|Inhalt|Herkunftsland|Tabakart|EAN|Artikelnummer|Marke|Hersteller)\s*:",
        raw, flags=re.I
    )[0]
    parts = re.split(r",|/|\||\+|&| und ", raw, flags=re.I)
    parts = [norm(p) for p in parts if norm(p)]
    out, seen = [], set()
    for p in parts:
        key = p.lower()
        if key not in seen:
            seen.add(key); out.append(p)
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
    args = ap.parse_args()

    seen_links = set()
    seen_keys = set()   # (manufacturer.lower(), name.lower())
    written = 0

    with open(args.out, "w", encoding="utf-8") as f:
        for list_url in list_page_urls(args.start, args.end):
            try:
                product_links = collect_product_links(list_url)
            except Exception as e:
                print(f"[WARN] Kategorieseite {list_url}: {e}")
                continue

            if not product_links:
                print(f"[STOP] Keine Produkte auf {list_url} – Abbruch.")
                break

            print(f"[INFO] {list_url} -> {len(product_links)} Links")
            for link in product_links:
                if link in seen_links:
                    continue
                seen_links.add(link)
                time.sleep(args.delay)
                try:
                    item = parse_product(link)
                    if args.require_flavor and not item.get("flavor"):
                        print(f"[SKIP] {item['manufacturer']['name']} – {item['name']} (kein flavor)")
                        continue
                    key = (item["manufacturer"]["name"].lower(), item["name"].lower())
                    if key in seen_keys:
                        continue
                    seen_keys.add(key)
                    f.write(json.dumps(item, ensure_ascii=False) + "\n")
                    written += 1
                    print(f"[OK] {item['manufacturer']['name']} – {item['name']}")
                except ValueError as ve:
                    print(f"[SKIP] {link} -> {ve}")
                except Exception as e:
                    print(f"[FAIL] {link}: {e}")

    print(f"\nGespeichert: {args.out} (Artikel: {written})")

if __name__ == "__main__":
    main()
