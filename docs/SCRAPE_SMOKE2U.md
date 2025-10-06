# Anleitung: scrape_shishaworld.py (smoke2u)

Diese Anleitung erklärt, wie man das Skript [`scripts/scrape_shishaworld.py`](scripts/scrape_shishaworld.py:1) ausführt und welche Optionen verfügbar sind.

Voraussetzungen
- Python 3.8+
- Abhängigkeiten installieren: siehe [`scripts/requirements.txt`](scripts/requirements.txt:1)

Installation
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r scripts/requirements.txt
```

Zweck / Verhalten
- Zielseite: https://www.smoke2u.de/shisha-tabak/200g  
- Das Skript filtert Produkte basierend auf dem Feld "EINHEIT:" (nur 200g) und extrahiert das Feld "Geschmack:".  
- Falls "Geschmack:" fehlt oder als "nicht verfügbar" markiert ist, versucht das Skript, Phrasen wie "schmeckt nach ..." im Seitentext zu erkennen und daraus Aromen zu extrahieren.

Beispiele
```bash
# Alle Seiten 1..10 scrapen, Ausgabe tabak_200g.jsonl
python3 scripts/scrape_shishaworld.py --start 1 --end 8 --out tabak_200g.json

# Nur Einträge mit gefülltem flavor schreiben
python3 scripts/scrape_shishaworld.py --start 1 --end 5 --out only_with_flavor.json --require-flavor
```

Optionen (wichtig)
- --start / --end : Seitennummern (?p=), Standard 1..30  
- --out : Ausgabedatei (JSONL), Standard tabak_200g.jsonl  
- --delay : Wartezeit zwischen Requests in Sekunden (default 0.6)  
- --require-flavor : nur Produkte mit non-empty "flavor" in die Ausgabe schreiben

Hinweise & Troubleshooting
- Das Skript macht einfache Retries bei 429/503; erhöhe --delay bei Raten‑Limit-Problemen.  
- Wenn Daten fehlen oder Felder nicht erkannt werden: prüfe die Selektoren / Textmuster in [`scripts/scrape_shishaworld.py`](scripts/scrape_shishaworld.py:1).  
- Respektiere die robots.txt und Nutzungsbedingungen der Zielseite; setze angemessene Delays und nutze das Skript verantwortungsvoll.

Ende

## Ausführen des Skripts (virtuelle Umgebung)

Das Skript benötigt die Python‑Pakete BeautifulSoup4 und requests. Lege deshalb eine virtuelle Umgebung im Projekt an und installiere die Abhängigkeiten:

```bash
python3 -m venv .venv_scraper
.venv_scraper/bin/pip install --upgrade pip
.venv_scraper/bin/pip install -r scripts/requirements.txt
```

Anschließend das Skript mit der virtuellen Umgebung ausführen:

```bash
.venv_scraper/bin/python scripts/scrape_shishaworld.py --start 1 --end 8 --out tabak_200g.jsonl --verbose
```

Wenn du das Skript ohne venv startest und die Fehlermeldung `ModuleNotFoundError: No module named 'bs4'` erhältst, dann nutze bitte die obigen Befehle.

Referenz zur Datei: [`scripts/scrape_shishaworld.py`](scripts/scrape_shishaworld.py:1)
