# Changelog

Format angelehnt an „Keep a Changelog“. Versionen folgen `application/config/version` in `project.godot`.

## [0.5.0] – Phase 3: Living World

### Hinzugefügt
- **Simulation des Siedlungslebens** (`scripts/sim/`, `data/sim/living_world.json`): persistente NPC-Identitäten (Persönlichkeit, Alter, Beruf mit Fertigkeit), 5 Bedürfnisse, 9 Aktivitäten, Berufe mit Schichten, Utility AI, ereignisgesteuertes Fortschreiben (`advance`), Siedlungszeitzone.
- **Navigation**: Raster-A* (AStarGrid2D), Orte (Türen, Dorfplatz, Grün) mit Stehplätzen, gecachte Wegzeiten; NPCs gehen sichtbar über Gehwege und queren Straßen.
- **Simulations-LOD**: S0 (im Bild, detailliert, nach Grafikprofil begrenzt) / S1 (nur Daten); Darstellung als Funktion von Zustand und Zeit → nie veraltet, kein Nachsimulieren; Nachholen nach Abwesenheit beim Laden.
- **Interaktionen**: Live-Infokarte und „Grüßen“ (persistente Wirkung), Gruppen und Sprechblasen auf Platz/Grün/Läden, Arbeits- und Benutzen-Animationen.
- **Visuelle Folgen**: `VisualEventRouter` – Kaminrauch/Werkstattfunken aus dem aktuellen Zustand; Simulationsereignisse → dauerhafte Living-Assets-Zustände (`record.visual_states`).
- **Grafikprofile** Ultra/Hoch/Leistung (automatisch erkannt, nur Darstellung).
- **Lizenz**: Penzilla-Pflichtnennung und vollständige Bearbeitungsliste im Menü („Mitwirkende & Lizenzen“) und in `CREDITS.md`; verbindliche Lizenzauswertung.
- **Cooked FX** (Cozy Chunky) bewertet: privater Import, Testgalerie `?gallery=cookedfx`, Entscheidungsvorlage.
- Tests: 185 Prüfungen (Determinismus, Ein-Sprung = viele Schritte, Schichten, Nachtruhe, Navigation, Speichern/Laden, Nachholen, LOD-Invarianz, 1 000 NPCs, Interaktion, Router, Credits).

### Geändert
- Speicherschema 4 (Migration automatisch). NPC-Präsenz nach fester Uhrzeit (Phase 1) durch die Simulation ersetzt.

## [0.4.2] – Living Assets Schritt G: Materialerkennung, kombinierbare Zustände, Serienproduktion

### Hinzugefügt
- **Materialerkennung** `tools/assets/living_materials.py` (Glas, Dach, Putz, Ziegel, Stein, Holz natürlich/lackiert, Zierteile, Metall, Stoff, Pflanze, Wasser) aus Farbe, Lage, Form, Textur und Kontext; RPG-Läden exakt über Ebenennamen; Korrekturen je Asset.
- **Kombinierbare Merkmale** `tools/assets/living_traits.py`: Strukturbasen (Teileinsturz, ausgebrannt, zerstört, Ruine; umgestürzt, verbrannt, Wrack, trocken, abgestorben, Brunnen leer/veralgt/gefroren …) + unabhängige Overlays (Abnutzung 2/3, Schaden 1/2, Brand 1/2, Bewuchs 1/2, Reparaturspuren 1/2, Schnee) mit materialgerechten Effekten; Overlays je Basis vorab beschnitten.
- **Serienproduktion** `tools/assets/make_living_states.py` für 87 Einträge (alle Spiel-Assets aller Kategorien + Fahrzeuge + Innenraum-Blätter), Profile nach Funktion (`tools/assets/living_assets.json`), Bodenfamilien mit gemeinsamen Overlays.
- **Produktionskontrolle** `tools/assets/living_qa.py`: Kontaktbögen in voller und echter Spielgröße (iPhone 15 Pro Max, älteres iPhone), automatische Prüfungen (Leinwand/Anker, Ränder, Kantenpixel, Konturen, Rauschen, Sichtbarkeit und Unterscheidbarkeit in Spielgröße).
- **Laufzeit-Bausteine** (noch nicht im Spiel verdrahtet): `VisualState` (dauerhaft speicherbarer visueller Zustand, nur ereignisgesteuert, kein Verfall durch Abwesenheit) und `LivingComposer` (Basis + Overlays + Shader, Qualitätsprofile Ultra/Hoch/Leistung).
- Galerie `?gallery=living` nutzt den Composer, Profilwahl `&profile=…`; Diagnoseberichte tragen `context` (testgalerie/spiel).
- Lizenzdokumentation `docs/living_assets/LICENSES.md`.
- Tests: 164 Prüfungen (+15 Living Assets).

