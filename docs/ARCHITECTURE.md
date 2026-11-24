# ARCHITECTURE

Legende: **[IMPLEMENTIERT]** in Phase 1 vorhanden und getestet · **[GEPLANT]** konzeptionell festgelegt · **[OFFEN]** noch zu entscheiden.

## 1. Leitprinzipien

1. **Daten ≠ Darstellung.** Weltzustand liegt in reinen Datenklassen/JSON (`SettlementData`), Szenen bauen sich daraus auf. Dieselben Daten können später aus Firestore oder vom Simulationsserver kommen.
2. **Nur die aktive Siedlung als Szene.** Globus/Weltkarte ist eine eigene Szene (seit Phase 2); entfernte Siedlungen existieren nur als Daten (Simulations-LOD).
3. **Lose Kopplung.** UI ↔ Welt nur über `EventBus`-Signale und Dictionaries – nie direkte Knotenreferenzen.
4. **Server-tauglich.** Aktionen laufen über einen Service (`InteractionService.run_action`), der später zur Anfrage an den autoritativen Server wird.
5. **Kleine Skripte.** Kein Gott-Manager; jedes Skript hat eine Aufgabe.

## 2. Laufzeitstruktur [IMPLEMENTIERT]

```
Main (scripts/core/main.gd)                 Ablauf: Figur erstellen → Globus (Gründung) → Welt; Orientierung
├─ Settlement (SettlementScene)             lokale Siedlung, LOD "aktiv"
│  ├─ DayNight (CanvasModulate)             Umgebungsfarbe aus dem Sonnenstand
│  ├─ Ground (GroundLayer)                  Kacheln, einmal gezeichnet
│  ├─ GroundLights (Node2D, additiv)        Lichtkegel der Laternen auf dem Boden
│  ├─ Objects (Node2D, y_sort)              Gebäude, Props, Laternen, NPCs, Spieler
│  ├─ Bounds (StaticBody2D)                 Kartenrand, Wasser
│  ├─ InteractionService
│  └─ Camera (CameraRig)
├─ HUD (CanvasLayer, Hud)
│  └─ Root ─ GestureSurface (hinten) · Info · Uhr/Buttons · Joystick · Interact · Panels
├─ Globe (GlobeScreen)                      nur bei Gründung / „Karte“; Siedlung derweil angehalten
│  ├─ GlobeView (Node3D)                    Kugel, Atmosphäre, Sterne, Orbit-Kamera
│  └─ CanvasLayer 20 ─ Gesten · GlobeLabels · Kopfzeile · Zoom · Infotafel
└─ CanvasLayer 30 ─ CharacterEditor        nur bei Erstellung / „Figur bearbeiten“
Autoloads: EventBus · GameClock · AssetRegistry · LocalProfile · Geography · WorldState · CharacterCatalog · CharacterComposer
```

## 3. Module

