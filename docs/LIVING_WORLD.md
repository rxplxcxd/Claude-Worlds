# LIVING_WORLD – Phase 3 (umgesetzt in 0.5.0)

Umfang laut Master-Prompt: **NPC-Identitäten, Bedürfnisse, Tagesabläufe, Berufe, Navigation, Utility AI, Interaktionen, Simulations-LOD, Persistenz.** Nichts aus Phase 4+ (Wirtschaft, Bevölkerungswachstum, Bauen, soziale Beziehungen) ist umgesetzt.

## 1. Überblick

```
data/sim/living_world.json      Bedürfnisse, Aktivitäten, Berufe/Schichten, Orte, Wegkosten, visuelle Ereignisse
scripts/sim/nav_grid.gd         NavGrid      – begehbares Raster (AStarGrid2D), Orte, Wege, Wegzeiten
scripts/sim/npc_brain.gd        NpcBrain     – Identität, Bedürfnisse, Utility AI, ereignisgesteuertes advance()
scripts/sim/settlement_sim.gd   SettlementSim – alle NPCs einer Siedlung, Zeitzone, Nachholen, Persistenz, Abfragen
scripts/sim/visual_event_router.gd  Simulation → Living Assets / VFX
scripts/npc/npc.gd, chat_bubble.gd  Darstellung (nur Anzeige des Simulationszustands)
scripts/settlement/settlement_scene.gd  LOD S0/S1, Tick, Speichern, Interaktion
scripts/core/graphics_profile.gd   Ultra/Hoch/Leistung (nur Darstellung)
```
Alle `scripts/sim/*` sind **reine Datenklassen ohne Szene** – lauffähig auf einem späteren Godot-Headless-Server (SIMULATION_ARCHITECTURE.md §6).

## 2. NPC-Identität (persistent)
Je NPC im Siedlungsdatensatz (`record.npcs[]`), einmalig deterministisch ergänzt (Migration älterer Spielstände):
- `personality` {openness, diligence, sociability, ambition, risk} (0..1, Normalverteilung um 0,5)
- `birth_day` (Tage seit 1970; Alter 19–67 bei Gründung) → Alter in der Infokarte
- `profession` {title, skill_name, skill (0..1), shift_offset_min} – Beruf aus der Rolle; Fertigkeit wächst mit Arbeitszeit (+0,01 je 40 h, `skill_now`, `skill_worked_h`)
- unverändert aus Phase 1: Name, Rolle, Aussehen, Wohnung, Arbeitsplatz

## 3. Bedürfnisse
| Bedürfnis | Abbau/h | Besonderheit |
|---|---|---|
| Hunger (food) | 0,065 | im Schlaf ×0,35 |
| Energie (energy) | 0,045 | Arbeit zusätzlich −0,012/h |
| Gesellschaft (social) | 0,040 | × (0,6 + 0,8 · Geselligkeit) |
| Freizeit (leisure) | 0,035 | × (0,6 + 0,8 · Offenheit) |
| Hygiene (hygiene) | 0,030 | im Schlaf ×0,4 |
Gespeichert als **Ganzzahlen in Millionstel** (Festkomma) – exakt über JSON-Speichern/Laden (Godot speichert Fließkommazahlen in JSON nur mit ~6 Stellen).

## 4. Aktivitäten, Berufe, Tagesabläufe
- 9 Aktivitäten (datengetrieben): schlafen, zu Hause essen, frisch machen, entspannen (drinnen); arbeiten, auswärts essen, Leute am Platz treffen, im Grünen erholen, Besorgungen (draußen). Jede mit Ort, Dauer, Bedürfnis-Gewinnen, Zeitfenstern (Ortszeit), Abklingzeit.
- **Berufe/Schichten** (Ortszeit der Siedlung): Verwaltung Mo–Fr 8:00–16:30 · Handel Mo–Sa 8:30–18:00 · Sanitätsdienst Mo–Fr 7:00–15:30 + Sa 9–13 · Sicherheit 14:00–22:00 (Mi frei) · Bau Mo–Fr 7:00–15:30 · Handwerk Mo–Fr 8:00–17:00 · Landwirtschaft Mo–Sa 6:00–14:00 · Bewohner:innen ohne feste Zeiten. Individuelle Verschiebung −15…+30 min.
- **Arbeit sichtbar**: je Beruf ein Anteil Arbeitszeit draußen vor dem Arbeitsplatz (z. B. Landwirtschaft 90 %, Verwaltung 40 %), sonst drinnen; deterministisch in 20-min-Blöcken.

