# ROADMAP

Phasen werden **nur nach ausdrücklicher Freigabe durch den Projektinhaber** begonnen.

| Phase | Name | Status |
|---|---|---|
| 1 | World Foundation | **Freigegeben** (Projektinhaber startete Phase 2 am 24.11.2026); iPhone-Test weiterhin offen |
| 2 | World Geography | **Implementiert (0.3.0)** + **Paket 2.1 umgesetzt (0.4.0)**, Abnahme ausstehend |
| 2.x | Living Assets (visuelles Projekt, kein Gameplay) | Schritte A–G umgesetzt; Lizenz-PDF geprüft (Pflichtnennung + Bearbeitungsliste im Spiel seit 0.5.0); Anbindung an Simulationsereignisse vorbereitet (VisualEventRouter) |
| 3 | Living World | **Freigegeben 24.11.2026 – implementiert (0.5.0)**: Identitäten, Bedürfnisse, Tagesabläufe, Berufe, Navigation, Utility AI, Interaktionen, Simulations-LOD, Persistenz ([LIVING_WORLD.md](LIVING_WORLD.md)); Abnahme + iPhone-Test ausstehend |
| 4 | Settlement Foundation | umgesetzt (0.6.0), Abnahme offen |
| 5 | Social Life | umgesetzt (0.11.0), Abnahme offen |
| 6 | Economy | geplant |
| 7 | Property & Construction | geplant |
| 8 | Inter-Settlement Systems | geplant |
| 9 | Government & Politics | geplant |
| 10 | Councils & World Governance | geplant |
| 11 | Conflict & Society | geplant |
| 12 | Multiplayer Foundation (bis ~50 Spieler) | geplant |
| 13 | Persistent Multiplayer Universe | geplant |

## Phase 1 – Abnahmekriterien

| # | Kriterium | Stand |
|---|---|---|
| 1 | Projekt korrekt importierbar | ✅ lokal + CI |
| 2 | Szene startet zuverlässig | ✅ Headless, Chromium (Desktop/iPhone-Emulation), keine Fehler |
| 3 | Assets korrekt dargestellt | ✅ alle 6 Pakete geprüft und je nach Eignung integriert (ASSET_INVENTORY §2); im veröffentlichten Build erst nach Setzen des Secrets `MEGA_ASSETS_URL` |
| 4 | Spielfigur steuerbar | ✅ Tastatur, Joystick, Tippen (automatisiert getestet) |
| 5 | Kamera funktioniert | ✅ getestet |
| 6 | Touch-Eingaben funktionieren | ✅ automatisiert + Chromium-Touch-Emulation; ⏳ echtes iPhone |
| 7 | HUD sichtbar und bedienbar | ✅ |
| 8 | Webexport erfolgreich | ✅ lokal + CI |
| 9 | PWA-Grundlage vorhanden | ✅ Manifest, Service Worker, Icons, iOS-Meta |
| 10 | Build-Workflow funktioniert | ✅ CI-Lauf #1 grün |
| 11 | Deployment nachvollziehbar | ✅ Workflow + Doku; ⏳ Pages-Aktivierung/Merge nach `main` durch Projektinhaber |
| 12 | Verwendete Assets dokumentiert | ✅ ASSET_INVENTORY.md |
| 13 | Art-Direction-Regeln eingehalten | ✅ keine Fremd-Außenassets; technischer Wächter |
| 14 | Bekannte Fehler dokumentiert | ✅ siehe unten |
| 15 | Charakter-Editor (modular, lebendige Vorschau, Speicherung, im Spiel genutzt) | ✅ Browser + Tests (inkl. Bearbeiten-Ablauf); ⏳ iPhone |
| 16 | NPC-Rollenkleidung, dauerhaft | ✅ |
| 17 | Stadtbild nach Platzierungsregeln, Laternen mit Ausleger und Licht | ✅ |
| 18 | Figur hinter Gebäuden sichtbar | ✅ |
| 19 | Echtzeituhr mit automatischer Zeitzone/Sommerzeit | ✅ (Berlin, New York geprüft) |
| 20 | QA-Prüfliste | ✅ [QA_CHECKLIST.md](QA_CHECKLIST.md) |

### Bekannte Fehler / Einschränkungen Phase 1
1. Veröffentlichter Build zeigt Platzhalter, bis das Secret `MEGA_ASSETS_URL` gesetzt ist (Lizenzschutz, siehe ASSET_INVENTORY).
2. Tippen-zum-Gehen nutzt gerade Linien; hinter Hindernissen bleibt die Figur stehen (Pfadfindung = Phase 3).
3. Y-Sortierung per Grundflächenmittelpunkt; bei sehr großen Gebäuden können später Sortierfehler auftreten.
4. Innenräume noch nicht begehbar („Betreten“ zeigt Info); Top-Down Retro Interior + CC0-Pakete liegen bereit.
4a. NPCs wechseln den Ort ohne Weg (erscheinen am Arbeitsplatz/zu Hause); Präsenz nach Lokalzeit des Spielers statt Siedlungszeitzone.
4b. RPG-Läden sind im Detailmaßstab etwas größer als City-Builder-Häuser (bewusst, ADR-10); RPG-Häuser 2×2/3×3 noch ungenutzt.
4c. Sonnenmodell nutzt feste Breite 51° N bis Siedlungen echte Koordinaten haben (Phase 2).
5. Keine Audio-Ausgabe.
6. Node-20-Deprecation-Hinweis in GitHub Actions (nicht blockierend).
7. Echte iPhone-Leistung unbekannt.