| Ordner | Inhalt | Status |
|---|---|---|
| `scripts/core` | `event_bus`, `game_clock` (Echtzeit/Zeitzonen/Sonne), `asset_registry`, `ids`, `input_actions`, `main` | IMPLEMENTIERT |
| `scripts/geography` | `Iso` (Raster↔Welt), `Geo` (Breite/Länge), `PlanetGenerator`, `PlanetData`, `PlanetTextures`, `planet_bake.gd`, Autoload `Geography` (Planet laden, Standortbewertung) | IMPLEMENTIERT – GEOGRAPHY_SYSTEM.md |
| `scripts/globe` | `GlobeScreen` (Modi Gründen/Erkunden, Infotafel), `GlobeView` (3D, Kamera, Auswahl, Zoomstufen), `GlobeLabels` | IMPLEMENTIERT |
| `scripts/settlement` | `SettlementData` (Vorlage + Gründungsdatensatz, Validierung), `SettlementScene`, `StreetPlanner` (Platzierungsregeln Straßenmobiliar) | IMPLEMENTIERT |
| `scripts/world` | `WorldState` (Siedlungsregister, Gründungsregel), `GroundLayer`, `Prop`, `StreetLamp` (Auslegerlaterne + Licht), `IsoPainter` (Platzhalter) | IMPLEMENTIERT |
| `scripts/buildings` | `Building` (inkl. Verdeckungs-Fläche) | IMPLEMENTIERT |
| `scripts/character` | `CharacterCatalog` (Daten/Regeln), `CharacterComposer` (GPU-Zusammensetzen), `CharacterRig` (Animation, Richtungen, Blinzeln) | IMPLEMENTIERT – siehe CHARACTER_SYSTEM.md |
| `scripts/npc` | `NpcRoster` (Gründungsgemeinschaft, Platzwahl), `Npc` (Präsenz, Idle, Karte) | IMPLEMENTIERT (Präsenz) · Simulation GEPLANT Phase 3 |
| `scripts/player` | `Player`, `PlayerVisual` | IMPLEMENTIERT |
| `scripts/camera` | `CameraRig` | IMPLEMENTIERT |
| `scripts/interaction` | `Interactable`, `InteractionService` | IMPLEMENTIERT |
| `scripts/ui` | `Hud`, `CharacterEditor`, `CharacterThumb`, `GestureSurface`, `TouchJoystick`, `TouchButton`, `UiTheme` | IMPLEMENTIERT |
| `scripts/persistence` | `LocalProfile` (inkl. Figur) | IMPLEMENTIERT (lokal) |
| `shaders` | `occluder.gdshader` (Durchsicht-Loch), `globe.gdshader`, `atmosphere.gdshader`, `stars.gdshader` | IMPLEMENTIERT |
| `data/world/planet` | gebackener Planet (`planet.json`, `planet_cells.bin`) | IMPLEMENTIERT (generiert) |
| `ai`, `economy`, `politics`, `firebase`, … | – | GEPLANT (werden erst mit ihrer Phase angelegt) |

## 4. Zeitmodell [IMPLEMENTIERT]

WORLDS läuft in **Echtzeit**. Es gibt kein Vorspulen und keine Spielgeschwindigkeit mehr (beides wurde mit Version 0.1.1 entfernt). Vier Begriffe sind strikt getrennt (`scripts/core/game_clock.gd`):

| Begriff | Bedeutung | API |
|---|---|---|
| **UTC** | Einzige gemeinsame Zeitbasis. Gemeinsame Ereignisse, Verträge, Gründungszeitpunkte werden in UTC gespeichert und verglichen. | `get_utc_unix()` |
| **Lokaler Versatz** | Aktueller UTC-Versatz des Spielers inkl. Sommerzeit. Im Browser über `Intl` (IANA-Name, z. B. `Europe/Berlin`) und `getTimezoneOffset()` (Januar/Juli-Vergleich → Sommerzeit ja/nein); Desktop: Differenz Lokal-/UTC-Wanduhr. Alle 15 min neu geprüft → Zeitumstellung greift automatisch. | `detect_timezone()`, `timezone_name`, `utc_offset_minutes`, `is_dst` |
| **Lokalzeit** | UTC + Versatz. HUD-Uhr, Datum, Himmel/Sonnenstand des Spielers. | `get_local_unix()`, `format_time()`, `format_date()` |
| **Siedlungszeitzone** | Wird bei der Gründung im Datensatz gespeichert (`timezone`, `utc_offset_minutes_at_founding`, `founded_at_unix`). Für Regeln, die für alle Bewohner gleich sein müssen (Öffnungszeiten, NPC-Tagesplan, Ratssitzungen). | Datensatz in `WorldState` |
| **Serverzeit** | `server_offset_seconds` korrigiert die Geräteuhr, sobald ein autoritativer Server existiert. Die Client-Uhr wird für gemeinsamen Zustand nie vertraut. | GEPLANT Phase 3/12 |

**Sonne & Licht:** einfaches Sonnenmodell (Deklination nach Tag im Jahr, Breite 51° N bis Siedlungen echte Koordinaten haben, wahrer Mittag ≈ 12:20 Normalzeit, +1 h bei Sommerzeit) → `get_sun_altitude()`, `get_sun_times()` (Auf-/Untergang fürs Menü), `get_night_factor()` (weich über die bürgerliche Dämmerung), `get_ambient_color()` (Nacht → Dämmerung → goldene Stunde → Tag). Laternen schalten bei Nachtfaktor > 0,35.

