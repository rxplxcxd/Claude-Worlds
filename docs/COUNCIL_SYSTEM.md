# COUNCIL_SYSTEM

**Status: [GEPLANT] – Phase 10.** Nicht implementiert.

## 1. Ratstypen
| Typ | Mitglieder | Themen | Rhythmus |
|---|---|---|---|
| Lokaler Rat | benachbarte Siedlungen | Straßen, Wasser/Energie, Handel, Sicherheit, Migration, Projekte, Konflikte | frei wählbar: wöchentlich … jährlich, nach Bedarf |
| Regionaler Rat | Verbünde/politische Einheiten | Infrastruktur, Verkehr, Ressourcen, Grenzen, Sicherheit | frei wählbar |
| **Weltrat** | anerkannte Länder | globale Abkommen, Konflikte, Routen, Infrastruktur, Umwelt, Organisationen, Anerkennung neuer Staaten | **1× pro Spieljahr** |

Ein Rat beschließt nur innerhalb seiner Zuständigkeit (kein lokaler Rat entscheidet global).

## 2. Datenmodell
```
Council        { council_id, kind, member_entity_ids[], rules {quorum, majority, seats_per_member}, schedule }
CouncilSession { session_id, council_id, start, agenda[], delegates[] {entity_id, person_id, role (delegate|substitute|proxy)},
                 motions[], votes[], decisions[], minutes, public_summary, state (planned|open|voting|closed) }
Motion         { motion_id, author_entity_id, text, effects (strukturiert), support[] }
```

## 3. Vertretung & Ausfallsicherheit
Stellvertreter, Ersatzdelegierte, **vorab eingereichte Positionen/Stimmen**, Vollmachten. Ist niemand online, zählt die hinterlegte Position; sonst Enthaltung. Sitzungen haben Zeitfenster (z. B. 48 h Abstimmung), damit keine Einzelperson blockiert.

## 4. Weltrat als Community-Ereignis
Eigene Versammlungsszene (Delegierte als Figuren, Flaggen), Tagesordnung, Redebeiträge (Zeitslots), Anträge, Live-Abstimmung, Beschlüsse, Protokoll, öffentliche Zusammenfassung. Zuschauermodus für Streamer (nur lesen, Kamerafahrten).

## 5. Offene Fragen [OFFEN]
Gewichtung der Stimmen (je Land gleich vs. nach Bevölkerung), Zeitzonen-Planung des Weltrats.
