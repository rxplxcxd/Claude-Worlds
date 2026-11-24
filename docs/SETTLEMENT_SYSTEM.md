# SETTLEMENT_SYSTEM

## 0. Grundregel: Siedlungen entstehen nur durch Spieler [VERBINDLICH]
Der Planet startet leer (siehe WORLD_DESIGN.md §1). **Jede Siedlung wird von einem menschlichen Spieler gegründet**; es gibt keine vorplatzierten und keine reinen NPC-Siedlungen. Der erste Spieler muss gründen; jeder weitere kann einer bestehenden Spielersiedlung beitreten oder selbst gründen.

## 1. Implementiert (Phase 1)
- **Gründungsvorlage** `data/settlement_templates/founding_basic.json` (`tpl_founding_basic`, Standardname „Lichtfeld“) – eine Vorlage ist **keine** Siedlung.
- **Gründung** über `WorldState.found_settlement(template, founder_player_id, name)`: erzeugt `stl_…`-ID, speichert Gründer, Bewohner (Gründer), Gründungszeitpunkt, Reihenfolge auf dem Planeten. Ohne menschlichen Gründer → abgelehnt.
- **Seit Phase 2:** Nach dem Charakter-Editor wählt der Spieler **auf dem Globus** Ort und Namen (Standortbewertung, „Vorschlag“). Die Siedlung speichert Position, Region, Kontinent; die Region wird ihr Gebiet (GEOGRAPHY_SYSTEM.md §4). Danach wird die gespeicherte Siedlung geladen. Alte Spielstände werden einmalig verortet.
- Texte der Vorlage enthalten Platzhalter `{settlement}`, die bei der Gründung gefüllt werden.
- Vorlagenformat: Ort (Welt/Planet/Kontinent/Region), Standardname, Region, Entwicklungsstufe, Rastergröße, Spawn, Boden (Basis + Rechtecke), Gebäude (`id, type, name, grid, footprint, height, roof, Farben, function, text, actions`), Requisiten, Streuvegetation (Seed), Schwarzes-Brett-Text.
- **Validierung** (`SettlementData.validate`): eindeutige `bld_`-IDs, keine Überlappungen, nur bebaubarer Untergrund, Requisiten nicht in Gebäuden, Spawn frei.
- Gebäude besitzen bereits ihre **Funktion** (Verwaltung, Handel, Wasser, Energie, Lebensmittel, Bau, Gesundheit, Sicherheit/Brandschutz, Wohnen) – als Information, ohne Simulation.

## 2. Gründungsgemeinschaft [Phase 1: 12 NPCs IMPLEMENTIERT – siehe NPC_SYSTEM.md §0a · Ausbau GEPLANT, Phase 4]
Zielgröße der Startbevölkerung 20–50 NPCs, die **mit dem Gründer** kommen (Annahme, Bestätigung offen – WORLD_DESIGN.md §5). Funktionen können zusammengelegt sein:

| Funktion | Gebäude in Lichtfeld | Min. Personal (Vorschlag) |
|---|---|---|
| Verwaltung & Leitung | Gemeindehaus | 2 |
| Wasser | Wasserwerk | 2 |
| Energie | Energiestation + Solarfeld | 2 |
| Lebensmittel | Gewächshaus + Felder | 6 |
| Bau & Instandhaltung | Werkstatt & Bauhof | 4 |
| Handel | Handelsposten, Marktstand | 2 |
| Sicherheit, Brand- & Notfallschutz | Notfallposten (geteilt) | 3 (Bereitschaft) |
| Medizin | Sanitätsstation | 2 |
| Transport | Lager | 2 |
| Allgemein | – | Rest |

## 3. Siedlungsgründung [Standortwahl + Bewertung IMPLEMENTIERT (Phase 2) · Beitreten, Gründungspaket GEPLANT (Phase 4/12) · Regeln überarbeitet 24.11.2026 → §8, TERRITORY_SYSTEM.md]
Einziger Weg, wie Siedlungen entstehen.
0. Neuer Spieler: Ist der Planet leer → nur „Siedlung gründen“. Sonst Auswahl „Bestehender Siedlung beitreten“ (Liste/Karte der Spielersiedlungen) oder „Eigene Siedlung gründen“.
1. Standortwahl auf der Weltkarte mit **Standortbewertung** (Wasser, Klima, Gelände, Rohstoffe, Landwirtschaft, Nähe/Abstand zu Siedlungen, Verkehrswege, Territorium).
2. Gründungspaket: Startgebäude-Set aus Vorlage, Startbevölkerung, Grundvorräte für ~30 Spieltage.
3. Freie Entwicklungsflächen, Bauplätze.

