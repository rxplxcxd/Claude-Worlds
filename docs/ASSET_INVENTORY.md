# ASSET_INVENTORY

Legende: **[IMPLEMENTIERT]** · **[GEPLANT]** · **[OFFEN]**

## 1. Bereitstellung der gekauften Penzilla-Pakete [IMPLEMENTIERT]

| Schritt | Stand |
|---|---|
| Quelle | Privater MEGA-Ordner des Projektinhabers („Worlds_Assets“, 6 Dateien, 1,1 GB) |
| Download | `tools/assets/fetch_mega_folder.py` – nur HTTPS, Dateinamen bereinigt, keine Pfade aus dem Archiv übernommen; byte-identisch verifiziert |
| Prüfung | Alle ZIPs vollständig gelesen, **keine** unsicheren Pfade (`..`, absolute Pfade), nur PNG/SVG-Bilddateien (+ eine `.blend` im Fremdpaket), nichts ausgeführt |
| Verarbeitung | `tools/assets/import_penzilla.py` liest **nur die ausgewählten Dateien direkt aus den ZIPs** (`tools/assets/penzilla_selection.json`), verkleinert sie (Welt 50 %, GUI 25 %), berechnet Ankerpunkte → `assets/penzilla/` + `import_meta.json` |
| Originale | Bleiben unverändert in den ZIP-Archiven (MEGA) |
| Ergebnis | **83 Dateien, 3,5 MB** (aus 1,1 GB Quellmaterial) |

### Lizenz und öffentliches Repository
Laut Shopseiten: „Royalty free and commercial use – once purchased (see also licence)“; Details in `PenzillaDesign_StandardLicense.pdf` (**nicht** im MEGA-Ordner enthalten → **[OFFEN]**: bitte nachreichen). Übliche Standardlizenzen verbieten die Weitergabe der Rohdateien. Deshalb:
- `assets/penzilla/` steht in `.gitignore` – die gekauften Grafiken liegen **nicht** im öffentlichen Repo.
- CI lädt die Pakete über das Repository-Secret `MEGA_ASSETS_URL` (siehe BUILD_AND_DEPLOYMENT.md) und baut sie in den Web-Build ein (normale Nutzung in einem veröffentlichten Spiel).
- Ohne Secret/Assets startet das Spiel mit markierten Platzhaltern (getestet).

## 2. Paket-Inventar

| Paket (Datei) | Größe | Inhalt (tatsächlich geprüft) | Raster | Verwendung | Status |
|---|---|---|---|---|---|
| **GiantCityBuilder.zip** (Penzilla) | 59 MB, 864 Einträge | Tiles (Gras, Erde, Wasser, Beton, Asphalt, Straßen 9×, Feldwege 9×, Gehwege 9×, Schienen, Rohre), Appartments (54), Houses (163, 8 Farben), Public (82: Rathaus, Wasserwerk, Kraftwerk, Arzt, Feuerwehr, Schule, Hotel, Stadien…), Restaurants (32), Shopping (68), DecorItems (142), Plants (82), Fences (33), Vehicles (116) | 512×292 px pro Kachel | **Außenwelt: Boden, Straßen, Gebäude, Pflanzen, Deko** | ✅ integriert |
| **Isometric_RPG_Buildings.zip** (Penzilla) | 20 MB, 407 Einträge | Zelt, Kleines Haus 2×2, Laden 2×2, Haus 3×3 – in Ebenen zerlegt (Wände, Balken, Dächer, Fenster, Türen in Holz-/Dachvarianten), Icons | 800×486 px | **nicht verwendet**: anderes Raster (Verhältnis 1,646 statt 1,753) → würde nicht exakt auf den Giant-City-Builder-Boden passen. Ebenen eignen sich später für „Figuren im Haus“ | dokumentiert |
| **Ultimate_Protagonist.zip** (Penzilla) | 998 MB, 5 582 Einträge | 8 fertige Figuren (Character0–7) + Baukasten in Ebenen; Animationen Idle, Walk, Run, Interact, Sit, Dig, Fish, Swing, Damage, Die, GetUp … jeweils mit Werkzeugvarianten | Frame 460×460 px, 5 Richtungsreihen (S, SW, W, NW, N; Ost = gespiegelt) | **Spielfigur: Character1** (Entdecker mit Hut) – Idle 8, Walk 6, Run 4, Interact 3 Frames | ✅ integriert |
| **Basic_GUI_Bundle.zip** (Penzilla) | 3 MB, 543 Einträge | Boxen/Banner, Text-Buttons, Icon-Buttons (Rund/Eckig/Kreis in 6 Farben), Icons (Menü, X, Home, Pause, Audio, Herzen, Sterne, Münzen…), Slider/Scrollbars – PNG + SVG | – | **HUD**: 9-Slice-Panels und Buttons, Menü-/Schließen-Icons, orange Aktionstaste | ✅ integriert |
| **Top-Down_Retro_Interior.zip** (Penzilla) | 60 KB, 6 Sheets | 39 Möbel (Wohnzimmer, Küche, Bad: Wanne/WC/Waschbecken, Regale, Teppiche, Uhr, Kamin), 64 Kleinteile, 4 Böden/Tapeten, Treppen, Türen, Fenster | 16×16 px (Pixel Art, Top-Down) | Innenräume (ab begehbaren Gebäuden) | geprüft, noch nicht im Spiel |
| **Stylized_GrassAndDirt.zip** | 20 MB | 3D-PBR-Materialien (Basecolor/Normal/Height/AO …, JPEG) + Blender-Datei; **Hersteller unbekannt**, kein Penzilla | – | **nicht verwendet**: Außenwelt nur Penzilla (Art Direction); 3D-Materialien passen nicht zur 2D-Isometrie | ausgeschlossen |

