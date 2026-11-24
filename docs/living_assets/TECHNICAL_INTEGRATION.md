# Technische Integration – Living Assets

Status: **Schritt G – Serienproduktion + Laufzeit-Bausteine (`VisualState`, `LivingComposer`) mit Tests; Nachweis in der Galerie.** Im Spiel ist noch **nichts** davon aktiv (keine Änderung an Spielmechanik oder laufender Darstellung).

## 1. Drei Stufen (geprüft in Godot)

| Stufe | Technik | Zusätzliche Daten | Draw Calls | Wofür |
|---|---|---|---|---|
| **1 Shader** | `shaders/living_wear.gdshader` auf dem **Originalsprite**: flache, hartkantige Schmutzflecken (Schwellwert auf **einer** gemeinsamen, kachelbaren Feldtextur `assets/vfx/grime_field.png`, 256 px), mehr Schmutz unten, Ausbleichen, Abdunkeln; Konturen bleiben sauber | **keine** je Asset; 1 gemeinsame Textur (192 KB im Grafikspeicher) | 0 zusätzlich; je Verschleißstufe **ein gemeinsames Material** (z. B. 6 Stufen) → Batching bleibt | Zustände 1–5, 12; Verschmutzung von Straßen/Möbeln/Fahrzeugen |
| **2 Overlay** | Nur die **veränderten Pixel** (Risse, kaputte Fenster, Dachlöcher, Pfützen, Schlaglöcher, Schnee), zugeschnitten auf ihren Rahmen, über dem Original | 10–57 % der Originalfläche; 3–19 KB je Datei (gemessen) | +1 je Overlay | Zustände 6–7, Wetter auf Böden |
| **3 Variante** | Eigene Datei, gleiche Leinwand und gleicher Anker wie das Original (Ausnahme „umgestürzt“: Leinwand wächst symmetrisch, Anker bleibt unten mittig) | 100 % der Originalfläche | wie Original | Zustände 8–11, verbrannt, Wrack, umgestürzt |

Stufe 1 und 2 sind kombinierbar (z. B. „stark heruntergekommen“ = Shader Stufe 0,65 + Schadens-Overlay).

**Nachweis:** Galerie `?gallery=living` (Web-Build, `scripts/tools/living_gallery.gd`) zeigt alle drei Stufen und die Effekte mit echtem Godot-Rendering. Gemessen (Chromium, Software-Rendering): 41 Objekte inkl. 7 Partikelsysteme und 5 Animationen, **101 Draw Calls**, **47,6 MB Texturspeicher** (Galerie lädt alle Musterdateien gleichzeitig), keine Fehler.

## 2. Dateien und Pipeline
| Baustein | Aufgabe |
|---|---|
| `tools/assets/living_materials.py` | **Materialerkennung**: Segmentierung in flache Farbflächen (Penzilla = Cel-Look), Klassifikation in `outline, glass, roof, plaster, brick, stone, wood, trim, metal, fabric, plant, water` aus Farbe, Lage (Himmelskante = Dach/Markise), Form (Streifen ≠ Scheibe), Textur (Ziegel), Kontext (Licht-/Schattenseite derselben Wand; Texturdetails erben die Fläche); bei RPG-Läden **exakt aus den Ebenennamen** (`OuterWall_ClayBrick`, `Fabric_Green` …); Korrekturen je Asset in `living_assets.json` (`overrides`). Rathaus: 1,5 s statt 290 s. |
| `tools/assets/living_traits.py` | **Merkmal-Effekte je Material** (Putz blättert → Ziegel sichtbar; Ziegel: Treppenrisse, fehlende Steine; Holz: Risse längs der Maserung, Vergrauen, Fäulnis, gebrochene Bretter; lackiertes Holz/Metall: Lack platzt ab; Metall: Rost, Dellen; Glas: Schmutzfilm, Sternriss, Bruch, vernagelt; Dach: verschobene/neue Ziegel, Löcher mit Sparren, Moos; Stoff: Ausbleichen, Risse mit Lappen, Flicken, verkohlt) + Strukturvarianten + Profile je Funktion |
| `tools/assets/living_sources.py` | liest Originale **nur** aus den ZIP-Archiven (RPG-Läden wie im Hauptimport zusammengesetzt) |
| `tools/assets/make_living_states.py` | Produktion: `--pilot` (repräsentative Auswahl) oder alle; `--qa <ordner>` erzeugt Kontaktbögen + Prüfbericht |
| `tools/assets/living_qa.py` | automatische Prüfung (§7) + Kontaktbögen in voller Größe und **echter Spielgröße** |
| Ausgabe (privat, git-ignoriert) | `assets/penzilla/states/<schlüssel>/base_*.png, overlay_*.png[@basis]`, Bodenfamilien unter `surfaces/<familie>/`, Manifest `states.json` (Version 2) |
| Eigene VFX (Repository) | `tools/assets/make_vfx.py` → `assets/vfx/` |

