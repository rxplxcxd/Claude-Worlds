# Schritt F – Produktionsstandard (Vorschlag, wartet auf Bestätigung)

Dieser Standard gilt für **alle** Zustandsvarianten. Er wurde aus den Beispielen (Schritt C) und der Prüfung (Schritte D/E) abgeleitet. **Schritt G (systematische Erstellung)** beginnt erst nach Bestätigung durch den Projektinhaber.

## 1. Stil (verbindlich)
1. **Penzilla-Look:** flache Farbflächen, harte Kanten, keine fotografischen Texturen, kein Rauschen.
2. **Konturen:** neue Formen (Risse, Löcher, Trümmer, Bewuchs, Bruchkanten) tragen die Penzilla-Konturfarbe **#330022**; Strichstärke ≈ 1,2 % der Spritehöhe (bei 540 px: 6–8 px Quelle).
3. **Farben** stammen aus der Palette des Assets (dunkler, ausgeblichen, zu warmem Braun **gemischt**) plus feste Zusatzpalette: Ruß #2B2429, Innenraum #33203A, Putz #E0D6C2, Rost #A85C2E/#783D21, Moos #6B9E45/#4D7833, Schnee #F2F7FF/#C2D6F2, Wasser #6B9ED1, Schlamm #6B4F38, Holz #8F613B. **Nie** Farbtöne rotieren.
4. **Perspektive:** isometrisch 2:1 erhalten; Ellipsen auf dem Boden 2:1 gestaucht; Boden-Effekte nur auf der Oberseite.
5. **Licht:** Lichtrichtung der Originale (oben links); Glanzpunkte oben links, Schatten unten rechts.
6. **Proportionen:** gleiche Leinwand und Anker wie das Original (Ausnahme „umgestürzt“: Leinwand wächst symmetrisch, Anker bleibt).

## 2. Technik je Veränderung
| Veränderung | Technik |
|---|---|
| Verschmutzung, Ausbleichen, Abdunkeln | Stufe 1 Shader (keine Datei) |
| Abblätternde Farbe, Risse, kaputte Fenster/Türen, Dachlöcher, Rost, Wasserflecken | Stufe 2 Overlay (zugeschnitten) |
| Einsturz, Ausbrennen, Ruine, Umstürzen, Wrack, Bruch | Stufe 3 Variante |
| Feuer, Rauch, Funken, Regen, Schnee, Staub, Blätter, Bau/Reparatur, Belohnung | eigene VFX (Atlas) |
| Vorhandene Penzilla-Alternativen (BareTree, Lampe an/aus, Interior-State2, Türen offen, Fahrzeuglicht) | Original verwenden |

## 3. Dateien
- Pfad: `assets/penzilla/states/<kategorie>/<asset>/<zustand>.png` (git-ignoriert, aus den ZIPs erzeugt).
- Zustandsnamen nach [STATE_MATRIX.md](STATE_MATRIX.md): `03_benutzt`, `07_beschaedigt` …; Overlays `overlay_<art>.png` mit `offset_src` im Manifest.
- PNG RGBA, transparenter Hintergrund, Maßstab 0,5 (wie Hauptimport), später Atlanten je Kategorie.
- Manifest `states.json`: Quelle, Kategorie, Stufe, Versatz, Leinwand.

## 4. Materialkarte je Asset (neu, für Schritt G nötig)
Die automatische Segmentierung (Kontur, Glas, Dach, Fassade) ist für einfache Häuser zuverlässig, verwechselt aber z. B. Markisen mit Mauerwerk. Für die Serie wird je Asset eine kleine **Materialkarte** erzeugt (automatisch, dann bei Bedarf von Hand korrigiert): `masonry | wood | metal | glass | fabric | roof | vegetation | water`. Effekte wählen danach (Stoff reißt, Mauer bekommt Risse, Metall rostet).

## 5. Qualitätsprüfung je Charge
1. Kontaktbogen Original + alle Zustände.
2. Prüfliste: Kontur intakt? Farben aus der Palette? Keine Rauschmuster? Oberseite/Seiten korrekt? Anker identisch? Lesbar bei Spielzoom (0,25-fach)?
3. Godot-Galerie (`?gallery=living`): Darstellung, Draw Calls, Speicher.
4. Abnahme durch den Projektinhaber bei Hauptgebäuden.

## 6. Werkzeuge (vor Schritt G zu verbessern)
- Segmentierung zwischenspeichern und auf kleinerer Auflösung rechnen (Rathaus heute ~290 s).
- Erzeugung in CI nur für tatsächlich verwendete Assets (heute ~30), nicht für alle 404 Gebäude.
- Deterministisch (Seed je Asset und Zustand) – gleiche Eingaben ergeben gleiche Dateien.
