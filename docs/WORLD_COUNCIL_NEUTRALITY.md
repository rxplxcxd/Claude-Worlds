# Concordium – Neutralität, Grundstück, Sicherheit, humanitärer Schutz

Das Concordium ist ein international neutraler Ort. Es gehört keiner Nation, keinem Staat, keinem Bündnis und keiner politischen Fraktion. Der Status gilt **ganzjährig** und auch im Krieg. Hier begegnet sich die Weltgesellschaft, hier wird verhandelt, hier kann man Schutz suchen.

Die Neutralität ist ein **verbindliches Weltgesetz**, aber keine magische Wand. Ein bewusster Bruch bleibt grundsätzlich möglich. Er ist dann ein außergewöhnlicher historischer Tabubruch mit massiven Folgen und kein gewöhnlicher Kampf.

## 1. Grundstücksgrenzen (implementiert)
- **Neutrale Zone = Grundstückspolygon** `property.polygon_m` in `data/world/landmarks.json`.
  - Bezugsrahmen: Meter um `position`, +x Osten, +y Süden.
  - Derzeit 172 × 172 m, also die Anlage einschließlich Umfassung.
- Es gibt **keinen Schutzradius**. Außerhalb des Polygons gelten die normalen Regeln. Das betrifft auch Straßen, angrenzende Landschaft, Hotels, Bahnhöfe und Flughäfen.
- **Prüfung:**
  - Ob ein Punkt in der Zone liegt: `Landmarks.zone_at(lat, lon)` bzw. `inside_property(site_m)`.
  - Gründungsregel: `property_overlapping(start_ring)`. Ein Siedlungsgebiet darf das Grundstück nicht überdecken, direkt daneben ist eine Gründung erlaubt.
- **Änderung** nur durch die Weltautorität (`WorldState.update_landmark_property`). Bedingungen:
  - Herausgeber ist der Server (`srv_world_authority`),
  - es gibt einen gültigen Beschluss (`resolution_id`),
  - das neue Gelände enthält das alte vollständig; der neutrale Kern schrumpft nie.
  - Die Version der Grenze steigt, die Änderung wird in der Geschichte protokolliert.
- **Persistenz:** Die gültige Grenze liegt im Landmarkenzustand (Server). Die Definition liefert nur die Ausgangsgrenze.
- **Serverseitig verbindlich:** Jede spätere Aktion mit Gewalt, Besitz oder Bau wird vom Server gegen diese Grenze geprüft. Der Client meldet höchstens Absichten.

## 2. Grundprinzipien innerhalb der Grenze
Verboten sind:
- reguläre Kampfhandlungen und gewöhnliche PvP-Angriffe,
- gewaltsame Übergriffe, Tötungen und gezielte Verletzungen,
- militärische Besetzung, Belagerung, gewaltsame Blockade von Zugängen,
- einseitige Übernahme durch eine Nation,
- Benachteiligung wegen Herkunft, Staatsangehörigkeit, Bündnissen oder politischen Beziehungen.

Verfeindete Nationen und Spieler müssen dort miteinander verkehren können. Datenfassung: `neutrality.principles`.

## 3. Drei Stufen

| Stufe | Was passiert | Beispiele | Wer entscheidet |
|---|---|---|---|
| **1 – verhindert** (Normalzustand) | Die Aktion wird gar nicht ausgeführt, es entsteht kein Schaden. Der Angreifer erhält einen Hinweis. Waffen und gefährliche Gegenstände können an den Eingängen (Vestibül, Tor) kontrolliert und verwahrt werden. | Angriff auf Spieler, Verletzen, Beschädigen von Gebäuden, Versuch einer Besetzung | Server, sofort |
| **2 – Sicherheitsverletzung** | Ein bewusster Regelverstoß wird erkannt und als Vorfall gespeichert (`incidents`). Darauf folgt eine Intervention: Wachen bzw. Sicherheitskräfte greifen ein, beschlagnahmen Waffen, verweisen des Geländes, erteilen Zutrittssperren, leiten an die Nation des Täters weiter. | Waffe trotz Kontrolle mitgeführt, wiederholte Angriffsversuche, Eingänge blockiert, Belästigung | Server; Personal und Regeln des Concordiums (Phase 10/11) |
| **3 – politisches Krisenereignis** | Ein **außergewöhnliches, spielmechanisch vorgesehenes** Ereignis: ein Angriff auf das Concordium. Möglich nur unter **allen** Bedingungen aus §5. | erklärter Angriff eines Staates im Krieg | Server prüft die Bedingungen; die Folgen entstehen aus Weltpolitik und Simulation |

Umsetzung heute: `Landmarks.classify_act(kind, ctx)` liefert `normal | prevented | violation | crisis`, Regeln in `neutrality.acts`, Tests in `tests/run_tests.gd`. Ein Kampfsystem gibt es noch nicht (Phase 11). Die Klassifikation ist das verbindliche Regelwerk, an das sich dieses System später anschließt.

