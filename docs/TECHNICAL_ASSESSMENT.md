# TECHNICAL_ASSESSMENT – Bewertung der Architektur (Stand 0.3.0) gegen die Designvorgaben

Datum: 24.11.2026 · Grundlage: [DESIGN_DIRECTIVES.md](DESIGN_DIRECTIVES.md) · Geprüft wurde der tatsächliche Code von Phase 1 + 2 (nicht nur die Dokumentation).

## Zusammenfassung
Das Fundament ist tragfähig: Echtzeit in UTC, deterministischer, gebackener Planet, Datenklassen ohne Szenenbezug, persistente IDs, getrennte Globus- und Siedlungsszene, Absichten über Services. **Vier Stellen widersprechen den Vorgaben direkt** und müssen vor oder mit den nächsten Phasen geändert werden:

1. **Territorium = ganze natürliche Region** (Ø ~440 000 km²) + 300 km Mittelpunktabstand → höchstens ~157 Siedlungen. Muss zu eigenen Territoriums-Polygonen mit 20-km-Grenzabstand werden.
2. **Harte Sperren** (±62°, Eis, Hochgebirge) → Schwierigkeitsmodell.
3. **Siedlungslayout ist nicht persistent**: Es wird bei jedem Start aus der Vorlage gelesen; Gebäude/Straßen sind keine gespeicherten, veränderbaren Entitäten. Freies Bauen/Abreißen wäre so nicht speicherbar.
4. **Bodendarstellung als ein einziges Zeichenobjekt** (kein Culling, viele Texturwechsel) und volle Geräteauflösung → wahrscheinliche Hauptursachen der ~30 FPS; bei 1 × 1 km (≈ 15× mehr Kacheln) nicht tragfähig.

## 1. Bereits unterstützt

| Bereich | Was schon passt | Wo |
|---|---|---|
| Geografie | Deterministischer Planet, Kontinente/Regionen mit stabilen IDs, Breite/Länge, Großkreisdistanz, gebackene identische Daten für alle | `scripts/geography/*`, `data/world/planet/` |
| Hierarchie-IDs | `pln_ / cnt_ / reg_ / stl_ / ter_ / pol_` vorgesehen; Siedlung speichert Position, Region, Kontinent, Territorium | `WorldState`, ARCHITECTURE §5 |
| Leerer Planet | Natur ohne Siedlungen; Gründung nur durch Menschen; Invarianten getestet | `WorldState._check_record` |
| Globus | Getrennte Szene, nur aggregierte Daten, exakte Auswahl über Projektionsmatrix, Zoomstufen, Infotafel | `scripts/globe/*` |
| Standortbewertung | Faktorenmodell (Wasser, Klima, Boden, Rohstoffe, Gelände, Nachbarschaft) – erweiterbar zum Schwierigkeitsmodell | `Geography.rate_site` |
| Zeit | UTC als einzige gemeinsame Basis, Siedlungszeitzone gespeichert, Server-Offset vorgesehen | `GameClock` |
| Persistente Identitäten | NPCs mit dauerhaften Namen/Rollen/Aussehen; Spielerfigur als kleines Dictionary | `NpcRoster`, `LocalProfile` |
| Zustand zur Uhrzeit | NPCs erscheinen dort, wo ihr Plan zur aktuellen Uhrzeit sie vorsieht (kein Nachsimulieren) | `Npc.place_for_hour` |
| Regelbasierte Platzierung | Straßenmobiliar wird aus dem Straßennetz abgeleitet, nicht fest gesetzt → passt zu veränderbaren Straßen | `StreetPlanner` |
| Server-Tauglichkeit | Handlungen laufen über Services (`InteractionService.run_action`), UI ↔ Welt nur über Signale/Dictionaries | ARCHITECTURE §1 |
| Migration | Versionierte Daten, einmalige Migration alter Spielstände erprobt | `WorldState._migrate_positions` |

