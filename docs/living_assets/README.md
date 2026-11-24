# Living Assets & Environmental Storytelling

Eigenständiges visuelles Projekt (Auftrag vom 24.11.2026, vor Phase 3). **Keine neuen Spielsysteme, keine Änderung an Spielmechanik oder laufender Darstellung.** Originaldateien bleiben unverändert in den ZIP-Archiven; alle Ableitungen sind separate Dateien.

## Stand der Schritte

| Schritt | Inhalt | Stand |
|---|---|---|
| A | Vollständige Asset-Inventarisierung | ✅ [asset_inventory.csv](asset_inventory.csv) (7 901 Dateien), [inventory_summary.json](inventory_summary.json) |
| B | Repräsentative Beispiele | ✅ Wohnhaus, Rathaus, RPG-Laden, Baum, Kahlbaum, Straße, Gehweg, Laterne, Bank, Hydrant, Auto, 7 Innenraum-Möbel |
| C | Zustandsvarianten der Beispiele | ✅ erzeugt (privat, `assets/penzilla/states/`, Kontaktbögen an den Projektinhaber) |
| D | Visuelle Prüfung gegen die Originale | ✅ 3 Runden, [QA_REVIEW.md](QA_REVIEW.md) |
| E | Technische Prüfung in Godot | ✅ Galerie `?gallery=living`, 3 Stufen + VFX, gemessen |
| F | Einheitlicher Produktionsstandard | ✅ **bestätigt** (mit Ergänzungen) – [PRODUCTION_STANDARD.md](PRODUCTION_STANDARD.md) |
| G | Systematische Erstellung | ✅ Materialerkennung, kombinierbare Merkmale, Pilot (20 Assets) geprüft → Serie (87 Einträge, alle Kategorien) – [QA_REVIEW.md](QA_REVIEW.md) §4; Laufzeit-Bausteine `VisualState` + `LivingComposer` (nicht im Spiel verdrahtet) |

## Ergebnisse
| Ergebnis | Dokument / Datei |
|---|---|
| Vollständige Asset-Inventarliste | [asset_inventory.csv](asset_inventory.csv) – Datei, Kategorie, Quelle, Maße, Perspektive, Animation, Verwendung im Spiel, Godot-Kompatibilität, Lizenz, Zustandsgruppe |
| Zustandsmatrix | [STATE_MATRIX.md](STATE_MATRIX.md) |
| Sammlung der erzeugten Varianten | `assets/penzilla/states/` (privat) + Kontaktbögen (direkt übergeben, nicht öffentlich) |
| Übersicht VFX-Quellen | [VFX_SOURCES.md](VFX_SOURCES.md) |
| Lizenzdokumentation (Penzilla: erlaubte Bearbeitung/Weitergabe, offene Punkte) | [LICENSES.md](LICENSES.md) |
| Technische Integrationsdokumentation | [TECHNICAL_INTEGRATION.md](TECHNICAL_INTEGRATION.md) |
| Performance-Einschätzung | [TECHNICAL_INTEGRATION.md §6](TECHNICAL_INTEGRATION.md) |
| Prioritätenliste | [PRIORITIES.md](PRIORITIES.md) |
| Eigene VFX | `assets/vfx/` (eigene Arbeit) |

## Lizenzen im Überblick
| Material | Lizenz | Im öffentlichen Repository? |
|---|---|---|
| Penzilla-Originale (6 Pakete) | Penzilla Standard (kommerziell, keine Weitergabe der Rohdateien); Lizenz-PDF weiterhin nicht vorhanden | **nein** (nur Dateinamen/Maße im Inventar) |
| Abgeleitete Penzilla-Zustände | Bearbeitung zur Nutzung im eigenen Spiel – **Prüfung des Lizenz-PDF offen**, siehe [LICENSES.md](LICENSES.md) | **nein** (`assets/penzilla/` git-ignoriert) |
| Eigene VFX, Verschleiß-Feld | projekteigen | ja (`assets/vfx/`) |
| Kenney- und OpenGameArt-Effekte | CC0 (geprüft) | nicht eingebunden |
| CC0-Interior (Kenney, OpenGameArt) | CC0 | ja (bereits seit Phase 1) |

## Werkzeuge
```bash
python3 -I tools/assets/inventory.py <zip_ordner> .            # Schritt A
python3 -I tools/assets/make_living_states.py <zip_ordner> . --pilot --qa <qa_ordner>   # Pilot + Prüfung
python3 -I tools/assets/make_living_states.py <zip_ordner> . --qa <qa_ordner>           # Serie (numpy, scipy, pillow)
python3 -I tools/assets/make_vfx.py .                          # eigene VFX
# Godot-Galerie: Web-Build öffnen mit ?gallery=living (optional &perf=1)
```
