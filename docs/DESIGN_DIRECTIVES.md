# DESIGN_DIRECTIVES – Verbindliche Designvorgaben

**Festgelegt vom Projektinhaber am 24.11.2026 (nach Abschluss von Phase 2).** Diese Vorgaben bilden die langfristige Designrichtung von WORLDS und haben Vorrang vor älteren Vorschlägen in anderen Dokumenten. Die technische Bewertung steht in [TECHNICAL_ASSESSMENT.md](TECHNICAL_ASSESSMENT.md).

> Status: **dokumentiert, nicht implementiert.** Phase 3 ist ausdrücklich **nicht** freigegeben. Einige Phase-2-Regeln im Code widersprechen diesen Vorgaben (siehe §10) und werden erst nach Freigabe angepasst.

## 1. Geografische Welt und Regionen
- Die 5 Kontinente und 157 Regionen bleiben die erste **natürliche** Gliederung.
- **157 Regionen sind keine Obergrenze für Siedlungen.** Innerhalb einer Region müssen zahlreiche Siedlungen entstehen können; langfristig **Tausende** Siedlungen auf dem Planeten.
- Die Struktur muss hierarchisch erweiterbar sein: Kontinente → Regionen → Unterregionen → Siedlungen → Städte → weitere Verwaltungseinheiten.
- Territorien und politische Grenzen verändern sich **dynamisch**.
→ [GEOGRAPHY_SYSTEM.md](GEOGRAPHY_SYSTEM.md) §8, [TERRITORY_SYSTEM.md](TERRITORY_SYSTEM.md)

## 2. Vollständige Besiedelbarkeit
- **Der gesamte Planet ist besiedelbar**, auch die Polarregionen. **Keine künstliche geografische Sperre** (die ±62°-Grenze ist abgelehnt).
- Die Umgebung bestimmt die **Schwierigkeit**: Klima, Temperatur, Wasser, Nahrung, Rohstoffe, Gelände, Energiebedarf, Transport, technologischer Stand.
- Extreme Gebiete (z. B. Antarktis) sind möglich, erfordern aber erhebliche Ressourcen, Technologien und Logistik; fortgeschrittene Spieler erschließen sie später.
→ [TERRITORY_SYSTEM.md](TERRITORY_SYSTEM.md) §6 (Gründungsschwierigkeit)

## 3. Mindestabstand 20 km – zwischen Territoriumsgrenzen
- Eine neue Siedlung benötigt **mindestens 20 km Abstand zur nächsten bestehenden Territoriumsgrenze** – gemessen zwischen den **tatsächlichen Grenzen**, nicht zwischen Mittelpunkten.
- Standortwahl auf dem Globus; **unzulässige Standorte als Sperrzone sichtbar**.
- Distanz **geodätisch** entlang der Planetenoberfläche; korrekt bei Krümmung, Küsten und allen Breitengraden.
- Technisch getrennt: **Siedlungsfläche**, **beanspruchtes Territorium**, **bebaute Fläche**, **spätere territoriale Erweiterung**.
- Die 20-km-Regel gilt zunächst für **Neugründungen**; Erweiterung und Annäherung benachbarter Siedlungen werden ein eigenes System.
- Exploits (Mehrfachgründungen, Zweitaccounts, Blockaden, strategisches Beanspruchen) müssen berücksichtigt werden.
→ [TERRITORY_SYSTEM.md](TERRITORY_SYSTEM.md)

## 4. Gründung und Ausgangszustand
- Genre-Mischung: Life Simulation, City Builder, Gesellschaftssimulation, Strategie.
- Eine neue Siedlung beginnt auf **höchstens 1 × 1 km** mit grundlegender Infrastruktur (erste Verwaltung, Wohngebäude, Straßen, Grundversorgung) – **funktionsfähig, aber klein, ineffizient und entwicklungsbedürftig**. Der Spieler soll ausbauen wollen, bis hin zur großen Stadt.
- Bei der Charaktererstellung wählt der Spieler: **A) einer bestehenden Siedlung beitreten** oder **B) eine eigene Siedlung gründen** (Standort auf dem Globus).
→ [SETTLEMENT_SYSTEM.md](SETTLEMENT_SYSTEM.md) §8, [PLAYER_SYSTEM.md](PLAYER_SYSTEM.md) §3a

## 5. Vollständig gestaltbare Städte
- Gebäude errichten, verschieben, abreißen; Straßen bauen, verlegen, abreißen; Grundstücke neu aufteilen; Wohn-/Gewerbe-/Industriegebiete umgestalten; Infrastruktur ändern; Verwaltungsgebäude verlegen; Stadtstrukturen vollständig umbauen.
- **Keine dauerhaft vorgegebene Straßenaufteilung oder unveränderbare Gebäudestruktur.** Die Architektur muss das tragen.
→ [SETTLEMENT_SYSTEM.md](SETTLEMENT_SYSTEM.md) §9