## 4. Humanitärer Schutz
- **Zugang bedingungslos:** `neutrality.humanitarian.access = unconditional`. Er hängt nie von politischer Zugehörigkeit ab.
- **Schutzsuchende:** Zivilisten, Familien, Kinder, Verletzte, Verfolgte, Menschen ohne politische oder militärische Macht, Geflüchtete.
- **Geplante Einrichtungen** (Orte in `data/landmarks/concordium_interiors.json → humanitarian`):

| Einrichtung | Ort |
|---|---|
| Medizinische Versorgung | Westpavillon (nach Restaurierung der Kuppel) |
| Notunterkünfte | Östliche Säulenhalle, Westflügel |
| Gemeinschaftsräume | Westflügel |
| Lebensmittelversorgung | Nordpavillon (Gästehaus, Küche) |
| Trinkwasser | Aquädukt und Wasserschloss |
| Geschützte Aufenthaltsbereiche | Forum, Gärten, Peristyl |

- Bau und Betrieb kommen mit Phase 7 (Bau), 6 (Versorgung, Wirtschaft) und 11 (Krisen, Flucht).

## 5. Der Ausnahmefall: Angriff auf das Concordium (Stufe 3)
Damit ein Angriff **nicht alltäglich** und **kein Exploit** wird, gelten alle diese Bedingungen gleichzeitig:
1. Das Konfliktsystem ist freigegeben: Phase 11, `neutrality.crisis_enabled` bzw. Weltregel. Heute ist es **aus**.
2. Der Angriff ist ein **staatlicher Akt**: von der Regierung einer anerkannten Nation nach deren Verfassung erklärt (Phase 9). Einzelne Spieler, Gruppen oder Gilden können ihn nie auslösen. Ein Versuch gilt als Stufe 2.
3. Er ist **öffentlich und angekündigt**: Erklärung, Frist, Weltöffentlichkeit. Keine Überraschungsmechanik aus der Zonengrenze heraus.
4. Er ist **serverseitig validiert**: Truppen und Mittel müssen tatsächlich und auf normalem Weg angereist sein, ohne Teleport. Der Server führt den Ablauf.
5. Die **Kosten sind hoch** und stehen vorher fest.

Mögliche Folgen, die aus Politik und Simulation entstehen und nicht vorgeschrieben sind:
- internationale Empörung, Abbruch diplomatischer Beziehungen, Sanktionen, politische Isolation,
- Ermittlungen und Gerichtsverfahren,
- ein außerordentliches Concilium Mundi (Notfallversammlung) und Reaktionen anderer Nationen,
- Schäden an Gebäuden und Infrastruktur, die persistent bleiben,
- ein dauerhafter Eintrag in der Geschichte des Ortes und langfristige Veränderungen der internationalen Ordnung.

Ein solcher Vorfall wird nie wie ein gewöhnlicher PvP-Kampf behandelt.

## 6. Schutz vor Ausnutzung
- **Kein taktischer Vorteil aus der Zone:**
  - Wer in die Zone flieht, um sich einem laufenden Kampf zu entziehen, wird nicht belohnt; der Kampfzustand bleibt, Details in Phase 11.
  - Aus der Zone heraus kann niemand angreifen: Angriffe über die Grenze hinweg werden wie Angriffe innerhalb behandelt.
- **Provokation lohnt sich nicht:** Wer andere zu einem Verstoß reizt, um diese bestrafen zu lassen, wird selbst als Belästigung (Stufe 2) erfasst. Stufe-1-Versuche schaden niemandem und lösen allein keine Strafe gegen das Opfer aus.
- **Eingänge:** Blockieren ist Stufe 2.
  - Figuren lassen sich nicht wegstoßen, aber das Personal kann räumen.
  - Mehrere Eingänge (Tor, Gärten, Theater, Terrassen) verhindern Sackgassen.
- **Technische Umgehungen:**
  - Teleport, Client-Manipulation und Positionsfälschung wirken nicht, weil der Server Position und Aktion prüft.
  - Sicherheitsmechanismen laufen nur auf dem Server.

## 7. Phasenzuordnung
| Phase | Neutralität |
|---|---|
| jetzt | Grenze, Zonenprüfung, Gründungsregel, Grenzänderung nur durch Weltautorität, Regelwerk der drei Stufen, Daten zu humanitären Orten |
| 6/7 | Personal, Versorgung, Bau der humanitären Einrichtungen, Restaurierung |
| 9/10 | Nationen, Regierungsakte, Beschlüsse über Grenze und Nutzung, Sicherheitsordnung des Geländes, außerordentliche Versammlungen |
| 11 | Kampfsystem mit den Stufen 1–3, Wachen, Vorfälle, Krisenereignis, Folgen |
| 12/13 | vollständige Durchsetzung auf dem Server im Mehrspielerbetrieb |
