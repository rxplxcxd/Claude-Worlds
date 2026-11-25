# WORLDS Innenraum-Standard (verbindlich für alle Innenräume)

## 1. Ursache des früheren Perspektivfehlers
Die vorhandenen Innenraum-Grafiken haben eine **gerade 3/4-Draufsicht**:
- Penzilla „Top-Down Retro Interior“, 16 px,
- Kenney „Roguelike Indoors“, CC0, 16 px.

Ihre Böden sind quadratische Kacheln, Rückwände sind frontale Flächen, Möbel zeigen ihre Vorderseite.
Das frühere Innenraumsystem baute die Räume dagegen als **um 45° gedrehte Isometrie-Rauten** wie die Außenwelt. Es verzerrte Böden und Wände auf die schrägen Flächen und stellte frontale Möbel auf Rauten. Dadurch passten Perspektive und Grafik nicht zusammen: Möbel standen „schief“ im Raum, Betten lagen diagonal.

Die Lösung liegt auf Systemebene: Die Innenräume verwenden jetzt die Projektion, in der ihre Grafiken gezeichnet sind. Es wird **nichts gedreht oder verzerrt**.

## 2. Projektion und Geometrie
| Festlegung | Wert |
|---|---|
| Kamera | erhöhte, gerade 3/4-Ansicht (schiefe Parallelprojektion): Bildschirm = (X, Y − Z), Höhe senkrecht nach oben |
| Raumachsen | x nach rechts, y (Süden) nach unten; Räume sind Rechtecke (Sonderformen: Ausschnitte, Kreis mit gerader Rückwand oben) |
| Kachel | 16 px Grafik × Faktor 2 = **32 Weltpixel** (≈ 0,6 m), quadratisch |
| Wandhöhe | Standard **3 Kacheln** (48 px = Höhe einer Penzilla-Tür); je Raum anpassbar (`wall_tiles`), z. B. Säle 4–6 |
| Rückwand | frontale Fläche über der Oberkante des Bodens, mit dunkler Mauerkappe |
| Seitenwände | schmale Kappen (8 px) |
| Vorderwand | aufgeschnitten zu einer niedrigen Kappe; der Eingang ist eine 2 Kacheln breite Lücke darin |
| Innenwände | waagerechte Wände sind frontale Flächen (y-sortiert mit Figuren), senkrechte Wände schmale Streifen; Höhe je Wand einstellbar (`wall_tiles`) |
| Türen | Typen `single` (2 Kacheln, Penzilla in Häusern, eigene antike Tür im Concordium), `double` (Doppeltür) und `gate` (Bronzetor, 4 Kacheln, langsam). Sie gehen bei Annäherung von Spieler oder NPC auf, mit 4 Phasen. Die Kollision folgt dem Öffnungsgrad: zu = Sperre, ab 60 % offen = Durchgang |
| Runde Räume | volle Wandflächen nur im oberen Band (2 Reihen), die Rundung als Kappe |

## 3. Möbel und Gegenstände
- **Ausrichtung:** Alle Stücke sind frontal gezeichnet. Betten stehen mit dem Kopfteil an der Wand, längs nach Süden.
- **Ankerpunkt:** Die Standfläche (Breite der Grafik × Tiefe `solid`) liegt auf dem Raster. Die Unterkante der Grafik ist die Vorderkante der Standfläche.
- **Tiefensortierung:** Sortiert wird nach der Vorderkante, gemeinsam mit Figuren und waagerechten Innenwänden. Kleinteile auf Möbeln (`lift`) werden direkt danach gezeichnet.
- **Kollision:** Die Standfläche ist ein Rechteck. Teppiche und Matten sind flach und begehbar.
- **Wandgegenstände** (Fenster, Bilder, Oberschränke, Banner) hängen auf der Rückwand bzw. einer Innenwand (`row`), mit Höhe über dem Boden.
- **Größe:** Kein stehendes Stück ist höher als die Wand seines Raumes (Test). Eine Person ist etwa 1,7 m groß, eine Tür etwa 2,1 m.
- **Interaktion:** Der Knopf erscheint nur an der Standfläche des Objekts (plus 0,4 Kacheln Rand), der Ausgang nur an der Türmatte.