## 6. Eigentum, Bewohner, Befugnisse
- Gestaltungsfreiheit heißt **nicht**, dass jeder alles zerstören darf. Unterschieden werden **Eigentum**, **politische Befugnisse** und **Gesetze**.
- Einwohner dürfen keine fremden Gebäude abreißen; Eigentümer haben bestimmte Rechte; Bürgermeister erweiterte Verwaltungsbefugnisse – **auch Amtsträger sind an Gesetze gebunden**.
- Bewohnte Gebäude unterliegen Räumungs-, Umsiedlungs- und Entschädigungsregeln; Straßen und öffentliche Infrastruktur können besonders geschützt sein.
- Das konkrete Verhalten bestimmt später die Gesetzgebung.
→ [LAW_ENGINE.md](LAW_ENGINE.md) §2 (Berechtigungsprüfung)

## 7. Flexible Gesetzgebung
- **Regelbasierte Gesetzes-Engine** statt einer Liste fest programmierter Gesetze: **WENN** Bedingungen erfüllt **DANN** Handlungen erlaubt / verboten / an Voraussetzungen geknüpft.
- Bausteine: Bedingungen, Auslöser, Berechtigungen, Verbote, Genehmigungen, Fristen, Abstimmungen, Ausnahmen, Sanktionen, Einspruchsmöglichkeiten, Geltungsbereiche.
- Ebenen: Siedlung, Stadt, Region, Staat, Land. **Datengetrieben, keine tausenden hartcodierten Gesetze.**
→ [LAW_ENGINE.md](LAW_ENGINE.md)

## 8. Mehrstufige Simulation („GTA-Prinzip“ für eine persistente Welt)
- Nahbereich individuell und detailliert; mittlere Entfernung reduziert; große Entfernung aggregiert (wichtige Ereignisse weiter verarbeitet); sehr große Entfernung ereignisbasiert und zeitlich zusammengefasst.
- **Die Welt friert nicht ein.** Nach Stunden oder Tagen ist der Zustand konsistent und aktuell – **ohne sichtbares Nachsimulieren**.
- Persistente Zustände, Zeitstempel, Simulationsintervalle, zuverlässige serverseitige Verarbeitung; im Mehrspieler **serverseitig autoritativ**.
→ [SIMULATION_ARCHITECTURE.md](SIMULATION_ARCHITECTURE.md)

## 9. Performance und iOS
- ~30 FPS in ersten Tests sind vorerst akzeptabel; **Ziel 60 FPS**, ohne unnötige Qualitätseinbußen.
- Zu untersuchen: Rendering-LOD, Simulations-LOD, Occlusion/Frustum Culling, Batching, Schatten, Texturkompression, Speicher, dynamische Auflösung, effiziente NPC-Verarbeitung.
- **Das echte iPhone bleibt Zielgerät**; Desktop-Emulation ist kein Leistungsnachweis.
→ [PERFORMANCE.md](PERFORMANCE.md) §6

## 10. Abweichungen des aktuellen Codes (Stand 0.3.0) von diesen Vorgaben

| Vorgabe | Aktueller Code (Phase 2) | Anpassung |
|---|---|---|
| Keine Breitengrad-Sperre | `Geography.MAX_FOUNDING_LATITUDE = 62°` lehnt Polargebiete ab | Entfernen → Schwierigkeitsmodell |
| Polar-/Extremgebiete möglich | Eis und Hochgebirge sind harte Ausschlüsse | Ersetzen durch Voraussetzungen/Aufwand |
| 20 km zwischen **Grenzen** | 300 km zwischen **Mittelpunkten** | Neue Geometrie-Prüfung |
| Viele Siedlungen je Region | Territorium = ganze Region (Ø ~440 000 km²); fremde Region gesperrt | Territorium als eigene Fläche (Polygon) |
| Siedlung ≤ 1 × 1 km, frei umbaubar | Feste Vorlage 26 × 26 Kacheln (~260 m), Layout wird bei jedem Start aus der Vorlage geladen, Änderungen nicht speicherbar | Siedlungszustand als veränderbare, gespeicherte Entitäten |
| Beitreten **oder** Gründen | Nur Gründen | Auswahlbildschirm (Beitreten benötigt Mehrspieler) |
| Sonne auch an den Polen | Sonnenbreite auf ±60° begrenzt | Begrenzung entfernen, Polartag/-nacht gestalten |

Diese Anpassungen sind **noch nicht umgesetzt** – Vorschlag: als kleines „Phase 2.1“-Paket vor Phase 3 (siehe [ROADMAP.md](ROADMAP.md)).
