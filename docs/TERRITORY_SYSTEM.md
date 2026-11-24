# TERRITORY_SYSTEM – Flächen, Territorien, Gründungsabstand

**Status: [GEPLANT]** – Grundlage: [DESIGN_DIRECTIVES.md](DESIGN_DIRECTIVES.md) §1–4. In Phase 2 existiert nur eine Vorstufe (Territorium = ganze Region), die diese Anforderungen **nicht** erfüllt (siehe §10).

## 1. Vier Flächenbegriffe (technisch getrennt)

| Begriff | Bedeutung | Gespeichert als | Wer ändert es |
|---|---|---|---|
| **Siedlungsfläche** (`SettlementArea`) | Der lokal spielbare Bereich mit eigenem Kachelraster (Start ≤ 1 × 1 km = 100 × 100 Kacheln à 10 m). Hier stehen Gebäude, Straßen, Grundstücke. | Ursprung (lat/lon), Ausrichtung, Rastergröße, Chunks | Wächst nur durch Erweiterung (§5) |
| **Beanspruchtes Territorium** (`Territory`) | Rechtlich-politisches Gebiet einer Siedlung oder Einheit: Siedlungsfläche + Umland (Felder, Wald, Rohstoffe, Küstengewässer). **Grundlage der 20-km-Regel.** | Polygon(e) auf der Kugel, Version, Historie | Gründung, Erweiterung, Verträge, Zusammenschlüsse |
| **Bebaute Fläche** (abgeleitet) | Was tatsächlich genutzt ist: Grundstücke mit Gebäuden, Straßen, Infrastruktur. | **Nicht** autoritativ gespeichert – aus Gebäuden/Straßen berechnet, als Statistik zwischengespeichert | Entsteht durch Bauen/Abreißen |
| **Territoriale Erweiterung** (`ExpansionClaim`) | Antrag auf zusätzliches Gebiet mit Kosten, Fristen, Einspruch. | Antragsdatensatz mit Zielgeometrie und Zustand | Eigenes System (§5) |

Beziehung: *bebaute Fläche ⊆ Siedlungsfläche ⊆ Territorium*. Zum Start gilt **Territorium = Siedlungsfläche** (1 × 1 km, Vorschlag – [OFFEN]: etwas Umland, z. B. 2 × 2 km?).

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

## 5. Territoriale Erweiterung [GEPLANT, eigenes System – Entwurf]
Bewusst getrennt von der Gründungsregel. Entwurf zur späteren Ausarbeitung (Phase 4/7/9):
- **Antrag** auf angrenzende Fläche (zusammenhängend), Kosten (Vermessung, Verwaltung), Voraussetzungen (Einwohner, Nutzung der vorhandenen Fläche, Versorgung).
- **Einspruchsfrist** für Nachbarn innerhalb einer Distanz (z. B. 50 km); bei Konkurrenz zweier Anträge: Verhandlung, sonst Mittellinie oder Schiedsverfahren (Rat).
- **Nutzungspflicht:** beanspruchte, aber dauerhaft ungenutzte Erweiterungsflächen können nach Frist verfallen (nicht die Kernfläche).
- **Annäherung:** Nach der Gründung dürfen Territorien sich durch Erweiterung bis zur gemeinsamen Grenze annähern (Verträge regeln das) – der 20-km-Abstand gilt nur für Neugründungen. [OFFEN]: Mindestpuffer auch bei Erweiterung?
- **Verträge/Fusion/Abtretung** ändern Territorien direkt ([CONTRACT_SYSTEM.md](CONTRACT_SYSTEM.md), [POLITICAL_SYSTEM.md](POLITICAL_SYSTEM.md)).

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

Klassen (Vorschlag): **leicht · mittel · schwer · extrem**. „Extrem“ (Eisschild, Hochgebirge, Wüsteninneres) ist **nicht verboten**, sondern verlangt nachgewiesene Voraussetzungen (Technologie, Startkapital, Versorgungsvertrag mit einer bestehenden Siedlung). Neue Spieler sehen dort eine klare Erklärung, was fehlt. Wasserflächen bleiben ungeeignet, weil dort kein Land ist (schwimmende Siedlungen: [OFFEN], späte Technologie).