## 2. Fehlende Funktionen

| Vorgabe | Fehlt |
|---|---|
| §1 Tausende Siedlungen | Territorien als Polygone, räumlicher Index, Unterregionen, Cluster-Darstellung auf dem Globus |
| §2 Besiedelbarkeit | Schwierigkeitsmodell, Voraussetzungen (Technologie/Ressourcen), Polartag/-nacht im Sonnenmodell (derzeit ±60° begrenzt), Kamera bis zu den Polen (derzeit ±80°) |
| §3 20-km-Regel | Geodätische Polygon-Distanz, Startfläche, Sperrzonen-Overlay, serverseitige Transaktion, Gelände-Verfeinerung unter 49 km |
| §4 Gründung | 1 × 1-km-Siedlungsfläche mit Chunks, absichtlich ineffizientes Gründungspaket, Auswahl „Beitreten / Gründen“, Beitritt (braucht Mehrspieler) |
| §5 Gestaltungsfreiheit | Persistenter Siedlungszustand (Grundstücke, Gebäude, Straßengraph, Zonen, Netze), Bau-/Abriss-/Verschiebe-Befehle, Bauzeit/-kosten, Planungsmodus |
| §6 Eigentum & Befugnisse | Eigentumsregister, Ämter, Berechtigungsprüfung, Verfahren (Fristen, Entschädigung, Umsiedlung) |
| §7 Gesetzgebung | Gesetzes-Engine (Regeln, Bedingungen, Anforderungen, Sanktionen, Einspruch, Ebenen), Abstimmungen, Baukasten-UI |
| §8 Mehrstufige Simulation | Simulationsstufen S0–S3, `advance()`-Fortschreibung, Ereigniswarteschlange, Server |
| §9 60 FPS | Messwerkzeug auf dem Gerät, gekachelter Boden, Atlas/Batching, Auflösungsskalierung, Sichtbarkeits-Drosselung |

## 3. Erforderliche Architekturänderungen

| # | Änderung | Warum | Wann (Vorschlag) |
|---|---|---|---|
| A1 | **Territorium entkoppeln:** `Territory.geometry` (sphärisches Polygon) statt `region_ids`; natürliche Regionen nur noch Landschaft/Statistik | Viele Siedlungen pro Region, dynamische Grenzen | Phase 2.1 |
| A2 | **Gründungsprüfung** = geodätische Grenz-zu-Grenz-Distanz ≥ 20 km zur 1-km-Startfläche; Sperrzonen-Overlay | Vorgabe §3 | Phase 2.1 |
| A3 | **Schwierigkeitsmodell** statt Sperren (Breite/Eis/Gebirge); Sonnenmodell ohne ±60°-Grenze | Vorgabe §2 | Phase 2.1 |
| A4 | **Räumlicher Index** (Würfel-Kugel-Quadtree, Ebene 8 ≈ 24 km) für Territorien/Siedlungen | Tausende Einträge, Firestore-Abfragen | Phase 2.1 (lokal), Phase 12 (Server) |
| A5 | **Siedlungszustand als Entitäten-Datenbank** pro Siedlung: Grundstücke, Gebäude, Straßengraph, Zonen, Netze, Props – mit IDs, Version, in Chunks gespeichert. Vorlage nur einmalig beim Gründen kopiert | Vorgabe §5; heute nicht speicherbar | Phase 4 (Struktur) / 7 (Bauen) |
| A6 | **Befehle statt direkter Änderungen:** `BuildCommand`, `DemolishCommand`, `MoveCommand`, `RezoneCommand`, `RoadCommand` → Berechtigungsprüfung → Ausführung → Ereignis | Eigentum/Gesetze, Server-Autorität, Undo/Protokoll | Phase 7 |
| A7 | **Berechtigungs-Pipeline** (Weltregeln → Eigentum → Amt → Gesetze) als zentraler Dienst | Vorgabe §6/§7 | Phase 7 (ohne Gesetze), Phase 9 (mit Engine) |
| A8 | **Gesetzes-Engine** datengetrieben (Regeln/Bedingungen/Anforderungen/Sanktionen), Verfahren als Zustandsautomat | Vorgabe §7 | Phase 9 |
| A9 | **Simulationskern** mit `advance(einheit, zeit)`, Raten + Ereignissen, Stufenwechsel | Vorgabe §8 | Phase 3 (lokal) |
| A10 | **Lokale Karte gechunkt** (z. B. 16 × 16 Kacheln je Chunk) für Laden, Culling, Speichern, Synchronisation | 1 × 1 km = 10 000 Kacheln; Performance | vor/mit Phase 4; Boden-Chunking schon im Performance-Paket |
| A11 | **Gelände-Verfeinerung** (deterministisch, serverentschieden) für 1-km-Flächen | 49-km-Zellen zu grob für Küsten/Flüsse | Phase 4 |
| A12 | **Referenzielle Integrität**: NPC-Wohnung/Arbeitsplatz, Mietverträge, Verfahren verweisen auf Gebäude-IDs → Abriss muss Folgen auslösen (Umzug, Kündigung) | Gestaltungsfreiheit ohne kaputte Verweise | Phase 7 |