Erzeugung arbeitet auf einer **gepufferten Leinwand** (Schutt, Efeu, umgestürzte Objekte werden nie abgeschnitten); Basen werden auf die Original-Leinwand zurückgeschnitten, wenn sie hineinpassen, sonst mit `pad_src` (Anker bleibt exakt). Versätze sind gerade Zahlen (exakt bei Maßstab 0,5). Deterministisch (fester Seed je Asset und Merkmal).

## 3. Godot-Bausteine (umgesetzt, noch nicht im Spiel verdrahtet)
```
VisualState (scripts/living/visual_state.gd)      reine Daten, speicherbar
  structure, wear, damage, fire, overgrowth, repair, changed_at_unix, history
  to_dict()/from_dict()  · apply_event(…)  · layer_names()  · preset("07_beschaedigt")

LivingComposer (scripts/living/living_composer.gd)
  resolve(key, state, profile, weather) -> {base, layers[], shader}   (reine Entscheidung, getestet)
  build(key, state, original_texture, profile, weather) -> Node2D
    ├─ Sprite2D  Basis (Original oder Strukturvariante) + gemeinsames Verschleiß-Material
    └─ Sprite2D  je Overlay (vorab beschnitten, Versatz aus dem Manifest)
```
- **Keine Pixelarbeit zur Laufzeit**: nur gestapelte Sprites; Overlays sind je Strukturvariante vorab beschnitten. Batching bleibt erhalten (ein Material je Verschleißstufe).
- Overlays bleiben **ohne Shader** (das Schmutzfeld ist je Textur verankert und würde zwischen getrennten Sprites nicht passen).
- **CPUParticles2D** für Feuer/Rauch/Wetter (WebGL 2 im Compatibility-Renderer zuverlässig).
- Texturen werden nur bei Bedarf geladen; später Atlanten je Kategorie.

### Dauerhafte Speicherung (vorbereitet)
`VisualState.to_dict()` ist das Speicherformat je Objekt (z. B. künftig `WorldState.settlements[…].buildings[id].visual`):
```json
{"schema": 1, "structure": "intact", "wear": 1, "damage": 0, "fire": 0, "overgrowth": 0, "repair": 2,
 "changed_at_unix": 1764000000, "history": [{"event": "repaired", "at": 1764000000}]}
```
- Änderungen **nur durch Ereignisse** der Simulation (`damaged`, `fire_large`, `burnt_out`, `destroyed`, `became_ruin`, `repaired`, `restored`, `traces_faded`, `maintained`, `neglected`, `overgrown`, `cleared`); Historie (max. 12 Einträge).
- **Laden verändert nichts** – es gibt keine Funktion, die Verfall aus verstrichener Echtzeit ableitet (Test: *absence does not cause decay*).
- Wetter wird **nicht** gespeichert (kommt aus der Umwelt).

## 4. Qualitätsprofile (Referenzgerät iPhone 15 Pro Max) – umgesetzt in `LivingComposer.PROFILES`