**Vorschau (nur Optik):** `preview_minute_of_day` per Menü-Schieberegler oder `?preview=HH:MM` in der URL. Ändert nur Licht/NPC-Präsenz lokal, wird nie gespeichert oder geteilt.

**Phase-1-Vereinfachung [OFFEN]:** NPC-Präsenz nutzt derzeit die Lokalzeit des Spielers; mit Mehrspieler wechselt sie auf die Siedlungszeitzone (eine Zeile in `Npc.update_presence`).

**Test:** `fixed_utc_unix` fixiert die Uhr (Sommer-/Winterzeit, UTC−5); Browser-Test mit `TZ_ID=America/New_York node tools/world_shots.js …`.

## 5. ID-Schema [IMPLEMENTIERT]

`<präfix>_<id>`: `plr` Spieler · `npc` · `wld` Welt · `pln` Planet · `cnt` Kontinent · `reg` Region · `stl` Siedlung · `ter` Territorium · `bld` Gebäude · `prp` Objekt · `biz` Unternehmen · `ctr` Vertrag · `org` Organisation · `pol` politische Einheit · `cnc` Rat · `ses` Ratssitzung · `evt` Ereignis.
Handgeschriebene Daten nutzen lesbare stabile IDs (`tpl_founding_basic`, `bld_town_hall`); Siedlungen erhalten ihre ID erst bei der Gründung, generierte IDs zufällige Base36 (`Ids.generate`).

## 6. Asset-Pipeline [IMPLEMENTIERT]

Code fragt logische Schlüssel ab (`exterior.building.town_hall`). Dateien entstehen über `tools/assets/import_penzilla.py` (Einzeldateien + **zusammengesetzte Gebäude** aus den Ebenen des RPG-Pakets) und `tools/assets/import_character.py` (Figuren-Ebenen); `AssetRegistry.get_sprite()` liefert Textur, Skalierung und Versatz anhand der Ankerpunkte (`canvas` = Penzilla-Rasterkonvention, `content` = Unterkante des sichtbaren Inhalts). `data/asset_manifest.json` ordnet Schlüssel → Datei + Quelle zu. Fehlt die Datei → Platzhalter. **Art-Direction-Wächter:** Schlüssel der Domäne `exterior.*` werden nur aufgelöst, wenn der Hersteller der Quelle `penzilla` ist; Verstöße werden gemeldet und nicht geladen (getestet).

## 7. Eingabe [IMPLEMENTIERT]

- Tastatur → Input-Actions (in Code registriert).
- Touch/Maus auf der Welt → `GestureSurface` (unterste HUD-Ebene): Tippen, Ziehen, Pinch. Emulierte Mausereignisse (Gerät −1) werden ignoriert → jede Geste genau einmal.
- Joystick/Interact-Taste verfolgen ihren eigenen Finger → echtes Multi-Touch.

## 8. Architekturentscheidungen (ADR)

### ADR-1: 2D-Isometrie statt 3D
- *Problem:* 2.5D-Look, Web/iPhone-Leistung, vorhandene 2D-Penzilla-Grafiken.
- *Alternativen:* (a) Node2D + isometrische Sprites, (b) 3D mit orthografischer Kamera.
- *Entscheidung:* (a). Penzilla-Pakete sind 2D-Isometrie; Compatibility-Renderer + 2D ist auf iOS am günstigsten.
- *Folgen:* Sortierung per Y-Sort mit Grundflächen-Mittelpunkt; sehr große, unregelmäßige Gebäude benötigen ggf. Aufteilung in Sortierstücke.

### ADR-2: Web-Export ohne Threads
- *Problem:* Threads erfordern SharedArrayBuffer + COOP/COEP-Header; GitHub Pages setzt diese nicht, iOS Safari ist damit historisch instabil.
- *Entscheidung:* `variant/thread_support=false` (seit Godot 4.3 unterstützt).
- *Folgen:* Etwas höhere Audio-Latenz, keine Hintergrund-Threads. Spätere Simulation läuft ohnehin serverseitig.

