# Concordium – verbindliche Innenarchitektur und Begehbarkeit

**Ziel:** Das Concordium wird **vollständig begehbar und funktional**: jedes Gebäude, jeder Innenraum, jeder Hof und jeder Platz. Die heutige Vorschau ist ein Entwicklungsprototyp. Sie wird später in die endgültige Spielarchitektur überführt: dasselbe Laufraster, dieselbe Tiefenkarte, dieselben Bauteil-IDs.

**Regel:** Jeder Innenraum folgt dem Äußeren seines Gebäudes. Kein generischer Rechteckraum. Übereinstimmen müssen:
- Grundriss und Form (rund, rechteckig, quadratisch mit Kuppel),
- Eingänge und Fenster aus dem Asset,
- Säulen, Treppen, Galerien und Innenhöfe.

Die Daten liegen in `data/landmarks/concordium_interiors.json` (Bezugsrahmen: Meter, +x Osten, +y Süden). Gebaut werden die Innenräume mit dem Innenraumsystem in Phase 7 (Restaurierung und Bau). Die Funktionen des Ratssaals folgen in Phase 10.

## 1. Großer Ratssaal (Rotunde) – politisches Herzstück
- **Vorbild:** die Bouleuterien von Aphrodisias und Milet, nur als Anregung, kein Bauplan.
  - Aphrodisias: monumentale Größe, Kapazität, Ränge, repräsentativer Charakter.
  - Milet: halbrunde Sitzordnung, Zugänge, Umgänge, klare Gliederung.
- **Form:** Saal im Tambour der Rotunde, im Innenraum 120 × 62 Kacheln (≈ 72 × 37 m).
- **Zugang:** über Portikus und Vestibül, dann durch das **Bronzetor** in der Portalwand. Seitlich liegen der westliche und der östliche Umgang mit Doppeltüren.
- **Plenarsaal:**
  - **1182 Delegiertenplätze** in 16 konzentrischen Reihen um die Orchestra.
  - Jeder Platz ist zum **Rostrum** gedreht. Dahinter steht das **Präsidium** vor der Nordwand mit Säulen, Statuen, Wandgemälden, Reliefs und Flaggen.
  - 3 Radialgänge und ein Ringumgang (Diazoma) auf halber Höhe.
- **Sitzplatz-Grundlage für Phase 10** (nicht umgesetzt):
  - Jeder Platz hat eine eindeutige ID `D<Reihe>-<Sektor>-<Nr.>`, Reihe, Sektor, Position und Zugangspunkt.
  - Sitzordnung nach Nationen, Abstimmungen und Protokolle folgen mit dem Ratssystem.
- **Galerie:** echte begehbare Ebene, 4 Kacheln über dem Saalboden, mit Boden, Brüstung, Kante und Kollision.
  - West- und Ostgalerie entlang der Seitenwände, Südgalerie in zwei Hälften beiderseits des Portals.
  - Treppen führen vom Mittelgang und von den Umgängen hinauf. Die Bänke sind für Beobachter und Presse.
- **Kapazität ohne künstliche Grenze:** Die Reihen lassen sich verlängern; Übertragungssäle liegen in den Palastflügeln (Konzept).
- **Nutzung:** jährlich das Concilium Mundi, außerordentliche Sitzungen, Debatten, Abstimmungen, Protokolle, Übertragungen.
- **Technik:** eigener Innenraum mit Ladeansicht. Aufbau in etwa 130 ms.
  - Die Plätze haben kein eigenes Interaktionsobjekt, sondern werden über das Sitzplatzregister angeboten. So bleibt die Szene auch mobil schlank.

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

**Innenräume in der Entwicklungsvorschau (seit 0.9.0, eingerichtet nach dem Innenraum-Standard):**

| Innenraum | Zugang auf dem Gelände | Übergang |
|---|---|---|
| Großer Ratssaal (Vestibül, Umgänge, Galerie) | Bronzetür im Portikus | Tor öffnet sich, Ladeansicht |
| Ausstellungshalle | Arkaden des Westflügels | offene Arkade |
| Diplomatieflügel | Arkaden des Nordflügels | offene Arkade |
| Archiv der Welt | Zugang im Innenhof | Doppeltür |
| Zufluchtsort | Westpavillon | Doppeltür |
| Gästehaus | Nordpavillon | Doppeltür |
| Rundtempel (Tholos) | Steg durch das Becken (seit 0.10.0) | offene Säulenstellung |
| Wasserschloss | Bogentür neben dem Nordpavillon (seit 0.10.0) | Tür |

- Innen gibt es Laufen, Kollisionen, Türen mit Öffnungsanimation, Interaktionen und den Ausgang an der Türmatte. Beim Verlassen steht man wieder vor der Tür.
- NPCs nutzen dieselben Türen: Die Tür öffnet für jede Figur in der Nähe, die Kollision folgt dem Öffnungsgrad.

**Außengelände in der Entwicklungsvorschau** (Globus → „Ansehen (Vorschau)“), gemessen am Laufraster und durch Tests mit Erreichbarkeitsprüfung ab dem Tor belegt:
- **erreichbar:**
  - Tor mit Durchgang durch den Mittelbogen,
  - Forum,
  - Große Freitreppe und Antrittsstufen, Portikus zwischen den Säulen,
  - Podium mit Peristyl (Ringkolonnade),
  - die drei Wasserterrassen über die Treppenläufe,
  - Säulenhallen, Gärten und Wege,
  - Theatergarten, Theaterrand und **über den Gang bis zur Orchestra**,
  - **Steg zum Rundtempel**, **Wasserschloss**,
  - alle 8 Gebäudetüren (Test).
- **nicht begehbar:**
  - Wasserflächen, Statuen, Pflanzen,
  - die Sitzstufen des Theaters außerhalb des Gangs,
  - die Dachflächen.

Das Laufraster misst mit zwei Strahlhöhen (8,9 m und 3 m), damit auch niedrige Durchgänge in Mauern erkannt werden.

Bei der Prüfung behobene Mängel des Entwurfs:
- fehlende Treppen zu den oberen Wasserterrassen,
- zu hohe Stufen an Ringkolonnade (0,65 m) und Säulenhallen (0,88 m),
- ein eingeschlossener Theatergarten,
- das Wasserschloss überschnitt den Nordpavillon (versetzt).

Der Test „reachable from the gate“ prüft das bei jedem Build.

**Konzept**, verbindlich festgelegt, aber noch nicht spielmechanisch umgesetzt:
- das erweiterbare Ausstellungssystem (Stiftungen der Spieler),
- die Funktionen der Räume: Abstimmungen (Phase 10), Versorgung und Betrieb (Phase 6/11),

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
