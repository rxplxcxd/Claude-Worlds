# Concordium – Architektur, Gestaltung und Asset

## 1. Leitidee
Ein Ort, an dem Stein, Wasser, Pflanzen und Architektur zusammenwirken. Er ist so alt, dass niemand mehr weiß, wer ihn gebaut hat, und so schön, dass die Nationen dort zusammenkommen wollen.
Vorbilder sind keine Kopie eines realen Bauwerks, sondern eine eigene Kombination aus:
- Pantheon-artiger **Rotunde** (Parlament),
- römischem **Forum** mit Säulenhallen,
- griechischem **Theater**,
- Tempel-**Portikus**,
- Palastflügeln,
- Wasserterrassen und Aquädukt.

Inspirationsbilder des Projektinhabers: Tempelfassaden mit Bannern, Nymphäum mit Brunnen, Forum mit Versammlung, überwucherte Kolonnaden am Wasser, Rundhalle mit Kreistreppen. Sie dienten nur als Inspiration, kein Bild wurde verwendet.

## 2. Architekturkonzept (Stufe 1 „Historische Anlage“)
Grundriss 168 × 168 m. Die Rotunde liegt hinten in der Mitte, die Hauptachse führt zur Kamera hin nach Südwesten (Forum), eine Querachse nach Südosten (Wasser).

| Bereich | Gestaltung | Komponente |
|---|---|---|
| **Versammlungsrotunde** (Großer Ratssaal) | Dreistufiges Podium (+6 m). Tambour mit Bogenfenstern und Gesims, 32-säulige Ringkolonnade (Peristyl) mit Gebälk und Balustrade, oberer Tambour mit Attikafenstern und Pilastern. Patina-Kuppel mit vergoldeten Rippen, Laterne mit Säulchen, Goldkuppel und Spitze – höchster Punkt 56,25 m (~33 Figurenhöhen). | `assembly_hall` |
| **Portikus** | 8 Säulen in der Front plus Seitenreihen, Bronzetor in der Cella-Wand. Fries mit vergoldeter Inschrift „CONCILIUM MUNDI“, Giebel mit vertieftem Tympanon und Goldrelief (Medaillon, Figuren). Akroterien in Gold. | `portico` |
| **Große Freitreppe** | 15 Stufen und 2 Antrittsstufen. Wangen mit Statuen, seitlich fünfstufige Wasserkaskaden. | `grand_stairs` |
| **Forum** | Gepflasterter Platz mit langem Wasserkanal, Statuenreihen und Mosaikmedaillon. Bronze-Feuerschalen, Pflanzkübel. | `forum`, `canal`, `statues` |
| **Großer Brunnen** | Rundes Becken mit Schale und Säule. In Stufe 1 trocken, der obere Teil liegt zerbrochen im Becken. | `great_fountain` |
| **Säulenhallen (Stoen)** | West und Ost, Säulenreihen zum Forum, Rückwände mit Nischen bzw. Bogenfenstern, Ziegeldächer. Im Osten fehlt ein Dachstück (sichtbare Balken, Schutt). | `stoa_west`, `stoa_east` |
| **Triumphtor** | Haupteingang des Forums: drei Bögen, vorgesetzte Säulen, Attika mit Inschrift „CONCORDIUM – UBI MUNDUS CONVENIT“, Statuengruppe. | (Forum) |
| **Wasserterrassen** | Drei Ebenen (4,4 / 2,2 / 0 m) mit Kanal, Kaskaden und Treppenläufen beiderseits des Kanals. Balustraden, Zypressenalleen, großes Spiegelbecken mit Rundtempel (Tholos) auf einer Insel. | `gardens`, `canal` |
| **Aquädukt** | Bogenreihe aus den Hügeln im Nordosten, Wasserschloss (Castellum). Ein Bogen eingestürzt. | `aqueduct` |
| **Palastflügel** | L-förmig (Delegationen West, Diplomatie Nord): Arkaden im Erdgeschoss, Bogenfenster, Gesimse, Balustraden mit Dachstatuen. Drei Kuppelpavillons, einer mit eingestürzter Kuppel. | `palace_west`, `palace_east` |
| **Theater** | Versenkte halbrunde Cavea mit 9 Sitzreihen, Mosaik-Orchestra, Bühne, Randmauer. | (öffentliche Veranstaltungen) |
| **Gärten** | Rasen, Hecken, Blumenbeete, Zypressen, Laubbäume, Kieswege. | `gardens` |

