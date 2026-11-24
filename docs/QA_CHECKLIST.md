# QA_CHECKLIST

Prüfliste für Version 0.2.0 (Phase 1). Spalte **Stand**: ✅ automatisiert (Headless-Testsuite, 78 Prüfungen) · 🌐 im Browser geprüft (Chromium/Playwright, Desktop 1280×720, Software-GL) · ⏳ muss vom Projektinhaber auf dem iPhone geprüft werden.

> Ehrlicher Hinweis: Es wurde **kein echtes iPhone** getestet. Alle 🌐-Prüfungen liefen in Chromium; Safari/WebKit-Eigenheiten (Touch, Tastatur, Speicher) sind damit nicht abgedeckt.

## A. Start & Ablauf
| # | Prüfung | Stand |
|---|---|---|
| A1 | Erster Start: Charakter-Editor erscheint vor der Welt | 🌐 |
| A2 | „Fertig“ → Siedlung wird gegründet, Figur steht in der Welt | 🌐 ✅ |
| A3 | Neu laden: kein Editor mehr, gleiche Figur, gleiche Siedlung, gleiche NPCs | 🌐 ✅ |
| A4 | Ohne Penzilla-Dateien startet das Spiel mit Platzhaltern, ohne Editor und ohne NPCs | ✅ |
| A5 | Keine Fehler in der Browser-Konsole | 🌐 |

## B. Charakter-Editor
| # | Prüfung | Stand |
|---|---|---|
| B1 | Kategorien Körper/Haare/Oberteil/Unterteil/Schuhe/Extras/Outfits umschaltbar | 🌐 |
| B2 | Karte antippen → Figur ändert sich sofort | 🌐 |
| B3 | Farbfeld antippen → Farbe ändert sich sofort | 🌐 |
| B4 | Zufall, Rückgängig, Zurücksetzen, Abbrechen (nur im Bearbeiten-Modus) | 🌐 |
| B5 | Drehen per Pfeil und Wischen; Auto-Drehen; Gehen/Benutzen-Vorschau; Blinzeln | 🌐 |
| B6 | Mütze/Strohhut ersetzen die Frisur (Hinweis sichtbar) | 🌐 |
| B7 | Hochformat: Bühne oben, Bedienfeld unten, nichts abgeschnitten | ⏳ |
| B8 | Namensfeld: iOS-Tastatur öffnet sich | ⏳ |
| B9 | Menü → „Figur bearbeiten“ → Änderung → Figur in der Welt aktualisiert | 🌐 |

## C. Welt, Stadtbild, Tiefe
| # | Prüfung | Stand |
|---|---|---|
| C1 | Straßen mit Gehwegen, Übergänge Gras/Weg/Gehweg ohne Lücken | 🌐 |
| C2 | Laternen nur am Bordstein, Ausleger über der Straße, versetzt auf beiden Seiten | ✅ 🌐 |
| C3 | Hydranten am Gehweg, nicht auf der Straße, nicht vor Türen, ≥ 1,5 Zellen von Laternen | ✅ |
| C4 | Bushaltestelle an der Hauptstraße, Schilder an Kreuzungen, Briefkästen neben Haustüren | ✅ 🌐 |
| C5 | Figur läuft vor/hinter Laternen, Bäumen, NPCs korrekt sortiert | 🌐 |
| C6 | Figur hinter Gebäude: nur Umgebung der Figur wird weich durchsichtig, kein Flackern | ✅ 🌐 |
| C7 | Figur vor Gebäude: Gebäude bleibt deckend | ✅ 🌐 |
| C8 | Marktzeile (Bäckerei, Gemischtwaren, Schmiede) und Gründerzelt sitzen exakt auf dem Raster | 🌐 |

## D. Zeit & Licht
| # | Prüfung | Stand |
|---|---|---|
| D1 | HUD-Uhr = Ortszeit des Geräts (Europe/Berlin und America/New_York geprüft) | 🌐 ✅ |
| D2 | Sommer-/Winterzeit: Versatz korrekt (CEST/CET, UTC−5) | ✅ |
| D3 | Menü zeigt Zeitzone, Sonnenauf- und -untergang | 🌐 |
| D4 | Vorschau-Schieberegler bzw. `?preview=21:00`: Dämmerung/Nacht, Laternen an, Lichtkegel, Lichtfleck auf der Straße | 🌐 |
| D5 | „Echtzeit“ setzt die Vorschau zurück | 🌐 |
| D6 | Zeitumstellung live (Gerät über Nacht offen lassen) | ⏳ |

## E. NPCs
| # | Prüfung | Stand |
|---|---|---|
| E1 | 12 NPCs, 8 Rollen, eindeutige Vornamen und Aussehen | ✅ |
| E2 | Rollenkleidung erkennbar (Bau: Mütze/Overall/Hammer, Landwirtschaft: Strohhut, Sanitäter: hellblau …) | ✅ 🌐 |
| E3 | Mittags am Arbeitsplatz, 20 Uhr am Wohnhaus, 2 Uhr niemand draußen | ✅ 🌐 |
| E4 | NPC antippen → Figur läuft hin, NPC schaut sie an, Karte mit Name/Rolle | ✅ |
| E5 | NPCs blockieren keine Türen/Wege | ✅ |

## F. Steuerung & Plattform
| # | Prüfung | Stand |
|---|---|---|
| F1 | Tastatur, Joystick, Tippen-zum-Gehen, Pinch-Zoom, Ziehen | ✅ |
| F2 | Multi-Touch (Joystick + Aktionstaste gleichzeitig) | ✅ ⏳ |
| F3 | iPhone Safari: Start, Bildrate (Menü → Leistungsanzeige), Wärme, Speicher | ⏳ |
| F4 | „Zum Home-Bildschirm“ → Start als PWA im Vollbild | ⏳ |
| F5 | Hoch-/Querformat-Wechsel während des Spiels | ⏳ |

## Ausführen
```bash
godot --headless --path . res://tests/test_runner.tscn                      # A–F (✅)
node tools/browser_editor_test.js build/web build/editor                     # B
node tools/world_shots.js build/web build/world "?preview=12:00" "?spawn=9.7,5.4&preview=12:00"
TZ_ID=America/New_York node tools/world_shots.js build/web build/ny ""       # D1
```
`?spawn=x,y` setzt die Figur (nur Test), `?preview=HH:MM` die Tageszeit-Vorschau.