## 4. Entwicklungsstufen [GEPLANT]
Gründungssiedlung → Kleine Siedlung → Dorf → Kleinstadt → Stadt → Großstadt → Metropole (→ Verbünde/Staaten siehe POLITICAL_SYSTEM). Schwellen (Vorschlag): 50 / 150 / 500 / 2 000 / 10 000 / 50 000 Einwohner + Infrastrukturbedingungen.

## 5. Spielerfreundlicher Einstieg [teilweise IMPLEMENTIERT]
Implementiert: eigenes Haus des Gründers, Gründungsmeldung, Orientierung (Schwarzes Brett), klare Steuerungshinweise. Geplant: erste Arbeitsangebote, Startkapital, kleine Einstiegsziele.

## 7. Stadtbild & Platzierungsregeln [IMPLEMENTIERT]

**Straßennetz (Vorlage v2):** Hauptstraßen (x = 12, y = 12) mit Kreuzung am Dorfplatz, Seitenstraße (y = 18) mit T-Kreuzung. **Jede Straße hat beidseitig Gehwege**; Gehwege verbinden Straße und Fußwege; Wege (Erde) schließen an Gehwege an (Autotiling `CONNECTS`). Gehwege = Penzilla-Beton + Penzilla-Gehwegplatten.

**Straßenmobiliar wird aus Regeln erzeugt, nicht von Hand gesetzt** (`scripts/settlement/street_planner.gd`):

| Objekt | Regel |
|---|---|
| Bordsteinzelle | Gehwegzelle, die direkt an eine Straße grenzt |
| Straßenlaterne | nur auf Bordsteinzellen, alle 4 Zellen, auf beiden Straßenseiten versetzt (Zickzack); Mast an der Bordsteinkante, **Ausleger zeigt über die Fahrbahn**, Leuchte hängt über der Straße |
| Hydrant | auf dem Gehweg an der Bordsteinkante, alle 6 Zellen; ≥ 1,5 Zellen Abstand zu Laternen; jede Kreuzung hat einen Hydranten im Umkreis von 3 Zellen |
| Straßenschild | an einer Ecke jeder Kreuzung |
| Vorfahrtsschild | an der Einmündung der Seitenstraße |
| Bushaltestelle | an der Hauptstraße (Nordseite, östlich des Platzes), mit Mülleimer daneben |
| Briefkasten | neben (nicht vor) dem Eingang jedes Wohnhauses |
| Eingänge | die Zellen vor den sichtbaren Fassaden (+y, +x) bleiben frei |

`StreetPlanner.validate()` prüft alle Regeln (nicht auf Straße/Wasser/Gebäude, Laternen/Hydranten/Haltestelle am Bordstein, keine blockierten Eingänge, Laterne zeigt zur Straße, Abstände) – getestet, inkl. Negativtest.

**Laternen-Perspektive:** Penzilla hat keine Auslegerlaterne; sie wird aus Penzilla-Teilen gebaut (Mast + Wandausleger entlang der isometrischen Achse gedreht + Leuchtenkopf). Nachts: Lichthof am Kopf, weicher Lichtkegel (Farbverlauf) zur Fahrbahn, elliptischer Lichtfleck auf dem Boden in einer eigenen Ebene unter allen Objekten; die Helligkeit gleicht die Nachttönung aus, damit das Licht dezent bleibt.

**Tiefensortierung:** Y-Sort nach Grundflächenmittelpunkt bzw. Fußpunkt (Figuren, Laternen, Props). **Verdeckung:** Steht der Spieler hinter einem Gebäude/Baum/Wasserturm/Bushäuschen/Zelt, wird nur der Bereich um die Figur weich durchsichtig (ARCHITECTURE.md ADR-11).

**Marktzeile:** Bäckerei, Gemischtwaren, Schmiede (Isometric RPG Buildings, aus Ebenen zusammengesetzt, ADR-10) an der Seitenstraße; Gründerzelt am Westrand.

## 6. Offene Fragen [OFFEN]
Rastergröße wachsender Städte (Chunks à 32×32 Kacheln vorgeschlagen), Stadtteile als eigene Szenen?