### Geändert
- Produktionsstandard bestätigt und ergänzt; Zustandsmatrix um Merkmalsmodell und Zustände je Funktion erweitert.

### Nicht geändert
- Spielmechanik und Darstellung im Spiel sind unverändert.

## [0.4.1] – Living Assets & Environmental Storytelling (visuell, kein Gameplay)

### Hinzugefügt
- **Asset-Inventar** aller 7 901 Dateien der Penzilla-Pakete (+ CC0-Interior): `docs/living_assets/asset_inventory.csv` (Kategorie, Quelle, Maße, Perspektive, Animation, Verwendung, Godot-Kompatibilität, Lizenz, Zustandsgruppe), erzeugt von `tools/assets/inventory.py`.
- **Zustandsmatrix** (12 Gebäudezustände, Gruppen für Vegetation, Böden, Stadtmöbel, Fahrzeuge, Innenräume) – `docs/living_assets/STATE_MATRIX.md`.
- **Variantengenerator** `tools/assets/living_states.py` + `make_living_samples.py` (in 0.4.2 ersetzt) (dreistufig: Shader / Overlay / Vollvariante); Ergebnisse privat in `assets/penzilla/states/` (git-ignoriert).
- **Eigene VFX im Penzilla-Stil** `assets/vfx/` (Feuer, Rauch, Funken, Regen, Schnee, Staub, Blätter, Spritzer, Reparatur, Belohnung, Trümmer) und Verschleiß-Shader `shaders/living_wear.gdshader`.
- **Test-Galerie** `?gallery=living` (nur Web, nur mit URL-Parameter) zur technischen Prüfung.
- Dokumente: Produktionsstandard (Vorschlag), Qualitätsprüfung, VFX-Quellen/Lizenzen, technische Integration inkl. Qualitätsprofile und Performance, Prioritätenliste.

### Nicht geändert
- Spielmechanik und Darstellung im Spiel sind unverändert; Zustände werden noch nirgends im Spiel verwendet.

## [0.4.0] – Paket 2.1: Territorien, 20-km-Regel, Besiedelbarkeit, Diagnose

### Hinzugefügt
- **Eigene Territorien** statt ganzer Regionen: Startterritorium genau 1 × 1 km (sphärisches Polygon, Ost/Nord ausgerichtet, auch an den Polen), mit Index-Zellen, Version, Historie, Status; Siedlungsfläche (`settlement_area`) getrennt gespeichert.
- **20 km zwischen Territoriumsgrenzen**, geodätisch (Punkt–Bogen-/Polygonabstand auf der Kugel, korrekt über Datumsgrenze und Pole); Überlappungsprüfung als Invariante.
- **Räumlicher Index** (Würfel-Kugel-Quadtree, Ebene 8 ≈ 24 km).
- **Sperrzonen** und Territorien exakt im Globus-Shader; Zoom bis ~120 km Höhe; Kamera bis 89°.
- **Ganzer Planet besiedelbar**: keine Breiten-/Biom-Sperren mehr; Schwierigkeitsklassen leicht/mittel/schwer/extrem mit Anforderungen; extrem nur mit Bestätigung.
- **Auswahl „Beitreten / Gründen“** nach dem Editor; Beitreten sichtbar als „Mehrspieler – noch nicht verfügbar“.
- **Eine aktive Gründung pro Spieler.**
- **Polartag/Polarnacht** im Sonnenmodell und im Menü.
- **Diagnose (`PerfMonitor`)**: Live-Werte, 20-s-Messung, Aufschlüsselung der Draw Calls, `tools/perf_measure.js`, QA-Parameter `?qa_quickstart=1`.
- Tests: 149 Prüfungen.

