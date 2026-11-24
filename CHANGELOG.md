# Changelog

Format angelehnt an „Keep a Changelog“. Versionen folgen `application/config/version` in `project.godot`.

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