**Geringe Auflösung:** Die Planetendaten haben 49-km-Zellen; für die 1-km-Startfläche (Landanteil, Fluss, Küste, Hang) braucht es eine **deterministische Gelände-Verfeinerung** (§9).

## 7. Exploits und Gegenmaßnahmen

| Exploit | Gegenmaßnahmen (Vorschlag) |
|---|---|
| **Mehrfachgründungen** (ein Spieler besetzt viele Orte) | Eine aktive Gründung pro Konto; zweite Gründung erst ab Entwicklungsstufe X der ersten oder nach Aufgabe + Abklingzeit; Gründungskosten (Startkapital, Material). |
| **Zweitaccounts** | Konto-Bindung (verifizierte Anmeldung, Firebase App Check), Ratenbegrenzung pro Gerät/Netz, Mindest-Spielzeit vor Gründung, Auffälligkeitsprüfung (gleiche Geräte, synchrones Verhalten) – mit Vorsicht bei Haushalten. Vollständig verhindern lässt sich das nicht → **unrentabel machen** (Unterhalt, Verfall, s. u.). |
| **Territoriale Blockade** (Gründung nur, um Gebiet zu sperren) | **Probezeit**: Gründung ist 7 Tage „vorläufig“ und verfällt ohne Mindestaktivität (z. B. erste Bauaufträge); 20-km-Puffer nur um die Kernfläche; Unterhalt pro km². Langfristig inaktive Siedlungen werden „ruhend“: Kernfläche bleibt (keine Bestrafung für Pausen), Erweiterungsflächen verfallen. |
| **Einkreisung** (Gründungen exakt 20 km rund um eine Siedlung) | Erweiterungs-Vorrang für die ältere Siedlung im Zwischenraum (z. B. bis zur Mittellinie) oder „Wachstumsreserve“ proportional zur Einwohnerzahl; Einspruchsrecht in Erweiterungsverfahren. [OFFEN] |
| **Strategisches Beanspruchen** (Rohstoffe, Pässe, Flussmündungen) | Rohstoffrechte getrennt vom Territorium (Konzessionen mit Nutzungspflicht); Erschließungsfrist; Durchgangs-/Transitrechte für Verkehrswege per Gesetz/Vertrag. |
| **Gründungs-Spam an beliebten Orten** | Abklingzeit, Kosten, Moderationswerkzeuge, Meldefunktion. |
| **Zeit-/Client-Manipulation** | Alle Prüfungen serverseitig mit Serverzeit; der Client zeigt nur Vorschau. |
| **Race Conditions** (zwei Gründungen gleichzeitig nebeneinander) | Server prüft in einer Transaktion über die betroffenen Index-Zellen; zweite Gründung wird abgelehnt. |

## 8. Auswirkungen auf Mehrspieler
- Gründung, Erweiterung, Grenzänderung = **Absichten an den Server**; der Server ist alleinige Instanz für Geometrieprüfungen (Transaktion über Index-Zellen).
- Territorien sind kleine Dokumente (Polygon + Index-Zellen + Version); der Globus lädt sie gekachelt nach Sichtbereich und Zoomstufe (Cluster bei planetarer Ansicht).

## 9. Gelände-Verfeinerung [GEPLANT]
Für 1-km-Flächen und lokale Karten wird aus den 49-km-Planetendaten deterministisch ein feineres Gelände abgeleitet (zusätzliche Rauschoktaven, Fluss-/Küstenverläufe als Linien). Damit Grenzfälle (Land/Wasser) auf allen Geräten gleich entschieden werden, entscheidet **der Server**; Clients berechnen nur die Darstellung. Alternative: höher aufgelöstes Backen (z. B. 4096 × 2048, 8 MB) – Abwägung in Phase 4.

## 10. Stand im Code (0.3.0)
- Territorium = `region_ids` (ganze natürliche Region) → muss durch Polygon-Territorien ersetzt werden; natürliche Regionen behalten nur Statistik/Namen.
- Abstand 300 km zwischen Mittelpunkten, Sperren für ±62°, Eis, Hochgebirge → werden durch §3 und §6 ersetzt.
- Globus-Overlay zeichnet Gebiete pro Region (LUT) → für kleine Polygone wird eine Mesh-Ebene benötigt.
- Siedlungs-Datensatz hat bereits `position`, `region_id`, `territory_id` → Migration: `territory.geometry` = 1-km-Quadrat um `position`.