| | **Ultra** (iPhone 15 Pro/Max und neuer) | **Hoch** (Standard; iPhone 12–14) | **Leistung** (ältere iPhones, z. B. XR/11/SE) |
|---|---|---|---|
| Strukturvarianten (Ausgebrannt, Zerstört, Ruine …) | an | an | an (gehören zur Lesbarkeit der Welt) |
| Overlays je Objekt | bis 6 | bis 4 | bis 2 – **Vorrang**: Schaden > Brand > Reparatur > Abnutzung > Bewuchs > Schnee |
| Verschleiß-Shader | an | an | aus |
| Wetter-Overlays (Schnee auf Objekten) | an | an | aus (Boden-Overlays bleiben) |
| Partikel (Feuer, Rauch, Regen, Schnee) | 100 % | 60 % | 25 % |
| animierte Flammen | an | an | aus (stehendes Bild) |

**Die Simulation ist in allen Profilen identisch**: Profile wirken nur in `resolve()/build()`, der `VisualState` wird nie verändert (Test: *quality profile never changes the visual/simulation state*). Galerie: `?gallery=living&profile=ultra|hoch|leistung`.

**Messungen:** Diagnoseberichte tragen jetzt `context` = `testgalerie` oder `spiel` – Galerie-Werte (alle Zustände gleichzeitig geladen) dürfen nicht mit dem Spielbetrieb verglichen werden.

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

## 6. Performance-Einschätzung (Stand Schritt G, gemessen)
| Aspekt | Wert / Einschätzung |
|---|---|
| Umfang der Serie | 771 PNG-Dateien, **23,3 MB** auf Datenträger (privat); Gebäude im Mittel 1,1 MB je Gebäude (alle Basen + Overlays), Stadtmöbel 8–126 KB, Bäume ~30 KB, Bodenfamilien: 32 Overlays für alle 23 Bodenkacheln |
| Grafikspeicher im Spiel | nur **aktive** Zustände werden geladen. Wohnhaus: Original 0,52 MB (RGBA), typischer Overlay 0,01–0,22 MB; Beispiel „verschmutzt + beschädigt + teilweise ausgebrannt“ = +0,47 MB. Rathaus mit **allen** Overlays gleichzeitig wären 6,6 MB – kommt nur in der Galerie vor |
| Overlay-Fläche | Median 12 % der Objektfläche (max. 83 % bei Schnee auf kleinen Objekten) |
| Draw Calls | Shader: 0 zusätzlich (gemeinsames Material je Stufe); Overlay: +1 je Overlay; Profil **Leistung** begrenzt auf 2 Overlays je Objekt |
| CPU zur Laufzeit | keine Pixelarbeit: Overlays sind je Strukturvariante vorab beschnitten; `resolve()` ist eine kleine Tabellenentscheidung |
| Galerie (Kontext **testgalerie**, Chromium/SwiftShader, iPhone-15-Pro-Max-Emulation) | 97–102 Objekte, **208–216 Draw Calls**, **71,3–71,8 MB** Texturspeicher je Profil (alle Zustände gleichzeitig geladen) – **nicht** mit dem Spielbetrieb vergleichbar; FPS unter Software-Rendering nicht aussagekräftig |
| Spielbetrieb (Kontext **spiel**) | unverändert, da noch nicht eingebaut (Referenz: PERFORMANCE.md §7 – 448 Draw Calls, davon 357 Boden) |
| Größtes Risiko | weiterhin Boden-Draw-Calls und Figuren-Texturen (PERFORMANCE.md §7) – vor einer breiten Zustandsintegration optimieren |
| Erzeugungszeit (Werkzeug) | gesamte Serie inkl. Prüfung ~15 min auf einem CPU-Kern (Gebäude 10–37 s, Objekte < 1 s) |
| iPhone | **nicht gemessen** – Messung durch den Projektinhaber: `?gallery=living&perf=1&profile=…` (Galerie) bzw. `?perf=1` (Spiel) |