## 4. Grafik
- 16 px pro Kachel, keine Kantenglättung, 1-px-Kontur in Dunkelbraun (#3B2318).
- Licht von vorn oben: Oberseiten am hellsten, Vorderseiten mittel.
- Farben aus der Palette der Penzilla-Innenraumtafeln plus wenige Heraldik- und Grautöne.
- Eigene Stücke erzeugt `tools/art/interior_assets.py` mit genau dieser Kamera:
  - oblique Projektion, Palettenquantisierung,
  - Ausgabe `assets/interior/worlds/` (eigene Grafik, darf ins Repository),
  - Atlas-Einträge in `data/interiors/worlds_items.json`.
- Die gekauften Penzilla-Stücke werden unverändert verwendet. Die Farbtafel „State2“ dient als zweite Farbvariante.

## 5. Raumprogramme, Varianten, Wiederverwendung
- Layouts sind Daten (`data/interiors/layouts.json`), erzeugt aus `tools/interiors/build_layouts.py`.
- **Wohnhäuser:** `house_small`, `house_medium` und `house_large` sind Grundtypen. Die Gebäudegrafiken verweisen darauf (`alias`).
- **Varianten:** Böden, Wände, Farbtafel, Bettfarben und Schrankart werden je Gebäude über einen Seed gewählt. Dazu kommen Stücke, die vom Wohlstand der Siedlung abhängen (`min_wealth`/`max_wealth`). Bis zur Wirtschaft (Phase 6) wird der Wohlstand aus Bevölkerung und Vorräten abgeleitet.
- **Neue Räume:** Raumrechtecke, Innenwände mit Öffnungen und Türen, Eingang und Stücke eintragen. Ein Prüflauf (`InteriorScene.layout_problems`) meldet Überschneidungen, Stücke außerhalb des Raumes und verstellte Eingänge.

## 6. Bestand und Herkunft der Innenraum-Assets
| Paket | Perspektive | Verwendung |
|---|---|---|
| Penzilla Top-Down Retro Interior (gekauft, 16 px, 2 Farbtafeln) | gerade 3/4 | Grundmöbel, Küche, Bad, Türen, Fenster, Böden, Wände, Kleinteile. Ein Bett gibt es im Paket nicht. |
| WORLDS-eigene Pixelgrafik (80 Stücke, 9 Texturen) | gerade 3/4 | Betten, Matratze, Feldbett, Schränke, Dusche, Badmöbel, Oberschränke, Laden, Bäckerei, Schmiede, Werkstatt, Büro, Praxis, Versorgung, das komplette antike Concordium-Set, Marmor-, Mosaik-, Stein-, Fliesen- und Metallböden, Marmor-, Fresko-, Fliesen- und Ziegelwände |
| Kenney Roguelike Indoors (CC0, 16 px) | gerade Draufsicht | geprüft, derzeit nicht verwendet: flacherer Stil, würde neben Penzilla auffallen |
| Kenney Furniture Kit (CC0) | isometrisch gerendert | passt nicht zum Standard, nicht verwendet |
| OpenGameArt Interior 16×16 (CC0) | gerade Draufsicht | zu wenig Inhalt, nicht verwendet |

Externe Recherche: Weitere freie Pakete gibt es zwar (itch.io, OpenGameArt), sie sind aber meist kostenpflichtig oder haben andere Pixeldichten bzw. Stile. Ich habe nichts gekauft. Fehlende Stücke sind eigene Grafik mit exakt dieser Perspektive.

## 7. Ebenen, Treppen, Laufraster, Sitzplätze (seit 0.10.0)
- **Ebenen** (`levels`): erhöhte, begehbare Flächen wie Galerien.
  - Je Ebene: Rechtecke mit Höhe `z` in Kacheln, Boden- und Wandtextur, Brüstungen `rails` = [Rechteck-Index, Kante].
  - Gezeichnet werden die Oberfläche, die Vorderwand nach Süden (nicht an Fugen zur Nachbarfläche) und eine Kante zum offenen Rand.
  - Der Raum darunter ist massiv.
- **Treppen** (`stairs`): Rechteck, Richtung (`north`, `west`, `east` = steigt nach …), Ziel-Ebene.
  - Stufen etwa 0,4 Kacheln hoch, Wangen auf beiden Seiten.
  - Treppen werden an ihrer Nordkante sortiert, Figuren auf den Stufen sind sichtbar.
- **Ebenenkollision** (`InteriorScene.carry`):
  - am Boden sperrt der Sockel der Galerie (Ebene 2),
  - auf der Galerie sperren ihre Ränder (Ebene 3), nur nicht am Treppenaustritt,
  - auf der Treppe gelten nur die Wangen.
  - Die Figur wird um die Laufhöhe angehoben gezeichnet. Gilt für Spieler und NPCs gleichermaßen.
- **Laufraster** (`build_nav`): 4 Zellen je Kachel (8 px).
  - Höhe je Zelle aus Räumen, Ebenen und Treppen. Wände, Möbel und Brüstungen sind gesperrt, um den Figurradius (9 px) vergrößert.
  - Türen zählen als passierbar, weil sie sich öffnen.
  - `reachable()` füllt ab einem Punkt; Schritte über 0,5 Kacheln Höhenunterschied sind ausgeschlossen.
- **Sitzplätze:** Stücke mit `seat` (eindeutige ID), `row` und `sector` landen im Register `seats`, mit Position, Standfläche und Zugangspunkt `stand` (freie Laufzelle daneben).
  - `nearest_seat()` bietet „Platz nehmen“ an.
- **Gedrehte Stücke** (`anchor`, `footprint` im Atlas): Die Grafik ist um den Ankerpunkt gedreht gerendert und sitzt mittig auf einer kompakten Standfläche. Beispiel: die Delegiertenplätze, in 15°-Stufen zum Rostrum gedreht.

## 8. Dynamischer Innenraumgenerator (`scripts/interior/interior_generator.gd`)
- **Eingabe:** Gebäudetyp, Grundfläche in Kacheln, Seed, Wohlstand.
  - Typen: `house`, `shop`, `office`, `clinic`, `workshop`, `palace`.
  - Grundfläche von 8 × 7 bis 60 × 60.
- **Schlüssel:** `gen:<typ>:<b>x<t>:<seed>:<wohlstand %>`. `InteriorScene.create(key)` und `resolve(key)` nehmen ihn direkt.
  - Gleicher Schlüssel und gleiche `VERSION` ergeben genau denselben Innenraum.
  - Ein Gebäude speichert nur diesen Schlüssel; das ist die Persistenz. Eine neue Generator-Version ändert ältere Schlüssel nicht, weil `VERSION` Teil des Seeds ist.
- **Aufbau:** Der Grundriss wird in Ost-West-Bänder geteilt, passend zur Kamera, die nach Norden blickt.
  - Vorne liegt die Halle bzw. der Wohnraum um den Eingang, daneben Seitenräume.
  - Ab etwa 150 Kacheln folgen Flure (3 Kacheln) und hintere Raumreihen. Große Grundrisse bekommen mehrere Flure, ein Palast einen Innenhof.
  - Türen sitzen in den waagerechten Wänden; die Halle öffnet sich breit zum Flur. Generierte Innenwände sind 2 Kacheln hoch, damit man in die hinteren Räume sieht.
- **Möblierung:** Regeln je Raumart (Rückwand, Mitte, Seiten, Ecken, Wand) mit Mindestwohlstand.
  - Laufwege bleiben frei: Abstand um jedes Stück, freie Flächen vor Türen und am Eingang, keine Wandstücke über Türen.
- **Prüfung:** Ein eigenes Belegungsraster prüft, ob alle Räume vom Eingang erreichbar sind. Wenn nicht, werden zuletzt gesetzte Stücke entfernt.
  - Die Tests bauen zusätzlich jeden Innenraum mit dem echten Laufraster.
- **Nur eigene Grafik:** funktioniert in jedem Build.
- **Grenzen:**
  - Die Siedlungsgebäude behalten ihre handgemachten Innenräume. Den Generator nutzt künftig, was keine eigene Einrichtung hat, z. B. in Phase 7 (Bau).
  - Er erzeugt rechteckige Grundrisse ohne Ausschnitte.
