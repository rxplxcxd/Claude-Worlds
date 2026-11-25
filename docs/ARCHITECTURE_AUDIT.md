# Architektur-Audit vor Phase 4 (24.11.2026)

Abgleich **Master-Prompt** (maßgeblich) ↔ Roadmap/Dokumente ↔ Code (Stand 0.5.0), ausgelöst durch die verbindlichen Architekturkorrekturen des Projektinhabers. Bei Widersprüchen gilt der Master-Prompt.

## 1. Abweichungen und Korrekturen

| # | Befund (Stand 0.5.0) | Master-Prompt / Vorgabe | Korrektur |
|---|---|---|---|
| A1 | Weltzustand lebt im **lokalen Spielstand** des Clients (`WorldState` → `user://worlds_world.json`); die Simulation läuft im Client und rechnet nach Abwesenheit **lokal hoch** | §7.3, §20.5, §21, Phase 12/13: autoritative Serversimulation, Client vertraut nie auf vom Client erzeugte Zustände; Welt läuft unabhängig von Spielern | **Weltautorität** (`WorldAuthority`) als eigene, szenenlose Schicht mit Befehlen, Ereignisprotokoll, Snapshots und Weltuhr; Client nur über `WorldClient`-Schnittstelle. Lokaler Betrieb = **Entwicklungsadapter** (`LocalWorldClient`), dieselbe Logik läuft später serverseitig (§2) |
| A2 | „Nachhol-Obergrenze 14 Tage“: nach langer Abwesenheit wird der Tag **neu angesetzt** (P3-G) | Welt darf nicht „künstlich auf einen neuen Zustand hochgerechnet“ werden; 5 Jahre offline = tatsächliche Weltentwicklung | Langzeitentwicklung (Alter, Gesundheit, Beschäftigung, Versorgung, Gebäudezustand, Bevölkerung, fremde Spieleraktionen) läuft in **S2/S3** der Autorität kontinuierlich und ereignisgenau; nur der **Tagesablauf-Mikrozustand** (wo jemand gerade steht) wird beim Hochstufen nach S1 deterministisch abgeleitet |
| A3 | Roadmap-Frage „Obergrenze NPCs je Siedlung auf älteren iPhones“; Grafikprofil-Feld `npc_detail_cap` | Weltbevölkerung geräteunabhängig (Vorgabe §2) | Frage gestrichen. `npc_detail_cap` begrenzt **nur** die Zahl gleichzeitig detailliert animierter Figuren im Bild; die Bevölkerung ist für alle gleich (Test) |
| A4 | **12 NPCs** in der Gründungsgemeinschaft | §4.2: **ungefähr 20 bis 50 NPCs** mit Verwaltung, Wasser, Energie, Lebensmitteln, Bau/Instandhaltung, Handel, Sicherheit, Medizin, Brand-/Notfallschutz, Transport, allgemeinen Arbeitskräften | Phase 4: Startbevölkerung per Simulation im Bereich 20–50 ermittelt (LIVING_WORLD.md / SETTLEMENT_SYSTEM.md) |
| A5 | Persönlichkeit: 5 Werte, Tagesabläufe stark wiederholend, Entscheidungen fast deterministisch gleich | Vorgabe §6; Master §10: eigenständige NPCs | Persönlichkeitsmodell erweitert (Extraversion, Selbstvertrauen, Pflichtbewusstsein, Zuverlässigkeit, Neugier, Ehrgeiz, Impulsivität, Chronotyp, Vorlieben); **gewichtete Zufallsauswahl mit Seed** (reproduzierbar, aber nicht jeden Tag gleich) |
| A6 | Schichten fest je Rolle, alle beginnen gleichzeitig | Vorgabe §6.5; Master §13.4–13.6 (Vertretung, Mindestbesetzung) | **Betriebsmodelle** je Gebäudetyp (Öffnungszeiten, 1–3 Schichten, 24/7), rotierende Dienstpläne, Pausen, individuelle Verschiebungen, Vertretung/Rufbereitschaft bei Ausfall |
| A7 | Keine Krankheit, Unfälle, Fehlzeiten, Konsequenzen | Vorgabe §6.3 | Gesundheitsmodell (Krankheit, Unfall, Genesung, Arztbesuch), Zuverlässigkeit (Verspätung, Fehlen), Beschäftigungsstatus (Abmahnung, Entlassung) – **ohne Geld** (Löhne/Finanzen = Phase 6, dokumentiert) |
| A8 | Navigation: statisches Raster, kein Ausweichen, keine Umplanung | Vorgabe §5, §9.4 | Dynamische Sperren/Bauen/Abreißen mit Versionierung und Chunk-Cache, Umplanung während der Reise, lokales Ausweichen, eindeutige Stehplätze |
| A9 | NPCs „verschwinden“ an Türen; nur Idle/Walk/Interact importiert | Vorgabe §9 | Penzilla liefert **Sit, GetUp, Run, Dig, Swing** (+ Damage, Die, Fish) → importiert; Animations-Zustandsautomat; eigene Tür-Overlays im Penzilla-Stil |
| A10 | Siedlungen nur aktiv/vorhanden; kein Verlassen, kein Verfall | Vorgabe §8; Master §13.8 (Abwesenheit ohne Verpflichtung ist kein Problem) | Siedlungs-Lebenszyklus: *aktiv* → (nur bei 0 Bewohnern) *verlassen* → Verfall über Living-Assets-Zustände; Gründer-Account-Löschung löscht nie die Siedlung |
| A11 | Kein Alter/Tod/Zuzug | Phase 4 „Bevölkerungsentwicklung“; Familien/Kinder = **Phase 5**; NPC-Migration zwischen Siedlungen = **Phase 8** | Phase 4: Altern, Sterblichkeit, Zuzug neuer Siedler bei freiem Wohnraum/Versorgung. Partnerschaften, Geburten, Kinder: Datenmodell + Konzept vorbereitet, **aktiviert in Phase 5** |
| A12 | `FIREBASE_SCHEMA.md` beschreibt Firestore als Weltspeicher | Master §20: Firebase = Daten-/Auth-Grundlage, **nicht** der Simulationsserver | Schema um Autoritäts-Schnittstelle ergänzt: Firestore hält Snapshots + Ereignisprotokoll, die Simulation gehört in einen späteren Simulationsdienst (Phase 12/13). Keine kostenpflichtigen Dienste beauftragt |