### ADR-3: Prozedurale, markierte Platzhalter statt Fremd-Assets
- *Problem:* Penzilla-Pakete nicht verfügbar; Außenwelt darf keinen fremden Stil erhalten.
- *Entscheidung:* Schlichte, prozedural gezeichnete Volumen + HUD-Hinweis; Austausch per Manifest.
- *Folgen:* Keine Stilverwässerung, Maßstab/Layout testbar; endgültiger Look erst nach Asset-Integration beurteilbar.

### ADR-4: UI in Code statt `.tscn`
- *Entscheidung:* HUD wird in `hud.gd` aufgebaut (kompakt, versionierbar, ein Theme-Token-File).
- *Folgen:* Für größere Menüs (ab Phase 4) sollen Teile in eigene Szenen ausgelagert werden – dann mit dem Basic-GUI-Theme.

### ADR-7: Gekaufte Assets über private Pipeline statt im Repository
- *Problem:* Öffentliches Repo; Penzilla-Lizenz erlaubt Nutzung im Spiel, aber üblicherweise keine Weitergabe der Dateien.
- *Entscheidung:* Auswahl (nur Dateinamen) + Import-Skript im Repo; Dateien kommen aus dem privaten MEGA-Ordner (Secret), werden verkleinert nach `assets/penzilla/` (git-ignoriert); Manifest-Schlüssel bleiben stabil; Platzhalter als Fallback.
- *Folgen:* Builds ohne Secret zeigen Platzhalter; Asset-Änderungen = Auswahl-JSON anpassen. Projektion an Penzilla-Raster gekoppelt (`Iso.TILE_H = 73`).

### ADR-5: Firebase erst ab Bedarf
- Phase 1 enthält keine Firebase-Anbindung (Anforderung: Singleplayer/lokal). Schema und Regeln sind in FIREBASE_SCHEMA.md vorbereitet. **[OFFEN]:** Godot-Firebase-Anbindung via REST/JS-Bridge (Web) – Entscheidung in Phase 3/12.

### ADR-6: Leerer Planet, Siedlungen nur durch Spielergründung
- *Problem:* Vorgabe des Projektinhabers (24.11.2026): Planet startet leer, keine NPC-only-Siedlungen.
- *Entscheidung:* Genesis-Datei ohne Siedlungen; `WorldState.found_settlement` als einziger Entstehungsweg mit Pflicht-Gründer (`plr_`) und ≥ 1 menschlichem Bewohner; Siedlungsdaten = Vorlage + Gründungsdatensatz.
- *Folgen:* Weltkarte/Server dürfen Siedlungen nie selbst erzeugen; NPC-KI darf keine Siedlungen gründen; offene Regel für verlassene Siedlungen (WORLD_DESIGN.md §5) muss vor Phase 8/13 entschieden werden.

### ADR-8: Echtzeit statt beschleunigter Spielzeit
- *Problem:* Vorgabe: Uhr synchron zur lokalen Zeit, automatische Zeitzone/Sommerzeit, später MMO mit gemeinsamer Welt.
- *Alternativen:* (a) eigene Spielzeit mit Faktor, (b) Echtzeit mit UTC-Basis.
- *Entscheidung:* (b). UTC als gemeinsame Basis, Lokalzeit nur für Anzeige/Himmel, Siedlungszeitzone für gemeinsame Regeln.
- *Folgen:* Kein „Schlafen bis morgen“; Ausruhen ist ein Moment. Tag/Nacht-Test über die Vorschau. Offline-Fortschreibung (Δ seit letztem Snapshot) wird in Phase 3 ereignisbasiert gelöst.

### ADR-9: Modulare Figuren per Ebenen + Einfärbung, zur Laufzeit zusammengesetzt
- *Entscheidung:* Penzilla-Baukasten-Ebenen; Farbvarianten durch Einfärben der weißen „Blank“-Ebenen (gemessene Multiplikatoren); NPCs/Spieler werden per SubViewport zu zwei Texturen (unter/über dem Gesicht) zusammengesetzt und gecacht; der Editor zeichnet gestapelt für Sofort-Updates.
- *Folgen:* 1 Satz Ebenen statt tausender Kombinationen im Build; wenige Draw-Calls pro Figur; Aussehen ist ein kleines Dictionary → server-/Firestore-tauglich.

