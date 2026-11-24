# GEOGRAPHY_SYSTEM

Legende: **[IMPLEMENTIERT]** · **[GEPLANT]** · **[OFFEN]**

## 1. Überblick [IMPLEMENTIERT, Phase 2]

| Ebene | Umsetzung | Datei |
|---|---|---|
| Planetenmodell | Planet **Aurel**, Radius 4 000 km, Gitter 512 × 256 Zellen (≈ 49 km am Äquator), deterministisch aus Seed 777 | `scripts/geography/planet_generator.gd` |
| Geografische Koordinaten | Breite/Länge in Grad, Umrechnung Kugel ↔ Grad, Großkreisdistanz | `scripts/geography/geo.gd` |
| Kontinente | 5 Kontinente (große Landmassen), kleine Inseln gehören zum nächsten Kontinent | `planet.json → continents` |
| Regionen | 157 Regionen (Voronoi auf der Kugel, nur innerhalb einer Landmasse) mit Gelände, Höhe, Klima, Wasserzugang, Rohstoffen, Erschließung | `planet.json → regions` |
| Weltkarte / Globus | 3D-Globus mit Zoomstufen planetar → kontinental → regional → lokal (Siedlung) | `scripts/globe/*`, `shaders/globe.gdshader` |
| Siedlungsstandorte | Jede Siedlung hat `position {lat, lon}`, `region_id`, `continent_id`; Standortwahl und -bewertung beim Gründen | `scripts/geography/geography.gd`, `WorldState` |
| Territorien | Gründung beansprucht die Region als Gebiet der Siedlung; Anzeige auf dem Globus | `WorldState.get_territories()` |

**Grundregel bleibt:** Der generierte Planet enthält **nur Natur** – alle Regionen starten mit `development: "wild"` und ohne `territory_id`. Siedlungen und Gebiete entstehen ausschließlich durch Spielergründung (WORLD_DESIGN.md §1, getestet).

## 2. Datenmodell [IMPLEMENTIERT]

```
Planet     { planet_id, name, seed, generator_version, radius_km, width, height }
Continent  { continent_id ("cnt_01"…), name, center [lat, lon], area_km2, region_ids[] }
Region     { region_id ("reg_001"…), continent_id, name, center [lat, lon], area_km2,
             terrain (plain|hills|mountain|forest|coast|desert|tundra|ice),
             biome_shares {biome: Anteil}, elevation_m (Ø),
             climate {temperature_c, rainfall 0..1, zone},
             water_access (none|river|lake|coast), river_cells, coast_share,
             resources [{type, abundance 0..1}], development (wild), territory_id ("") }
Zelle      { elevation_m, temperature_c, rainfall, biome, river, coastal, region, continent }
Settlement { …, position {lat, lon}, region_id, region_name, continent_id, continent_name,
             territory_id, site_score, terrain }                      (WorldState)
Territory  { territory_id ("ter_…"), owner_settlement_id, owner_player_id,
             region_ids[], kind ("settlement"), claimed_at_unix }      (WorldState)
```

- **Biome:** Ozean, See, Eis, Tundra, Gebirge, Hügelland, Wüste, Wald, Ebene.
- **Rohstoffe:** Holz, Stein, Erz, fruchtbarer Boden, Fisch, Süßwasser, Ton, Sand, Salz, Wild – Menge aus Biomanteilen, Klima, Küste/Flüssen und Rauschen.
- **Lokal ↔ global:** Die Siedlung liegt an `position`; ihr lokales Raster (Kacheln à ~10 m) ist im Verhältnis zu einer 49-km-Zelle winzig. Die lokale Karte wird noch **nicht** aus der Region abgeleitet (gleiche Gründungsvorlage überall) → Phase 4 [GEPLANT].
- **Sonne:** Die Breite der Siedlung bestimmt im Sonnenmodell die Tageslänge (`GameClock.latitude`, begrenzt auf ±60°).

## 3. Planetengenese [IMPLEMENTIERT]

Schritte (`PlanetGenerator.generate`, Version 2):
1. **Höhe:** 3D-Rauschen direkt auf der Kugel (keine Verzerrung an den Polen) mit Domain-Warp für natürliche Küsten, Gebirgsgrate (Ridged-Rauschen) auf Land, Polarmeere.
2. **Meeresspiegel** so gewählt, dass 34 % der Fläche Land sind (flächengewichtet).
3. **Gewässer:** große zusammenhängende Wasserflächen = Ozean, kleine = Seen.
4. **Klima:** Temperatur aus Breite und Höhe (−6,5 °C/km); Niederschlag aus Rauschen, Klimagürteln (feuchte Tropen, trockene Subtropen um 25°) und Küstennähe.
5. **Flüsse:** 70 Flüsse folgen dem steilsten Gefälle vom Hochland zum Meer; Senken werden zu Seen.
6. **Biome** aus Temperatur, Höhe, Niederschlag.
7. **Kontinente** = Landmassen ≥ 4 % der Landfläche; kleinere Inseln gehören zum nächsten Kontinent.
8. **Regionen:** Startpunkte im Mindestabstand 620 km; jede Landzelle gehört zum nächsten Startpunkt **derselben Landmasse** (Großkreisdistanz, leicht verrauscht → natürliche Grenzen). Danach Statistik, Gelände, Wasserzugang, Rohstoffe, Namen (deterministische Silbennamen + Geländewort, z. B. „Briislis-Küste“).

