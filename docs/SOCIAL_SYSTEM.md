# SOCIAL_SYSTEM

**Status: [GEPLANT] – Phase 5.** Nichts davon ist implementiert.

## 1. Beziehungen
```
Relationship { a_id, b_id, type (acquaintance|friend|partner|family|colleague|rival),
               affinity -1..1, trust 0..1, dependency 0..1, history[] (Ereignis-IDs), since }
```
Gilt gleichermaßen für Spieler↔Spieler, Spieler↔NPC, NPC↔NPC. Gespeichert als Kanten (Unterkollektion je Person), nicht als riesige Arrays.

## 2. Funktionen
Profile, Freundschaften, Familien, Partnerschaften, soziale Gruppen/Vereine, Gespräche (vorgefertigte, kontextbezogene Dialogbausteine), gemeinsame Aktivitäten, gesellschaftliche Ereignisse (Feste, Märkte), persönliche Ziele.

## 3. Wirkung auf andere Systeme
- Vertrauen senkt Verhandlungskosten (Handel, Verträge).
- Freunde/Familie beeinflussen Umzugsentscheidungen (MIGRATION_SYSTEM).
- Gruppen bilden Interessenblöcke in der Politik.

## 4. Gestaltungsregeln
- Keine Bestrafung für Offline-Zeit (Beziehungen verblassen langsam, nicht abrupt).
- Positive Momente aktiv erzeugen (Einladungen, Geschenke, Hilfeleistungen).

## 5. Offene Fragen [OFFEN]
Kinder/Familienplanung bei Spielern (siehe CONTRACT_SYSTEM §13.7: kein Schaden durch Abwesenheit), Moderation von Spieler-Chat.
