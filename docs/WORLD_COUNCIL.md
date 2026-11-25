# CONCORDIUM – Master-Erweiterung „Der internationale Weltratssitz“

Verbindliche Erweiterung des WORLDS-Master-Prompts. Erteilt am 25.11.2026, ergänzt am selben Tag durch die Entscheidungen des Projektinhabers (§6).
- Der ursprüngliche Master-Prompt bleibt **unverändert** und maßgeblich, auch seine Phasenreihenfolge.
- Dieses Dokument verankert die Anforderungen und verbindet sie mit den bestehenden Systemen.
- Korrektur des Projektinhabers: Der Kontinent heißt **Kalistia** (im ersten Auftragstext versehentlich „Area“).

Zugehörige Dokumente:
- [WORLD_COUNCIL_NEUTRALITY.md](WORLD_COUNCIL_NEUTRALITY.md): neutraler Status, Grundstücksgrenzen, Sicherheitsstufen, humanitärer Schutz
- [WORLD_COUNCIL_INTERIORS.md](WORLD_COUNCIL_INTERIORS.md): verbindliche Innenarchitektur und was heute begehbar ist
- [WORLD_COUNCIL_ART_DIRECTION.md](WORLD_COUNCIL_ART_DIRECTION.md): Architektur, Gestaltung, Asset, Iterationen
- [WORLD_COUNCIL_ROADMAP.md](WORLD_COUNCIL_ROADMAP.md): Phasenzuordnung und Abhängigkeiten
- [WORLD_COUNCIL_ARCHITECTURE.md](WORLD_COUNCIL_ARCHITECTURE.md): Daten, Persistenz, Serverautorität, Weltzeit

## 1. Anforderungen des ursprünglichen Auftrags (unverändert gültig)
1. Ein dauerhaft existierender, monumentaler Weltratssitz auf **Kalistia** als politisches, diplomatisches und gesellschaftliches Zentrum der Welt. Antik anmutender Komplex aus Parlament, Forum, Amphitheater, Tempel- und Palastanlage, Gärten und Wasser – kein gewöhnliches Regierungsgebäude.
2. **Historischer Ort:**
   - Er existiert bereits, ist verwittert, teils beschädigt und überwuchert; die Erbauer sind unbekannt.
   - Die Weltgemeinschaft kann ihn restaurieren und ausbauen. Jede Veränderung ist persistent (Stufen 1–4, nicht zwingend linear).
3. **Standort:**
   - Geografisch sinnvoll und im bewohnbaren Teil Kalistias vergleichsweise zentral, gemäßigtes Klima, schöne Landschaft.
   - Platz in der Umgebung für spätere Infrastruktur: Flughafen, Bahnhöfe, Straßen, Hafen, Hotels. Sie entsteht nicht automatisch und gehört nicht zum neutralen Gelände (§6.3).
4. **Globus:** Der Ort ist sichtbar, hat eine feste Position und eine eindeutige Kennung. Die Markierung liegt auf der Oberfläche und schwebt nicht.
5. **Architektur und Asset:** eigenes, sehr detailreiches Außen-Asset im **Penzilla-Stil**, in mehreren Iterationen verbessert und in Godot spieltauglich.
6. **Funktionsbereiche:** Versammlungshalle ohne künstliche Kapazitätsgrenze, diplomatische Räume, öffentliche Veranstaltungsflächen, Garten- und Außenanlagen.
7. **Weltrat:**
   - Jährliche Weltversammlung am **24. Juni**, berechnet in Weltzeit, unabhängig von Gerätezeit und Online-Status einzelner Spieler.
   - Vertretung durch Delegierte, Stellvertreter, Berater und Vollmachten.
   - Beschlüsse haben echte Auswirkungen; keine vorgegebenen Ergebnisse.
8. **Anreise als echte Reise** mit Auto, Bahn, Schiff und Flug, für alle Spieler. Reisekosten passen zum Wirtschafts- und Steuersystem; jede Nation regelt die Kosten ihrer Delegierten selbst.
9. **Persistenz und Multiplayer von Anfang an:**
   - Der Server ist die verbindliche Quelle.
   - Die Welt läuft weiter, auch wenn niemand online ist.
   - Skalierung über Detailstufen; die Bevölkerung wird nicht geräteabhängig gekürzt.
10. **Nutzung außerhalb der Versammlung:** Märkte, Kultur, Ausstellungen, Konferenzen, Feiern, Gedenktage.
11. **Qualitätsprüfung im echten Spiel.**

## 2. Verhältnis zum Master-Prompt
- Master-Prompt §9.3–9.6 (Weltrat einmal pro Spieljahr, Delegierte, Community-Ereignis, Ausfallsicherheit) und die Vision bleiben maßgeblich. Diese Erweiterung legt fest:
  - Ort und Gestalt,
  - Namen und Termin,
  - Neutralität, Innenarchitektur und Infrastruktur.
- „Einmal pro Spieljahr“ heißt konkret: **24. Juni der Weltzeit (UTC)**.
  - Das Weltjahr ist das Kalenderjahr der persistenten Echtzeitwelt.
  - Die beschleunigte NPC-Lebenszeit (LIVING_WORLD.md) ist nur ein Maß fürs Altern und nicht der politische Kalender.
