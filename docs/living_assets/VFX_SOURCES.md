# VFX-Quellen und Lizenzdokumentation

Geprüft am **24.11.2026**. Lizenzangaben wurden auf den **Originalseiten** gelesen (OpenGameArt „License(s)“-Feld) bzw. aus der `license.txt` im heruntergeladenen Archiv. Ergebnis und Empfehlung zuerst:

> **Empfehlung:** Effekte im Spiel aus dem **eigenen, prozedural gezeichneten VFX-Satz** im Penzilla-Stil (`assets/vfx/`), weil fremde Partikel (weich, ohne Konturen) neben Penzilla als Fremdkörper wirken. Kenney-Partikel (CC0) nur als Rückfall für sehr dezenten Hintergrundrauch/Staub.

## 1. Eigene VFX (im Repository)
| Datei | Inhalt | Herkunft | Lizenz |
|---|---|---|---|
| `assets/vfx/vfx_atlas.png` + `.json` | Flamme (8 Frames), Rauch dunkel/hell (je 6), Funken (3), Regentropfen, Schneeflocke, Staub (3), Blatt, Spritzer/Pfützenring (3), Reparatur-Funkeln (3), Belohnungsstern (3), Trümmerstück | **eigene Arbeit**, prozedural erzeugt von `tools/assets/make_vfx.py` (keine fremde Vorlage) | projekteigen, darf weitergegeben werden |
| `assets/vfx/grime_field.png` | kachelbares Feld für den Verschleiß-Shader | eigene Arbeit (`make_vfx.py`) | projekteigen |

Stil: flache Cartoon-Formen mit der Penzilla-Konturfarbe #330022, gesättigte Palette, keine weichen Fotopartikel.

## 2. Geprüfte externe Quellen

| Quelle | Inhalt | Lizenz (geprüft) | Kommerziell / Bearbeitung | Stil-Eignung zu Penzilla | Status |
|---|---|---|---|---|---|
| **Kenney – Smoke Particles** (OpenGameArt „Smoke particle assets“, Upload von Kenney) | 77 PNG: schwarzer Rauch, Explosion, Furz, Blitz, weiße Wolke | **CC0** (Seite: „License(s): CC0“; `license.txt`: „You may use these graphics in personal and commercial projects. Credit … would be nice but is not mandatory.“) | ja / ja | **gering**: weich, malerisch, ohne Konturen (Vorschau geprüft) | heruntergeladen nur zur Sichtprüfung (Arbeitsverzeichnis), **nicht** im Projekt |
| **Kenney – Particle Pack (80+)** (OpenGameArt, Upload von Kenney) | Partikel für Feuer, Rauch, Magie, Funken, Licht-Cookies | **CC0** (Seite) | ja / ja | gering (weich) | nicht heruntergeladen |
| **„Fire Smoke Animations“** (Reactorcore, OpenGameArt) | Pixel-Art-Feuer und -Rauch, mehrere Varianten | **CC0** (Seite) | ja / ja | gering (Pixel Art ≠ Penzilla-Vektorlook) | nicht heruntergeladen |
| **„Animated particle effects #1“** (para, OpenGameArt) | animierte Partikeleffekte (15,5 MB) | **CC0** (Seite) | ja / ja | ungeprüft (Vorschau nicht gesichtet) | nicht heruntergeladen |
| **„Free VFX asset pack“** (CodeManu, OpenGameArt) | VFX-Paket (94,6 MB) | **CC0** (Seite) | ja / ja | ungeprüft | nicht heruntergeladen |
| **„Fire FX – Burning Fire Animation“** (Mikodrak, OpenGameArt) | Feuer, 40 Frames | **CC0** (Seite) | ja / ja | ungeprüft (eher realistisch) | nicht heruntergeladen |
| **kenney.nl** (Originalseite) | – | – | – | – | Seite verweigert automatischen Abruf (HTTP 403); Lizenz über die von Kenney selbst hochgeladenen OpenGameArt-Seiten und die `license.txt` bestätigt |
| **pixor.art** | **kein Asset-Anbieter**: kostenpflichtiges Werkzeug (aktuell 11,99 USD statt 19,99 USD), das 3D-Modelle in Pixel-Art-Sprite-Sheets umwandelt | – | – | nicht passend (Pixel Art) | **nicht gekauft** (Kauf nur nach Zustimmung) |
| Brackeys VFX Bundle (itch.io) | – | nicht geprüft (Seite im Netzwerk nicht erreichbar) | – | – | offen |

## 3. Regeln für künftige Importe
1. Lizenz **auf der Originalseite** prüfen und Datum, Autor, Lizenztext, URL hier eintragen.
2. Nur Lizenzen mit **kommerzieller Nutzung und Bearbeitung** (CC0, CC-BY mit Namensnennung im Spiel-Abspann).
3. Archive in einem eigenen leeren Ordner prüfen (Pfade, Dateitypen), nichts ausführen.
4. Fremde Effekte nur, wenn sie zum Penzilla-Stil passen oder nachträglich angepasst werden (Kontur, Palette) – **keine** ungefilterte Mischung.
5. Lizenzdatei des Pakets mit ablegen.
