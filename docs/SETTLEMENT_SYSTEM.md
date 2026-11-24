# SETTLEMENT_SYSTEM

## 1. Implementiert (Phase 1)
- **Lichtfeld** (`stl_lichtfeld`): statische Gründungssiedlung aus `data/settlements/lichtfeld.json`.
- Format: IDs, Name, Region, Entwicklungsstufe, Rastergröße, Spawn, Boden (Basis + Rechtecke), Gebäude (`id, type, name, grid, footprint, height, roof, Farben, function, text, actions`), Requisiten, Streuvegetation (Seed), Schwarzes-Brett-Text.
- **Validierung** (`SettlementData.validate`): eindeutige `bld_`-IDs, keine Überlappungen, nur bebaubarer Untergrund, Requisiten nicht in Gebäuden, Spawn frei.
- Gebäude besitzen bereits ihre **Funktion** (Verwaltung, Handel, Wasser, Energie, Lebensmittel, Bau, Gesundheit, Sicherheit/Brandschutz, Wohnen) – als Information, ohne Simulation.

## 2. Gründungsgemeinschaft [GEPLANT, Phase 4]
Startbevölkerung 20–50 NPCs. Funktionen können zusammengelegt sein:

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
1. Standortwahl auf der Weltkarte mit **Standortbewertung** (Wasser, Klima, Gelände, Rohstoffe, Landwirtschaft, Nähe/Abstand zu Siedlungen, Verkehrswege, Territorium).
2. Gründungspaket: Startgebäude-Set aus Vorlage, Startbevölkerung, Grundvorräte für ~30 Spieltage.
3. Freie Entwicklungsflächen, Bauplätze.

## 4. Entwicklungsstufen [GEPLANT]
Gründungssiedlung → Kleine Siedlung → Dorf → Kleinstadt → Stadt → Großstadt → Metropole (→ Verbünde/Staaten siehe POLITICAL_SYSTEM). Schwellen (Vorschlag): 50 / 150 / 500 / 2 000 / 10 000 / 50 000 Einwohner + Infrastrukturbedingungen.

## 5. Spielerfreundlicher Einstieg [teilweise IMPLEMENTIERT]
Implementiert: eigene Unterkunft, Orientierung (Schwarzes Brett), klare Steuerungshinweise. Geplant: erste Arbeitsangebote, Startkapital, kleine Einstiegsziele.

## 6. Offene Fragen [OFFEN]
Rastergröße wachsender Städte (Chunks à 32×32 Kacheln vorgeschlagen), Stadtteile als eigene Szenen?