## 3. Verwendete Dateien (Auswahl → logischer Schlüssel)
Vollständige Liste: `tools/assets/penzilla_selection.json`, Zuordnung: `data/asset_manifest.json`.

| Bereich | Penzilla-Quelle | Schlüssel |
|---|---|---|
| Boden | Tiles/Grass, Dirt, LowDirt (Felder, abgesenkt), Water, Concreet (Platz) | `exterior.tile.*` |
| Straßen | Tiles/Road_Tile1–9 (Autotiling + Spiegelung) | `exterior.tile.road` |
| Feldwege | Tiles/GrassRoad_Tile1–9 | `exterior.tile.path` |
| Gemeindehaus | Public/Public_Townhall | `exterior.building.town_hall` |
| Handelsposten | Shopping/Groceries_Market | `…trade_post` |
| Wasserwerk | Public/Industrial_WaterPlant | `…water_works` |
| Sanitätsstation | Public/Doctor_Office | `…clinic` |
| Notfall-/Brandschutz | Public/Emergency_FireStation | `…emergency_post` |
| Energiestation | Public/Industrial_PowerPlant | `…energy_station` |
| Werkstatt | Shopping/Workplace_Handyman_OneFloor | `…workshop` |
| Gemüsehof | Shopping/Shop_Veggies_OneFloor | `…farm_shop` |
| Lager & Wertstoffhof | Public/Recycling | `…depot` |
| Dein Haus | Houses/Green/House_Type11 | `…player_home` |
| Wohnhäuser | Houses/{Blue,Red,Yellow,White,Brown,Grey}/House_Type{1,5,3,7,10,12} | `…house` (6 Varianten) |
| Platz | Public/Park_Fountain (Dorfbrunnen), DecorItems/SignMap (Schwarzes Brett), Seat, StreetLampOn/Off, AppleCrate, Cart2, Boxes1 | `exterior.prop.*` |
| Natur | Plants/Tree1,3,5,7,9,11,13,16, Pine1,3,5, Plant3/5/9/11, Weeds1/3 | `exterior.prop.tree/bush/crop` |
| Infrastruktur | ElectricalBox1, ElectricalTower, Watertower, Mailbox, TrashCan, FireHydrant, WheelBarrel, Houses/Garden_Rustic | `exterior.prop.*` |
| Spielfigur | AnimationSheets/PremadeCharacters/Character1 (Idle, Walk, Run, Interact) | `character.player` |
| HUD | IconButton_Large_Background/Rounded/Blue/Orange_Rounded, Icon_Small_WhiteOutline_Menu/X/Pause | `ui.*` |