Was **nicht** geändert werden muss: Planetengenerator, Regions-IDs, Globus-Grundaufbau, Zeitmodell, Figuren-/NPC-Identitäten, Asset-Pipeline.

## 4. Technische Risiken

| Risiko | Bewertung | Gegenmaßnahme |
|---|---|---|
| **Feinauflösung des Geländes** (49 km → 10 m) bleibt plattformübergreifend identisch | hoch | Server entscheidet; Ganzzahl-/Festkomma-Rauschen; oder höher aufgelöst backen |
| **Globus mit Tausenden Territorien/Markern** | mittel | Kachelweises Laden nach Sicht, Cluster planetar, Meshes nur kontinental/regional |
| **1-km-Siedlung auf dem iPhone** (10 000 Kacheln, Hunderte Gebäude/NPCs) | hoch | Chunking, Culling, Atlas, Simulationsstufen schon innerhalb der Siedlung |
| **Gesetzes-Engine wird zu komplex/langsam** | mittel | Kleiner fester Satz an Fakten/Wirkungen, Kostenlimit, Regel-Index, Vorschau, Vorlagen |
| **Aggregation ↔ Einzelsimulation inkonsistent** | mittel | Erhaltungsgrößen, deterministische Seeds, Tests |
| **Serverkosten** bei Tausenden Siedlungen | mittel | S3 ereignisbasiert, Auswertung bei Bedarf, Sharding nach Zellen |
| **Penzilla-Sprites haben feste Ausrichtung** (nur gespiegelt nutzbar) | mittel | „Drehen“ = 2 Ausrichtungen; Eingänge an Spiegelung koppeln; Straßenanschluss-Regeln |
| **Gameplay-Balance „ineffizient, aber nicht frustrierend“** | mittel | Klare Ausbauziele, Mindestversorgung, keine Sackgassen (GAMEPLAY_DESIGN §5) |
| **Datenmigration** bei jeder Modelländerung | mittel | Versionierte Schemas, Migrationen wie in Phase 2 erprobt |

