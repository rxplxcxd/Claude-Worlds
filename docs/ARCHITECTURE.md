# ARCHITECTURE

Legende: **[IMPLEMENTIERT]** in Phase 1 vorhanden und getestet · **[GEPLANT]** konzeptionell festgelegt · **[OFFEN]** noch zu entscheiden.

## 1. Leitprinzipien

1. **Daten ≠ Darstellung.** Weltzustand liegt in reinen Datenklassen/JSON (`SettlementData`), Szenen bauen sich daraus auf. Dieselben Daten können später aus Firestore oder vom Simulationsserver kommen.
2. **Nur die aktive Siedlung als Szene.** Globus/Weltkarte (Phase 2) ist eine eigene Szene; entfernte Siedlungen existieren nur als Daten (Simulations-LOD).
3. **Lose Kopplung.** UI ↔ Welt nur über `EventBus`-Signale und Dictionaries – nie direkte Knotenreferenzen.
4. **Server-tauglich.** Aktionen laufen über einen Service (`InteractionService.run_action`), der später zur Anfrage an den autoritativen Server wird.
5. **Kleine Skripte.** Kein Gott-Manager; jedes Skript hat eine Aufgabe.

## 2. Laufzeitstruktur [IMPLEMENTIERT]

```
Main (scripts/core/main.gd)                 Orientierung, Verdrahtung
├─ Settlement (SettlementScene)             lokale Siedlung, LOD "aktiv"
│  ├─ DayNight (CanvasModulate)
│  ├─ Ground (GroundLayer)                  Kacheln, einmal gezeichnet
│  ├─ Objects (Node2D, y_sort)              Gebäude, Props, Spieler
│  ├─ Bounds (StaticBody2D)                 Kartenrand, Wasser
│  ├─ InteractionService
│  └─ Camera (CameraRig)
└─ HUD (CanvasLayer, Hud)
   └─ Root ─ GestureSurface (hinten) · Info · Uhr/Buttons · Joystick · Interact · Panels
Autoloads: EventBus · GameClock · AssetRegistry · LocalProfile
```

## 3. Module

| Ordner | Inhalt | Status |
|---|---|---|
| `scripts/core` | `event_bus`, `game_clock`, `asset_registry`, `ids`, `input_actions`, `main` | IMPLEMENTIERT |
| `scripts/geography` | `Iso` – Projektion Raster↔Welt, Facing | IMPLEMENTIERT (Planet/Kontinente GEPLANT Phase 2) |
| `scripts/settlement` | `SettlementData` (Daten+Validierung), `SettlementScene` | IMPLEMENTIERT |
| `scripts/world` | `GroundLayer`, `Prop`, `IsoPainter` (Platzhalter-Zeichnung) | IMPLEMENTIERT |
| `scripts/buildings` | `Building` | IMPLEMENTIERT |
| `scripts/player` | `Player`, `PlayerVisual` | IMPLEMENTIERT |
| `scripts/camera` | `CameraRig` | IMPLEMENTIERT |
| `scripts/interaction` | `Interactable`, `InteractionService` | IMPLEMENTIERT |
| `scripts/ui` | `Hud`, `GestureSurface`, `TouchJoystick`, `TouchButton`, `UiTheme` | IMPLEMENTIERT |
| `scripts/persistence` | `LocalProfile` | IMPLEMENTIERT (lokal) |
| `npc`, `ai`, `economy`, `politics`, `firebase`, … | – | GEPLANT (werden erst mit ihrer Phase angelegt, keine leeren Ordner) |

## 4. Zeitmodell [IMPLEMENTIERT, Grundlage]

| Begriff | Bedeutung |
|---|---|
| Echtzeit | Wanduhr des Geräts/Servers |
| Spielzeit | `GameClock.total_minutes` (Float, Minuten seit Weltstart). Standard 1 Echtsekunde = 1 Spielminute (1 Tag = 24 min) |
| Geschwindigkeit | 0 (Pause), 1×, 4× – nur Singleplayer; in Multiplayer bestimmt der Server die Zeit |
| Kalender | 120 Tage/Jahr (**[OFFEN]**: Länge Spieljahr ↔ Weltrat-Rhythmus) |
| Gespeichert | Spielzeit stündlich lokal (`user://worlds_local.cfg`) |

[GEPLANT] Offline-Fortschreibung: Beim Laden wird `Δ = jetzt − letzter Snapshot` ereignisbasiert fortgeschrieben (Produktion, NPC-Tagesbilanz, Verträge) statt Sekunde für Sekunde (siehe PERFORMANCE.md).

## 5. ID-Schema [IMPLEMENTIERT]

`<präfix>_<id>`: `plr` Spieler · `npc` · `wld` Welt · `pln` Planet · `cnt` Kontinent · `reg` Region · `stl` Siedlung · `ter` Territorium · `bld` Gebäude · `prp` Objekt · `biz` Unternehmen · `ctr` Vertrag · `org` Organisation · `pol` politische Einheit · `cnc` Rat · `ses` Ratssitzung · `evt` Ereignis.
Handgeschriebene Daten nutzen lesbare stabile IDs (`stl_lichtfeld`), generierte IDs zufällige Base36 (`Ids.generate`).

## 6. Asset-Pipeline [IMPLEMENTIERT]

Code fragt logische Schlüssel ab (`exterior.building.town_hall`). `data/asset_manifest.json` ordnet Schlüssel → Datei + Quelle zu. Fehlt die Datei → Platzhalter. **Art-Direction-Wächter:** Schlüssel der Domäne `exterior.*` werden nur aufgelöst, wenn der Hersteller der Quelle `penzilla` ist; Verstöße werden gemeldet und nicht geladen (getestet).

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

### ADR-5: Firebase erst ab Bedarf
- Phase 1 enthält keine Firebase-Anbindung (Anforderung: Singleplayer/lokal). Schema und Regeln sind in FIREBASE_SCHEMA.md vorbereitet. **[OFFEN]:** Godot-Firebase-Anbindung via REST/JS-Bridge (Web) – Entscheidung in Phase 3/12.

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