## 2. Zielarchitektur (verbindlich ab 0.6.0)

```
Client (Godot, iOS Safari/PWA)                       Weltautorität (heute in-process, später Server)
  SettlementScene / HUD / Globe  ── WorldClient ──►  WorldAuthority
     Darstellung nur aus Snapshots        Befehle      ├─ Weltuhr (UTC der Autorität)
     (render_info = f(Zustand, Zeit))     ◄── Snapshots ├─ Befehlsprüfung (Berechtigung, Regeln), idempotent (command_id)
                                                        ├─ Ereignisprotokoll je Siedlung (append-only, kompaktiert in Snapshots)
  LocalWorldClient  = Entwicklungsadapter               ├─ Simulationsstufen je Siedlung:
  RemoteWorldClient = Phase 12 (Firebase Auth +         │    S0/S1 hot: Einzel-NPC ereignisgesteuert (SettlementSim)
                      Simulationsdienst)                │    S2 warm:  Tagesschritt aggregiert (Versorgung, Gesundheit,
                                                        │              Beschäftigung, Alter, Gebäudezustand, Bevölkerung)
                                                        │    S3 kalt:  Wochenschritt + geplante Ereignisse
                                                        └─ Persistenz: Snapshot + Protokoll (lokal: Datei; später Firestore)
```
- **Ein Weltzustand für alle**: Snapshots sind für jeden Client identisch (Hash-Test); Grafikprofile wirken nur in der Darstellung.
- **Detailstufe bestimmt Rechenaufwand, nicht Existenz**: Ereignisse (Krankheit, Tod, Zuzug, Ausfälle, fremde Befehle, Verfall) werden in jeder Stufe verarbeitet.
- **Determinismus**: Zufall nur über Seeds (Welt, Siedlung, NPC, Tag) → serverseitig nachvollziehbar und testbar.

## 3. Grenzen des Entwicklungsadapters (ehrlich)
Ohne Server läuft die Autorität nur, solange ein Client läuft; beim Start wird sie bis „jetzt“ fortgeschrieben – **dieselbe** Logik, die ein Server kontinuierlich oder bei Zugriff ausführt. Andere Spieler existieren lokal nur als Testbefehle. Echte gemeinsame Welt = Phase 12/13.

## 4. Status (v0.1 / 0.6.0)
A1 ✔ Weltautorität + Client-Schnittstelle · A2 ✔ jeder Tag wird simuliert · A3 ✔ Bevölkerung geräteunabhängig (Test) · A4 ✔ 30 NPCs per Simulation · A5 ✔ Persönlichkeit messbar · A6 ✔ Betriebsmodelle, Rotation, Vertretung · A7 ✔ Gesundheit, Fehlzeiten, Entlassung (ohne Geld) · A8 ✔ dynamische Navigation · A9 ✔ Animationen + Türen (Türbilder jetzt vorhanden) · A10 ✔ Lebenszyklus · A11 ✔ Altern/Tod/Zuzug (Familien Phase 5) · A12 ✔ Firestore-Rolle dokumentiert.