## 5. Mögliche Exploits (Auswahl, Details in den Fachdokumenten)
- **Gründung:** Mehrfachgründungen, Zweitaccounts, Blockade- und Einkreisungsgründungen, strategisches Beanspruchen, gleichzeitige Gründungen (Race), Zeitmanipulation → [TERRITORY_SYSTEM.md](TERRITORY_SYSTEM.md) §7.
- **Bauen/Eigentum:** Abriss fremden Eigentums über Amtsmissbrauch, Schein-Verkäufe zur Umgehung von Gesetzen, Blockieren von Zufahrten, Abriss bewohnter Häuser ohne Ersatz → Berechtigungs-Pipeline + Weltregeln ([LAW_ENGINE.md](LAW_ENGINE.md) §2, §8).
- **Gesetze/Politik:** Diskriminierende oder rückwirkende Gesetze, Abstimmungsmanipulation mit Zweitaccounts/NPC-Mehrheiten, Gesetzes-Spam → [LAW_ENGINE.md](LAW_ENGINE.md) §8.
- **Simulation:** Zeitreisen über die Geräteuhr, Ausnutzen der Fortschreibung (Abmelden zum „Ernten“), doppelte Ereignisverarbeitung → nur Serverzeit, deterministisches `advance`, idempotente Ereignis-IDs ([SIMULATION_ARCHITECTURE.md](SIMULATION_ARCHITECTURE.md) §6).
- **Client:** Manipulierte Clients senden ungültige Bauten/Gründungen → jede Prüfung serverseitig wiederholen; Client-Ergebnis ist nur Vorschau.

## 6. Auswirkungen auf die spätere Mehrspieler-Architektur
- **Autoritativer Server** für: Gründung (Geometrie-Transaktion), Bauen/Abreißen (Befehle), Gesetze/Verfahren, Simulation (`advance`), Zeit.
- **Datenmodell klein und kachelbar:** Territorien mit Index-Zellen, Siedlungen in Chunks, Ereignisprotokoll → Synchronisation nur des Sichtbereichs.
- **Gemeinsame Logik** Client/Server: Datenklassen ohne Szenen (schon heute so gebaut); Gesetzes- und Simulationskern ebenfalls szenenfrei planen.
- **Firestore-Struktur** um Index-Felder (`cover_l8`), Chunks, Verfahren und Gesetze erweitert ([FIREBASE_SCHEMA.md](FIREBASE_SCHEMA.md)); Realtime Database für Präsenz.
- **Abhängigkeit:** „Beitreten“ (Vorgabe §4A) ist erst mit gemeinsamer Welt (Phase 12) wirklich möglich; im Einzelspieler kann die Auswahl angezeigt, Beitreten aber nur erklärt werden.

## 7. Vorschlag zur Umsetzung in Phasen
Siehe [ROADMAP.md](ROADMAP.md) – Kurzfassung:

| Paket / Phase | Inhalt aus den Vorgaben |
|---|---|
| **2.1 Geografie-Korrekturen** (klein, vor Phase 3, nur nach Freigabe) | A1–A4: Polygon-Territorien (1 × 1 km), 20-km-Grenzabstand, Sperrzonen, Schwierigkeitsmodell statt Sperren, räumlicher Index, Polar-Sonne; Auswahlbildschirm „Beitreten / Gründen“ (Beitreten als „bald verfügbar“) |
| **Performance-Paket** (parallel/vor Phase 3) | Messanzeige (Frame-Zeit, Draw-Calls, Speicher), Boden in Chunks/Atlas, Auflösungsskalierung, Drosselung unsichtbarer Objekte; **Messung auf deinem iPhone** |
| **3 Living World** | A9 Simulationskern + Stufen S0/S1 lokal, NPC-Bedürfnisse/Tagesabläufe/Navigation (wie geplant) |
| **4 Settlement Foundation** | A5/A10/A11: 1-km-Siedlungsfläche, Chunks, Gründungspaket (klein, ineffizient), Gelände aus der Region |
| **7 Property & Construction** | A6/A7/A12: Bauen/Verschieben/Abreißen, Grundstücke, Zonen, Straßengraph, Eigentum, Berechtigungen, Räumung/Entschädigung (Standardregeln) |
| **8/9 Inter-Settlement, Politics** | Territoriale Erweiterung, A8 Gesetzes-Engine mit Ebenen, Abstimmungen |
| **12/13 Multiplayer** | Server-Autorität, S2/S3 serverseitig, Beitreten, Anti-Exploit-Maßnahmen |
