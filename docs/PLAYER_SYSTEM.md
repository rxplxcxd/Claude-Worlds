# PLAYER_SYSTEM

## 1. Implementiert (Phase 1)
- **Lokale Spieleridentität**: `LocalProfile.player_id` (`plr_…`, zufällig, in `user://worlds_local.cfg` gespeichert), Anzeigename „Siedler:in“, Einstellungen (FPS-Anzeige, Spielgeschwindigkeit), gespeicherte Spielzeit.
- **Spielfigur** (`Player`, `CharacterBody2D`): Geschwindigkeit 190 px/s auf der Bodenebene, Kollision (Ellipse), Interaktionsradius, Eingaben aus Tastatur, Joystick und Tipp-Zielen; 8 Blickrichtungen; Platzhalter-Optik mit Laufanimation, bereit für `SpriteFrames` (`idle_<dir>`, `walk_<dir>`).
- Beim ersten Start **gründet** der Spieler seine Siedlung (WorldState, Gründer = `player_id`) und wohnt im Haus `bld_player_home`. Danach lädt das Spiel die gespeicherte Siedlung (`user://worlds_world.json`).

## 2. Spieleridentität (Datenmodell) [GEPLANT]
```
Player {
  player_id, auth_uid, display_name, profile {avatar, bio},
  residence {settlement_id, property_id, since},
  occupation {employer_id, contract_id, role}, businesses[],
  wallet {balance, currency}, properties[], relationships[],
  memberships {organizations[], parties[], councils[]},
  contracts[], skills {name: level}, goals[], created_at, last_seen
}
```
`player_id` ist stabil; `auth_uid` verknüpft Firebase Auth (anonym → später E-Mail/Passwort, Kontoübernahme ohne Datenverlust).

## 3. Spieler = Bewohner [GEPLANT]
Spieler und NPCs nutzen dieselben gesellschaftlichen Regeln (Wohnen, Arbeiten, Verträge, Ämter). Technisch: gemeinsames Interface `Resident` (ID, Wohnort, Arbeit, Geldbörse, Beziehungen); Spieler-Entscheidungen kommen vom Menschen, NPC-Entscheidungen von der KI.

## 3a. Einstieg neuer Spieler [GEPLANT, verbindliche Regel]
- **Planet leer** (erster Spieler): Gründen ist die einzige Möglichkeit.
- **Es gibt Spielersiedlungen:** Wahl zwischen „Beitreten“ und „Eigene Siedlung gründen“ – gleichwertig, keine Pflicht zur eigenen Siedlung.
Später jederzeit: umziehen (MIGRATION_SYSTEM).

## 4. Abwesenheit [GEPLANT]
Siehe CONTRACT_SYSTEM: Abwesenheit ohne Verpflichtung ist folgenlos; Verpflichtungen haben faire, verhältnismäßige Folgen.

## 5. Offene Fragen [OFFEN]
Charaktererstellung (Aussehen aus Ultimate Protagonist?), Fähigkeitensystem (Lernen durch Tun vs. Ausbildung).
