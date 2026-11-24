# Schritt D – Visuelle Qualitätsprüfung gegen die Penzilla-Originale

Geprüft wurden Kontaktbögen (Original neben allen Zuständen) und die Godot-Galerie. Die Bögen enthalten abgeleitete Penzilla-Grafik und liegen deshalb **nicht** im öffentlichen Repository (an den Projektinhaber direkt übergeben).

## 1. Iterationen und Befunde

| Runde | Befund | Korrektur |
|---|---|---|
| 1 | Schmutz wirkte **grünlich** (Farbton-Drehung macht Blau zu Türkis) | Farben werden im RGB-Raum zu warmem Braun gemischt, nie per Farbton gedreht |
| 1 | „Ausgebrannt/Zerstört“: Wände wurden grün (gleicher Fehler), zu eintönig | Verkohlung als RGB-Mischung zu warmem Dunkelgrau, Helligkeitsunterschiede der Flächen bleiben erhalten |
| 1 | Ruinen-Bewuchs = Tarnmuster-Rauschen | Bewuchs als konturierte Blattbüschel und Efeuranken |
| 1 | Bruchkante mit senkrechten Pixelspitzen | geglättete Kante mit wenigen V-Kerben; „schwer beschädigt“ als einseitiger Eckeinsturz |
| 1 | Dachlöcher dunkel auf dunkel unsichtbar | heller Rand loser Ziegel + zwei Sparren in Holzfarbe |
| 1 | Risse zu dünn, Abblättern auch auf Türen | dickerer Zickzack, helle Flächen (Türen/Zierleisten) ausgenommen |
| 2 | Abgestorbener Baum = Konfetti-Löcher | wenige große Löcher – **und**: Penzilla hat **BareTree1–3** → Original verwenden |
| 2 | „Zerstört“ bei Bank/Hydrant/Laterne wirkte wie **abgeschnittenes Bild** | breite Objekte: gezackter Bruch + liegendes Bruchstück; schlanke Objekte: **umgestürzt** |
| 2 | Bruchkante als **Kammmuster** | echte Dreieckswelle statt zeilenweisem Wechsel |
| 2 | Boden-Effekte trafen die **Seitenkante** der Kachel | Effekte nur auf der isometrischen Oberseite (Rautenmaske) |
| 2 | Frost = Rauschen | leichter Eiston + wenige größere Kristalle |
| 2 | Rost auf lackiertem Metall unsichtbar | Rost auf allen Metallflächen, verstärkt an Kanten |
| 3 | Innenraum „kaputt“ zu unauffällig | Pixel-Riss über das Möbel + abgeplatzte Ecke mit Kontur |

## 2. Ergebnis je Kategorie (nach Runde 3)

| Kategorie | Bewertung | Kommentar |
|---|---|---|
| Wohngebäude (12 Zustände) | **gut** | Penzilla-Look bleibt erhalten; „restauriert“ ist von „neu“ nur leicht zu unterscheiden |
| Großes öffentliches Gebäude (Rathaus) | **gut** | Ausgebrannt mit kräftigen Rußfahnen (eher kräftig – Stärke im Standard festlegen) |
| RPG-Laden | **brauchbar** | Markise wird wie Mauer behandelt (Risse statt Riss im Stoff) → Materialkarte nötig |
| Bäume | **gut mit Original** | Abgestorben = BareTree (Penzilla), verbrannt/Schnee daraus abgeleitet – überzeugend |
| Straße/Gehweg | **gut** | Schlaglöcher, Pfützen, Schlamm, Schnee, Risse im Stil |
| Stadtmöbel | **gut** | umgestürzt/zerbrochen lesbar; Rost dezent |
| Fahrzeuge | **gut** | verlassen/ausgebrannt/Wrack lesbar |
| Innenraum (Pixel Art) | **brauchbar** | abgenutzt/verschmutzt/verbrannt gut, Penzilla-State2 = „in Benutzung“ ideal |
| Eigene VFX | **gut** | Flamme, Rauch, Funken, Wetter passen zur Kontur-Optik |

## 3. Grenzen der automatischen Ableitung (ehrlich)
- Ableitungen sind **regelbasiert**, nicht handgemalt. Für Hauptgebäude, die oft im Bild sind, sollte ein Mensch die Ergebnisse abnehmen und ggf. nachbessern.
- Fehlende Penzilla-Vorlagen (Baugerüst, Baumstumpf, Trümmerhaufen als eigenständige Objekte, eingeschlagene Ladenschilder) können nicht sauber abgeleitet werden → eigene Zeichnung oder weiteres Penzilla-Paket (Kauf nur nach Zustimmung).
- Die Bewertung erfolgte am Bildschirm in Chromium; auf dem iPhone bei Spielzoom noch prüfen (sehr feine Risse können bei 0,25-facher Darstellung verschwinden).

## 4. Schritt G – Pilot und Serienprüfung

**Pilot** (`--pilot`, 20 Assets aus allen Kategorien: Wohnhaus, Rathaus, Schmiede, Feuerwache, Zelt, Laubbaum, Busch, Feldpflanze, Laterne, Bank, Hydrant, Kisten, Brunnen, Auto, Asphalt, Gehweg, Weg, Gras, Wasser, Innenraum-Möbel). Jede Runde: Kontaktbögen (volle Größe + echte Spielgröße auf iPhone 15 Pro Max Standard-/kleinster Zoom und älterem iPhone) + automatische Prüfung.

