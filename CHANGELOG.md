# Changelog

Format angelehnt an „Keep a Changelog“. Versionen folgen `application/config/version` in `project.godot`.

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