## 5. Utility AI
Bei jedem Aktivitätsende wählt `NpcBrain.decide()` die nächste Aktivität:
`Wert = Σ Druck(Bedürfnis) · Gewinn / √max(Dauer, 1 h) × Persönlichkeit + Boni − Wegzeit · 0,02 + kleines deterministisches Rauschen`
- Druck = 4·(1−n)² (+2 unter 0,15) · Pflicht: in der Schicht Arbeit +2,5 × Fleiß (außer bei Hunger/Erschöpfung) · Nacht: Schlaf bis zur persönlichen Weckzeit (Frühaufsteher je Fleiß) · Mahlzeiten-Bonus nur bei Hunger · Abwechslung/Abklingzeiten.
- Zeitbudget: Aktivitäten werden gekürzt oder entfallen, wenn sie den Weg zur nächsten Schicht gefährden.
- **Kein LLM, kein Zufall ohne Seed**: gleiche Eingaben → gleiche Entscheidungen (getestet).

## 6. Navigation
- `AStarGrid2D` (Godot, nativ) auf den 26×26 Kacheln; Gebäude, Wasser, sperrende Objekte (Brunnen, Bänke, Stände …) gesperrt; **Straßen begehbar, aber teurer** (×2,5) → Gehwege werden bevorzugt, Straßen gequert.
- Orte: Tür jedes Gebäudes (`bld:<id>`), Dorfplatz (`plaza`, alle Platzkacheln), Grün (`park`, Kacheln um Brunnen/Garten/Bänke); je Ort Stehplätze (sichtbare Gebäudeseite, nie auf der Tür/Straße).
- Wege und Wegzeiten gecacht; Gehgeschwindigkeit 0,3 Kacheln/s (≈ 3 m/s, leicht beschleunigt, damit Wege sichtbar werden – die Zeit bleibt Echtzeit).

## 7. Simulations-LOD und Echtzeit
| Stufe | Wo | Umsetzung |
|---|---|---|
| **S0** | NPCs im Kamerabild (+220 px), max. nach Profil (Ultra 400 · Hoch 150 · Leistung 50, nächste zuerst) | Knoten sichtbar, Gehen entlang des Weges (fließend, Bruchteil-Sekunden), Arbeits-/Plauder-Animationen, Sprechblasen |
| **S1** | übrige NPCs der Siedlung | nur Daten: Zustand wird 4×/s fortgeschrieben, Knoten versteckt, `_process` aus |
| S2/S3 | andere Siedlungen | **nicht** lokal vorhanden (Einzelspieler); Grundlage: `advance()` bei Zugriff ist ereignisgesteuert und billig → Phase 8/13 |
- **Darstellung = reine Funktion von (Zustand, Zeit)** (`render_info`): Wechsel S0↔S1 ändert nichts (getestet); beim Betreten eines Bereichs steht jeder NPC genau dort, wo ihn sein Tag gerade hinführt – **nie veraltet, nie nachgespielt**.
- **Nachholen nach Abwesenheit**: beim Laden `advance(jetzt)` vor der ersten Anzeige; 3 Tage in ~50 ms (getestet, exakt gleich wie durchgehend). Über 14 Tage: Tagesablauf wird einen Tag vor jetzt neu angesetzt (begrenzter Aufwand; nichts Beobachtbares geht verloren).
- **Abwesenheit führt zu keinem Verfall** (Living-Assets-Regel bleibt).
- Zeitvorschau (Menü/QA `?preview=HH:MM`): eigene Wegwerf-Simulation, ändert nie die echte.

## 8. Siedlungszeit
Tagesabläufe folgen der **Ortszeit der Siedlung**, nicht dem Gerät des Betrachters: Zeitzone aus der Gründung (`record.timezone`, `utc_offset_minutes_at_founding` – seit Phase 1 gespeichert). Für das Gerät des Gründers folgt sie der Sommerzeit; im Mehrspieler sehen alle dieselbe Siedlungszeit.

## 9. Interaktionen
- **Spieler ↔ NPC**: Antippen öffnet eine **Live-Karte** (Name, Alter, Beruf, was die Person gerade tut und wo, Stimmung, dringende Bedürfnisse, Arbeitszeiten, Wohnung, Wesenszüge). „Grüßen“ verändert Gesellschaft/Freizeit (gespeichert) und ergibt eine stimmungsabhängige Antwort. NPCs schauen den Spieler an, wenn er nahe ist.
- **NPC ↔ NPC**: Wer gleichzeitig am selben öffentlichen Ort ist (Platz, Grün, Laden, Essen), steht in einer Gruppe, wendet sich einander zu; reihum zeigt eine Person eine Sprechblase (Profil Leistung: ohne Blasen).
- **NPC ↔ Objekt**: Arbeit mit Werkzeug-Animation, Einkaufen/Essen mit Benutzen-Animation.

