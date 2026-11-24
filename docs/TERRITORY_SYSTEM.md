# TERRITORY_SYSTEM – Flächen, Territorien, Gründungsabstand

**Status:** Gründung, Startterritorium, 20-km-Regel, Sperrzonen, Schwierigkeit, Index, Speicherung **[IMPLEMENTIERT – Paket 2.1, 0.4.0]** · Erweiterung, Erreichbarkeitsgarantie, Verfall von Erweiterungen **[GEPLANT, verbindliche Regeln §5]**.
Grundlage: [DESIGN_DIRECTIVES.md](DESIGN_DIRECTIVES.md) §1–4 und die Entscheidungen des Projektinhabers vom 24.11.2026 (§11).

## 1. Vier Flächenbegriffe (technisch getrennt)

| Begriff | Bedeutung | Gespeichert als | Wer ändert es |
|---|---|---|---|
| **Siedlungsfläche** (`SettlementArea`) | Der lokal spielbare Bereich mit eigenem Kachelraster (Start ≤ 1 × 1 km = 100 × 100 Kacheln à 10 m). Hier stehen Gebäude, Straßen, Grundstücke. | Ursprung (lat/lon), Ausrichtung, Rastergröße, Chunks | Wächst nur durch Erweiterung (§5) |
| **Beanspruchtes Territorium** (`Territory`) | Rechtlich-politisches Gebiet einer Siedlung oder Einheit: Siedlungsfläche + Umland (Felder, Wald, Rohstoffe, Küstengewässer). **Grundlage der 20-km-Regel.** | Polygon(e) auf der Kugel, Version, Historie | Gründung, Erweiterung, Verträge, Zusammenschlüsse |
| **Bebaute Fläche** (abgeleitet) | Was tatsächlich genutzt ist: Grundstücke mit Gebäuden, Straßen, Infrastruktur. | **Nicht** autoritativ gespeichert – aus Gebäuden/Straßen berechnet, als Statistik zwischengespeichert | Entsteht durch Bauen/Abreißen |
| **Territoriale Erweiterung** (`ExpansionClaim`) | Antrag auf zusätzliches Gebiet mit Kosten, Fristen, Einspruch. | Antragsdatensatz mit Zielgeometrie und Zustand | Eigenes System (§5) |

Beziehung: *bebaute Fläche ⊆ Siedlungsfläche ⊆ Territorium*. **Entschieden:** Das Startterritorium ist **genau 1 × 1 km** (= Siedlungsfläche); die bebaute Fläche kann kleiner sein; das Territorium kann später dynamisch erweitert werden.

## 2. Geometrie auf der Kugel

- Der Planet ist eine **Kugel** (R = 4 000 km). Geodäten sind Großkreise → exakte, einfache Formeln (keine Ellipsoid-Rechnung nötig).
- **Territorien = sphärische Polygone**: Eckpunkte als Breite/Länge, Kanten als Großkreisbögen. Ein Territorium kann aus mehreren Teilen bestehen (Inseln).
- **Lokales Raster ↔ Kugel:** Jede Siedlungsfläche hat einen Ursprung und einen lokalen Tangentialrahmen (Ost/Nord). Kachel (x, y) → Meter im Rahmen → Punkt auf der Kugel (azimutale äquidistante Abbildung). Fehler bei 1 km Ausdehnung < 1 mm, bei 50 km < 5 m – vernachlässigbar.
- **Pole:** Im Pol ist „Norden“ nicht definiert → Rahmen dort über den Nullmeridian festgelegt. Keine Sonderregel für Gründungen.
- **Abstand Punkt–Bogen:** Für Einheitsvektoren P, A, B: `n = (A×B)/|A×B|`; Fußpunkt `C = normalize(P − (P·n)·n)`; liegt C auf dem Bogen AB, ist der Abstand `R·asin(|P·n|)`, sonst `R·min(∠PA, ∠PB)`.
- **Abstand Polygon–Polygon:** 0, wenn sie sich schneiden oder enthalten; sonst Minimum aller Punkt–Bogen-Abstände in beide Richtungen. Bei 1-km-Quadraten (4 Kanten) und wenigen Nachbarn trivial schnell.
- **Küsten:** Die Distanz ist rein geometrisch entlang der Oberfläche (über Land und Wasser gleich). Küsten wirken nur auf die *Eignung* der Fläche (Landanteil, §6), nicht auf die Distanzregel.