- **Leerer-Planet-Regel:** Das Concordium ist keine Siedlung, sondern eine unbewohnte historische **Landmarke** (`rules.landmarks_are_not_settlements`).
- **Konflikte (Master-Prompt Phase 11):** Das Concordium ist von Kampfhandlungen ausgenommen, außer in dem eng begrenzten Krisenfall aus WORLD_COUNCIL_NEUTRALITY.md §5.

## 3. Standort (umgesetzt)
**28,28° N / 137,36° E** – Zaneris-Ebene (`reg_139`), Kontinent Kalistia (`cnt_05`).

| Merkmal | Wert |
|---|---|
| Gelände | Ebene, 162 m ü. M., geringe Hangneigung |
| Klima | Ø 16 °C, Niederschlag 0,56, warm-gemäßigt |
| Wasser | Meeresbucht ca. 30 km im Südwesten (Hafen möglich); Wasser des Komplexes historisch über ein Aquädukt aus den Hügeln |
| Landschaft | sanfte Hügel nach Nordosten (bis +218 m), offene Ebene nach Süden und Westen |

Begründung:
- Kalistia besteht großteils aus Eis und Tundra; gemäßigt ist nur der Süden.
- Die Analyse (`tools/world/council_site.gd`) bewertete alle Landzellen des Kontinents. Die Zaneris-Ebene lag durchgehend vorn.

## 4. Was umgesetzt ist – und was nicht

| Bereich | Stand |
|---|---|
| Ort in der Weltdefinition (`data/world/landmarks.json`), feste Koordinaten | **implementiert** |
| Namen (Concordium, Concilium Mundi, Weltrat/Weltversammlung) | **implementiert**: Daten, Globus, Vorschau, Inschriften im Asset |
| Persistenter Zustand (Stufe, Komponenten, Grundstück, Vorfälle, Geschichte) | **implementiert** (`WorldState.landmark_state`) |
| Grundstücksgrenze = neutrales Gelände (172 × 172 m) | **implementiert**: Gründungsregel, Zonenprüfung, Grenzänderung nur durch Weltautorität mit Beschluss |
| Neutralitätsstufen (verhindert, Verstoß, Krise) | **Regelwerk implementiert** (Daten + Klassifikation + Tests). Wirkung in Kampf und Sicherheit erst mit Phase 11/12, weil es noch kein Kampfsystem gibt |
| Globus-Markierung | **implementiert** |
| Außen-Asset Stufe 1 | **implementiert** (eigener Renderer) |
| Begehbares Außengelände | **Entwicklungsprototyp**: Vorschau vom Globus aus, ohne Anreise |
| Innenräume aller Gebäude | **Konzept, verbindlich festgelegt** (WORLD_COUNCIL_INTERIORS.md); gebaut wird in Phase 7 |
| Humanitäre Einrichtungen | **geplant**: Standorte im Gebäudeprogramm festgelegt |
| Concilium Mundi (Ablauf, Abstimmungen) | **Termin implementiert**; die Institution folgt in Phase 10 |
| Reisen und Infrastruktur | Phase 8 |

## 5. Offene Entscheidungen
Alle Entscheidungen aus der ersten Fassung sind getroffen (§6). Neu offen ist nur:
1. **Inschrift-Motto** am Tor: „UBI MUNDUS CONVENIT“ (lat. „wo die Welt zusammenkommt“) – ein Vorschlag, jederzeit änderbar.
2. **Abstimmungsregeln und Delegiertenzahl** des Concilium Mundi: werden in Phase 9/10 mit dem Projektinhaber festgelegt.

## 6. Ergänzung vom 25.11.2026 – verbindliche Entscheidungen des Projektinhabers
Der erste Entwurf bleibt Grundlage. Er ist gesichert in Commit `d21e116` und als Bild in `docs/world_council/concordium_entwurf_1.png`.

### 6.1 Name und offizielle Bezeichnung
- Der **Ort** heißt **Concordium**, mit C (verbindlich). Lat. *concordia*: Eintracht, Harmonie, Zusammenhalt, Übereinstimmung.
- Die jährliche internationale **Weltversammlung** heißt offiziell **Concilium Mundi** („Rat bzw. Versammlung der Welt“).
- Die Bezeichnungen haben unterschiedliche Funktionen und ersetzen sich nicht gegenseitig:

| Wo | Bezeichnung |
|---|---|
| Inschriften, historische Dokumente, Plakate, Informationstafeln, Einladungen, Veranstaltungsankündigungen, zeremonielle Darstellungen | **Concilium Mundi** (immer) |
| Normales Interface (lokalisiert) | „Weltrat“ (Institution), „Weltversammlung“ (Ereignis); englisch „World Council“ / „World Assembly“ |
| Ort | immer „Concordium“, nie übersetzt |

- Zeremonielle Kopfzeile (`Landmarks.ceremonial_heading`):
  **CONCORDIUM** · *Concilium Mundi* · „Der Ort, an dem die Welt zusammenkommt.“