## 10. Visuelle Folgen (Living Assets + VFX)
`VisualEventRouter`:
- **aktive Effekte aus dem aktuellen Zustand** (`visual_events.active`): z. B. Kaminrauch, solange jemand zur Mahlzeit zu Hause kocht; Funken in der Werkstatt bei Arbeit. Weil sie aus dem Zustand abgeleitet werden, sind sie beim Betreten nie veraltet. Menge je Grafikprofil.
- **dauerhafte Gebäudezustände** (`visual_events.building`): Simulationsereignisse (`fire_large`, `repaired`, `destroyed` …) → `VisualState.apply_event` → `record.visual_states[building_id]`. In Phase 3 erzeugt noch kein System solche Ereignisse (Brände, Schäden, Bau folgen in späteren Phasen); Zuordnung und Speicherung sind getestet.

## 11. Persistenz (Speicherschema 4)
`record.npcs[]` + `personality/birth_day/profession`, `record.time_zone`, `record.sim = {version, simulated_at, npcs: {id: state}}`, `record.visual_states{}`. Gespeichert beim Laden, alle 60 s, beim Verlassen/Fokusverlust und nach Interaktionen. ~0,6 KB je NPC.

## 12. Architekturentscheidungen (geprüfte Alternativen)
| # | Entscheidung | Alternativen | Begründung |
|---|---|---|---|
| P3-A | **Ereignisgesteuertes Fortschreiben** (Grenze zu Grenze, Bedürfnisse linear) | fester Takt (z. B. 1×/min für jeden NPC) | Aufwand ∝ Entscheidungen (~15/NPC/Tag) statt ∝ Zeit; exaktes Nachholen; servertauglich; S0/S1 konsistent |
| P3-B | **Utility AI + Schichtpflichten** | Behavior Trees, GOAP, Zeitplan-Tabellen | flexibel, datengetrieben, deterministisch, billig; GOAP bleibt für Langzeitziele (spätere Phasen) |
| P3-C | **Darstellung als Funktion von Zustand + Zeit** | Knoten bewegen sich selbst (Physik/Navigation pro Frame) | keine Abweichung zwischen sichtbaren und unsichtbaren NPCs, keine veralteten Zustände, Mehrspieler-tauglich (Server sendet Zustand) |
| P3-D | **Raster-A\* (AStarGrid2D)** | NavigationServer2D-Navmesh | Welt ist kachelbasiert; Bauen/Abreißen (Phase 7) ändert nur Kacheln statt Navmesh neu zu backen; deterministisch; headless nutzbar |
| P3-E | **Siedlungszeitzone** | Gerätezeit des Betrachters | alle Spieler sehen denselben Tagesablauf |
| P3-F | **Festkomma-Bedürfnisse** | Fließkomma | bitgenaue Fortsetzung nach Speichern/Laden |
| P3-G | **Nachhol-Obergrenze 14 Tage** | unbegrenzt nachrechnen | begrenzter Aufwand auch nach Monaten; Ergebnis entspricht einem normalen Tag |

## 13. Leistung
| Messung | Ergebnis |
|---|---|
| 12 NPCs, 2 Tage fortschreiben (headless, Desktop-CPU) | ~25 ms inkl. Wegnetz |
| 3 Tage Abwesenheit nachholen | ~50 ms |
| **1 000 NPCs**, Warmstart + 1 Tag | **2,2 s** (21 600 Ereignisse, ~100 µs/Ereignis) – im Spielbetrieb laufen nur Sekunden-Schritte (vernachlässigbar) |
| Spielbetrieb Siedlung (Chromium, iPhone-15-Pro-Max-Emulation, Kontext `spiel`) | 445 Draw Calls (vor Phase 3: 444), 359 MB Texturen (377), Knoten 773; FPS unter Software-Rendering nicht aussagekräftig |
| iPhone (echtes Gerät) | **nicht gemessen** – `?perf=1` durch den Projektinhaber |

## 14. Grenzen (ehrlich)
- Keine Ausweichbewegung zwischen NPCs (sie können sich auf Wegen überlagern); keine Türanimation (NPCs „verschwinden“ an der Tür).
- Tippen-zum-Gehen des Spielers nutzt weiterhin die direkte Steuerung (nicht A\*).
- Gesellschaft am Platz steigt unabhängig davon, ob andere dort sind (Anwesenheits-Bonus erst mit sozialen Beziehungen, Phase 5).
- Kein Geld, keine Vorräte: Essen/Einkaufen verbraucht nichts (Wirtschaft Phase 6).
- Kein Altern, keine Geburten/Todesfälle, keine Zu-/Abwanderung (Phasen 4/8).
- Innenräume nicht begehbar; Gespräche sind kurze Zeilen, keine Dialoge (Phase 5).
- Andere Siedlungen werden lokal nicht simuliert (Einzelspieler).
