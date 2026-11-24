# Technische Integration – Living Assets

Status: **Konzept + technischer Nachweis in Godot (Galerie)**. Im Spiel ist noch **nichts** davon aktiv (keine Änderung an Spielmechanik oder laufender Darstellung).

## 1. Drei Stufen (geprüft in Godot)

| Stufe | Technik | Zusätzliche Daten | Draw Calls | Wofür |
|---|---|---|---|---|
| **1 Shader** | `shaders/living_wear.gdshader` auf dem **Originalsprite**: flache, hartkantige Schmutzflecken (Schwellwert auf **einer** gemeinsamen, kachelbaren Feldtextur `assets/vfx/grime_field.png`, 256 px), mehr Schmutz unten, Ausbleichen, Abdunkeln; Konturen bleiben sauber | **keine** je Asset; 1 gemeinsame Textur (192 KB im Grafikspeicher) | 0 zusätzlich; je Verschleißstufe **ein gemeinsames Material** (z. B. 6 Stufen) → Batching bleibt | Zustände 1–5, 12; Verschmutzung von Straßen/Möbeln/Fahrzeugen |
| **2 Overlay** | Nur die **veränderten Pixel** (Risse, kaputte Fenster, Dachlöcher, Pfützen, Schlaglöcher, Schnee), zugeschnitten auf ihren Rahmen, über dem Original | 10–57 % der Originalfläche; 3–19 KB je Datei (gemessen) | +1 je Overlay | Zustände 6–7, Wetter auf Böden |
| **3 Variante** | Eigene Datei, gleiche Leinwand und gleicher Anker wie das Original (Ausnahme „umgestürzt“: Leinwand wächst symmetrisch, Anker bleibt unten mittig) | 100 % der Originalfläche | wie Original | Zustände 8–11, verbrannt, Wrack, umgestürzt |

Stufe 1 und 2 sind kombinierbar (z. B. „stark heruntergekommen“ = Shader Stufe 0,65 + Schadens-Overlay).

**Nachweis:** Galerie `?gallery=living` (Web-Build, `scripts/tools/living_gallery.gd`) zeigt alle drei Stufen und die Effekte mit echtem Godot-Rendering. Gemessen (Chromium, Software-Rendering): 41 Objekte inkl. 7 Partikelsysteme und 5 Animationen, **101 Draw Calls**, **47,6 MB Texturspeicher** (Galerie lädt alle Musterdateien gleichzeitig), keine Fehler.

## 2. Dateien und Pipeline
- **Ableitung (privat, git-ignoriert):** `tools/assets/living_states.py` (Effektbibliothek) + `tools/assets/make_living_samples.py` → `assets/penzilla/states/<asset>/<zustand>.png` + `states.json`. Liest die Originale **nur aus den ZIP-Archiven**, verändert sie nie; Maßstab 0,5 wie der Hauptimport.
- **Eigene VFX (im Repository, eigene Arbeit):** `tools/assets/make_vfx.py` → `assets/vfx/vfx_atlas.png` (39 Frames, 768 × 480, 14 KB) + `vfx_atlas.json` + `grime_field.png`.
- **Inventar:** `tools/assets/inventory.py` → `docs/living_assets/asset_inventory.csv` (7 901 Zeilen, nur Metadaten).
- Werkzeuge brauchen numpy + scipy + pillow (nur Entwicklungsrechner/CI, nie im Spiel).

## 3. Godot-Bausteine (Vorschlag für die Integration)
```
LivingVisual (Komponente am Building/Prop)
 ├─ base: Sprite2D           Original oder Stufe-3-Variante
 ├─ material                 gemeinsames Verschleiß-Material der Stufe (Stufe 1)
 ├─ overlay: Sprite2D?        Stufe 2, nur wenn nötig
 └─ fx: Node2D?              Flammen (AnimatedSprite2D), Rauch/Funken (CPUParticles2D)
```
- **CPUParticles2D** statt GPUParticles2D: läuft im Compatibility-Renderer auf WebGL 2 zuverlässig.
- Texturen der Stufe 3 werden **erst bei Bedarf geladen** (die meisten Gebäude sind die meiste Zeit in Zustand 2–4 = nur Original + Shader).
- Overlays und Varianten liegen später in **Atlanten je Kategorie** (weniger Texturwechsel).

## 4. Qualitätsprofile (Referenzgerät iPhone 15 Pro Max)