### Einmal backen statt zur Laufzeit erzeugen (ADR-12)
Die Erzeugung dauert ~1,4 s (Desktop) und hängt von Gleitkomma-Details ab. Darum wird der Planet **einmal gebacken** und versioniert:
```bash
godot --headless --path . -s res://scripts/geography/planet_bake.gd
```
Ergebnis `data/world/planet/planet.json` (Metadaten, Kontinente, Regionen, 129 KB) und `planet_cells.bin` (Zellschichten, 9 Byte/Zelle, Deflate, 500 KB). Alle Clients – und später der Server – laden **identische** Daten. Ein Test erzeugt den Planeten neu und vergleicht byte-genau mit den gebackenen Dateien.

**Regel:** Änderungen an Seed oder Generator ⇒ `generator_version` erhöhen, neu backen **und** gespeicherte Positionen/Regions-IDs migrieren.

## 4. Standortwahl und Standortbewertung [IMPLEMENTIERT – Regeln seit Paket 2.1 (0.4.0) nach TERRITORY_SYSTEM.md]

> **Seit Paket 2.1 umgesetzt:** keine Sperren nach Breite/Biom, 20 km Grenze-zu-Grenze, Schwierigkeitsklassen, Startterritorium 1 × 1 km. Die nachfolgende Tabelle beschreibt den **alten** Phase-2-Stand und dient nur der Nachvollziehbarkeit.
> Die folgenden Phase-2-Regeln (±62°, Eis/Hochgebirge gesperrt, 300 km zwischen Mittelpunkten, fremde **Region** gesperrt) widersprechen den verbindlichen Vorgaben ([DESIGN_DIRECTIVES.md](DESIGN_DIRECTIVES.md) §2–3) und werden ersetzt durch: 20 km zwischen Territoriumsgrenzen (geodätisch) und ein Schwierigkeitsmodell ohne geografische Sperren ([TERRITORY_SYSTEM.md](TERRITORY_SYSTEM.md) §3, §6). Die Faktorbewertung bleibt als Grundlage erhalten.

`Geography.rate_site(lat, lon, settlements, territories)` liefert `valid`, `score` (0–100), Faktoren und Gründe.

| Regel (ungültig, wenn …) | Wert |
|---|---|
| Wasser (Ozean/See) | – |
| Eis oder Hochgebirge | – |
| Breite jenseits von ±62° | `MAX_FOUNDING_LATITUDE` |
| Näher als 300 km an einer anderen Siedlung | `MIN_SETTLEMENT_DISTANCE_KM` |
| Region gehört bereits zum Gebiet einer anderen Siedlung | – |

| Faktor | Gewicht | Grundlage |
|---|---|---|
| Wasser | 24 % | Fluss in der Nähe 1,0 · See 0,9 · Küste 0,8 · Region mit Wasserzugang 0,5 |
| Klima | 20 % | Temperatur nahe 14 °C, ausgeglichener Niederschlag |
| Boden | 18 % | Rohstoff „fruchtbarer Boden“ + Ebene/Wald |
| Rohstoffe | 14 % | Summe der vier häufigsten Rohstoffe der Region |
| Gelände | 14 % | Ebene 1,0 · Wald 0,75 · Hügel 0,6 · Wüste 0,3 · Tundra 0,25 |
| Nachbarschaft | 10 % | ideal 400–1 600 km zur nächsten Siedlung; erste Siedlung 0,7 |

`Geography.best_site()` bewertet Regionsmitten + je 3 Stichproben und liefert den besten freien Ort (deterministisch). Er wird für „Vorschlag“, für Gründungen ohne Wahl und für die Migration alter Spielstände genutzt.

## 5. Globus und Zoomstufen [IMPLEMENTIERT]