## 3. Gründungsregel: 20 km zwischen Territoriumsgrenzen

```
gültig(P) ⇔ für jedes bestehende Territorium T:
             distanz_geodätisch( Startfläche(P), Grenze(T) ) ≥ 20 km
         ∧ Startfläche(P) liegt in keinem Territorium
         ∧ Startfläche(P) hat ausreichend Land (Vorschlag ≥ 70 %)
```
- `Startfläche(P)` = das 1 × 1-km-Quadrat der künftigen Siedlung um P (nicht nur der Punkt).
- Gemessen wird **Grenze zu Grenze**. Wächst ein Nachbar später, gilt für die Gründung trotzdem der Zustand zum Gründungszeitpunkt (serverseitig geprüft, siehe §7).
- **Kapazität:** Landfläche ≈ 68 Mio. km². Pro Siedlung (1 km² + 20 km Abstand, dichteste Packung) ≈ 385 km² → theoretisch ≈ 170 000 Gründungen. „Tausende“ sind also geometrisch problemlos möglich; begrenzend sind Server, Spielerzahl und Erweiterungen.

### Sperrzonen auf dem Globus
- Sperrzone = Menge aller Mittelpunkte P, für die die Regel verletzt ist ≈ jedes Territorium um **20 km + halbe Diagonale der Startfläche (0,71 km)** geodätisch „aufgebläht“ (Puffer).
- Darstellung: Pufferpolygone werden im lokalen Tangentialrahmen berechnet, auf die Kugel zurückgebildet und als halbtransparente rote Flächen leicht über der Oberfläche gezeichnet (eigene Mesh-Ebene; ab Zoomstufe kontinental). Planetar nur als Punkte/Cluster.
- Beim Antippen folgt die **exakte** Prüfung (§3) mit Begründung („18,4 km bis zur Grenze von Lichtfeld“). Die Anzeige ist eine Vorschau; entscheidend ist die Serverprüfung.

### Räumlicher Index
- Für tausende Territorien wird ein **hierarchisches Zellraster** (Würfel-Kugel-Quadtree, S2-ähnlich) eingeführt: Würfelfläche + Pfad → Zell-Token. Kantenlängen bei R = 4 000 km: Ebene 8 ≈ 24 km, Ebene 9 ≈ 12 km, Ebene 12 ≈ 1,5 km.
- Jedes Territorium speichert die Ebene-8-Zellen seiner Fläche **plus 21-km-Puffer** (`cover_l8[]`). Kandidaten für eine Gründungsprüfung = Territorien mit gemeinsamer Zelle → wenige Vergleiche statt aller Siedlungen.
- Firestore-tauglich (`array-contains-any`, ≤ 30 Werte) – siehe [FIREBASE_SCHEMA.md](FIREBASE_SCHEMA.md).

## 4. Hierarchie und Dynamik

```
Natur (unveränderlich, gebacken):   Planet → Kontinent → Region → (Unterregion) → Zelle
Menschlich (dynamisch, gespeichert): Territorium ← Siedlung ← Stadt/Verbund ← Region*/Staat/Land (PoliticalEntity)
```
- Natürliche Regionen sind **Landschaftsräume** (Name, Klima, Statistik) – **keine Besitz- oder Verwaltungseinheiten**. Beliebig viele Siedlungen pro Region.
- **Unterregionen** (Vorschlag): deterministische Unterteilung jeder Region in 8–20 Teile (gleiches Voronoi-Verfahren, eigener Seed) für Namen, Statistik und spätere Verwaltungsgliederung; bei Bedarf nachbackbar ohne bestehende IDs zu ändern (neue Datei, gleiche Generatorversion der Grobstufe).
- Verwaltungseinheiten (Gemeinde, Kreis, „politische Region“, Staat, Land) sind `PoliticalEntity`s mit **Verweisen** auf Territorien – sie entstehen und ändern sich durch Spieler ([POLITICAL_SYSTEM.md](POLITICAL_SYSTEM.md)).
- Jede Grenzänderung erzeugt eine neue `version` des Territoriums mit Historie (wer, wann, warum: Erweiterung, Vertrag, Fusion, Auflösung).

## 5. Territoriale Erweiterung [GEPLANT – verbindliche Regeln]
Eigenes System, getrennt von der Gründungsregel (Umsetzung frühestens Phase 8).