### Geändert
- Spielstände: Schema 3; Phase-2-Regionsansprüche werden einmalig in 1-km²-Territorien umgewandelt (gleiche ID, Historie).
- Breitengrad-Berechnung über `atan2` (exakt nahe den Polen); Planet neu gebacken (eine Regionsmitte um 0,001° verschoben, Zellen identisch).

### Gemessen
- Siedlung: 448 Draw Calls, davon 357 Boden; ~380 MB Texturspeicher, überwiegend Figuren-Ebenen → Optimierungsvorschläge O1–O9 (PERFORMANCE.md §7.3).

## [0.3.1] – Designvorgaben und technische Bewertung (nur Dokumentation)

### Hinzugefügt
- `docs/DESIGN_DIRECTIVES.md`: verbindliche Vorgaben des Projektinhabers vom 24.11.2026 (Regionen ≠ Siedlungsgrenze, ganzer Planet besiedelbar, 20 km zwischen Territoriumsgrenzen, 1 × 1 km Start, Beitreten/Gründen, Gestaltungsfreiheit, Eigentum/Befugnisse, Gesetzes-Engine, mehrstufige Simulation, 60 FPS).
- `docs/TECHNICAL_ASSESSMENT.md`: Bewertung des Codes (unterstützt, fehlend, Architekturänderungen A1–A12, Risiken, Exploits, Mehrspieler-Folgen, Phasenvorschlag).
- `docs/TERRITORY_SYSTEM.md`, `docs/LAW_ENGINE.md`, `docs/SIMULATION_ARCHITECTURE.md`.

### Geändert
- GEOGRAPHY_SYSTEM (§4 als überholt markiert, §8 Hierarchie/Kapazität), SETTLEMENT_SYSTEM (§8 Ausgangszustand, §9 Gestaltungsfreiheit), PLAYER_SYSTEM (§3a Beitreten/Gründen), NPC_SYSTEM, POLITICAL_SYSTEM, WORLD_DESIGN, PERFORMANCE (§6 Weg zu 60 FPS, Korrektur einer zu optimistischen Aussage zum Boden), ARCHITECTURE (vorgeschlagene ADR-15…20), FIREBASE_SCHEMA, ROADMAP.
- **Kein Code geändert.** Die im Code noch aktiven Phase-2-Regeln (±62°, 300 km, Region als Gebiet) sind als Abweichung dokumentiert (DESIGN_DIRECTIVES §10).

## [0.3.0] – Phase 2: World Geography

### Hinzugefügt
- **Planet Aurel:** deterministischer Generator (Höhe auf der Kugel, Ozeane/Seen, Klima, 70 Flüsse, Biome, 5 Kontinente, 157 Voronoi-Regionen mit Gelände, Klima, Wasserzugang, Rohstoffen, Namen); einmal gebacken nach `data/world/planet/` (630 KB), Test prüft byte-genaue Übereinstimmung.
- **Koordinaten:** `Geo` (Breite/Länge ↔ Kugel, Großkreisdistanz).
- **Autoload `Geography`:** Planet bei Bedarf laden, Standortbewertung (Wasser, Klima, Boden, Rohstoffe, Gelände, Nachbarschaft; Regeln: kein Wasser/Eis/Hochgebirge, ±62°, 300 km Abstand, keine fremde Region), bester freier Ort.
- **Globus:** 3D-Kugel mit eigenem Shader (Küstenlinie, Regionsgrenzen, Gebiete, Hervorhebung), Atmosphäre, Sterne; Drehen, Zoomen, Antippen; Zoomstufen planetar/kontinental/regional/lokal; Beschriftungen und Siedlungsmarker; Infotafel mit Regionsdaten.
- **Gründung auf dem Globus:** Ort wählen, Bewertung, Name, „Vorschlag“, „Hier gründen“.
- **Territorien:** Gründung beansprucht die Region; Anzeige auf dem Globus; Invarianten geprüft.
- HUD-Taste „Karte“ (und M); Sonnenstand folgt der Breite der Siedlung.
- Tests: 118 Prüfungen (u. a. Planet, Determinismus, Koordinaten, Standortregeln, Migration, Auswahl, Zoomstufen, Gründung, Gebiet).

### Geändert
- Gründungsablauf: Charakter → Globus → Siedlung (statt automatischer Gründung an festem Ort).
- Alte Spielstände werden einmalig auf den besten freien Ort gesetzt (Hinweis beim Laden).

