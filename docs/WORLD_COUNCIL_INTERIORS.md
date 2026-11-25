# Concordium – verbindliche Innenarchitektur und Begehbarkeit

**Ziel:** Das Concordium wird **vollständig begehbar und funktional**: jedes Gebäude, jeder Innenraum, jeder Hof und jeder Platz. Die heutige Vorschau ist ein Entwicklungsprototyp. Sie wird später in die endgültige Spielarchitektur überführt: dasselbe Laufraster, dieselbe Tiefenkarte, dieselben Bauteil-IDs.

**Regel:** Jeder Innenraum folgt dem Äußeren seines Gebäudes. Kein generischer Rechteckraum. Übereinstimmen müssen:
- Grundriss und Form (rund, rechteckig, quadratisch mit Kuppel),
- Eingänge und Fenster aus dem Asset,
- Säulen, Treppen, Galerien und Innenhöfe.

Die Daten liegen in `data/landmarks/concordium_interiors.json` (Bezugsrahmen: Meter, +x Osten, +y Süden). Gebaut werden die Innenräume mit dem Innenraumsystem in Phase 7 (Restaurierung und Bau). Die Funktionen des Ratssaals folgen in Phase 10.

## 1. Großer Ratssaal (Rotunde) – politisches Herzstück
- **Form:** rund, Tambour außen r 24 m, Saal innen r 21,5 m (Ø 43 m). Boden auf dem Podium bei +6 m, Kuppel ab 32,8 m.
- **Zugang:** über Portikus und Vestibül durch die bronzene Doppeltür, Achse Südwest.
- **Plenarsaal:**
  - Halbrund aus konzentrischen Delegationsreihen um das **zentrale Rednerpult (Rostrum)**, das Präsidium gegenüber dem Eingang.
  - Abstimmungsanzeige unter der Kuppel, Flaggen- und Wappenring.
- **Kapazität ohne künstliche Grenze:**
  - Ein Block je anerkannter Nation (Delegierte, Stellvertreter, Berater). Die Reihen wachsen mit der Zahl der Nationen.
  - Galerien im oberen Tambour für Beobachter und Presse.
  - Übertragungssäle in den Palastflügeln für weitere Teilnehmer.
- **Nutzung:**
  - jährlich das Concilium Mundi und außerordentliche Sitzungen,
  - Debatten, Abstimmungen, Protokolle, Übertragungen.
- **Umgang** zwischen Tambour und Saal: Treppen zu den Galerien, Ausgänge zum Peristyl.

## 2. Historische Ausstellungshallen
- **Ort:** Westflügel, zweigeschossig, 20 × 98 m, Arkaden zum Hof.
- **Ausstattung:** Statuen, antike Wandgemälde, Mosaike, Inschriften, Dokumente, Darstellungen früherer Ereignisse, Ausstellungen der Nationen, Kulturveranstaltungen.
- **Erweiterbares Ausstellungssystem (verbindlich):**
  - Spieler und Nationen stiften Statuen, Gemälde, Ausstellungsstücke und Erinnerungsobjekte.
  - Jedes Stück hat Stifter, Datum, Beschreibung und einen Platz im Raster der Halle.
  - Es ist persistent im Landmarkenzustand gespeichert (`extensions`).
  - Den Ausgangsbestand bilden griechisch-römische Stücke.
  - Wechselausstellungen werden per Beschluss oder durch die Verwaltung des Geländes bestimmt.

## 3. Diplomatie, Archiv, Gästehaus
| Gebäude | Form | Räume |
|---|---|---|
| Nordflügel | 66 × 20 m, zweigeschossig | Räume für bilaterale Gespräche, vertrauliche Verhandlungsräume (beschränkter Zutritt), Saal für Vermittlung und Vertragsunterzeichnung, Konferenzräume, Sekretariat, Archiv der Beschlüsse |
| Eckpavillon | 17 × 17 m, Kuppelsaal | **Archiv der Welt**: Urkunden, Verträge, historische Dokumente |
| Nordpavillon | 17 × 17 m, Kuppelsaal | Gästehaus und Speisesaal der Delegationen, Küche (Lebensmittelversorgung) |
| Westpavillon | 17 × 17 m, Kuppel eingestürzt | nach der Restaurierung: **medizinische Versorgung und humanitäre Koordination** |
| Portikus und Vestibül | 26 × 20 m | Empfang, Akkreditierung, **Sicherheitskontrolle und Waffenverwahrung** |

