# NPC_SYSTEM

**Status: [GEPLANT] – Phase 3.** In Phase 1 existieren keine NPCs.

## 0. Grundregel [VERBINDLICH]
NPCs existieren **nur innerhalb von Siedlungen, die ein Mensch gegründet hat** (als Gründungsgemeinschaft des Gründers oder durch Zuzug). NPCs **gründen keine Siedlungen**, und es gibt keine Siedlung ohne menschliche Bewohner (WORLD_DESIGN.md §1). NPC-Umzüge erfolgen nur zwischen bestehenden Spielersiedlungen.

## 1. Identität
```
Npc { npc_id, name, birth_day, personality {openness, diligence, sociability, ambition, risk} (0..1),
      skills {}, occupation {employer_id, role, contract_id}, residence {settlement_id, property_id},
      wallet, family_ids[], relationships[], interests[], political_leaning {economic, social},
      goals[], memories[] (begrenzt, gewichtet), needs {}, schedule_id, lod }
```

## 2. Bedürfnisse
Nahrung, Schlaf, Unterkunft, Sicherheit, Soziales, Einkommen, Gesundheit, Freizeit, Anerkennung, Entwicklung – jeweils 0..1, mit Abbauraten je Persönlichkeit.

## 3. Entscheidungslogik
- **Utility AI** für die Wahl der nächsten Aktivität (Bedürfnisdruck × Persönlichkeit × Verfügbarkeit × Entfernung).
- **Zustandsautomat** für die Ausführung (gehen → handeln → zurück).
- **GOAP** nur für langfristige Ziele (Unternehmen gründen, umziehen), selten ausgewertet.
- **Ereignisreaktionen** (Brand, Fest, Kündigung).
- **Kein LLM pro Entscheidung.** Deterministisch mit Seed → reproduzierbar und serverfähig.

## 4. Tagesablauf
Zeitplan-Vorlagen je Beruf (Frühschicht, Normal, Nacht) + individuelle Abweichungen durch Utility-Bewertung.

## 5. Navigation
`NavigationRegion2D` aus begehbaren Kacheln, Gebäudeeingänge als Ziele; Spieler-Tippen-zum-Gehen wird dann ebenfalls auf Pfadfindung umgestellt.

## 6. Simulations-LOD
| LOD | Wann | Umfang | Takt |
|---|---|---|---|
| Aktiv | sichtbar/nahe Spieler | Knoten, Navigation, Animation | jeder Frame |
| Hintergrund | gleiche Siedlung, nicht sichtbar | Bedürfnisse, Arbeit, Ortswechsel als Daten | jede Spielstunde |
| Entfernt | andere Siedlungen | Tagesbilanz, Ereignisse | jeder Spieltag / bei Bedarf |

## 7. Erinnerungen
Nur bedeutsame Ereignisse (Versprechen, Konflikte, Hilfe, Jobwechsel), max. ~30 je NPC, mit Gewicht und Verblassen.

## 8. Offene Fragen [OFFEN]
NPC-Altern/Geburt/Tod (spielerfreundlich gestalten), Obergrenze NPCs je Siedlung auf iPhone.
