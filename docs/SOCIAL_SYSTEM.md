# SOCIAL_SYSTEM – Phase 5: Social Life

**Status: [IMPLEMENTIERT] in v0.1 / 0.11.0.**
- Code: `scripts/sim/social_core.gd`, aufgerufen im Tagesschritt `SettlementCore.day_step`.
- Konfiguration: `data/sim/living_world.json` → `social`.
- Tests: `[social life – phase 5]`.
- Analyse: `tools/sim/social_analysis.tscn`.
- Die Abnahme durch den Projektinhaber steht aus.

Umgesetzt sind die sieben Punkte der Phase 5 (Master-Prompt §11, Phase 5): Beziehungen, Familien, Freundschaften, Gespräche, soziale Gruppen, Erinnerungen und persönliche Ziele. Dazu kommen die Kinder nach §13.7.

## 1. Grundsätze
- **Ein Tagesschritt für alle Stufen:** Das soziale Leben läuft einmal je Siedlungstag, in jeder Simulationsstufe identisch.
  - S0/S1: Spieler vor Ort. S2/S3: Hintergrund und Nachholen nach Abwesenheit.
  - Zufall nur über Seeds (Siedlung, Tag, Personen). Dieselbe Welt ergibt dieselben Freundschaften (Test).
- **Serverfähig:** Der Zustand liegt im Siedlungsdatensatz (`record.social`, `npc.social`). Er gehört zum geteilten, gehashten Zustand der Weltautorität.
  - Gespräche des Spielers sind **Befehle an die Weltautorität** (`talk`). Nur Bewohner dürfen sie geben; Besuch anderer Siedlungen kommt mit Phase 8.
- **Keine externe KI:** Entscheidungen folgen Regeln, Gespräche Textbausteinen nach Kontext.
- **Fair bei Abwesenheit** (§13.1, §13.8):
  - Kontakte zu einem abwesenden Spieler verblassen nur sehr langsam, nie abrupt (Test: 70 Tage).
  - **Kinder kommen nie zu Schaden** (§13.7). Sie sind von der Sterblichkeit ausgenommen und brauchen keine Pflege durch den Spieler.

## 2. Beziehungen
```
record.social.edges["a|b"] = {a, b, kind, affinity -1..1, trust 0..1, familiarity 0..1,
                              colleague, family, since_day, last_day, meetings}
kind: acquaintance | friend | close_friend | partner | family | rival
```
- **Begegnungen:**
  - täglich im Haushalt,
  - an Arbeitstagen unter Kollegen (70 %),
  - in der Freizeit am Platz und im Park: kontaktfreudige Menschen und solche mit dem Ziel „Freundschaften“ treffen mehr Leute und suchen zuerst ihre Freunde,
  - bei Vereinstreffen.
- **Verträglichkeit:** Ähnliche Extraversion und Gewissenhaftigkeit, gemeinsame Interessen und Geselligkeit bringen Pluspunkte.
  - Die Sympathie strebt einem Gleichgewicht zu, das etwa 1,5 × der Verträglichkeit entspricht. So werden verträgliche Menschen Freunde, die meisten bleiben Bekannte.
  - Bei impulsiven Menschen gibt es seltene Streits, sie werden als Erinnerung gespeichert. Daraus können Rivalitäten entstehen.
- **Stufen:**
  - Freundschaft ab Sympathie 0,42 und Vertrautheit 0,35,
  - eng befreundet ab 0,62 und 0,65,
  - Rivalität ab −0,35.
  - Freundschaften sind „klebrig“: Sie enden erst unter 0,3.
- **Grenzen:** höchstens 30 Kanten je Person (die schwächsten Bekanntschaften fallen weg). Ungenutzte Bekanntschaften verblassen nach 3 Wochen.

## 3. Familien, Partnerschaften, Kinder
- **Partnerschaft:** Zwei erwachsene Singles mit enger Bindung (Sympathie ≥ 0,45, Vertrautheit ≥ 0,5), höchstens 15 Jahre Altersunterschied und persönlicher Anziehung. Die Anziehung ist ein Seed je Paar, nicht jede Freundschaft wird zur Liebe.
  - Täglich 1 %, mit dem Ziel „Partnerschaft“ 1,6 %.
  - **Zusammenziehen:** Wer in seinem Zuhause Platz hat, nimmt den Partner auf (Kinder ziehen mit). Ist beides voll, tauscht ein Mitbewohner ohne Familie die Wohnung.
