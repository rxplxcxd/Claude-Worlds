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