## [0.2.0] – Charakter-Editor, NPC-Rollen, Echtzeit, Stadtbild

### Hinzugefügt
- **Modularer Charakter** aus dem Penzilla-Ultimate-Protagonist-Baukasten (`CharacterCatalog`, `CharacterComposer`, `CharacterRig`): Körper, Gesicht, 10 Frisuren + Mütze/Strohhut, Oberteile, Ärmel, Hosen, Overalls, Schuhe, Taschen, Schals, Fliegen, Ketten, Werkzeuge; Farbvarianten durch Einfärbung; Blinzeln; 8 Richtungen.
- **Charakter-Editor** vor der Gründung und über „Figur bearbeiten“: lebendige Vorschau (Atmen, Drehen, Gehen, Benutzen), Karten mit der eigenen Figur, Farbfelder, 6 Outfits, Zufall, Rückgängig, Zurücksetzen, Name; responsiv; gespeichert im Profil.
- **NPC-Gründungsgemeinschaft** (12 NPCs, 8 Rollen) mit dauerhaften Namen, Arbeitsplätzen, Wohnungen und rollentypischer Kleidung; Präsenz nach Tageszeit; ansprechbar.
- **Echtzeituhr** mit UTC-Basis, automatischer IANA-Zeitzone und Sommerzeit, Sonnenstandsmodell, Tageszeit-Vorschau (Menü/URL); Zeitzone wird bei der Gründung gespeichert.
- **Stadtbild v2**: Gehwege an allen Straßen, `StreetPlanner` mit Platzierungsregeln und Validierung (Laternen, Hydranten, Schilder, Bushaltestelle, Briefkästen), Auslegerlaternen aus Penzilla-Teilen mit Lichthof, Lichtkegel und Lichtfleck.
- **Verdeckung**: weiches Durchsicht-Loch um die Figur hinter Gebäuden/Bäumen.
- **Isometric RPG Buildings**: Marktzeile (Bäckerei, Gemischtwaren, Schmiede) aus Ebenen zusammengesetzt und auf das City-Builder-Raster abgebildet; Gründerzelt.
- Docs: CHARACTER_SYSTEM.md, QA_CHECKLIST.md; Zeitmodell, Platzierungsregeln, NPCs, ADR-8…11.
- Tests: 82 Prüfungen (u. a. Zeitzonen, Platzierungsregeln, Verdeckung, NPC-Rollen/Plätze/Präsenz/Persistenz).

### Geändert
- Spielgeschwindigkeit und Zeitsprung entfernt (Echtzeit); „Ausruhen“ ist ein Moment ohne Zeitsprung.
- Gründungsvorlage v2 (26×26, Kreuzung am Dorfplatz, Seitenstraße, 21 Gebäude).
- Blickrichtungen der Penzilla-Sheets korrigiert (Reihen S, SO, O, NO, N; Westen gespiegelt).

### Behoben
- „Figur bearbeiten“ → „Fertig“ aktualisierte die Figur in der Welt nicht (fehlende Weiterleitung `Player.refresh_appearance`).
- Editor im Bearbeiten-Modus (Querformat): „Fertig“ wurde durch „Abbrechen“ aus dem Bild geschoben, Reiter „Outfits“ war verdeckt → Aktionen brechen bei Bedarf in eine zweite Zeile um, Reiter umbrechen statt versteckt zu scrollen.
- Menütext „gelbe Taste“ → „orange Taste“.

## [0.1.2] – Penzilla-Assets integriert

### Hinzugefügt
- Asset-Pipeline: `tools/assets/fetch_mega_folder.py` (MEGA-Ordner, nur HTTPS) und `tools/assets/import_penzilla.py` (Auswahl, Verkleinerung, Ankerpunkte). Ergebnis `assets/penzilla/` (83 Dateien, 3,5 MB) ist git-ignoriert.
- CI lädt die Assets über das Secret `MEGA_ASSETS_URL`, cached das Ergebnis, Platzhalter-Fallback ohne Secret.
- Penzilla Giant City Builder: texturierter Boden, Straßen und Feldwege mit Autotiling (9 Varianten + Spiegelung), 18 Gebäude, Bäume, Büsche, Felder mit Pflanzen, Brunnen, Laternen (an/aus + Licht), Deko.
- Penzilla Ultimate Protagonist (Character1): 8 Richtungen, Idle/Walk/Interact-Animation.
- Penzilla Basic GUI: 9-Slice-Panels und Buttons, Icons, orange Aktionstaste; Credit im Menü.
- CC0-Interior-Assets (Kenney Roguelike Indoors, Kenney Furniture Kit, OpenGameArt) inkl. Lizenzdateien in `assets/interior/`.