- **Kinder:** Paare in gemeinsamer Wohnung, beide 20–44, höchstens 3 Kinder, mindestens 2 Jahre Abstand.
  - Kinder zählen nur halb gegen die Wohnungsgröße. Es müssen mindestens 5 Tage Nahrung im Vorrat sein.
  - Täglich 0,4 %, mit dem Ziel „Familie“ 2 %.
  - Es ist die Familienplanung des Paares; das Geschlecht wird nicht modelliert.
  - Das Kind bekommt den Familiennamen und eine Persönlichkeit zwischen der der Eltern mit eigenem Charakter. Es hat Familienkanten zu Eltern und Geschwistern.
- **Lebensphasen:** Säugling, Kleinkind, Kindergartenkind, Schulkind, Jugendliche:r, erwachsen. Bei 60 realen Tagen je Lebensjahr ist man nach etwa 3 realen Jahren erwachsen.
  - Kinder werden kleiner gezeichnet, haben keine Arbeit und keine Schichten.
  - Mit 18 kommen sie in den Arbeitskräftepool und wählen ein Ziel.
- **Abschied:** Stirbt ein Mensch, erinnern sich Freunde, Partner und Familie daran. Die Kanten werden Geschichte, Partner sind wieder frei.

## 4. Soziale Gruppen (Vereine)
- Es gibt 10 Interessen: Gärtnern, Musik, Sport, Lesen, Handwerk, Kochen, Spiele, Natur, Geschichte, Politik. Jede Person hat 1–3 davon (Seed).
- **Gründung (wöchentlich):** ab 4 Interessierten, durch eine gesellige, selbstbewusste Person oder jemanden mit dem Ziel „Verein“.
  - Höchstens 1 Verein je 8 Erwachsene.
  - Beispiele: Chor, Gartenfreunde, Werkstattrunde, Spieleabend, Bürgerrunde.
- **Beitritt:** Die Chance hängt von Geselligkeit, Freundschaften zu Mitgliedern und dem Ziel ab.
- **Treffen:** fester Wochentag und Uhrzeit (Seed), am Platz oder im Park.
  - Die Termine stehen bei jedem Mitglied (`npc.social.meetings`). Der Tagesablauf (`NpcBrain`) plant die Aktivität `group_meeting` dorthin. Man sieht die Gruppe also im Spiel zusammenkommen.

## 5. Erinnerungen
- Gespeichert werden nur wichtige Ereignisse (§10.4), höchstens 16 je Person:
  - Kennenlernen, Freundschaft, enge Freundschaft, Streit, Rivalität,
  - Partnerschaft, Geburt eines Kindes, Abschied,
  - Gründung von oder Eintritt in einen Verein,
  - erreichte Ziele, Erwachsenwerden,
  - Versprechen und gehaltene Versprechen, das erste Gespräch mit einem Spieler.
- Behalten wird nach Bedeutung, die mit der Zeit nachlässt. Familienereignisse und gehaltene Versprechen bleiben länger.
- Belangloses wird nicht gespeichert.

## 6. Persönliche Ziele
| Ziel | erfüllt, wenn |
|---|---|
| Neue Freundschaften schließen | 3 Freundschaften |
| Eine Partnerschaft finden | Partner:in |
| Eine Familie gründen | ein Kind |
| Im Beruf vorankommen | +0,1 Fertigkeit (wächst mit der Arbeitszeit) |
| Sich in einem Verein engagieren | Mitglied |
| Anderen helfen | 5 Vertretungen für Kolleg:innen |
| Ein ruhiges, gesundes Leben führen | 60 Tage gesund |

- Die Wahl richtet sich nach Persönlichkeit, Alter und Lage (z. B. „Familie“ nur mit Partner:in).
- Ziele verändern Verhalten: mehr Begegnungen, höhere Chancen auf Partnerschaft, Kind oder Verein.
- Ein erreichtes Ziel wird zur Erinnerung. Nach 2 Wochen folgt ein neues.

