# SETTLEMENT_SYSTEM

## 0. Grundregel: Siedlungen entstehen nur durch Spieler [VERBINDLICH]
Der Planet startet leer (siehe WORLD_DESIGN.md §1). **Jede Siedlung wird von einem menschlichen Spieler gegründet**; es gibt keine vorplatzierten und keine reinen NPC-Siedlungen. Der erste Spieler muss gründen; jeder weitere kann einer bestehenden Spielersiedlung beitreten oder selbst gründen.

## 1. Implementiert (Phase 1)
- **Gründungsvorlage** `data/settlement_templates/founding_basic.json` (`tpl_founding_basic`, Standardname „Lichtfeld“) – eine Vorlage ist **keine** Siedlung.
- **Gründung** über `WorldState.found_settlement(template, founder_player_id, name)`: erzeugt `stl_…`-ID, speichert Gründer, Bewohner (Gründer), Gründungszeitpunkt, Reihenfolge auf dem Planeten. Ohne menschlichen Gründer → abgelehnt.
- Beim ersten Start gründet der lokale Spieler automatisch (Standort/Name fest bis Phase 2/4); danach wird die gespeicherte Siedlung geladen.
- Texte der Vorlage enthalten Platzhalter `{settlement}`, die bei der Gründung gefüllt werden.
- Vorlagenformat: Ort (Welt/Planet/Kontinent/Region), Standardname, Region, Entwicklungsstufe, Rastergröße, Spawn, Boden (Basis + Rechtecke), Gebäude (`id, type, name, grid, footprint, height, roof, Farben, function, text, actions`), Requisiten, Streuvegetation (Seed), Schwarzes-Brett-Text.
- **Validierung** (`SettlementData.validate`): eindeutige `bld_`-IDs, keine Überlappungen, nur bebaubarer Untergrund, Requisiten nicht in Gebäuden, Spawn frei.
- Gebäude besitzen bereits ihre **Funktion** (Verwaltung, Handel, Wasser, Energie, Lebensmittel, Bau, Gesundheit, Sicherheit/Brandschutz, Wohnen) – als Information, ohne Simulation.

## 2. Gründungsgemeinschaft [GEPLANT, Phase 4]
Startbevölkerung 20–50 NPCs, die **mit dem Gründer** kommen (Annahme, Bestätigung offen – WORLD_DESIGN.md §5). Funktionen können zusammengelegt sein:

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

## 3. Siedlungsgründung [GEPLANT, Phase 4 + 2]
Einziger Weg, wie Siedlungen entstehen.
0. Neuer Spieler: Ist der Planet leer → nur „Siedlung gründen“. Sonst Auswahl „Bestehender Siedlung beitreten“ (Liste/Karte der Spielersiedlungen) oder „Eigene Siedlung gründen“.
1. Standortwahl auf der Weltkarte mit **Standortbewertung** (Wasser, Klima, Gelände, Rohstoffe, Landwirtschaft, Nähe/Abstand zu Siedlungen, Verkehrswege, Territorium).
2. Gründungspaket: Startgebäude-Set aus Vorlage, Startbevölkerung, Grundvorräte für ~30 Spieltage.
3. Freie Entwicklungsflächen, Bauplätze.

## 4. Entwicklungsstufen [GEPLANT]
Gründungssiedlung → Kleine Siedlung → Dorf → Kleinstadt → Stadt → Großstadt → Metropole (→ Verbünde/Staaten siehe POLITICAL_SYSTEM). Schwellen (Vorschlag): 50 / 150 / 500 / 2 000 / 10 000 / 50 000 Einwohner + Infrastrukturbedingungen.

## 5. Spielerfreundlicher Einstieg [teilweise IMPLEMENTIERT]
Implementiert: eigenes Haus des Gründers, Gründungsmeldung, Orientierung (Schwarzes Brett), klare Steuerungshinweise. Geplant: erste Arbeitsangebote, Startkapital, kleine Einstiegsziele.

## 6. Offene Fragen [OFFEN]
Rastergröße wachsender Städte (Chunks à 32×32 Kacheln vorgeschlagen), Stadtteile als eigene Szenen?
