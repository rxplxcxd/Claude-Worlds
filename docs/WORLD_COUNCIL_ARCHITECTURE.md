# World Council – Daten, Persistenz, Serverautorität

## 1. Definition (unveränderlich)
`data/world/landmarks.json` → `Landmarks` (`scripts/world/landmarks.gd`)
- `landmark_id` `lmk_world_council`, `kind` `world_council`, Name, Untertitel, Arbeitstitel des Ortes
- `position` {lat 28.28, lon 137.36}, `continent_id` cnt_05 (Kalistia), `region_id` reg_139
- `reserve_radius_km` 18, `site_tiles`
- `assembly` {month 6, day 24, time_basis world_time_utc, duration_days 1}
- `stages` (1 historisch … 4 monumental), `components` (IDs, Ausgangszustand, Zugang)
Teil der Weltdefinition wie der Planet: identisch auf jedem Client und dem Server, nie neu gewürfelt. `genesis.json` verweist darauf; Landmarken sind keine Siedlungen (`rules.landmarks_are_not_settlements`).

## 2. Zustand (veränderlich, persistent)
`WorldState.landmark_state(id)`, gespeichert im Weltstand (`landmarks` neben `settlements`/`territories`):
```
{ landmark_id, stage, version,
  components: { <id>: { condition 0..1, access open|closed|event, restored 0..1, built } },
  extensions: [ {id, kind, footprint, built_at, by} ],     # Phase 7
  decisions:  [ {resolution_id, assembly_year, text_key, effects} ],  # Phase 10
  history:    [ {t, kind, text, by} ] }
```
Firestore (später): `landmarks/{landmark_id}` mit demselben Inhalt, Unterkollektionen `history`, `assemblies/{year}` (Tagesordnung, Anträge, Abstimmungen, Protokoll).

## 3. Serverautorität
- Clients lesen nur. Jede Änderung ist ein **Befehl** an die Weltautorität (`WorldAuthority.submit`). Später kommen Befehlsarten wie `landmark_restore`, `landmark_build`, `landmark_set_access`, `assembly_submit_motion`, `assembly_vote` hinzu. Der Server prüft Berechtigung (Nation, Delegierter, Vollmacht), Ressourcen und Regeln und schreibt dann den Zustand fort. Er protokolliert dabei (`history`) und erhöht `version`.
- Lokal (Einzelspielerstand) übernimmt die `LocalWorldClient`-Autorität dieselbe Rolle. Der Wechsel zum `RemoteWorldClient` ändert keine Spiellogik (WORLD_AUTHORITY.md).
- Kein Client entscheidet über gültige Beschlüsse oder den baulichen Zustand.

## 4. Weltzeit und Versammlung
- `Landmarks.next_assembly(id, unix)` berechnet den 24. Juni aus **UTC**. Die Gerätezeit oder -zone spielt keine Rolle.
- Die Versammlung findet statt, ob jemand online ist oder nicht.
  - Delegierte, Stellvertreter, Vollmachten und vorab eingereichte Positionen kommen aus Phase 9/10.
  - Wer nicht teilnimmt, wird nach den Regeln seiner Nation vertreten.
  - Beschlüsse werden am Ende des Tages vom Server ausgewertet und persistent wirksam.
- Wer nach Jahren zurückkehrt, findet den aktuellen Stand vor: Stufe, Beschlüsse, Geschichte.

## 5. Skalierung
- **Darstellung:** Besucher im Detail nur in Sichtweite (wie Simulationsebene S0/S1 der Siedlungen), weiter entfernte als Gruppen bzw. gar nicht. Die tatsächliche Zahl der Teilnehmer bleibt im Serverzustand erhalten.
- **Versammlungsablauf:** in Phase 10 serverseitig als Ereignisstrom (Reden, Anträge, Abstimmungen), damit Zuschauer und Streams ihn verfolgen können.

## 6. Schutzgebiet
`Landmarks.reserved_at(lat, lon, radius_km, margin_km)`. Es wird geprüft:
- bei der Gründung (`Geography.rate_site`, auch in „Vorschlag“),
- **künftig** bei Gebietserweiterungen (Phase 7) und Infrastrukturplanung (Phase 8). Dort entsteht Infrastruktur nur durch Beschlüsse und Bauaufträge.