| | **Ultra** (iPhone 15 Pro/Max und neuer) | **Hoch** (iPhone 12–14) | **Leistung** (ältere iPhones, z. B. XR/11/SE) |
|---|---|---|---|
| Stufe 1 Shader | an | an | aus → Original (Zustände 3–5 sehen wie 2 aus) |
| Stufe 2 Overlays | alle | alle | nur Schäden ab Zustand 6 |
| Stufe 3 Varianten | an | an | an (gehören zur Lesbarkeit der Welt) |
| Feuer/Rauch | volle Partikelzahl | 60 % | 25 %, Flamme ohne Rauch |
| Wetter-Partikel | 100 % | 50 % | 20 % + Boden-Overlay |
| Funken, Staub, Blätter | an | an | aus |
| Auflösung | 100 % | 100 % | 75 % (dynamisch) |

**Die Simulation ist in allen Profilen identisch.** Profile ändern nur Darstellung; der sichtbare Zustand wird aus denselben Simulationswerten abgeleitet (§5). Umschalten per Menü; Standard nach Gerätemessung.

## 5. Automatische Zustandsauswahl (Vorschlag, noch nicht umgesetzt)
Eine reine Funktion `VisualStateResolver.resolve(sim) → {base, wear, overlay, fx}` liest **nur** Simulationswerte:

| Eingang | Wirkung |
|---|---|
| `structure` (0–1, bauliche Intaktheit) | < 0,1 → 10 zerstört; < 0,4 → 8; < 0,7 → 7 |
| `fire` (none / burning / burnt) | burning → Effekt Feuer (+ aktueller Zustand); burnt → 9 |
| `maintenance` (0–1, Pflegezustand) | ≥ 0,8 → 2; ≥ 0,6 → 3; ≥ 0,4 → 4; ≥ 0,2 → 5; sonst 6 |
| `dirt` (0–1) | Shader-Stufe (unabhängig von der Pflege) |
| `age_days`, `repaired_at` | < 7 Tage → 1 neu; Reparatur < 14 Tage → 12 restauriert |
| `vacancy_days` + Zustand 10 | > 60 Tage ohne Wiederaufbau → 11 Ruine |
| `weather` (Schnee, Regen, Frost) | Wetter-Overlays/Partikel, nicht der Bauzustand |
| `usage` (belegt, Licht) | Fenster-/Lampenlicht, Interior-State2 |

**Abwesenheitsregel (verbindlich):** Die Abwesenheit eines Spielers verändert **keinen** Eingangswert. `maintenance` sinkt nur, wenn die Simulation tatsächlich keine Instandhaltung leistet (fehlendes Budget, fehlendes Personal, Leerstand) – Instandhaltung durch NPCs/Verträge läuft auch während der Pause weiter ([SIMULATION_ARCHITECTURE.md](../SIMULATION_ARCHITECTURE.md)). **Hysterese** (z. B. ±0,05) verhindert Flackern zwischen zwei Stufen.

## 6. Performance-Einschätzung
| Aspekt | Einschätzung |
|---|---|
| Speicher Stufe 1 | ~0 (eine 192-KB-Textur für alles) |
| Speicher Stufe 2 | gering: Overlays 10–57 % der Originalfläche; nur geladen, wenn aktiv |
| Speicher Stufe 3 | wie das Original je aktivem Zustand; bei 21 Gebäuden, davon typischerweise 0–3 im Zustand ≥ 8 → wenige MB |
| Draw Calls | Stufe 1: keine zusätzlichen (gemeinsame Materialien je Stufe); Stufe 2: +1 je Overlay; Effekte: +1 je Partikelsystem/Animation |
| Shaderkosten | 2 Texturzugriffe + wenige Rechenschritte je Pixel – auf dem iPhone vernachlässigbar im Vergleich zur Füllrate der Sprites |
| Größtes Risiko | nicht die Zustände, sondern der bestehende Boden (357 Draw Calls) und die Figuren-Texturen (~380 MB) – siehe [PERFORMANCE.md](../PERFORMANCE.md) §7. Diese sollten **vor** einer breiten Zustandsintegration optimiert werden. |
| Erzeugungszeit (Werkzeug) | Haus ~40 s, Rathaus ~290 s (Segmentierung in Python) → vor Schritt G optimieren (Segmentierung zwischenspeichern, gröber analysieren) |