- **Eigene Szene** (`GlobeScreen` + `GlobeView`), getrennt von der Siedlung. Öffnen über „Karte“ (oder Taste M); die Siedlungsszene wird angehalten und ausgeblendet, nicht neu simuliert.
- **Darstellung:** Einheitskugel mit eigenem Shader (Compatibility-Renderer, unbeleuchtet + einfache Schattierung): Biomfarben mit Hügelschattierung und Flüssen, glatte Küstenlinie mit dunkler Kontur (aus der Höhentextur), dünne Regionsgrenzen, Gebiete (goldene Tönung + Rand), Hervorhebung der gewählten Region, Atmosphärenschein, Sternenhimmel.
- **Zoomstufen** (Kameraabstand): **planetar** (Kontinentnamen, Siedlungsmarker) → **kontinental** (Regionsgrenzen und -namen, Gebiete, Siedlungsnamen) → **regional** (Regionen im Detail) → **lokal** = „Siedlung betreten“ (Siedlungsszene).
- **Bedienung:** Ziehen dreht, zwei Finger/Mausrad zoomen, Tippen wählt die Region (Infotafel). Die Auswahl berechnet den Strahl über die Projektionsmatrix der Kamera → Antippen und Beschriftung stimmen exakt überein (getestet).
- **Gründungsmodus:** Ohne eigene Siedlung öffnet das Spiel nach dem Charakter-Editor den Globus. Ort antippen → Bewertung mit Balken und Gründen → Name → „Hier gründen“. „Vorschlag“ springt zum besten freien Ort.
- **Nur aggregierte Daten:** Der Globus lädt keine Gebäude, NPCs oder Siedlungsszenen.

## 6. Versionierung und Migration [IMPLEMENTIERT]

- Spielstände aus Phase 1 (Siedlung ohne Position) werden beim ersten Laden **einmal** auf den besten freien Ort gesetzt, die Region wird als Gebiet beansprucht und ein Hinweis erscheint („… hat jetzt einen festen Ort auf Aurel …“). Getestet: einmalig, Position stabil.
- Region-IDs sind nur innerhalb einer `generator_version` stabil.

## 7. Offene Punkte [OFFEN]

1. **Planetengröße/Seed:** Radius 4 000 km, 5 Kontinente, 157 Regionen – vom Projektinhaber am 24.11.2026 „grundsätzlich in Ordnung“ befunden.
2. **Gründungsregeln:** entschieden – siehe [DESIGN_DIRECTIVES.md](DESIGN_DIRECTIVES.md) §2–3 (keine Breitengrad-Sperre, 20 km zwischen Grenzen).
3. **Dürfen Gründer Regionen benennen?** (WORLD_DESIGN.md §3)
4. **Lokale Karte aus der Region ableiten** (Küste, Fluss, Wald im Siedlungsraster) – Phase 4.
5. **Gebietswachstum** (weitere Regionen, Grenzen zwischen Siedlungen) – Phase 4/9.
6. **Echter Tag/Nacht-Schatten auf dem Globus** aus der UTC-Zeit – Idee, nicht umgesetzt.
7. **Detailgrad:** 49-km-Zellen wirken in der regionalen Stufe grob; höhere Auflösung (1024 × 512) kostet etwa 4× Ladezeit/Speicher – erst nach Messung auf dem iPhone entscheiden.


## 8. Hierarchie und Kapazität [GEPLANT – Bewertung 24.11.2026]
Vorgabe: [DESIGN_DIRECTIVES.md](DESIGN_DIRECTIVES.md) §1.

**Ergebnis der Prüfung:** Das *natürliche* Modell (Planet → Kontinent → Region → Zelle) trägt die Anforderungen. Nicht tragfähig ist die Kopplung **Territorium = Region** (eine Siedlung belegt eine ganze Region; zusammen mit 300 km Abstand ≈ 157 Siedlungen maximal).

Neues Schichtenmodell:
```
Natur (gebacken, unveränderlich)        Menschlich (dynamisch, gespeichert)
Planet                                   PoliticalEntity: Land / Staat / politische Region / Stadtverbund
 └ Kontinent                                └ Siedlung / Stadt (Settlement)
    └ Region (Landschaftsraum)                  └ Territorium (Polygon, versioniert)
       └ Unterregion (optional, Seed)               └ Siedlungsfläche (lokales Raster, Chunks)
          └ Zelle 49 km → Verfeinerung                  └ Grundstücke, Gebäude, Straßen
```
- Natürliche Regionen = Namen, Klima, Statistik, **keine** Besitz-/Verwaltungseinheit → beliebig viele Siedlungen je Region.
- Verwaltungseinheiten verweisen auf Territorien und ändern sich durch Spieler.
- **Räumlicher Index** (S2-ähnlicher Würfel-Kugel-Quadtree) für Abfragen „Was liegt in der Nähe?“ – [TERRITORY_SYSTEM.md](TERRITORY_SYSTEM.md) §3.
- **Kapazität:** ≈ 68 Mio. km² Land; bei 1-km-Startflächen und 20 km Abstand theoretisch ≈ 170 000 Gründungen.
- **Globus bei Tausenden Siedlungen:** Marker nach Sicht kacheln, planetar als Cluster, Territorien als eigene Mesh-Ebene statt Regions-Tönung.
- **Pole:** Sonnenmodell ohne ±60°-Grenze (Polartag/-nacht als Spielfaktor), Globuskamera bis nahe 90°.
