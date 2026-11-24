# GEOGRAPHY_SYSTEM

## 1. Implementiert (Phase 1)
- **Lokales Raster** einer Siedlung (`SettlementData.size`, Kacheltypen `grass, path, road, plaza, water, sand, field`).
- **Isometrische Projektion** `Iso` (2:1, 128×64 Weltpixel pro Kachel), Raster ↔ Welt, 8 Blickrichtungen.
- Hierarchische IDs in den Siedlungsdaten: `world_id, planet_id, continent_id, region_id, settlement_id`.

## 2. Datenmodell [GEPLANT, Phase 2]

```
Planet      { planet_id, name, radius_km, seed, sea_level }
Continent   { continent_id, planet_id, name, outline (Polygon lat/lon), climate_zones[] }
Region      { region_id, continent_id, name, center {lat, lon}, area_km2,
              terrain (plain|hills|mountain|forest|coast|desert|tundra),
              elevation_m, climate (temp, rainfall), resources[] {type, abundance},
              water_access (none|river|lake|coast), development (wild|sparse|settled|urban),
              territory_id? }
Settlement  { settlement_id, region_id, position {lat, lon}, local_grid_size, stage, ... }
Territory   { territory_id, owner_entity_id (pol_*/stl_*), regions[], borders (Polygon) }
```
Positionen global in **Breite/Länge** (Kugel), lokal im **Raster** der Siedlung. Umrechnung: Siedlungsursprung (lat/lon) + Rasterkachel × Kachelmaß in Metern (Vorschlag 10 m).

## 3. Weltkarte und Globus [GEPLANT, Phase 2]
- **Eigene Szene** `scenes/globe/`, getrennt von der Siedlungsszene; beim Wechsel wird die Siedlungsszene entladen bzw. pausiert.
- Darstellung: Kugel (3D im Compatibility Renderer, einfache Textur + Overlays) für die planetare Stufe; 2D-Kartenprojektion für kontinentale/regionale Stufe. **[OFFEN]**: rein 3D vs. Hybrid – Hybrid empfohlen (iPhone-Leistung, Lesbarkeit).
- Zoomstufen: **Planetar → Kontinental → Regional → Lokal (Siedlungsszene)**.
- Inhalte je Stufe nur aggregiert (Siedlungsmarker, Grenzen, Routen); keine Gebäude/NPC-Knoten.

## 4. Einfluss auf Spielsysteme [GEPLANT]
Wasserzugang → Siedlungswachstum; Gelände → Baukosten & Transportgeschwindigkeit; Ressourcen → Wirtschaftsprofil; Klima → Landwirtschaft; Flüsse/Küsten → Schifffahrt.

## 5. Offene Fragen [OFFEN]
- Planetengröße (Spielfläche) und Anzahl Kontinente (Vorschlag: 4 Kontinente + Inselgruppen).
- Prozedural (Seed) vs. handgestaltet (Vorschlag: prozedurale Basis, handkuratierte Startregionen).
