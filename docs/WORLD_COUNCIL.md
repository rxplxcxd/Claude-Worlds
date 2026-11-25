# WORLD COUNCIL – Master-Erweiterung „Der internationale Weltratssitz“

Verbindliche Erweiterung des WORLDS-Master-Prompts (erteilt am 25.11.2026). Der ursprüngliche Master-Prompt bleibt **unverändert** und maßgeblich, auch seine Phasenreihenfolge. Dieses Dokument verankert die neuen Anforderungen und verbindet sie mit den bestehenden Systemen.
Korrektur des Projektinhabers: Der Kontinent heißt **Kalistia** (im Auftragstext versehentlich „Area“).

Zugehörige Dokumente:
- [WORLD_COUNCIL_ART_DIRECTION.md](WORLD_COUNCIL_ART_DIRECTION.md): Architektur, Gestaltung, Asset-Erstellung
- [WORLD_COUNCIL_ROADMAP.md](WORLD_COUNCIL_ROADMAP.md): Phasenzuordnung und Abhängigkeiten
- [WORLD_COUNCIL_ARCHITECTURE.md](WORLD_COUNCIL_ARCHITECTURE.md): Daten, Persistenz, Serverautorität, Weltzeit

## 1. Verbindliche Anforderungen (Zusammenfassung des Auftrags)
1. Ein dauerhaft existierender, monumentaler Weltratssitz auf **Kalistia** als politisches, diplomatisches und gesellschaftliches Zentrum der Welt. Kein gewöhnliches Regierungsgebäude, sondern ein antik anmutender Komplex: Parlament, Forum, Amphitheater, Tempel- und Palastanlage, Gärten, Wasser.
2. **Historischer Ort:** Er existiert bereits, ist verwittert, teils beschädigt und überwuchert, die Erbauer sind unbekannt. Restaurierung und Ausbau durch die Weltgemeinschaft, persistent (Stufen 1–4, nicht zwingend linear).
3. **Standort:** sinnvoll und vergleichsweise zentral, gut erreichbar, gemäßigtes Klima ohne Extreme, schöne Landschaft, Platz für den Komplex, Erweiterungen und künftige Infrastruktur (Flughafen, Bahnhöfe, Straßen und Autobahn, Bus/Shuttle, Hafen, Hotels). Nichts davon entsteht automatisch.
4. **Globus:** Der Ort ist jetzt schon sichtbar, mit fester Position und eindeutiger Kennung. Die Markierung bewegt sich mit dem Globus, liegt exakt auf der Oberfläche und schwebt nicht.
5. **Architektur und Asset:**
   - Eigenes, sehr detailreiches Außen-Asset im **Penzilla-Stil**: Konturen, Palette, Licht, Perspektive.
   - Heller, leicht verwitterter Marmor, Sandstein, gezieltes Gold und Bronze.
   - Säulen, Bögen, Treppen, Reliefs, Statuen, Kuppeln, Wasseranlagen, Gärten.
   - In mehreren Iterationen verbessert, in Godot verwendbar: Tiefensortierung, Kollisionen, Wege, Eingänge, Detailstufen, Web und iOS.
6. **Funktionsbereiche** (architektonisch eingeplant): Versammlungshalle ohne künstliche Kapazitätsgrenze, diplomatische Räume, öffentliche Veranstaltungsflächen, Garten- und Außenanlagen.
7. **Weltrat:** jährliche Weltversammlung am **24. Juni** in der Weltzeit des Servers, unabhängig von Gerätezeit und Online-Status einzelner Spieler.
   - Vertretung mit Delegierten, Stellvertretern, Beratern und Vollmachten.
   - Tagesordnung, Anträge, Koalitionen, Abstimmungen.
   - Beschlüsse mit echten Auswirkungen, keine vorgegebenen Ergebnisse.
8. **Anreise als echte Reise:** Auto, Bahn, Schiff und Flug für alle Spieler.
   - Kosten nach Verkehrsmittel, Entfernung, Klasse, Kraftstoff, Maut, Gebühren und Unterkunft.
   - Nationen regeln die Reisekosten ihrer Delegierten selbst, passend zum Wirtschafts- und Steuersystem.
9. **Persistenz und Multiplayer von Anfang an:**
   - Gespeichert werden Position, Gebäudeteile, Zustände, Erweiterungen, Beschlüsse und Geschichte.
   - Der Server ist die verbindliche Quelle, die Welt läuft weiter.
   - Skalierbar über Detail- und Simulationsebenen, ohne geräteabhängige Kürzung der Bevölkerung.
10. **Nutzung außerhalb der Versammlung:** Märkte, Kultur, Ausstellungen, Konferenzen, Feiern und Gedenktage. Die Weltgemeinschaft entscheidet darüber.
11. **Qualitätsprüfung** im echten Spiel: Zoomstufen, Tag und Nacht, Wetter, Web, Mobilgerät, Kollisionen, Wege, Sortierung, Wasser, Leistung.