### Geändert
- Projektion an das Penzilla-Raster angepasst (128×73 Welt-Einheiten = 512×292 px).
- Gründungsvorlage neu gestaltet (24×24 Kacheln, einspurige Straßen, Platz mit Brunnen, Gebäudefronten zur Straße, Freiflächen für Wachstum).
- Mipmaps für verkleinerte Sprites; HUD-Layout im Hochformat korrigiert.

## [0.1.1] – Designänderung „Leerer Planet“

### Geändert
- **Der Planet startet leer** (`data/world/genesis.json`, 0 Siedlungen). Siedlungen entstehen ausschließlich durch Gründung eines menschlichen Spielers; reine NPC-Siedlungen sind ausgeschlossen.
- Neuer Autoload `WorldState` (Siedlungsregister, Gründungsregel, lokale Speicherung `user://worlds_world.json`).
- Lichtfeld ist jetzt eine **Gründungsvorlage** (`data/settlement_templates/founding_basic.json`); beim ersten Start gründet der Spieler seine Siedlung (generierte `stl_`-ID, Gründer = Spieler).
- Texte überarbeitet: „Dein Haus“, Schwarzes Brett nennt dich als Gründer, keine Hinweise auf bereits existierende Siedlungen/Händler/Nachbarn.
- HUD: Gründungsmeldung beim ersten Start, „Willkommen zurück“ danach, Status „von dir gegründet“.
- Tests: 55 Prüfungen (u. a. leerer Planet, Ablehnung von Gründungen ohne Mensch, Persistenz).
- Dokumentation an die Grundregel angepasst (WORLD_DESIGN §1 ersetzt Masterprompt Abschnitt 2).

## [0.1.0] – Phase 1: World Foundation (zur Abnahme)

### Hinzugefügt
- Godot-4.7.2-Projekt mit GL Compatibility Renderer, Hoch-/Querformat-Anpassung (kurze Bildschirmseite = 540 logische Pixel).
- Autoloads: `EventBus`, `GameClock` (Spielzeitmodell), `AssetRegistry` (Manifest + Art-Direction-Wächter), `LocalProfile` (lokale Spieler-ID, Einstellungen, Spielzeit).
- Datengetriebene Startsiedlung „Lichtfeld“ mit Validierung (Überlappung, Untergrund, Spawn, IDs).
- Isometrische Darstellung: Boden, 16 Gebäude, Requisiten, gestreute Vegetation, Kollisionen, Y-Sortierung, Tag/Nacht.
- Spielfigur mit Tastatur-, Joystick- und Tipp-Steuerung; Platzhalterfigur mit Laufanimation und 8 Blickrichtungen.
- Kamera mit Folgen, Verschieben, Zoom (Pinch, Mausrad, Buttons, Trackpad) und Grenzen.
- Interaktionssystem (Fokus, Interaktions-Taste, Info-Panels, Aktionen „Ausruhen“, „Wasser trinken“, Schwarzes Brett).
- HUD mit Menü, Toasts, FPS-Anzeige, Asset-Status.
- Web-Export ohne Threads, PWA (Manifest, Service Worker, Icons, iOS-Meta-Tags).
- GitHub-Actions-Workflow (Build, Tests, Artefakt, Pages-Deployment von `main`).
- Headless-Testsuite (41 Prüfungen) und lokaler Browser-Smoke-Test (`tools/serve_and_shoot.js`).
- Vollständige Dokumentation (21 Dokumente).

### Bekannte Einschränkungen
- Penzilla-Assets nicht verfügbar (Download blockiert) → Platzhaltergrafik.
- Kein Pfadfinden (gerade Linie mit Gleiten an Hindernissen).
- iPhone-Test durch den Projektinhaber steht aus.