### Designänderung 24.11.2026: Leerer Planet
Planet startet ohne Siedlungen; Siedlungen nur durch Spielergründung; keine NPC-only-Siedlungen. In Phase 1 als Regel umgesetzt (genesis.json, WorldState, Gründungsvorlage, Tests). Phase 2 muss die Planetengenese ohne Siedlungen und die Standortwahl für Gründungen liefern.

## Phase 2 – World Geography: Umfang und Stand

| Masterprompt-Punkt | Stand |
|---|---|
| Planetenmodell | ✅ Aurel, deterministisch erzeugt und gebacken (Seed 777, Generator v2) |
| Kontinente | ✅ 5 Kontinente + Inseln |
| Regionen | ✅ 157 Regionen mit Gelände, Klima, Wasser, Rohstoffen, Erschließung |
| Geografische Koordinaten | ✅ Breite/Länge, Großkreisdistanz, Zellraster |
| Weltkarte | ✅ Globus mit Infotafel, Ebenenschalter „Gebiete“ |
| Erste Globusdarstellung | ✅ 3D-Kugel, Küsten, Grenzen, Atmosphäre, Sterne |
| Zoomstufen | ✅ planetar → kontinental → regional → lokal (Siedlung betreten) |
| Siedlungsstandorte | ✅ Standortwahl + Bewertung bei der Gründung, Marker, Migration alter Spielstände |
| Territorien | ✅ Gründung beansprucht die Region; Anzeige, Regeln (keine fremde Region, Mindestabstand) |

### Bekannte Einschränkungen Phase 2
1. Lokale Siedlungskarte ist überall gleich (Vorlage), unabhängig von Region/Küste/Fluss → Phase 4.
2. Ein Gebiet = eine Region; kein Wachstum, keine Grenzen zwischen Siedlungen → Phase 4/9.
3. 49-km-Zellen wirken in der regionalen Zoomstufe grob (Grenzen als Treppenlinien).
4. Nur eine lokale Siedlung (Singleplayer); „Beitreten“ fremder Siedlungen erst mit Mehrspieler (Phase 12).
5. Kein Tag/Nacht-Schatten auf dem Globus.
6. Globus-Leistung auf echtem iPhone ungemessen.

## Designvorgaben vom 24.11.2026 – Einordnung in die Phasen
Verbindlich: [DESIGN_DIRECTIVES.md](DESIGN_DIRECTIVES.md) · Bewertung: [TECHNICAL_ASSESSMENT.md](TECHNICAL_ASSESSMENT.md). **Nichts davon ist implementiert**; jedes Paket startet erst nach Freigabe.

| Paket / Phase | Inhalte |
|---|---|
| **2.1 Geografie-Korrekturen** ✅ umgesetzt (0.4.0) | Territorien als Polygone (1 × 1 km Start), 20 km Grenzabstand geodätisch, Sperrzonen auf dem Globus, Schwierigkeitsmodell statt Sperren (±62°, Eis, Gebirge entfallen), räumlicher Index, Polar-Sonne, Auswahl „Beitreten / Gründen“ (Beitreten erklärt, aktiv ab Phase 12), Migration bestehender Territorien |
| **Performance-Paket** – Diagnose ✅ (0.4.0), Optimierungen O1–O9 vorgeschlagen (PERFORMANCE.md §7.3), warten auf Freigabe | Messanzeige, Boden in Chunks + Atlas, Sprite-Atlanten, dynamische Auflösung, Drosselung unsichtbarer Objekte; Messung auf dem iPhone ([PERFORMANCE.md](PERFORMANCE.md) §6) |
| **3 Living World** | Simulationskern (`advance`, Stufen S0/S1 lokal), Bedürfnisse, Tagesabläufe, Navigation ([SIMULATION_ARCHITECTURE.md](SIMULATION_ARCHITECTURE.md)) |
| **4 Settlement Foundation** | 1-km-Siedlungsfläche in Chunks, Gründungspaket (klein, ineffizient), Gelände aus der Region, Siedlungszustand persistent (ADR-17) |
| **7 Property & Construction** | Bauen/Verschieben/Abreißen über Befehle, Grundstücke, Zonen, Straßengraph, Eigentum, Berechtigungs-Pipeline, Räumung/Entschädigung |
| **8 Inter-Settlement** | Territoriale Erweiterung, Annäherung, Verträge über Grenzen ([TERRITORY_SYSTEM.md](TERRITORY_SYSTEM.md) §5) |
| **9 Government & Politics** | Gesetzes-Engine mit Ebenen, Verfahren, Abstimmungen ([LAW_ENGINE.md](LAW_ENGINE.md)) |
| **12/13 Multiplayer** | Server-Autorität für Gründung/Bau/Gesetze/Simulation (S2/S3), Beitreten, Anti-Exploit |

