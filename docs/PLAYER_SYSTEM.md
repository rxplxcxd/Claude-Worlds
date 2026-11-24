# PLAYER_SYSTEM

## 1. Implementiert (Phase 1)
- **Lokale Spieleridentität**: `LocalProfile.player_id` (`plr_…`, zufällig, in `user://worlds_local.cfg` gespeichert), Anzeigename (im Charakter-Editor wählbar, Standard „Siedler:in“), Einstellungen (FPS-Anzeige), **Aussehen der Figur** (`LocalProfile.character`).
- **Charakter-Editor & modulare Figur**: neue Spieler erstellen zuerst ihre Figur (vor der Gründung), später über Menü → „Figur bearbeiten“. Details: [CHARACTER_SYSTEM.md](CHARACTER_SYSTEM.md).
- **Spielfigur** (`Player`, `CharacterBody2D`): Geschwindigkeit 190 px/s auf der Bodenebene, Kollision (Ellipse), Interaktionsradius, Eingaben aus Tastatur, Joystick und Tipp-Zielen; 8 Blickrichtungen; Darstellung mit dem eigenen modularen Penzilla-Charakter (Stehen mit Blinzeln, Gehen, Benutzen beim Interagieren; Rückfall: fertige Figur bzw. Platzhalter). Bleibt hinter Gebäuden sichtbar (Durchsicht-Loch, ARCHITECTURE ADR-11).
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

## 3a. Einstieg neuer Spieler [GEPLANT, verbindliche Regel – präzisiert 24.11.2026]
Nach dem Charakter-Editor folgt eine **Auswahl** ([DESIGN_DIRECTIVES.md](DESIGN_DIRECTIVES.md) §4):
- **A) Einer bestehenden Siedlung beitreten:** Globus/Liste der Spielersiedlungen mit Filtern (Entfernung, Größe, Einwanderungsregeln aus der Gesetzgebung, Sprache/Spielstil); je nach Regel sofortiger Zuzug, Antrag oder geschlossen. Benötigt eine gemeinsame Welt (Phase 12); vorher wird die Option angezeigt und erklärt.
- **B) Eigene Siedlung gründen:** Standortwahl auf dem Globus mit Sperrzonen und Schwierigkeitsanzeige (heute: Gründungsmodus des Globus).
- Ist der Planet leer, ist nur B möglich.
- **Planet leer** (erster Spieler): Gründen ist die einzige Möglichkeit.
- **Es gibt Spielersiedlungen:** Wahl zwischen „Beitreten“ und „Eigene Siedlung gründen“ – gleichwertig, keine Pflicht zur eigenen Siedlung.
Später jederzeit: umziehen (MIGRATION_SYSTEM).

## 4. Abwesenheit [GEPLANT]
Siehe CONTRACT_SYSTEM: Abwesenheit ohne Verpflichtung ist folgenlos; Verpflichtungen haben faire, verhältnismäßige Folgen.

## 5. Offene Fragen [OFFEN]
Fähigkeitensystem (Lernen durch Tun vs. Ausbildung).