## 4. Art Direction [IMPLEMENTIERT]
- **Außenwelt ausschließlich Penzilla:** technisch erzwungen (`AssetRegistry`: `exterior.*` nur Hersteller „penzilla“, getestet). Alle sichtbaren Außenobjekte stammen aus Giant City Builder.
- **Innenräume:** andere lizenzierte Hersteller erlaubt (Test vorhanden).
- **Bewusst nicht verwendet:** Isometric RPG Buildings (anderes Raster), Stylized_GrassAndDirt (Fremdhersteller, 3D).
- **Lücken in der Außenwelt (kein Fremdstil eingeführt):**
  - Solarfeld/Solarmodule – Giant City Builder enthält keine → ersetzt durch Kraftwerk + Stromkästen/Strommast.
  - Gewächshaus – ersetzt durch „Gemüsehof“ (Shop_Veggies) + Felder (LowDirt + Pflanzen).
  - Lösungsvorschlag für echte Lücken: weitere Penzilla-Pakete (z. B. *Medieval City Builder*, *Free City Builder*, laut Hersteller kompatibel) – Kauf nur nach Zustimmung.

## 5. Interior-Assets: Recherche, Lizenzprüfung, Download

Lizenzen am **24.11.2026 direkt auf den Originalseiten geprüft**.

| Paket | Quelle | Stil | Lizenz (geprüft) | Status |
|---|---|---|---|---|
| **Penzilla Top-Down Retro Interior** (gekauft) | penzilla.itch.io/top-down-retro-interior | Pixel Art 16×16 | Penzilla Standard | vorhanden (privat) – Wohnzimmer, Küche, Bad, **kein Bett** |
| **Kenney Roguelike Indoors** | kenney.nl/assets/roguelike-indoors | Pixel Art 16×16, warme Brauntöne – passt sehr gut zum Retro-Interior | **CC0** (`License.txt`) | ✅ heruntergeladen → `assets/interior/kenney_roguelike_indoors/` – **Betten**, Tische, Stühle, Theken, Herde, Regale, Teppiche |
| **Kenney Furniture Kit** | kenney.nl/assets/furniture-kit | 3D-Renders, isometrisch, 4 Richtungen | **CC0** (`License.txt`) | ✅ heruntergeladen → `assets/interior/kenney_furniture_kit/isometric/` (120 Möbel × 4): Büro (Schreibtisch, PC, Bürostuhl), Bad, Küche, Schlafzimmer, Wohnzimmer |
| **Interior spritesheet 16×16** (InThePixel) | opengameart.org/node/114339 | Pixel Art 16×16 | **CC0** | ✅ heruntergeladen → `assets/interior/opengameart_interior_16x16/` |
| **MetroCity – Free Top Down Interior** (JIK-A-4) | jik-a-4.itch.io/metrocity | Pixel Art | **CC0 v1.0** (Seite geprüft) | ⚠️ automatischer Download von itch.io abgelehnt („invalid key“) → manuell herunterladen (`Interior.rar`, 180 KB) |
| Modern Interiors Free Pack (SOMETHING) | a-something.itch.io/dev-essentials-modern-interiors | Pixel Art 16×16, Apartment | kommerziell erlaubt, **keine Weitergabe** | nicht heruntergeladen (nur über privaten Weg nutzbar) |
| Pixel Interior (bitglow) | bitglow.itch.io/pixel-interior | Pixel Art 16×16 | kommerziell erlaubt, **keine Weitergabe** | nicht heruntergeladen |
| LimeZu Modern Interiors | limezu.itch.io/moderninteriors | Pixel Art 16×16, sehr umfangreich (Büro, Krankenhaus, Schule, Läden …) | kostenpflichtig ab 1,50 USD, **Credits Pflicht**, keine Weitergabe | **Kaufempfehlung** (nur nach Zustimmung) |
| Penzilla Ultimate Interior Pack | penzilla.itch.io/ultimate-interior-pack | isometrisch, Penzilla | kostenpflichtig (~10 USD) | Alternative für isometrische Innenräume im Penzilla-Stil (nur nach Zustimmung) |

**Weiterhin ohne freie Quelle:** Krankenhaus, Schule, Fabrik/Lager, Werkstatt-Innenräume → LimeZu Modern Interiors deckt diese ab (Kauf nach Zustimmung).

`assets/interior/` enthält nur CC0-Dateien (öffentlich erlaubt) und ist per `.gdignore` vom Import ausgeschlossen, bis Innenräume gebaut werden.

## 6. Selbst erstellte Dateien
| Datei | Verwendung |
|---|---|
| `icon.svg`, `web/icons/*.png` | App-/PWA-Icons (projekt-eigen) |
| Prozedurale Platzhalter (`IsoPainter`, `GroundLayer`, `Building`, `Prop`, `PlayerVisual`) | Fallback ohne Penzilla-Dateien |
