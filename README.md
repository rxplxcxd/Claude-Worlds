# WORLDS

**Lebendige, persistente Gesellschafts-, Wirtschafts- und Zivilisationssimulation**
2.5D-isometrische Lebens-, Aufbau- und Gesellschaftssimulation · Godot 4.7.2 · GDScript · Web / iOS Safari / PWA

> **Projektstatus: Phase 2 + Paket 2.1, Version 0.4.0** (zur Abnahme durch den Projektinhaber). Phase 3 ist **nicht** freigegeben.
> Spätere Phasen sind dokumentiert, aber **nicht implementiert**.

## Was Phase 1 enthält (implementiert)

| Bereich | Stand |
|---|---|
| Godot-Projekt | Godot 4.7.2, GL Compatibility Renderer, GDScript |
| Leerer Planet | Planet startet ohne Siedlungen (`data/world/genesis.json`); Siedlungen entstehen nur durch Gründung eines Spielers (`WorldState`), keine NPC-only-Siedlungen |
| **Planet & Globus (Phase 2)** | Planet Aurel mit 5 Kontinenten und 157 Regionen (Gelände, Klima, Wasser, Rohstoffe), 3D-Globus mit Zoomstufen, Standortwahl mit Bewertung bei der Gründung – [GEOGRAPHY_SYSTEM](docs/GEOGRAPHY_SYSTEM.md) |
| **Territorien (Paket 2.1)** | Startterritorium 1 × 1 km, 20 km zwischen Gebietsgrenzen (geodätisch), Sperrzonen auf dem Globus, ganzer Planet besiedelbar mit Schwierigkeitsklassen, Auswahl „Beitreten/Gründen“ – [TERRITORY_SYSTEM](docs/TERRITORY_SYSTEM.md) |
| Living Assets (visuell, in Vorbereitung) | Asset-Inventar, Zustandsmatrix, Beispielzustände, eigene VFX, Test-Galerie `?gallery=living` – noch **nicht** im Spiel verwendet – [living_assets](docs/living_assets/README.md) |
| Diagnose | Leistungsanzeige mit 20-s-Messung (F3 / Menü / `?perf=1`) – [PERFORMANCE §7](docs/PERFORMANCE.md) |
| Deine Siedlung „Lichtfeld“ | Beim ersten Start von dir gegründet aus der Vorlage `data/settlement_templates/founding_basic.json`, 26×26 Kacheln, 21 Gebäude (inkl. Marktzeile), Dorfplatz mit Brunnen, Straßen mit Gehwegen, Felder, Teich, Gründerzelt, Vegetation |
| Charakter-Editor | Modulare Penzilla-Figur (Körper, Gesicht, Frisur/Hüte, Oberteile, Hosen/Overalls, Schuhe, Extras, Farben, Outfits), lebendige Vorschau (Atmen, Blinzeln, Drehen, Gehen, Benutzen), Zufall/Rückgängig, Speicherung – [CHARACTER_SYSTEM](docs/CHARACTER_SYSTEM.md) |
| NPCs | Gründungsgemeinschaft (12) mit dauerhaften Namen, Rollen, Arbeitsplätzen und rollentypischer Kleidung; tagsüber am Arbeitsplatz, abends zu Hause, nachts drinnen – [NPC_SYSTEM](docs/NPC_SYSTEM.md) |
| Echtzeit | Uhr synchron zur Ortszeit, Zeitzone/Sommerzeit automatisch, Sonnenstand → Tag/Nacht, Laternen automatisch |
| Stadtbild | Regelbasierte Platzierung: Laternen mit Ausleger über der Straße und Lichtkegel, Hydranten am Bordstein, Schilder, Bushaltestelle, Briefkästen – [SETTLEMENT_SYSTEM §7](docs/SETTLEMENT_SYSTEM.md) |
| Grafik | **Penzilla-Assets integriert**: Giant City Builder (Boden, Straßen/Gehwege mit Autotiling, Gebäude, Pflanzen, Deko), Isometric RPG Buildings (Läden, Zelt), Ultimate Protagonist (modulare Figuren), Basic GUI (HUD, Editor); Stylized Grass als Editor-Hintergrund |
| Darstellung | Isometrisch im Penzilla-Raster (512×292), Y-Sortierung, Kollisionen, Figur hinter Gebäuden sichtbar (weiches Durchsicht-Loch), Tag/Nacht nach Sonnenstand |
| Spielfigur | Tastatur (WASD/Pfeile), virtueller Joystick, Tippen/Klicken = dorthin gehen, 8 Blickrichtungen |
| Kamera | Folgen, Ziehen zum Verschieben, Pinch-/Mausrad-Zoom, Grenzen, Zentrieren |
| Interaktion | Gebäude/Objekte ansehen, NPCs ansprechen (Name, Rolle, Arbeitsplatz), Schwarzes Brett, Ausruhen, Brunnen |
| HUD | Siedlungsname, Region, Uhrzeit & Datum (Ortszeit), Kamera-Buttons, Interaktions-Taste, Menü (Figur bearbeiten, Tageszeit-Vorschau, Zeitzone, Sonnenauf-/-untergang), Hinweise, FPS-Anzeige |
| Web | Export ohne Threads (kompatibel mit GitHub Pages & iOS Safari), PWA (Manifest, Service Worker, Icons) |
| CI/CD | GitHub Actions: Asset-Import → 149 automatische Tests → Web-Export → GitHub Pages (von `main`) |

![Lichtfeld mit Penzilla-Grafik (Chromium, iPhone-Emulation)](docs/screenshots/phase1-iphone-landscape-emulated.png)

