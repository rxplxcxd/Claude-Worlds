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
| Innenwände | waagerechte Wände sind frontale Flächen (y-sortiert mit Figuren), senkrechte Wände schmale Streifen; Türen als Penzilla-Türgrafik, die beim Annähern aufgeht |
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