### 5.1 Grundregeln (entschieden 24.11.2026)
- Die **20-km-Regel gilt nur für Neugründungen** unabhängiger Siedlungen – nicht dauerhaft für bestehende.
- **Erweiterungen dürfen bis an die Grenze benachbarter Siedlungen heranwachsen**; zwei Siedlungen dürfen direkte Nachbarn werden.
- **Territorien dürfen sich nie unberechtigt überlappen** (Prüfung `TerritoryGeometry.overlapping_pairs`, heute schon Teil der Invarianten). Berechtigte Überschneidungen gibt es nur durch Verträge (z. B. Abtretung, gemeinsame Verwaltung) – dann ändert sich die Geometrie, nicht die Regel.
- **Kein automatisches Vorrecht älterer Siedlungen.** Konkurrierende Anträge werden nach denselben Regeln für alle entschieden (§5.3).

### 5.2 Erreichbarkeitsgarantie (gegen Einkreisung und Blockaden)
Jede Siedlung behält **immer** Zugang zum übergeordneten Wegenetz. Regel:
1. **Zugangskorridor:** Von jeder Territoriumsgrenze muss es einen zusammenhängenden Weg mit **mindestens 1 km Breite** (Vorschlag) geben, der **nicht durch fremdes Territorium** führt und das **übergeordnete Netz** erreicht.
2. **Übergeordnetes Netz** = Verbindungsstraßen/Schienen/Häfen zwischen Siedlungen (Phase 8). Solange es nicht existiert, gilt als Netz: **freies Land ab 50 km Entfernung** oder **offene Küste** (Seezugang).
3. **Prüfung bei jeder Gebietsänderung** (Erweiterung, Vertrag, Fusion, Neugründung): Nach der Änderung müssen **alle** betroffenen Siedlungen im Umkreis (Vorschlag 100 km) noch einen Korridor haben. Eine Änderung, die eine Siedlung abschneiden würde, wird **abgelehnt** – egal ob die betroffene Siedlung älter oder jünger ist (symmetrisch).
4. **Wegerecht statt Korridor:** Führt der einzige Zugang durch fremdes Gebiet, ist das nur zulässig mit einem **Wegerecht** (dauerhafte Dienstbarkeit, an das Land gebunden, durch Weltregeln geschützt; Kündigung nur mit Ersatzweg).
5. **Neugründungen allein können nicht einkreisen:** Zwischen den Grenzen liegen stets ≥ 20 km > 1 km Korridorbreite. Die Regel greift daher vor allem bei Erweiterungen.
6. **Algorithmus (serverseitig):** lokales Raster (1-km-Zellen) um die betroffene Siedlung, fremde Territorien als Hindernis, Korridorbreite durch Erosion der freien Fläche um ½ Breite, Flutfüllung von der eigenen Grenze bis zum Netz bzw. 50-km-Rand.

### 5.3 Erweiterungsverfahren (Entwurf)
- **Antrag** auf angrenzende, zusammenhängende Fläche mit Kosten (Vermessung, Verwaltung) und Voraussetzungen (Einwohner, Nutzung der vorhandenen Fläche, Versorgung).
- **Einspruchsfrist** für Nachbarn im Umkreis (z. B. 50 km). Konkurrierende Anträge: Verhandlung → sonst **Mittellinie** zwischen den Grenzen oder Schiedsverfahren (Rat). Kriterien sind Nutzung und Bedarf, nicht das Alter der Siedlung.
- Jede Erweiterung wird als eigener Eintrag in `expansions[]` mit Zustand, Fristen und Geometrie gespeichert; das Kerngebiet bleibt getrennt.

### 5.4 Inaktivität und Gründungsschutz (entschieden 24.11.2026)
- **Die Kernfläche (Startterritorium) verfällt nie** wegen Abwesenheit; **keine automatische Auflösung** einer Siedlung; **keine Bestrafung für normale Spielpausen**.
- **Erweiterungsflächen** können unter klar definierten Bedingungen anders behandelt werden – **nur wenn alle** zutreffen (Vorschlag):
  1. ungenutzt (keine Gebäude, Felder, Leitungen, Abbau, Bewohner),
  2. Unterhalt seit mindestens 60 Tagen nicht bezahlt,
  3. eine andere Partei beantragt die Fläche,
  4. Ankündigung mit 14 Tagen Frist; Halten durch Zahlung oder Nutzung jederzeit möglich.
  Flächen mit Gebäuden, Bewohnern oder Infrastruktur fallen **nie** zurück.