**Verfall in Stufe 1:**
- abgebrochene Säulen mit herabgefallenen Trommeln, kopflose Statuen,
- trübes, grünliches Wasser, Moos in den Fugen, Efeu an Wänden und Säulen,
- Verwitterungsflecken.

**Spätere Stufen** (2–4, Phase 7):
- vollständige Säulen, Wasser fließt (Kaskaden fallen), Brunnenstatue in Gold, Tholos-Kuppel, Banner der Nationen,
- neue Bauten auf der Erweiterungsfläche im Schutzgebiet.

Das Modell kennt die Stufen bereits (`build(stage)`).

## 3. Warum ein eigener Renderer (Werkzeuge und Vorgehen)
Kein Paket enthält ein passendes Monumentalgebäude im Penzilla-Stil. Fremde Assets in anderen Stilen hätten die Art-Direction gebrochen. Gekauft wurde nichts.
Blender als Python-Modul aus PyPI wurde in dieser Umgebung nicht zugelassen (Regel: keine heruntergeladenen Programme ausführen). Deshalb entstand ein **eigener isometrischer Renderer** (`tools/art/isorender.py`, nur numpy/scipy):
- **Kamera wie Penzilla:** Raute 512 × 292 px, also orthografisch mit 34,8° Neigung und 45° Drehung.
- **Körper:** Quader, Prismen (Giebel), Zylinder, Ellipsoide, Vielecke, jeweils mit Aussparungen (Fenster, Bögen, Nischen). Die Strahlen werden analytisch geschnitten.
- **Penzilla-Regeln:**
  - flache Farben in drei Tönen (Oberseite, linke und rechte Fläche),
  - gerundete Flächen in Stufen,
  - dunkelviolette Kontur (#2B0F2A) um jedes Bauteil,
  - Innenkanten in einem dunklen Ton der Fläche, tiefe Öffnungen in Pflaumenviolett, flache Nischen als beschatteter Stein.
- **Oberflächen (prozedural):**
  - Steinlagen mit versetzten Fugen, Plattenpflaster, kannelierte Säulen, Ziegeldächer,
  - Patina-Kuppel mit Goldrippen, Wasser mit Lichtreflexen und Kaskaden,
  - Laub in drei Tönen, Rasen, Blumen, Mosaike, Goldinschrift,
  - Verwitterung, Efeu und Moos je nach Stufe.
- 2-fache Überabtastung (Kantenglättung), Kacheln zu 512 px.

**Iterationen** (Zwischenbilder im Arbeitsordner):
1. Grundkomposition: Rotunde, Portikus, Forum, Stoen, Terrassen, Palastflügel, Theater, Aquädukt.
2. Detailprüfung in der Nahansicht. Treppenlinien zu dicht → Innenkanten weicher. Verwitterung reduziert. Giebeldach füllte das Tympanon → korrigiert. Goldrelief ergänzt. Efeu-Überwucherung eingeführt; die erste Fassung war viel zu stark und wurde neu kalibriert.
3. Nischen und Öffnungen unterschieden. Kuppelrippen je Pavillon zentriert. Wasser trüb-blau statt rasengrün. Dezentere Mosaike. Triumphtor, Feuerschalen, Kieswege, Mosaikmedaillon. Kanalwasser sichtbar gemacht.
4. Spieltauglichkeit: Antrittsstufen am Portikus, Laufraster mit Durchgängen unter Bögen und Säulenhallen, Zoomgrenze passend zur Bildauflösung. → **Entwurf 1**, gesichert (Commit `d21e116`, `docs/world_council/concordium_entwurf_1.png`).
5. Entscheidungen des Projektinhabers (25.11.2026): Höhe auf **56,25 m** (Kuppel −1,2 m, Laterne/Spitze kürzer; alles andere unverändert); echte **vergoldete Antiqua-Inschriften** (Liberation Serif Bold, SIL OFL, als Pixel in die Grafik gerastert): Portikusfries „CONCILIUM MUNDI“ (Fries vergrößert), Tor „CONCORDIUM / UBI MUNDUS CONVENIT“; **Treppenläufe** zwischen Podium und Wasserterrassen (vorher waren die oberen Terrassen unerreichbar), niedrigere Unterbauten (Ringkolonnade 0,5 m, Antrittsstufe an den Säulenhallen), Bogendurchgang zum Theatergarten, Heckentore.

## 4. Lizenzen und Quellen
- Alle Grafiken des Weltratssitzes sind **eigene Erzeugnisse** dieses Projekts (Code und Modell in `tools/art/`). Es stecken keine Fremd- oder Penzilla-Pixel darin, daher dürfen sie ins Repository (`assets/landmarks/`).
- Die Penzilla-Stilmerkmale (Perspektive, Konturfarbe, Tonwerte) wurden nachempfunden, nicht kopiert. Die Penzilla-Lizenz ist nicht berührt.
- Externe Assets: keine verwendet. Geprüft wurde, ob freie Pakete (CC0) mit antiken Bauteilen im passenden Stil existieren. Sie hätten stark umgezeichnet werden müssen, der eigene Renderer liefert stilgleichere Ergebnisse.

## 5. Maßstab, Auflösung, Leistung
- **Maßstab:** Eine Penzilla-Figur (~54 Weltpixel) entspricht 1,75 m, das ergibt 37,5 Weltpixel pro Meter. Der Komplex ist damit etwa 8 900 Weltpixel breit, deutlich größer als eine Siedlung.
- **Bildauflösung:** 16 Texel pro Meter, das sind 0,43 Texel pro Weltpixel. Das ergibt ein 3 866 × 2 599-Bild in 31 Kacheln, 4,6 MB PNG für Farbe und Tiefe. Die Kontur bleibt bis zur Zoomstufe 0,8 scharf, deshalb ist der Zoom auf 0,1–0,8 begrenzt.
- **Detailstufen:** Für sehr nahe Ansichten können später Kacheln mit 32 Texel pro Meter nur für die Umgebung der Kamera nachgeladen werden. Die Architektur und der Weltzustand ändern sich dadurch nicht.

## 6. Technische Einbindung in Godot
- **Export:** `tools/art/export_council.py <stage> <px_per_m>` erzeugt:
  - `assets/landmarks/world_council/stage1/`: Farbkacheln, Tiefenkacheln, `site.json`, `preview.png`.
- **Tiefensortierung, pixelgenau:**
  - Die Tiefenkacheln speichern pro Pixel die Fußpunkttiefe x + y der sichtbaren Fläche, dazu ein Bodenflag.
  - Für eine aufrecht stehende Figur ist ein Bildpunkt genau dann vor ihr, wenn seine Fußpunkttiefe größer ist als ihre eigene (aus der Projektion hergeleitet).
  - Die Szene zeichnet die Farbkacheln unter der Figur und eine Kopie der Kacheln um die Figur darüber. Der Shader `shaders/landmark_occluder.gdshader` lässt dort nur die Pixel stehen, die vor der Figur liegen. Die Toleranz beträgt 0,4 m, damit Figuren dicht an Wänden stehen können.
- **Laufraster** (0,5 m), gemessen mit senkrechten Strahlen knapp unter den niedrigsten Decken:
  - Höhe der Lauffläche und Art je Zelle: begehbar, blockiert, Wasser, Pflanzen.
  - Treppen, Podium und Terrassen sind begehbar (Stufen ≤ 0,55 m).
  - Durchgänge unter Bögen und in den Säulenhallen sind frei.
  - Geschlossene Gebäude, Säulen, Statuen und Wasser blockieren.
- **Szene** `CouncilSiteView`:
  - Figur des Spielers mit Lauf-Animation, Höhe folgt dem Gelände.
  - Joystick und Tastatur, Zoom per Knöpfen, Mausrad oder Pinch.
  - Tag und Nacht nach der Sonnenzeit am Ort.
  - Erreichbar vom Globus aus über „Ansehen (Vorschau)“.
