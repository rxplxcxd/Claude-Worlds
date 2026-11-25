# LIVING_WORLD – lebendige Welt (Phase 3, vertieft in 0.6.0)

Stand 0.6.0: Architekturkorrekturen und Vertiefung laut Auftrag vom 24.11.2026 (Abweichungen: [ARCHITECTURE_AUDIT.md](ARCHITECTURE_AUDIT.md)). Siedlungsgründung, Grundversorgung, Verwaltung usw. (Phase 4): [SETTLEMENT_SYSTEM.md](SETTLEMENT_SYSTEM.md). Weltautorität, Detailstufen, Befehle: [SIMULATION_ARCHITECTURE.md](SIMULATION_ARCHITECTURE.md). Soziales Leben (Phase 5, seit 0.11.0): Beziehungen, Familien und Kinder, Vereine, Erinnerungen, Ziele, Gespräche – [SOCIAL_SYSTEM.md](SOCIAL_SYSTEM.md).

## 1. Überblick

```
data/sim/living_world.json          Bedürfnisse, Aktivitäten, Persönlichkeit, Betriebsmodelle, Gesundheit,
                                    Beschäftigung, Demografie, Versorgung, Gründungsbevölkerung
scripts/sim/settlement_core.gd      SettlementCore – TAGESSCHRITT der Siedlung (Makro, jede Detailstufe)
scripts/sim/npc_brain.gd            NpcBrain       – Tagesablauf EINER Person (Mikro, S0/S1)
scripts/sim/settlement_sim.gd       SettlementSim  – Mikro + Makro einer Siedlung, Persistenz, Abfragen
scripts/sim/nav_grid.gd             NavGrid        – begehbares Raster, dynamische Sperren, Caches
scripts/sim/visual_event_router.gd  Simulation → Living Assets / VFX
scripts/world/world_authority.gd    WorldAuthority – Weltzustand, Befehle, Detailstufen (server-fähig)
scripts/npc/npc.gd                  Darstellung + Animationszustände (nur Anzeige)
```
Alle `scripts/sim/*` und `world_authority.gd` sind **szenenlose Datenklassen** – unverändert auf einem späteren Simulationsserver lauffähig.

## 2. Zwei Ebenen, eine Welt
| Ebene | Code | Wann | Was |
|---|---|---|---|
| **Makro** | `SettlementCore.day_step` | einmal je Siedlungs-Ortstag, in **jeder** Detailstufe identisch | Gesundheit, Fehlzeiten, Dienstplan, Vertretung, Unfälle, Versorgung, Gebäudezustand, Brände, Einstellungen/Entlassungen, Altern, Tod, Zuzug, Lebenszyklus |
| **Mikro** | `NpcBrain.advance` | nur wenn jemand hinsieht (S0/S1) | wer gerade wo was tut, Bedürfnisse, Wege |
Das Mikro **liest** das Makro (Dienstplan, Gesundheit, Beschäftigung, Engpässe) und verändert es nicht. Getestet: 3 Wochen in voller Detailstufe und 3 Wochen nur mit Tagesschritten ergeben **denselben** Siedlungszustand.

**Siedlungszeit:** feste Zeitverschiebung der Gründung (`record.time_zone.offset_min`), für **alle Betrachter gleich**. Die bisherige Sonderregel „Gerät des Gründers folgt der Sommerzeit“ wurde entfernt, weil sie den Zustand geräteabhängig gemacht hätte; Sommerzeit-Regeln folgen mit einer serverseitigen Zeitzonendatenbank (Phase 12).

## 3. Persönlichkeit (messbar)
Je NPC dauerhaft (`record.npcs[].personality`), Normalverteilung um 0,5; alte Werte werden übernommen (Offenheit → Neugier, Fleiß → Pflichtbewusstsein):