**Wichtig – Grafik & Lizenz:** Die gekauften Penzilla-Grafiken liegen **nicht** in diesem öffentlichen Repository. `tools/assets/` lädt sie aus dem privaten MEGA-Ordner (lokal oder in CI über das Secret `MEGA_ASSETS_URL`) und verarbeitet sie nach `assets/penzilla/` (git-ignoriert). Ohne diese Dateien startet das Spiel mit gekennzeichneten Platzhaltern. Details: [docs/ASSET_INVENTORY.md](docs/ASSET_INVENTORY.md). Freie Interior-Assets (CC0) liegen in `assets/interior/`.

## Starten

**Im Browser (nach Deployment):** `https://rxplxcxd.github.io/Claude-Worlds/` – siehe [BUILD_AND_DEPLOYMENT](docs/BUILD_AND_DEPLOYMENT.md) (Pages muss einmalig aktiviert werden, Deployment erfolgt von `main`).

**Lokal (Editor):** Godot 4.7.2 öffnen → `project.godot` importieren → F5.

**Lokal (Kommandozeile):**
```bash
godot --headless --path . --import                         # Import
godot --headless --path . res://tests/test_runner.tscn      # Tests
godot --headless --path . --export-release "Web" build/web/index.html
```

## Steuerung

| | Touch (iPhone) | Desktop |
|---|---|---|
| Gehen | Joystick unten links | WASD / Pfeiltasten |
| Dorthin gehen / Objekt benutzen | Tippen | Linksklick |
| Kamera verschieben | Ein Finger ziehen | Maus ziehen |
| Zoom | Zwei Finger | Mausrad, `+` / `-` |
| Interagieren / NPC ansprechen | Orange Taste unten rechts | `E` / Enter / Leertaste |
| Kamera zentrieren | „Fokus“ | `C` |
| Menü / FPS | „Menü“ | `Esc` / `F3` |
| Weltkarte | „Karte“ | `M` |
| Globus drehen / zoomen | Ziehen / zwei Finger | Ziehen / Mausrad |
| Figur drehen (Editor) | Pfeile neben der Figur, Wischen | Pfeile anklicken, Ziehen |

## Projektstruktur

```
project.godot, export_presets.cfg, icon.svg
scenes/      main/, settlement/, player/          (schlanke Szenen)
scripts/     core/ geography/ globe/ world/ settlement/ buildings/ player/ character/ npc/
             camera/ interaction/ ui/ persistence/
shaders/     occluder, globe, atmosphere, stars
data/        asset_manifest.json, character_catalog.json, world/genesis.json, world/planet/ (gebackener Planet), settlement_templates/
assets/      penzilla/ (generiert, git-ignoriert) · interior/ (CC0-Innenraum-Assets)
web/icons/   PWA-/Home-Screen-Icons
tests/       Headless-Testsuite
tools/       assets/ (MEGA-Download, Penzilla-/Figuren-Import), Icon-Rendering, Browser-Tests (Smoke, Editor, Welt/Zeitzone)
docs/        Design- und Technikdokumentation
.github/workflows/web.yml
```

## Dokumentation

**Verbindlich:** [DESIGN_DIRECTIVES](docs/DESIGN_DIRECTIVES.md) · [TECHNICAL_ASSESSMENT](docs/TECHNICAL_ASSESSMENT.md) · [TERRITORY_SYSTEM](docs/TERRITORY_SYSTEM.md) · [LAW_ENGINE](docs/LAW_ENGINE.md) · [SIMULATION_ARCHITECTURE](docs/SIMULATION_ARCHITECTURE.md)

[ARCHITECTURE](docs/ARCHITECTURE.md) · [CHARACTER_SYSTEM](docs/CHARACTER_SYSTEM.md) · [QA_CHECKLIST](docs/QA_CHECKLIST.md) · [ROADMAP](docs/ROADMAP.md) · [ASSET_INVENTORY](docs/ASSET_INVENTORY.md) · [BUILD_AND_DEPLOYMENT](docs/BUILD_AND_DEPLOYMENT.md) · [PERFORMANCE](docs/PERFORMANCE.md) · [LIVING_ASSETS](docs/living_assets/README.md) · [WORLD_DESIGN](docs/WORLD_DESIGN.md) · [GEOGRAPHY_SYSTEM](docs/GEOGRAPHY_SYSTEM.md) · [SETTLEMENT_SYSTEM](docs/SETTLEMENT_SYSTEM.md) · [PLAYER_SYSTEM](docs/PLAYER_SYSTEM.md) · [NPC_SYSTEM](docs/NPC_SYSTEM.md) · [SOCIAL_SYSTEM](docs/SOCIAL_SYSTEM.md) · [ECONOMY_SYSTEM](docs/ECONOMY_SYSTEM.md) · [TRADE_AND_LOGISTICS](docs/TRADE_AND_LOGISTICS.md) · [POLITICAL_SYSTEM](docs/POLITICAL_SYSTEM.md) · [COUNCIL_SYSTEM](docs/COUNCIL_SYSTEM.md) · [MIGRATION_SYSTEM](docs/MIGRATION_SYSTEM.md) · [CONTRACT_SYSTEM](docs/CONTRACT_SYSTEM.md) · [FIREBASE_SCHEMA](docs/FIREBASE_SCHEMA.md) · [GAMEPLAY_DESIGN](docs/GAMEPLAY_DESIGN.md) · [CHANGELOG](CHANGELOG.md)

Jedes Dokument kennzeichnet Inhalte als **[IMPLEMENTIERT]**, **[GEPLANT]** oder **[OFFEN]**.