## 4. Säulenhallen, Höfe, Wasser, Plätze (Gestaltungsidee bleibt erhalten)
| Bereich | Nutzung |
|---|---|
| Westliche Säulenhalle | offene Halle: Marktstände, Ausstellungen, Statuennischen der Nationen |
| Östliche Säulenhalle | Reden, Lesungen, Informationstafeln; bei Krisen Notunterkunft |
| Forum | internationale Märkte, Kultur, Ausstellungen, öffentliche Reden, Begegnungen, Gespräche zwischen Delegationen |
| Wasserterrassen mit Kanal und Kaskaden | ruhige Begegnungsorte: Bänke, Brunnen, Pflanzen, Statuen |
| Rundtempel (Tholos) | Gedenkort; nach der Restaurierung über einen Steg erreichbar |
| Theater | öffentliche Reden, Kultur, Feiern; später Bühnenhaus mit Garderoben |
| Gärten und Innenhöfe | Aufenthalt, Zuflucht (geschützte Bereiche) |
| Wasserschloss | Wasserverteilung, Trinkwasser |

Alle Plätze gehören zum neutralen Gelände.

## 5. Was heute tatsächlich begehbar ist
**Begehbar im Spiel** (regulär, mit Anreise): **nichts**. Die Anreise kommt in Phase 8.

**Entwicklungsvorschau** (Globus → „Ansehen (Vorschau)“), gemessen am Laufraster und durch Tests mit Erreichbarkeitsprüfung ab dem Tor belegt:
- **erreichbar:**
  - Tor mit Durchgang durch den Mittelbogen,
  - Forum,
  - Große Freitreppe und Antrittsstufen, Portikus zwischen den Säulen,
  - Podium mit Peristyl (Ringkolonnade),
  - die drei Wasserterrassen über die Treppenläufe,
  - Säulenhallen (Kolonnadenbereich, Antrittsstufe), Gärten und Wege,
  - Theatergarten und Theaterrand (über den Bogendurchgang in der Rückwand der östlichen Säulenhalle und die Heckentore).
- **nicht begehbar:**
  - alle Innenräume: Rotunde, Palastflügel, Pavillons, Vestibül hinter der Bronzetür, Tholos, Wasserschloss,
  - das Theaterinnere (Sitzstufen 0,68 m hoch),
  - Wasserflächen, Statuen, Pflanzen.

Bei der Prüfung behobene Mängel des Entwurfs:
- fehlende Treppen zu den oberen Wasserterrassen,
- zu hohe Stufen an Ringkolonnade (0,65 m) und Säulenhallen (0,88 m),
- ein eingeschlossener Theatergarten.

Der Test „reachable from the gate“ prüft das bei jedem Build.

**Konzept** (verbindlich festgelegt, nicht gebaut): alle Innenräume aus §1–3, das Ausstellungssystem, die humanitären Einrichtungen.

## 6. Überführung in die endgültige Spielarchitektur
1. **Außengelände:** Die Vorschau-Szene wird zum regulären Ort, erreichbar über Reisen (Phase 8).
   - Mehrere Spieler und NPCs nutzen dieselbe Verdeckung. Dafür kommt die Tiefenkarte aller Figuren in einen Viewport.
   - Dazu Wegfindung auf dem Laufraster.
2. **Innenräume:** je Gebäude ein isometrischer Innenraum im Stil des Concordiums (Marmor, Säulen, Mosaike), gebaut mit dem Innenraumsystem.
   - Grundriss aus `concordium_interiors.json`.
   - Die Eingänge liegen an den Türen bzw. Bögen des Assets.
3. **Zustände:** Je Komponente sind Zustand und Zugang (`open`/`closed`/`event`) bereits im Landmarkenzustand gespeichert.
   - Restaurierung öffnet Räume; heute sind Rotunde und Paläste in Stufe 1 geschlossen.
   - Das Asset wird je Stufe neu erzeugt.