- Im Asset stehen:
  - auf dem Fries des Versammlungsportikus: **CONCILIUM MUNDI**,
  - auf dem Eingangstor: **CONCORDIUM** und das Motto aus §5.

### 6.2 Höhe und Maßstab
- Der höchste Punkt (Goldkugel der Laterne auf der Rotundenkuppel) liegt bei **56,25 m**. Das sind etwa **33 Figurenhöhen zu je 1,7 m**.
- Die erste Fassung lag bei 60,6 m. Gesenkt wurden nur die Kuppel (um 1,2 m) sowie Laterne und Spitze. Grundriss, Säulen, Nebengebäude und Statuen sind unverändert.
- Keine künstliche Vergrößerung. Lesbarkeit im Spielmaßstab und der Speicherbedarf auf Mobilgeräten bleiben Anforderungen. Die Kacheln der Stufe 1 belegen 4,6 MB als PNG.

### 6.3 Schutzgebiet = Grundstücksgrenze
- Der **18-km-Schutzradius ist verworfen.**
- Neutral ist **ausschließlich das Grundstück des Concordiums**: ein Polygon um den Standort, derzeit 172 × 172 m (2,96 ha, `property.polygon_m`).
- Außerhalb gelten die normalen Regeln. Wer 100 m vor der Mauer steht, genießt keinen Schutz.
- Straßen, angrenzende Landschaft und spätere Hotels, Bahnhöfe oder Flughäfen gehören **nicht** automatisch dazu.
- Siedlungsgebiete dürfen das Grundstück nicht überdecken, direkt daneben ist eine Gründung aber erlaubt.
- Die Grenze ist Teil des **Serverzustands**. Erweiterungen gibt es nur so:
  - über einen Beschluss plus Aktualisierung durch die Weltautorität (`WorldState.update_landmark_property`),
  - das neue Gelände muss das alte vollständig enthalten,
  - jede Änderung wird protokolliert.

### 6.4 Neutralität und Unverletzlichkeit
- Das Concordium gehört keiner Nation, keinem Staat, keinem Bündnis und keiner Fraktion.
- Neutral ist es **ganzjährig**, nicht nur beim Concilium Mundi, und auch im Weltkrieg.
- Es gilt ein dreistufiges System:
  1. **Gewöhnliche Gewalt wird technisch verhindert.**
  2. **Bewusste Verstöße** werden erkannt, dokumentiert und von Sicherheitskräften beantwortet.
  3. Ein **Angriff auf das Concordium** ist als außergewöhnlicher historischer Tabubruch grundsätzlich möglich. Voraussetzungen: Erklärung durch eine Staatsregierung, Prüfung durch den Server, Konfliktsystem aktiv. Er hat massive Folgen.
- Der Ort ist weder magisch unverwundbar noch frei angreifbar. Details und Schutz vor Ausnutzung: [WORLD_COUNCIL_NEUTRALITY.md](WORLD_COUNCIL_NEUTRALITY.md).

### 6.5 Humanitärer Schutz
- Zivilisten, Familien, Kinder, Verletzte, Schutzsuchende und Geflüchtete finden dort Zuflucht.
- Der Zugang hängt nicht von der politischen Zugehörigkeit ab.
- Geplante Einrichtungen mit festen Orten im Gebäudeprogramm:
  - medizinische Versorgung, Notunterkünfte, Gemeinschaftsräume,
  - Lebensmittel, Trinkwasser (Aquädukt),
  - geschützte Bereiche.

### 6.6 Vollständig begehbar
- Die Vorschau ist ein Prototyp, nicht das Ziel.
- Jedes Gebäude bekommt einen eigenen Innenraum, dessen Form zum Äußeren passt:
  - Großer Ratssaal in der Rotunde,
  - Ausstellungshallen,
  - Diplomatieflügel, Archiv, Gästehaus, Zufluchtsort,
  - Innenhöfe, Wasseranlagen, Plätze.
- Verbindlich festgehalten in [WORLD_COUNCIL_INTERIORS.md](WORLD_COUNCIL_INTERIORS.md) und `data/landmarks/concordium_interiors.json`. Dort ist für jeden Bereich vermerkt, ob er begehbar, nur Vorschau oder Konzept ist.

### 6.7 Termin
- Das Concilium Mundi findet jährlich am **24. Juni** statt, berechnet aus der Weltzeit (UTC) und nie aus der Uhr des Geräts.
- Alle anerkannten Nationen können Vertreter entsenden.
- Das Concordium bleibt auch außerhalb des Termins zugänglich und neutral.

### 6.8 Versionierung
- Die sichtbare Produktversion bleibt **v0.1**. Sie erscheint auf dem Ladebildschirm und im Menü.
- Erhöht wird sie erst bei einem vom Projektinhaber **freigegebenen** Entwicklungsstand, nicht weil weitergearbeitet wurde.
- Die technische Build-Version wird unabhängig geführt (jetzt 0.8.0). Siehe [VERSIONING.md](VERSIONING.md).