- **Blockadegründungen unattraktiv machen** (statt Verfall): eine aktive Gründung je Konto (**implementiert**), Gründungskosten (mit der Wirtschaft, Phase 6), Abklingzeit nach Aufgabe einer Siedlung (Vorschlag 30 Tage), Mindest-Spielzeit neuer Konten vor einer Gründung (Vorschlag: nach dem Einstieg), Unterhalt für Erweiterungen (nicht für die Kernfläche).

## 6. Gründungsschwierigkeit statt geografischer Sperre
Keine Breitengrad-Grenze, kein Biom-Verbot. Stattdessen wird jeder Standort in eine **Schwierigkeitsklasse** eingeordnet, die Startbedingungen und laufende Kosten bestimmt:

| Faktor | Wirkung (Beispiele) |
|---|---|
| Temperatur | Heizenergie, Bauweise, Arbeitszeit im Freien |
| Wasser | Brunnen/Fluss/See/Küste vs. Eisschmelze/Entsalzung (Energie) |
| Nahrung | lokaler Ertrag vs. Importbedarf, Gewächshäuser |
| Rohstoffe | Bau-/Produktionsmaterial vor Ort vs. Einfuhr |
| Gelände | Baukosten, Straßenbau, Hangbebauung |
| Energie | Grundbedarf × Klima; verfügbare Quellen (Wind, Wasser, Solar, Brennstoff) |
| Transport | Erreichbarkeit (Küste, Flüsse, Nähe zu Siedlungen) |
| Technologie | benötigte Stufe (z. B. Polarausrüstung, Isolierbau, Entsalzung) |

Klassen **leicht · mittel · schwer · extrem** – **implementiert** (`Geography.difficulty`): Härte = gewichtete Summe aus Kälte/Hitze 22 %, Nahrung 18 %, Gelände 16 %, Wasser 14 %, Energie 12 %, Transport 10 %, Rohstoffe 8 %; Grenzen 0,30 / 0,45 / 0,62. Der Globus zeigt Klasse und konkrete Anforderungen; ein **extremer** Standort verlangt eine ausdrückliche Bestätigung. **Ehrlich:** Die Anforderungen sind heute nur Information – sie werden erst mit Wirtschaft/Technologie (Phase 6) spielwirksam; bis dahin startet jede Siedlung mit dem Grundpaket. „Extrem“ (Eisschild, Hochgebirge, Wüsteninneres) ist **nicht verboten**, sondern verlangt nachgewiesene Voraussetzungen (Technologie, Startkapital, Versorgungsvertrag mit einer bestehenden Siedlung). Neue Spieler sehen dort eine klare Erklärung, was fehlt. Wasserflächen bleiben ungeeignet, weil dort kein Land ist (schwimmende Siedlungen: [OFFEN], späte Technologie).

**Geringe Auflösung:** Die Planetendaten haben 49-km-Zellen; für die 1-km-Startfläche (Landanteil, Fluss, Küste, Hang) braucht es eine **deterministische Gelände-Verfeinerung** (§9).

## 7. Exploits und Gegenmaßnahmen

| Exploit | Gegenmaßnahmen |
|---|---|
| **Mehrfachgründungen** | **Eine aktive Gründung pro Konto (implementiert, getestet)**; zweite Gründung erst nach Aufgabe + Abklingzeit; Gründungskosten (Phase 6). |
| **Zweitaccounts** | Konto-Bindung (verifizierte Anmeldung, Firebase App Check), Ratenbegrenzung pro Gerät/Netz, Mindest-Spielzeit vor Gründung, Auffälligkeitsprüfung (vorsichtig bei Haushalten). Nicht vollständig verhinderbar → **unrentabel machen** (Kosten, Unterhalt für Erweiterungen, Erreichbarkeitsgarantie). |
| **Territoriale Blockade** | 20-km-Puffer nur um echte Territorien; Erweiterungen kosten Unterhalt und können unter §5.4 zurückfallen; die **Kernfläche** bleibt geschützt (keine Bestrafung für Pausen). |
| **Einkreisung** | **Erreichbarkeitsgarantie §5.2** (symmetrisch, kein Altersvorrecht). |
| **Strategisches Beanspruchen** (Rohstoffe, Pässe, Mündungen) | Rohstoffrechte getrennt vom Territorium (Konzessionen mit Nutzungspflicht); Korridor-/Wegerechte für Verkehrswege. |
| **Gründungs-Spam an beliebten Orten** | Abklingzeit, Kosten, Moderation, Meldefunktion. |
| **Zeit-/Client-Manipulation** | Alle Prüfungen serverseitig mit Serverzeit; der Client zeigt nur Vorschau. |
| **Race Conditions** | Server prüft in einer Transaktion über die betroffenen Index-Zellen. |