| Runde | Befund (Sicht oder automatisch) | Korrektur |
|---|---|---|
| G1 | Zierleisten (reines Weiß) als **Glas** erkannt, dunkelblaue Scheiben der Feuerwache nicht | Farbton-Artefakt bei Weiß ausgeschlossen, lange Streifen sind kein Glas, kompakte dunkelblaue Flächen an Gebäuden sind Glas |
| G1 | Brunnenwasser als **Stein** erkannt | große blaue Flächen an Objekten = Wasser |
| G1 | „Ausgebrannt“ veränderte versehentlich das Original (fehlende Kopie) → alle folgenden Zustände verkohlt | Kopie; seitdem jede Basis/Overlay aus unverändertem Original |
| G2 | Ruine mit gleichmäßigen Zacken (künstlich) | stufig abgebrochenes Mauerwerk mit Plateaus und einer höheren Ecke; Restdach entfernt |
| G2 | verbrannte Markise wurde durchsichtig (Hintergrund sichtbar) | verkohlter Stoff bleibt deckend |
| G2 | Schutt schwebte unter der Markise | Schutt und Bewuchs auf der isometrischen Bodenlinie |
| G2 | Bewuchs/Balken/umgestürzte Teile am **Bildrand abgeschnitten** | Erzeugung auf gepufferter Leinwand; Overlays mit negativen Versätzen |
| G3 | „Beschädigt“ bei Bank/Hydrant/Auto, „Verwittert“ bei kleinen Objekten, „Restauriert“, „Brandspuren“ am Zelt **in Spielgröße unsichtbar** | Fleckenanteile flächenbezogen statt über die Leinwand normiert; Mindest-Fleckgröße; größere Dellen + Lackabplatzer; Brandspuren vom Boden aus; Reparaturspuren deutlicher, Stoff-Flicken |
| G3 | lackiertes Holz (Bank) wurde grau statt Lack abplatzen zu lassen | natürliches vs. lackiertes Holz getrennt |
| G3 | Schmutz/Schlaglöcher auf dunklem Asphalt unsichtbar | heller Staub + Ölflecken; Schlaglöcher mit hellem Bruchrand und Splitt; Risse mit Lichtkante |
| G4 | abgestorbene/verbrannte Bäume: Löcher, schwebende Krone, alte Kontur als Ring | Krone bleibt geschlossen, wird grau-braun bzw. verkohlt, dunkle Lücken mit kahlen Ästen, Glut |
| G4 | Zelt „eingestürzt“ wie Gebäudeschutt; Wrack ≈ Ausgebrannt; verbrannte Kisten mit Durchsicht | flach liegender Stoff mit gebrochener Stange; Wrack mit eingedrücktem Dach und Schieflage; Holz verkohlt mit Asche und Glut, ohne Löcher |
| Serie | Bäume 3–8: „Trocken/Abgestorben“ unsichtbar (blühend rosa, herbstlich orange, sehr dunkel) | Krone farbunabhängig erkannt, kräftigere Trocken-Färbung |
| Serie | Schnee auf winzigem Unkraut verschwand | Mindestdicke, schwächere Glättung für kleine Objekte |

Pilot ohne Befund → Serie gestartet. Ergebnis der Serie siehe §5.

## 5. Ergebnis der Serie (letzter Lauf)
| Prüfung | Ergebnis |
|---|---|
| Umfang | 87 Einträge: 19 Gebäude, Zelt, 21 Stadtmöbel/Beleuchtung/Dekoration, Brunnen, 15 Bäume/Büsche, 2 Feldpflanzen, 3 Fahrzeuge, 2 Innenraum-Blätter, 23 Bodenkacheln in 6 Familien |
| Geprüfte Dateien | 625 Basen/Overlays (automatisch) |
| Geprüfte Zustände | 694 Darstellungen in echter Spielgröße, davon 544 „nicht nur leichte Abnutzung“ |
| Befunde | **0** (Leinwand/Anker, Bildrand, weiche Kantenpixel, Konturschutz, Rauschen, Sichtbarkeit, Unterscheidbarkeit) |
| knappster Zustand | „Restauriert (Spuren)“ bei Wohnhaus 6: 1,2 % der Fläche sichtbar verändert (gewollt dezent, über der Grenze von 1 %) |
| knappstes Zustandspaar | Haltestelle „Verwittert“ / „Bewachsen“: 1,4 % |
| bewusst kaum unterscheidbar | Neu / Gepflegt / Benutzt / Leicht verschmutzt (feine Shader-Stufen – im Spiel über Zeit sichtbar, nicht als Einzelbild) |
| Sichtprüfung | alle Kontaktbögen der Pilotgruppe in mehreren Runden; Serie stichprobenartig (Bäume, Gebäude, Fahrzeuge) |

Grenzen: regelbasierte Ableitung, keine Handzeichnung; die Lesbarkeit auf dem echten iPhone kann nur der Projektinhaber bestätigen.