## 2. Verhältnis zum Master-Prompt
- Master-Prompt §9.3–9.6 (Weltrat einmal pro Spieljahr, Delegierte, Community-Ereignis, Ausfallsicherheit) und §16 (Vision) bleiben maßgeblich. Diese Erweiterung legt **Ort, Gestalt, Datum und Infrastruktur** fest.
- „Einmal pro Spieljahr“ wird konkret: **24. Juni der Weltzeit (UTC)**. Das Weltjahr ist das Kalenderjahr der persistenten Echtzeitwelt (GameClock läuft in Echtzeit). Die beschleunigte Lebenszeit der NPCs (60 Tage = 1 Lebensjahr, LIVING_WORLD.md) ist ein reines Alterungsmaß und nicht der politische Kalender.
- **Leerer-Planet-Regel** (genesis.json): Der Weltratssitz ist **keine Siedlung**, sondern eine unbewohnte historische **Landmarke** (`rules.landmarks_are_not_settlements`). Der Planet startet weiterhin ohne Siedlungen.
- Gründungsregeln (TERRITORY_SYSTEM.md) gelten weiter. Zusätzlich gibt es ein **Schutzgebiet** von 18 km um den Sitz, in dem keine Siedlung gegründet werden kann. Dort ist Platz für Erweiterungen und die künftige Infrastruktur. Spätere Gebietserweiterungen (Phase 7) müssen dieses Schutzgebiet ebenfalls respektieren.

## 3. Standortentscheidung (umgesetzt)
**28,28° N / 137,36° E** – Zaneris-Ebene (`reg_139`), Kontinent Kalistia (`cnt_05`).

| Merkmal | Wert |
|---|---|
| Gelände | Ebene, 162 m ü. M., Hangneigung gering (Platz für Komplex, Flughafen, Bahnhof) |
| Klima | Ø 16 °C, Niederschlag 0,56 (mäßig), Klimazone „gemäßigt“ (warm-gemäßigt) |
| Wasser | Meeresbucht ca. 30 km im Südwesten (Hafen möglich); keine Flüsse im Planetenraster in der Nähe → Wasserversorgung des Komplexes historisch über ein **Aquädukt** aus den Hügeln |
| Landschaft | sanfte Hügel nach Nordosten (bis +218 m, Aussicht, Quellgebiet), offene Ebene nach Süden/Westen |
| Erreichbarkeit | Land in 150 km Umkreis zu ~70 % (Straßen-/Bahnnetz möglich), Küste für Fähren/Hafen, ebene Flächen für eine Start- und Landebahn |

**Begründung:**
- Kalistia ist zu großen Teilen Eis und Tundra. Der flächengewichtete Mittelpunkt (52° N) liegt im Eisgebiet und eignet sich nicht.
- Ein angenehmes, gemäßigtes Klima gibt es nur im südlichen Gürtel (Zaneris-Ebene, Briheim-Ebene, Briislis-Küste).
- Die Analyse (`tools/world/council_site.gd`) bewertete alle Landzellen des Kontinents nach Klima, Wasser, Ebenheit, Platz, Höhe, Gelände und Küstenzugang. Die Zaneris-Ebene lag durchgehend vorn.
- Im Feinraster (0,1°) wurde ein Punkt etwa 30 km landeinwärts gewählt: geschützt vor Küstenwetter, mit Raum für einen Hafen an der Bucht und einem Hügelrücken als Wasserquelle und Aussichtspunkt.
- „Zentral“ heißt hier: zentral im bewohnbaren Teil Kalistias und mit Seezugang zu den anderen Kontinenten.
- Nicht gewählt: Briislis-Küste (zerklüfteter, schmaler) und Briheim-Ebene (8 °C, kühler).

## 4. Was jetzt umgesetzt ist (v0.1 → technisch 0.7.0)
- Ort in der Weltdefinition: `data/world/landmarks.json` (feste Koordinaten, Kontinent, Region, Schutzradius, Stufen, Komponenten mit Ausgangszustand, Versammlungstermin). `genesis.json` verweist darauf.
- Persistenter Zustand: `WorldState.landmark_state(id)` (Stufe, Komponenten mit Zustand/Zugang/Restaurierung, Erweiterungen, Beschlüsse, Geschichte), gespeichert im Weltstand. Clients lesen nur, Änderungen nur über die Weltautorität (siehe ARCHITECTURE).
- Gründungssperre im Schutzgebiet (`Geography.rate_site`, auch für „Vorschlag“).
- Globus: Markierung „WORLD COUNCIL – Internationaler Weltratssitz“. Ein Ring liegt auf der Kugeloberfläche, der kleine Tempel steht auf dem exakten Punkt. Antippen zeigt Beschreibung, Zustand, Klima und den nächsten Versammlungstermin.
- Architekturkonzept und eigenes Außen-Asset (eigener Renderer, Penzilla-Regeln, mehrere Iterationen): siehe ART_DIRECTION.
- Einbindung in Godot als besuchbare Entwicklungsvorschau: siehe ART_DIRECTION §6 und ROADMAP.

## 5. Offene Entscheidungen (Projektinhaber)
1. **Name** der Anlage: Arbeitstitel „Concordium von Kalistia“ – bitte bestätigen oder ändern.
2. **Größe:** Kerngelände 168 × 168 m. Die Rotunde mit Kuppel ist ~60 m hoch, also etwa 33 Personenhöhen. Größer geht, kostet aber Speicher auf dem iPhone (siehe ART_DIRECTION §5).
3. **Schutzradius** 18 km: genug für Flughafen (3–4 km Bahn), Bahnhof, Hotels, Straßen. Bei Bedarf anpassbar.
4. **Abstimmungsregeln** (eine Stimme je Nation oder gewichtet?) und Delegiertenzahl: gehören in Phase 9/10 und werden dort mit dir entschieden.
