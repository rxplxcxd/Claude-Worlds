# Produktionsstandard (bestätigt am 24.11.2026, mit Ergänzungen)

Dieser Standard gilt für **alle** Zustandsvarianten. Bestätigt vom Projektinhaber mit Ergänzungen (deutlichere Unterscheidbarkeit, kombinierbare Merkmale, Materialerkennung, vollständige Abdeckung, dauerhafte Zustände, Lizenzprüfung, Produktionskontrolle, Performance) – eingearbeitet in §7–§9.

## 1. Stil (verbindlich)
1. **Penzilla-Look:** flache Farbflächen, harte Kanten, keine fotografischen Texturen, kein Rauschen.
2. **Konturen:** neue Formen (Risse, Löcher, Trümmer, Bewuchs, Bruchkanten) tragen die Penzilla-Konturfarbe **#330022**; Strichstärke ≈ 1,2 % der Spritehöhe (bei 540 px: 6–8 px Quelle).
3. **Farben** stammen aus der Palette des Assets (dunkler, ausgeblichen, zu warmem Braun **gemischt**) plus feste Zusatzpalette: Ruß #2B2429, Innenraum #33203A, Putz #E0D6C2, Rost #A85C2E/#783D21, Moos #6B9E45/#4D7833, Schnee #F2F7FF/#C2D6F2, Wasser #6B9ED1, Schlamm #6B4F38, Holz #8F613B. **Nie** Farbtöne rotieren.
4. **Perspektive:** isometrisch 2:1 erhalten; Ellipsen auf dem Boden 2:1 gestaucht; Boden-Effekte nur auf der Oberseite.
5. **Licht:** Lichtrichtung der Originale (oben links); Glanzpunkte oben links, Schatten unten rechts.
6. **Proportionen:** gleiche Leinwand und Anker wie das Original (Ausnahme „umgestürzt“: Leinwand wächst symmetrisch, Anker bleibt).

## 2. Technik je Veränderung
| Veränderung | Technik |
|---|---|
| Verschmutzung, Ausbleichen, Abdunkeln | Stufe 1 Shader (keine Datei) |
| Abblätternde Farbe, Risse, kaputte Fenster/Türen, Dachlöcher, Rost, Wasserflecken | Stufe 2 Overlay (zugeschnitten) |
| Einsturz, Ausbrennen, Ruine, Umstürzen, Wrack, Bruch | Stufe 3 Variante |
| Feuer, Rauch, Funken, Regen, Schnee, Staub, Blätter, Bau/Reparatur, Belohnung | eigene VFX (Atlas) |
| Vorhandene Penzilla-Alternativen (BareTree, Lampe an/aus, Interior-State2, Türen offen, Fahrzeuglicht) | Original verwenden |

## 3. Dateien
- Pfad: `assets/penzilla/states/<spielschlüssel>/base_<struktur>.png`, `overlay_<merkmal>_<stufe>.png`, vorab beschnitten `overlay_<…>@<struktur>.png`; Böden `surfaces/<familie>/overlay_<zustand>.png` (git-ignoriert, aus den ZIPs erzeugt).
- PNG RGBA, transparenter Hintergrund, Maßstab 0,5 (wie Hauptimport), gerade Versätze, später Atlanten je Kategorie.
- Manifest `states.json` (Version 2): Quelle, Kategorie, Profil, Materialanteile, Basen (`canvas_src`, `pad_src`), Overlays (`offset_src`, Größe, Abdeckung, beschnittene/eigene Varianten je Basis), erlaubte Kombinationen, Zeichenreihenfolge, Presets.

## 4. Materialkarte je Asset (umgesetzt)
Jedes Asset erhält eine **Materialkarte** (`living_materials.py`): `outline, glass, roof, plaster, brick, stone, wood (natürlich/lackiert), trim, metal (lackiert/blank), fabric, plant, water`. Quellen in dieser Reihenfolge: automatische Regeln → Ebenennamen der RPG-Pakete (exakt) → Korrekturen je Asset (`living_assets.json`). Jede Materialkarte wird als Bild geprüft (QA-Ordner). Effekte wählen nach Material: Markisen **reißen** (dunkler Spalt + hängender Lappen), Putz **blättert** und zeigt Ziegel, Ziegel bekommen **Treppenrisse**, Holz **spaltet längs der Maserung**, lackiertes Holz/Metall verliert **Lack**, Metall **rostet/verbeult**, Glas **verschmutzt/springt/bricht/wird vernagelt**, Dächer verlieren **Ziegel**.

## 5. Qualitätsprüfung je Charge
1. Kontaktbogen Original + alle Zustände.
2. Prüfliste: Kontur intakt? Farben aus der Palette? Keine Rauschmuster? Oberseite/Seiten korrekt? Anker identisch? Lesbar in echter Spielgröße (iPhone 15 Pro Max, älteres iPhone)? – automatisch durch `living_qa.py` (§9).
3. Godot-Galerie (`?gallery=living`): Darstellung, Draw Calls, Speicher.
4. Abnahme durch den Projektinhaber bei Hauptgebäuden.

## 6. Werkzeuge (umgesetzt)
- Segmentierung ~200× schneller (nur innerhalb der Farbbereiche gelabelt): Rathaus 1,5 s.
- Produktion für die **im Spiel verwendeten** Assets + repräsentative Fahrzeuge/Innenräume (87 Einträge); weitere Assets durch Eintrag in `living_assets.json`.
- Deterministisch (Seed je Asset und Merkmal).

## 7. Unterscheidbarkeit (Ergänzung)
- **Heruntergekommen ≠ Beschädigt**: Verfall (ausgeblichen, Putz ab, vernagelt, Moos, Unkraut, keine Risse/kein Schutt) gegen frischen Schaden (kräftige Farben, Risse, Glasbruch, Dachloch, frischer Schutt).
- **Beschädigt ≠ Schwer beschädigt**: lokale Schäden gegen Teileinsturz mit Balken und Schuttkegel.
- **Ausgebrannt ≠ Zerstört ≠ Ruine**: Mauern stehen/Dach weg/alles verkohlt · Mauerstümpfe/frischer bunter Schutt/Staub · stufiges altes Mauerwerk/kein Dach/verwittert/Gras auf Schutt/Efeu, kein Ruß.
- **Restauriert ≠ Neu**: Reparaturspuren je Grad (Grad 1 dezent, Grad 2 deutlich).
- Prüfung **in echter Spielgröße** (iPhone 15 Pro Max Standard- und kleinster Zoom, älteres iPhone): Anteil sichtbar veränderter Fläche je Zustand und zwischen Zuständen (§9).

## 8. Kombinierbarkeit (Ergänzung)
Zustände = Merkmale (Struktur-Basis + unabhängige Overlays + Shader), siehe [STATE_MATRIX.md](STATE_MATRIX.md) §1a. Keine Grafik je Kombination.

## 9. Produktionskontrolle (Ergänzung)
1. **Pilot** (`--pilot`, 20 repräsentative Assets aller Kategorien) vollständig ausarbeiten.
2. Kontaktbögen + automatische Prüfung (`--qa`): Leinwand/Anker, abgeschnittene Ränder, weiche neue Randpixel, Konturschutz, Pixelrauschen (Flächenanteil), Sichtbarkeit je Zustand (≥ 1 % der Objektfläche sichtbar verändert), Unterscheidbarkeit zwischen Zuständen (≥ 1 %).
3. Sichtprüfung auf Stiltreue, Materialwirkung, Perspektive/Proportionen, Transparenz/Ränder.
4. Erst wenn Pilot ohne Befund: Ausweitung auf alle Assets, erneute Prüfung aller Bögen.