| Merkmal | Wirkung im Code | gemessen (Test, je 26 NPCs, 7 Tage) |
|---|---|---|
| Extraversion | Bedarf an Gesellschaft ×(0,4…1,6), Treffen am Platz ×(0,3…1,7) + Zuschlag, Zuhause-Bleiben ↔ | Treffen: introvertiert **145** vs. extravertiert **695** |
| Selbstvertrauen (↔ Schüchternheit) | Besorgungen, Auswärtsessen | – |
| Geselligkeit | Treffen ×(0,7…1,3) | – |
| Pflichtbewusstsein | früher zur Schicht (5–20 min), Arbeitsbonus, Waschen, frühere Weckzeit | – |
| Zuverlässigkeit | Verspätung bis 25 min, unentschuldigtes Fehlen 0,6× … 1,5× Basis | 120 Tage: unzuverlässig **19**, zuverlässig **2** Fehltage |
| Risikobereitschaft | Arbeitsunfälle ×(0,5…1,5) | – |
| Neugier | Freizeitbedarf, Abwechslung, Grünflächen | – |
| Ehrgeiz | Überstunden bis 15 min | – |
| Impulsivität | Zufallstemperatur der Auswahl, länger unterwegs, spätere Bettzeit | – |
| Chronotyp (−1 Frühaufsteher … +1 Nachteule) | Weck- und Bettzeit, Wochenende länger | Samstag aktiv ab **5,9 h** vs. **7,8 h** |
| Vorlieben | Lieblingsort (Park/Platz), Auswärtsessen | – |

## 4. Entscheidungen (Utility AI, gewichteter Zufall mit Seed)
`Wert = Σ Druck(Bedürfnis)·Gewinn / √Dauer + Boni + Persönlichkeit − Weg − Wiederholung − Abklingzeit`.
Dann **gewichtete Zufallsauswahl** unter den vier besten Möglichkeiten (Softmax, Temperatur 0,08 + 0,45 × Impulsivität, Seed = NPC + Entscheidungsnummer). Pflichten (Arbeit, Pause) und Erschöpfung werden nicht dem Zufall überlassen. Ergebnis: **reproduzierbar** (gleicher Seed → gleicher Tag), aber kein Tag gleicht dem anderen (Test: 6 von 6 Tagen einer Bewohnerin unterschiedlich). Kein LLM.

## 5. Arbeit: Betriebsmodelle, Dienstpläne, Pausen
Arbeitszeiten kommen nicht mehr aus der Rolle, sondern aus dem **Betriebsmodell des Arbeitsplatzes** (`operating_models`):

| Betrieb | Funktion | Schichten (Ortszeit) |
|---|---|---|
| Gemeindehaus | Verwaltung | Büro Mo–Fr 8:00–16:30 |
| Wasserwerk | Wasser (kritisch) | Tagdienst täglich 6–14 + Rufbereitschaft nachts |
| Energiestation | Energie (kritisch) | Tagdienst täglich 12–20 + Rufbereitschaft |
| Hof | Lebensmittel | Feld früh Mo–Sa 5:30–13:30 (3), Feld spät 11–19 (1) |
| Praxis | Medizin (kritisch) | Praxis Mo–Sa 7–15, Spätdienst Mo–Fr 13–21, Rufbereitschaft |
| Wache | Brand-/Notfall (kritisch) | Tag 7–15, Abend 15–23 täglich + Rufbereitschaft nachts |
| Depot | Bau & Transport | Bau Mo–Fr 7–15:30 (2), Transport Mo–Sa 9–17 |
| Werkstatt, Handelsposten, Läden | Handwerk, Handel | 8–16 / Früh 7:30–14 + Spät 13–19:30 / 7–15 |
- **Dienstplan** je Tag (`SettlementCore.roster_for_day`): wöchentliche Rotation (Früh/Spät wechselt), in 7-Tage-Betrieben zwei rotierende freie Tage, individuelle Startverschiebung −10…+10 min → **gestaffelte Schichtbeginne** (Test: ≥ 8 verschiedene Beginnzeiten an einem Tag).
- **Pause** in Schichten ab 6 h (30 min um die Schichtmitte, am Arbeitsplatz/auf einer Bank).
- **Vertretung** (Master §13.6): Fällt ein kritischer Dienst aus, springt eine freie Kollegin oder eine allgemeine Arbeitskraft ein; allgemeine Arbeitskräfte füllen auch sonstige Lücken und helfen sonst als Aushilfe auf dem Hof.
- **Unpünktlichkeit**: Verspätete laufen (Animation „Laufen“, 1,8× schneller).

