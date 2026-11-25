# Concordium – Phasenzuordnung

Die Phasenreihenfolge des Master-Prompts bleibt unverändert (1 Foundation … 13 Persistent Multiplayer Universe). Jeder Bestandteil des Weltrats wird der Phase zugeordnet, in der sein Fundament laut Master-Prompt entsteht. Hier wird nichts vorgezogen; die Abhängigkeiten sind dokumentiert, damit später nichts umgebaut werden muss.

## Jetzt umgesetzt (Arbeitspaket „World Council“, nach Phase 4)
| Bestandteil | Stand |
|---|---|
| Standortanalyse Kalistia, feste Koordinaten | ✅ `tools/world/council_site.gd`, `data/world/landmarks.json` |
| Registrierung in der Weltdefinition | ✅ Landmarke `lmk_world_council`, `genesis.json` |
| Persistenter Zustand (Stufe, Komponenten, Geschichte) | ✅ `WorldState.landmark_state`, im Weltstand gespeichert |
| ~~Schutzgebiet 18 km~~ → **Grundstücksgrenze = neutrale Zone** (172 × 172 m), Gründungsregel, Grenzänderung nur durch Weltautorität mit Beschluss | ✅ `Landmarks`, `WorldState.update_landmark_property` (Entscheidung 25.11.2026) |
| Namen Concordium / Concilium Mundi / Weltrat (lokalisiert) | ✅ Daten, Globus, Vorschau, Inschriften im Asset |
| Höhe ~56 m (33 Figurenhöhen) | ✅ Asset + Test |
| Neutralitäts-Regelwerk (3 Stufen), humanitäre Orte | ✅ Daten + Klassifikation + Tests (Wirkung ab Phase 11) |
| Verbindliches Innenraumprogramm mit Status | ✅ `data/landmarks/concordium_interiors.json` |
| Sichtbarkeit auf dem Globus | ✅ Oberflächenmarkierung + Info |
| Architekturkonzept | ✅ ART_DIRECTION §2 |
| Eigenes Außen-Asset (Stufe 1 „Historische Anlage“) | ✅ eigener Renderer, mehrere Iterationen |
| Erste Einbindung in Godot | ✅ Entwicklungsvorschau (kein Reisen) |
| Technische Grundlagen für Erweiterungen | ✅ Komponenten-IDs je Gebäudeteil, Stufen-Renderings, Gelände mit Höhen |

## Spätere Phasen
| Phase (Master-Prompt) | Weltrat-Bestandteil | Abhängigkeit |
|---|---|---|
| 5 Social Life | Besucher, Gespräche, Gruppen am Ort; Feiern/Gedenktage als soziale Ereignisse | NPC-Beziehungen |
| 6 Economy | Kosten von Reisen, Tickets, Maut, Unterkunft; Reisebudgets/Erstattungen; Hotels, Läden, Märkte am Sitz; Finanzierung von Restaurierungen | Preise, Löhne, Steuern, Unternehmen |
| 7 Property & Construction | **Alle Innenräume** nach dem Programm (Ratssaal, Ausstellungshallen mit erweiterbarem Ausstellungssystem, Diplomatie, Archiv, Gästehaus, humanitäre Einrichtungen); **Restaurierung und Ausbau** (Komponenten-Zustand, neue Gebäudeteile, Wasser- und Gartenanlagen), Bau von Infrastruktur im Schutzgebiet, Respekt des Schutzgebiets bei Gebietserweiterungen; **Innenräume** (Versammlungshalle, Diplomatenräume) mit dem Innenraumsystem | Bausystem, Ressourcen, Bauaufträge |
| 8 Inter-Settlement Systems | **Reise- und Verkehrssystem** für alle Spieler: Straßen, Autos (Kraftstoff, Zustand, Parken), Bahn (Netz, Fahrplan, Tickets, Umstiege), Busse/Shuttles, Schiffe (Häfen, Fähren), Flüge (Flughäfen, Check-in, Boarding, Reiseansicht über die Weltkarte); sichtbare Landschaft während der Reise | Regionale Geländedaten (Phase 2), Wirtschaft (6), Bau (7) |
| 9 Government & Politics | Nationen und Anerkennung, Staatsformen, Auswahl von Delegierten (gewählt/ernannt/parlamentarisch), Stellvertreter, Vollmachten, Reisekostenregeln der Nation | politische Einheiten |
| 10 Councils & World Governance | **Weltrat als Institution:** jährliche Weltversammlung am 24. Juni (Weltzeit), Tagesordnung, Anträge, Koalitionen, Verhandlungen, Abstimmungen, Beschlüsse mit Auswirkungen, Protokolle, öffentliche Zusammenfassungen, Live-Ereignis für Zuschauer; Verwaltung und Nutzungsregeln des Geländes; Veranstaltungen (Märkte, Messen, Ausstellungen) per Beschluss | Phase 9, Reisen (8) |
| 11 Conflict & Society | Friedensverhandlungen, Konflikte; **Neutralität im Kampfsystem**: Stufe 1 verhindert, Stufe 2 Verstoß mit Wachen/Intervention, Stufe 3 Krisenereignis (erklärter Staatsangriff) mit Folgen; Flucht und humanitäre Zuflucht | Phase 9/10, WORLD_COUNCIL_NEUTRALITY.md |
| 12 Multiplayer Foundation | Serverseitige Autorität über Landmarken-Zustand und Beschlüsse, Befehle (`landmark_*`) über WorldClient | WorldAuthority/RemoteWorldClient |
| 13 Persistent Universe | Skalierung: sehr viele Delegierte/Besucher, Detailstufen/Simulationsebenen, Übertragungen | Phase 12 |

## Bekannte Abhängigkeiten und Vorkehrungen
- **Reisen ist allgemein:** Der Weltrat ist nur ein Anwendungsfall des weltweiten Verkehrssystems (Phase 8). Es entsteht kein Sonderweg „Delegierten-Teleport“.
- **Komponenten-IDs** (`assembly_hall`, `portico`, `canal`, `great_fountain` …) sind dieselben in Weltdefinition, Zustand und Grafik. Die Restaurierung in Phase 7 ändert nur Zustandswerte, die Darstellung folgt daraus.
- **Stufen-Grafiken:** Der Renderer erzeugt Stufe 1 (historisch) und Vorschauen weiterer Stufen aus demselben Modell (`render_council.py <out> <px> <stage>`). Neue Gebäudeteile kommen als weitere Solids hinzu.
- **Weltzeit:** Der Termin wird aus UTC berechnet (`Landmarks.next_assembly`), nie aus der Gerätezeit.