### ADR-10: RPG-Gebäude auf das City-Builder-Raster abbilden
- *Problem:* Isometric RPG Buildings hat eine steilere Projektion (Kantensteigung 0,603 statt 0,570) und einen größeren Detailmaßstab.
- *Entscheidung:* Beim Import Ebenen zusammensetzen, Grundflächenbreite auf eine City-Builder-Kachel (512 px) skalieren und vertikal um ≈ 5,5 % stauchen, sodass die Kanten exakt auf dem Boden liegen; Anker = rekonstruierte untere Grundflächenecke.
- *Folgen:* Läden/Zelt passen nahtlos ins Raster; Wände sind minimal niedriger als im Original (nicht wahrnehmbar). Größere RPG-Häuser bleiben ungenutzt, bis ein Gebäude-Baukasten (Phase 4) sie braucht.

### ADR-11: Verdeckung per Durchsicht-Loch statt Ganz-Transparenz
- *Entscheidung:* Gebäude/hohe Objekte vor dem Spieler bekommen ein weiches, kreisförmiges Loch um die Figur (Shader); Stärke wird pro Objekt weich ein-/ausgeblendet (6/s) und im Alpha der Modulate-Farbe codiert → ein gemeinsames Material, Batching bleibt erhalten.
- *Folgen:* Nur der verdeckende Teil wird durchsichtig, kein Flackern beim Vorbeilaufen.

### ADR-12: Planet einmal backen statt zur Laufzeit erzeugen
- *Problem:* Erzeugung ~1,4 s (Desktop, auf dem iPhone mehrere Sekunden); Gleitkomma-Unterschiede zwischen Plattformen könnten Regionsgrenzen verschieben → in einer gemeinsamen Welt unzulässig.
- *Entscheidung:* Deterministischer Generator + `planet_bake.gd`; die gebackenen Dateien sind versioniert und werden mit dem Spiel ausgeliefert. Test vergleicht Neuerzeugung byte-genau.
- *Folgen:* Laden in ~0,1 s (Desktop); identische Geografie überall; Generatoränderungen brauchen neue Version + Migration.

### ADR-13: 3D-Globus im Compatibility-Renderer mit eigenem Shader
- *Alternativen:* (a) 2D-Kartenprojektion, (b) 3D-Kugel, (c) Hybrid.
- *Entscheidung:* (b) für Phase 2 – eine Kugel mit unbeleuchtetem Shader (wenige Texturzugriffe), Zoomstufen über den Kameraabstand. Eine 2D-Regionalkarte kann später ergänzt werden.
- *Folgen:* Ein Draw-Call für den Planeten; Auswahl analytisch (Strahl/Kugel) über die Projektionsmatrix; Bildschirmversatz per Frustum-Offset (ohne Parallaxe), damit die Kugel neben der Infotafel zentriert ist.

### ADR-14: Regionen als Voronoi-Zellen auf der Kugel
- *Problem:* Flutfüllung auf dem Gitter ergab achsenparallele, lineal-gerade Grenzen.
- *Entscheidung:* Nächster Startpunkt nach Großkreisdistanz (leicht verrauscht), nur innerhalb derselben Landmasse.
- *Folgen:* Natürliche, polygonale Grenzen; Regionen springen nicht übers Meer (außer kleinen Inseln ohne eigenen Startpunkt).

## 9. Zukünftige Systemtrennung [GEPLANT]

```
Client (Godot Web)  ── Auth ──▶ Firebase Authentication
      │  Anfragen (Intents)          │
      ▼                              ▼
Simulationsserver (autoritativ) ◀──▶ Firestore (Snapshots, Stammdaten)
      │  Ereignisse                  Realtime DB (Präsenz, Chat, Live-Status)
      ▼
Client erhält nur bestätigte Zustände
```
Clients senden **Absichten** („kaufe X“, „betrete Gebäude“), nie Zustände.