## 7. Gespräche (Spieler ↔ NPC)
- **Themen im Infofenster der Person:** Plaudern, Nach dem Befinden fragen, Über Interessen sprechen.
  - Ab einer gewissen Vertrautheit kommen hinzu: Nach Zielen fragen, Hilfe anbieten.
  - Für Vereinsmitglieder: Nach dem Verein fragen (Ort und Termin).
- **Antworten** kommen aus Bausteinen, abhängig von Stimmung, Gesundheit, Familie, Interessen, Ziel und jüngster Erinnerung.
- **Wirkung:** Sympathie, Vertrauen und Vertrautheit steigen. Es entsteht eine Beziehung zum Spieler (`player:<id>`), die bis zur Freundschaft wachsen kann.
- **Kein Grinding:** Ab dem 3. Gespräch am Tag wirkt jedes weitere weniger (Test: 10 Gespräche ≈ 4 × die Wirkung eines einzigen).
- **Versprechen:** „Hilfe anbieten“ ist ein Versprechen mit 3 Tagen Frist. Wer in der Frist wiederkommt, gewinnt Vertrauen und wird in Erinnerung behalten. Später: kleiner, fairer Vertrauensabzug, keine Strafe.
- **Infofenster:** Beziehung zu dir, Familie, Freunde, Vereine, aktuelles Ziel (ab etwas Vertrautheit) und eine Erinnerung (ab etwas Vertrauen).

## 8. Wirkung auf andere Systeme (§11: Beziehungen beeinflussen Entscheidungen)
- **Vertretungen:** Bei Ausfällen springen zuerst Leute aus dem Pool ein, die dem Team nahestehen. Das zählt für das Ziel „Anderen helfen“.
- **Stellenbesetzung:** Wer Freunde unter den Beschäftigten hat, erfährt zuerst von offenen Stellen.
- **Wohnen:** Paare ziehen zusammen, Kinder brauchen Platz. Das verändert die Belegung und damit den Zuzug.
- **Tagesablauf:** Treffen mit Freunden, Vereinsabende.
- Vorbereitet für spätere Phasen:
  - Vertrauen senkt Verhandlungskosten (Phase 6 Wirtschaft),
  - Freunde und Familie beeinflussen Umzüge (Phase 8),
  - Vereine bilden Interessenblöcke (Phase 9 Politik).

## 9. Messung (`tools/sim/social_analysis.tscn`, Gründungsbevölkerung, 3 Seeds, 720 Tage ≈ 12 Lebensjahre)
| Seed | Bevölkerung | Kinder | Freundschaften (eng) | Paare | Geburten | Vereine (Mitglieder) | Rivalitäten | erreichte Ziele |
|---|---|---|---|---|---|---|---|---|
| 0 | 33 | 0 | 35 (14) | 3 | 0 | Werkstattrunde 5, Spieleabend 8, Chor 6, Sportgruppe 5 | 2 | 20 |
| 1 | 36 | 2 | 46 (7) | 7 | 2 | Werkstattrunde 7, Spieleabend 6, Chor 7, Bürgerrunde 12 | 1 | 46 |
| 2 | 37 | 3 | 41 (11) | 7 | 3 | Werkstattrunde 6, Spieleabend 5, Gartenfreunde 8, Chor 9 | 2 | 24 |

- **Laufzeit:** etwa 11 ms je simuliertem Tag zusätzlich zu Phase 4 (ca. 12 ms), gemessen im Entwicklungscontainer. Auf dem iPhone nicht gemessen.
- **Begrenzung:** 30 Kanten je Person. Für sehr große Siedlungen sind Kanten als Unterkollektion je Person vorgesehen (Firestore, Phase 12).

## 10. Offen / später
- **Spieler ↔ Spieler:** Beziehungen, Chat und Moderation kommen mit dem Mehrspielerbetrieb (Phase 12).
- **Spielerkinder und Familienplanung:** Spielerinnen und Spieler haben noch keine eigenen Kinder. Das Grundgerüst (Familienkanten, Lebensphasen, §13.7) steht.
- **Schule, Kinderbetreuung, Feste, Märkte:** gesellschaftliche Ereignisse als Ortsereignisse.
- **Geschenke und Einladungen** zu gemeinsamen Aktivitäten (Phase 6: mit Waren).
- Tiefere Gesprächsbäume (weiterhin regelbasiert).