## Voraussetzungen für Phase 4 (Settlement Foundation)
Vorhanden aus Phase 3: Bewohner mit Bedürfnissen, Berufen, Arbeitsplätzen und Tagesablauf; Orte und Wegnetz; ereignisgesteuerte, persistente Simulation; Ereignis-Schnittstelle zu Living Assets.
Offen / zu entscheiden:
- Abnahme Phase 3 auf dem iPhone (Tagesablauf, Lesbarkeit, Leistung mit `?perf=1`).
- Startbevölkerung: bleibt es bei 12 oder abhängig von Schwierigkeit/Region? Obergrenze NPCs je Siedlung auf älteren iPhones (Messung).
- Grundversorgung: sollen Essen/Wasser/Energie Vorräte verbrauchen (Kopplung Bedürfnisse ↔ Ressourcen) schon in Phase 4 oder erst Phase 6?
- Siedlungsfläche 1 km² in Chunks (ADR-17) und Navigation über Chunks (Wegnetz je Chunk, Fernwege).
- Bevölkerungsentwicklung (Zuzug, Geburten) und verlassene Siedlungen (WORLD_DESIGN.md §5).


## Stand v0.1 (technisch 0.6.0, 25.11.2026)
- Architekturkorrekturen (Weltautorität, Detailstufen, geräteunabhängige Bevölkerung) – ARCHITECTURE_AUDIT.md, SIMULATION_ARCHITECTURE.md §9.
- Living World vertieft (Persönlichkeit, Betriebsmodelle, Gesundheit, Beschäftigung) – LIVING_WORLD.md.
- **Phase 4 – Settlement Foundation umgesetzt** (SETTLEMENT_SYSTEM.md §10) – Abnahme durch den Projektinhaber offen.
- **Phase 5 – Social Life umgesetzt** (0.11.0, SOCIAL_SYSTEM.md): Beziehungen, Familien und Kinder, Freundschaften, Gespräche, Vereine, Erinnerungen, persönliche Ziele – Abnahme durch den Projektinhaber offen.
- Gameplay-Polishing: Richtungen, Clip-Bibliothek, Türen, Innenräume, Kollisionen, Umland, Globus, Farbpalette, Ladenbeschreibungen, Versionsanzeige – INTERIORS_AND_INTERACTION.md, VERSIONING.md.

## Master-Erweiterung World Council (25.11.2026, technisch 0.7.0)
Weltratssitz auf **Kalistia**: Standort, Weltdefinition, Globus, eigenes Außen-Asset und begehbare Vorschau umgesetzt. Alle weiteren Bestandteile sind den bestehenden Phasen zugeordnet, ohne die Reihenfolge zu ändern: Restaurierung/Innenräume Phase 7, Reisen und Verkehr Phase 8, Delegierte Phase 9, Weltversammlung am 24. Juni Phase 10, Serverautorität Phase 12. Siehe [WORLD_COUNCIL.md](WORLD_COUNCIL.md) und [WORLD_COUNCIL_ROADMAP.md](WORLD_COUNCIL_ROADMAP.md).

## Vorbereitete Anforderungen für spätere Phasen
| Phase | Anforderung | Vorbereitung heute |
|---|---|---|
| 5 Social Life | **umgesetzt in 0.11.0** (SOCIAL_SYSTEM.md); offen: Spielerkinder, Spieler↔Spieler (Phase 12), Feste/Schule | – |
| 6 Economy | Löhne, Lohnausfall bei Krankheit/Fehlen, Kündigungsfristen, Ersparnisse, Preise, Einkaufen, Spieler-Arbeitsstellen, eigene Läden und Ladenbeschreibungen | Beschäftigungsstatus, Abmahnungen, Stellen, Versorgung, `business_texts`, Interieur-`upgrade` |
| 7 Construction | Bauen/Abreißen, Möbel kaufen und tauschen, Bett statt Matratze, Innenausbau, begehbares Umland, Territoriumserweiterung | Navigation mit Sperren/Versionen, Grundriss-Daten, Innenraum-Layouts als Daten, LocalTerrain |
| 8 Inter-Settlement | NPC-/Spieler-Wanderung, Wiederbesiedlung verlassener Siedlungen, Busverkehr | Befehl `join_settlement` (gesperrt), Lebenszyklus |
| 11 Conflict | Kriminalität, Verletzungen durch Konflikte | Clips flinch/hurt, Animation „Die“ importiert |
| 12/13 Multiplayer | Simulationsdienst, Firestore, Echtzeit | WorldAuthority/WorldClient, Befehle, Snapshots, Hash-Tests |
| Wetter/Jahreszeiten | regionales Wetter und Jahreszeiten (Master-Prompt: Klima/Geografie), Schnee auf Boden und Dächern | `record.climate`, Living-Assets-Schnee- und Wetterzustände |