## 8. Ausgangszustand einer neuen Siedlung [VERBINDLICH seit 24.11.2026 · Territorium/Fläche IMPLEMENTIERT (0.4.0) · Gründungspaket GEPLANT, Phase 4]
Vorgabe: [DESIGN_DIRECTIVES.md](DESIGN_DIRECTIVES.md) §4.
- **Siedlungsfläche höchstens 1 × 1 km** (Vorschlag: 100 × 100 Kacheln à 10 m, in Chunks à 16 × 16 Kacheln). Die heutige Vorlage (26 × 26 Kacheln ≈ 260 m) wird zum **Kern** dieser Fläche; der Rest ist freies Bauland, Feld, Wald – abgeleitet aus dem Gelände der Region.
- **Gründungspaket:** kleine Verwaltung, wenige Wohngebäude, ein paar Straßen, Grundversorgung (Wasser, Energie, Lager, Lebensmittel) – **funktionsfähig, aber klein und ineffizient**: z. B. Behelfsbauten (Zelte, Baracken), geringe Kapazität, umständliche Wege, hoher Unterhalt, wenig Komfort. Jede Schwäche ist ein sichtbares Ausbauziel („Wasserwerk ausbauen“, „Straße pflastern“).
- Der Start hängt von der **Gründungsschwierigkeit** ab ([TERRITORY_SYSTEM.md](TERRITORY_SYSTEM.md) §6): im Polargebiet z. B. beheizte Unterkünfte, Energie- und Lebensmittelvorräte statt Feldern.
- **Beitreten oder Gründen** bei der Charaktererstellung: siehe [PLAYER_SYSTEM.md](PLAYER_SYSTEM.md) §3a.
- **Gründungsregel:** 20 km Abstand zwischen Territoriumsgrenzen, geodätisch ([TERRITORY_SYSTEM.md](TERRITORY_SYSTEM.md) §3) – **umgesetzt in 0.4.0**; die Phase-2-Regeln sind entfernt.
- **Gespeichert (0.4.0):** `settlement_area` (Ursprung, Rahmen Ost/Nord, 1 000 m, Kacheln à 10 m), `territory_id`, `difficulty`, `difficulty_requirements`. Die lokale Karte nutzt weiterhin die ~260-m-Vorlage als Kern (Ausbau auf 1 km in Phase 4).

## 9. Vollständige Gestaltungsfreiheit [VERBINDLICH seit 24.11.2026 · GEPLANT, Phase 7]
Vorgabe: [DESIGN_DIRECTIVES.md](DESIGN_DIRECTIVES.md) §5–6. Es gibt **keine dauerhaft vorgegebene Straßen- oder Gebäudestruktur**.

### 9.1 Siedlungszustand als veränderbare Daten
Heute (0.3.0) wird das Layout bei jedem Start aus der Vorlage gelesen – Änderungen wären nicht speicherbar. Künftig:
```
SettlementState { settlement_id, version, area {origin, frame, size_tiles, tile_m}, chunks[] }
Chunk           { chunk_id (x,y), version, terrain[], parcels[], buildings[], road_segments[], props[], zones[] }
Parcel          { parcel_id, polygon (Kacheln), owner_id, zone (residential|commercial|industrial|public|agri|green), lease? }
Building        { building_id, type, variant, footprint, orientation (normal|gespiegelt), parcel_id, owner_id,
                  state (planned|under_construction|active|damaged|demolishing), occupants[], built_at }
RoadNetwork     { nodes[], edges[] (type, width, Gehweg ja/nein) } → wird für die Darstellung in Kacheln gerastert
Networks        { water[], power[] } (Leitungen/Versorgungsgebiete)
```
- Die Gründungsvorlage wird **einmal** in diesen Zustand kopiert; danach ist alles änderbar.
- Straßenmobiliar bleibt **regelbasiert abgeleitet** (`StreetPlanner`) und wird bei Straßenänderungen für die betroffenen Chunks neu berechnet.

### 9.2 Bauen, Verschieben, Abreißen über Befehle
`BuildCommand · DemolishCommand · MoveCommand · RezoneCommand · ParcelSplit/Merge · RoadBuild/Remove/Reroute · InfraModify · AdminRelocate`
→ **Berechtigungsprüfung** (Weltregeln → Eigentum → Amt → Gesetze, [LAW_ENGINE.md](LAW_ENGINE.md) §2) → Kosten/Material/Bauzeit → Ausführung als Ereignis (protokolliert, serverfähig).
- **Planungsmodus** (Entwurfsebene) vs. **Bau** (kostet Zeit und Ressourcen); Entwürfe sind frei, Ausführung geprüft.
- **Verschieben** = Abbau + Neubau mit Kosten (realistisch; Penzilla-Sprites erlauben 2 Ausrichtungen: normal/gespiegelt).
- **Folgen** werden automatisch ausgelöst: Bewohner brauchen Ersatzwohnung, Arbeitsplätze ziehen um, Verträge enden, Straßen ohne Anschluss werden markiert (referenzielle Integrität).
- **Schutz öffentlicher Infrastruktur** und bewohnter Gebäude über Standardregeln + Gesetze.
