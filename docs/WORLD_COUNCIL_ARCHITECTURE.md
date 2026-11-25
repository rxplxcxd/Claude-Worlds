# Concordium – Daten, Persistenz, Serverautorität

## 1. Definition (unveränderlich)
`data/world/landmarks.json` → `Landmarks` (`scripts/world/landmarks.gd`)
- `landmark_id` `lmk_world_council`, `kind` `world_council`, `name` CONCORDIUM, `site_name` Concordium, Bedeutung, Untertitel, Leitsatz (de/en), Inschriften
- `position` {lat 28.28, lon 137.36}, `continent_id` cnt_05 (Kalistia), `region_id` reg_139, `site_frame` (+x Osten, +y Süden)
- `property` {version, polygon_m}: Ausgangsgrenze des neutralen Grundstücks (172 × 172 m); `height_m` 56,25
- `assembly` {month 6, day 24, time_basis world_time_utc, duration_days 1, official_name „Concilium Mundi“, ui_name {de, en}}, `institution.ui_name` (Weltrat / World Council)
- `neutrality` (Status, Prinzipien, Handlungsarten mit Stufe, Krisenbedingungen, Folgen, humanitärer Zugang) – siehe WORLD_COUNCIL_NEUTRALITY.md
- Innenraumprogramm: `data/landmarks/concordium_interiors.json` (WORLD_COUNCIL_INTERIORS.md)
- `stages` (1 historisch … 4 monumental), `components` (IDs, Ausgangszustand, Zugang)
Teil der Weltdefinition wie der Planet: identisch auf jedem Client und dem Server, nie neu gewürfelt. `genesis.json` verweist darauf; Landmarken sind keine Siedlungen (`rules.landmarks_are_not_settlements`).

## 2. Zustand (veränderlich, persistent)
`WorldState.landmark_state(id)`, gespeichert im Weltstand (`landmarks` neben `settlements`/`territories`):
```
{ landmark_id, stage, version, neutral,
  property:   { version, polygon_m },        # gültige Grenze (nur Weltautorität + Beschluss)
  components: { <id>: { condition 0..1, access open|closed|event, restored 0..1, built } },
  incidents:  [ {t, kind, tier, actor, nation, action} ],     # Neutralitätsverstöße, Phase 11
  extensions: [ {id, kind, footprint, built_at, by} ],     # Phase 7
  decisions:  [ {resolution_id, assembly_year, text_key, effects} ],  # Phase 10
  history:    [ {t, kind, text, by} ] }
```
Firestore (später): `landmarks/{landmark_id}` mit demselben Inhalt, Unterkollektionen `history`, `assemblies/{year}` (Tagesordnung, Anträge, Abstimmungen, Protokoll).

## 3. Serverautorität
- Grenzänderung heute schon serverseitig gekapselt: `WorldState.update_landmark_property(id, polygon, issuer, resolution_id)` – nur `srv_world_authority`, nur mit Beschluss, neues Gelände ⊇ altes; Version + Protokoll. Ältere Spielstände erhalten fehlende Felder (Grenze, Vorfälle) beim Laden aus der Definition.
- Neutralität: `Landmarks.classify_act` ist das Regelwerk (verhindert / Verstoß / Krise), das das Kampfsystem (Phase 11) serverseitig anwendet.
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

## 6. Grundstück = neutrale Zone
`Landmarks.zone_at(lat, lon)`, `inside_property(site_m)`, `property_overlapping(ring)` – ausschließlich das Grundstückspolygon (der frühere 18-km-Radius ist verworfen). Geprüft bei Gründungen (`Geography.rate_site`), künftig bei jeder Aktion mit Gewalt, Besitz oder Bau (Phasen 7, 11) – immer serverseitig.