## 8. Auswirkungen auf Mehrspieler
- Gründung, Erweiterung, Grenzänderung = **Absichten an den Server**; der Server ist alleinige Instanz für Geometrieprüfungen (Transaktion über Index-Zellen).
- Territorien sind kleine Dokumente (Polygon + Index-Zellen + Version); der Globus lädt sie gekachelt nach Sichtbereich und Zoomstufe (Cluster bei planetarer Ansicht).

## 9. Gelände-Verfeinerung [GEPLANT]
Für 1-km-Flächen und lokale Karten wird aus den 49-km-Planetendaten deterministisch ein feineres Gelände abgeleitet (zusätzliche Rauschoktaven, Fluss-/Küstenverläufe als Linien). Damit Grenzfälle (Land/Wasser) auf allen Geräten gleich entschieden werden, entscheidet **der Server**; Clients berechnen nur die Darstellung. Alternative: höher aufgelöstes Backen (z. B. 4096 × 2048, 8 MB) – Abwägung in Phase 4.

## 10. Stand im Code (0.4.0, Paket 2.1) [IMPLEMENTIERT]
| Baustein | Datei |
|---|---|
| Geodäsie auf der Kugel: Tangentialrahmen, Versatz, Punkt–Bogen-, Polygon-Abstand, Überlappung, Fläche; Breite per `atan2` (exakt an den Polen trotz einfacher Genauigkeit) | `scripts/geography/geo.gd` |
| Räumlicher Index (Würfel-Kugel-Quadtree, Ebene 8 ≈ 24 km) | `scripts/geography/geo_index.gd` |
| Startterritorium 1 × 1 km, nächste Grenze, Überlappungsprüfung | `scripts/geography/territory_geometry.gd` |
| Standortprüfung ohne geografische Sperren, Landprüfung, 20 km Grenze-zu-Grenze, Schwierigkeitsklassen | `scripts/geography/geography.gd` |
| Speicherung (Schema 3): Territorium mit Polygon, Kern, Index-Zellen, Version, Historie, Status; Siedlungsfläche; Schwierigkeit; eine Gründung je Spieler; Migration der Phase-2-Regionsansprüche | `scripts/world/world_state.gd` |
| Globus: Territorien und Sperrzonen exakt im Shader (bis 32 nächste Territorien), Zoom bis ~120 km Höhe, Kamera bis 89° | `shaders/globe.gdshader`, `scripts/globe/*` |

**Bekannte Grenzen:** Landprüfung auf 49-km-Zellen (Küsten unscharf bis zur Gelände-Verfeinerung); das 1-km-Quadrat ist auf dem Globus nur wenige Pixel groß (Markierung über die Stecknadel); Shader zeigt höchstens 32 Territorien gleichzeitig (für Tausende → Kachelung, §3); Erweiterungen und Erreichbarkeitsprüfung sind beschrieben, nicht umgesetzt.

## 11. Entscheidungen des Projektinhabers (24.11.2026)
1. Startterritorium **genau 1 × 1 km**; bebaute Fläche kann kleiner sein; später dynamisch erweiterbar.
2. 20-km-Regel zwischen tatsächlichen Grenzen, **nur für Neugründungen**; Erweiterungen dürfen bis an Nachbargrenzen wachsen; **keine unberechtigten Überlappungen**.
3. **Keine vollständige Einkreisung**; jede Siedlung behält Erreichbarkeit/Anbindung; **kein automatisches Altersvorrecht** → §5.2.
4. **Kernfläche verfällt nie durch Abwesenheit**; keine Bestrafung für Pausen; Erweiterungen nur unter klaren Bedingungen; Kosten/Missbrauchsschutz gegen Blockadegründungen → §5.4.