## 6. Gesundheit, Zuverlässigkeit, Beschäftigung (ohne Geld)
- Krankheit 0,35 %/Tag (+2 % je Lebensjahr über 40, ×3 bei Nahrungs-/Wassermangel), 2–7 Tage, mit besetzter Praxis 40 % kürzer. Unfälle je Arbeitstag nach Funktion (Bau, Hof, Notfall …) × Risikobereitschaft, 4–15 Tage.
- Kranke werden aus dem Dienstplan genommen, bleiben zu Hause (`rest_sick`) und gehen zur Praxis (`see_doctor`) – getestet.
- Unentschuldigtes Fehlen (nur an Diensttagen) → Abmahnung; 3 in 45 Tagen → **Entlassung**, nach 10 Tagen neue Stelle über die Verwaltung (nicht beim alten Betrieb). Ruhestand mit 67.
- **Finanzielle Folgen** (Lohnausfall, Kündigungsfristen, Ersparnisse) gehören zu **Phase 6** – siehe [ROADMAP.md](ROADMAP.md#vorbereitete-anforderungen-für-spätere-phasen).

## 7. Navigation (dynamisch)
- Raster-A* (AStarGrid2D); Straßen begehbar, aber teurer; Orte = Türen, Platz, Grün; eindeutige Stehplätze je Ort (zweiter Ring bei Andrang).
- **Sperren/Öffnen** (Befehl `close_path`/`open_path` der Verwaltung, später Bauen in Phase 7): `NavGrid.set_closed` mit Versionsnummer. Gecachte Wege werden **gezielt** verworfen (Sperrung: nur Wege durch die Zelle; Öffnung: alle, weil Abkürzungen entstehen können).
- **Umplanung unterwegs**: Wer gerade geht, dessen Weg wird eingefroren; kreuzt der Rest die Sperrung, wird ab der aktuellen Position neu geplant (Test).
- **Ausweichen** (nur Darstellung): Rechtsverkehr auf Wegen (0,2 Kacheln) + Abstoßung unter 0,42 Kacheln; Stehende behalten ihren Platz. Test: keine zwei sichtbaren Figuren ineinander.
- Große Städte: Wegezeiten und Wege sind je Ortspaar gecacht; der Raster-A* ist lokal je Siedlung (Chunk = Siedlungsfläche). Für Städte über ~100×100 Kacheln ist eine hierarchische Wegsuche (Bezirke) vorgesehen – noch nicht nötig.

## 8. Simulationsstufen und Bevölkerung
| Stufe | Wo | Rechnung |
|---|---|---|
| S0 | NPCs im Bild (max. nach Grafikprofil) | Mikro + Animation |
| S1 | übrige NPCs der geöffneten Siedlung | Mikro, nur Daten |
| S2 | Siedlungen in der Region des Spielers | Tagesschritte alle 5 min |
| S3 | alle anderen | Tagesschritte bei Zugriff (oder Sammellauf) |
Die **Weltbevölkerung ist geräteunabhängig**: Grafikprofile begrenzen nur, wie viele Figuren gleichzeitig detailliert gezeichnet werden (`npc_detail_cap`), nie wie viele Menschen existieren (Test: zwei Autoritäten mit Profil Ultra bzw. Leistung und unterschiedlichem Takt → identischer Zustands-Hash).

Lange Abwesenheit: **jeder Tag** wird als Tagesschritt verarbeitet (5 Jahre ≈ 1 826 Schritte ≈ 6 s für eine Siedlung); nur der Mikrozustand (wo jemand gerade steht) wird nach mehr als einem Tag Lücke einen Tag vor jetzt neu angesetzt – das ist nicht beobachtbar.

## 9. Animationen
Penzilla „Ultimate Protagonist“: Stehen, Gehen, **Laufen**, Benutzen, **Hinsetzen, Aufstehen, Graben, Schlagen** (Hammer/Axt) und Werkzeug-Varianten (Stehen/Gehen/Sitzen/Aufstehen). Eigener Bildausschnitt je Animation (weit ausholende Bewegungen), Fußpunkt identisch (getestet). Zustandsautomat in `Npc.apply_render`:
Tür (an die Tür greifen, im Türbereich ein-/ausblenden) → Gehen/Laufen → Sitzen auf freien Bänken (eine Person je Sitz) → Aufstehen → Arbeiten passend zum Werkzeug (Graben mit Schaufel, Schlagen mit Hammer/Axt, sonst Benutzen) → Stehen/Zuwenden. QA-Galerie: `?gallery=anim`.
**Offen:** eigene Tür-Overlays (geöffnete Tür) im Penzilla-Stil – die Türpositionen der 19 Gebäudesprites müssen dafür einzeln vermessen werden; bis dahin Greifen + Einblenden.

## 10. Visuelle Folgen
- Aktive Effekte aus dem Zustand (Kaminrauch beim Kochen, Funken in der Werkstatt).
- Dauerhafte Gebäudezustände aus dem Tagesschritt: Abnutzung folgt dem Gebäudezustand (Instandhaltung durch den Bau), Brände (klein = gelöscht, groß = ohne Notfalldienst), in **verlassenen** Siedlungen Überwucherung und Schäden. Die Gebäude zeigen diese Zustände jetzt im Spiel (`Building.apply_visual_state` → LivingComposer).

## 11. Persistenz (Schema 5)
`record.npcs[]` (+ personality v2, alive, arrived_day, age_at_arrival, health, employment), `record.core` (Vorräte, Zustand, Abdeckung, Dienstplan heute/gestern, Ereignisse, Verlauf, Richtlinien, Zähler), `record.lifecycle`, `record.region_factors`, `record.authority` (Befehlsprotokoll), `record.nav_changes`, `record.sim` (Mikro, Version 2), `record.visual_states`. JSON mit voller Genauigkeit gespeichert.

## 12. Entscheidungen
| # | Entscheidung | Alternativen | Begründung |
|---|---|---|---|
| L-1 | Makro-Tagesschritt in jeder Stufe identisch, Mikro liest nur | getrennte vereinfachte Formeln je Stufe | Detailstufe ändert nie das Ergebnis (Test) |
| L-2 | Zeitskala Alter: **1 Lebensjahr = 60 reale Tage** (Tagesablauf Echtzeit) | 1:1 (nie Generationswechsel), 28 Tage (Gründer nach ~1 Jahr tot) | Kinder würden in ~3 Jahren erwachsen (Phase 5), Gründer leben typischerweise 5–8 reale Jahre; Bevölkerungsentwicklung wird in einer MMO-Laufzeit sichtbar, ohne dass Bekannte im Wochentakt sterben |
| L-3 | Seeds mit Murmur3-Finalisierung | Godots `String.hash()` | `hash("x#1")`, `hash("x#2")` liegen direkt nebeneinander → kein Zufall (gefunden: 0 Ereignisse in 60 Tagen) |
| L-4 | Gewichteter Zufall unter den besten Optionen | rein deterministisches Maximum | Abwechslung bei voller Reproduzierbarkeit |
| L-5 | Betriebsmodelle statt Rollenschichten | feste Rollenzeiten | Öffnungszeiten, Mehrschicht, Rotation, Vertretung realistisch abbildbar |

## 13. Leistung (headless, Desktop-CPU; Gerätewerte siehe PERFORMANCE.md)
| Messung | Ergebnis |
|---|---|
| Tagesschritt (Makro), 30 NPCs | ≈ 3 ms |
| 5 Jahre offline aufholen (Makro) | ≈ 6 s |
| 120 Tage Abwesenheit beim Öffnen | ≈ 0,9 s |
| Mikro: 1 000 NPCs, Warmstart + 1 Tag | ≈ 9,5 s (34 000 Ereignisse, ≈ 280 µs/Ereignis; 0.5.0: 2,2 s – mehr Verhalten je Entscheidung) |
| Mikro im Spiel (30 NPCs, 4×/s fortgeschrieben) | vernachlässigbar |
Eine Siedlung mit 1 000 Einwohner:innen wäre im Mikro heute zu teuer für Echtzeit-Aufholen über Tage – deshalb das Makro für alles außer der aktuellen Szene. Millionen gleichzeitig simulierter NPCs werden **nicht** behauptet.

## 14. Grenzen
- Keine eigenen Tür-Overlays (siehe §9); Innenräume nicht begehbar.
- Gesellschaft am Platz steigt unabhängig von Beziehungen (Phase 5).
- Sommerzeit der Siedlung fehlt (§2).
- Mikro-Kosten je Entscheidung gestiegen; Optimierung (Kandidaten-Vorfilter, Caching der Dienstplanabfragen) möglich, wenn größere Siedlungen sichtbar simuliert werden.
