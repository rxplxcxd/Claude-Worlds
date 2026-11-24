# NPC_SYSTEM

**Status:** Gründungsgemeinschaft mit dauerhaften Identitäten und Rollenkleidung **[Phase 1]** · Persönlichkeit, Beruf, Bedürfnisse, Tagesabläufe, Utility AI, Navigation, Interaktionen, Simulations-LOD, Persistenz **[IMPLEMENTIERT, Phase 3 – siehe [LIVING_WORLD.md](LIVING_WORLD.md)]** · Beziehungen, Erinnerungen, Dialoge **[GEPLANT, Phase 5]**.

## 0a. Was in Phase 1 implementiert ist
- **Gründungsgemeinschaft** (`scripts/npc/npc_roster.gd`): Bei der Gründung entstehen 12 NPCs – Verwaltung 1, Händler:in 2, Sanitäter:in 1, Sicherheitsdienst 1, Bauarbeiter:in 2, Handwerker:in 1, Landwirt:in 2, Bewohner:in 2. Deterministisch aus der Siedlungs-ID (Seed), danach **im Siedlungsdatensatz gespeichert** (`record.npcs[]`): `npc_id, name, role, workplace_id, home_id, appearance, index_in_role`. Ältere Spielstände ohne NPCs erhalten sie beim nächsten Laden einmalig.
- **Rollenkleidung** (`CharacterCatalog.role_appearance(role, seed)`, Regeln in `data/character_catalog.json → roles`): zivile Zufallsbasis + Uniform der Rolle. Beispiele: Bau → Mütze orange/gelb, Overall orange/gelb, Hammer · Landwirtschaft → Strohhut, grünes Hemd, Schaufel/Gießkanne · Sanitäter → hellblaues Hemd mit langen Ärmeln, hellblaue Hose · Verwaltung → dunkles Hemd/Kleid, Fliege · Sicherheit → blaues Langarmhemd, schwarze Hose · Handel → Hemd orange/gelb/beige, Tasche. Strohhut und Mütze sind **Rollenmerkmale** und werden anderen Rollen nicht zufällig gegeben. Jede Kombination ist eindeutig (getestet); das Aussehen bleibt dauerhaft gleich (gespeichert, nicht neu gewürfelt).
- **Arbeitsplätze** werden je Rolle reihum verteilt (z. B. Händler:in 1 → Handelsposten, Händler:in 2 → Bäckerei). Wohnungen reihum auf die Wohnhäuser.
- **Präsenz nach Uhrzeit** (`scripts/npc/npc.gd`): 07:30–18:30 neben der Tür des Arbeitsplatzes (Bewohner:innen am Dorfplatz), 18:30–22:00 neben dem eigenen Wohnhaus, nachts drinnen (unsichtbar, keine Kollision). Plätze (`NpcRoster.plan_spots`): nie auf Straße/Wasser/Gebäude, nie im Eingang, nie auf Straßenmobiliar, eindeutig, sichtbare Gebäudeseite bevorzugt.
- **Verhalten:** Idle-Animation mit Blinzeln, gelegentliches Umdrehen, Werkzeuggebrauch (Rollen mit Werkzeug), schaut den Spieler an, wenn er näher als ~70 px kommt. Antippen → Karte mit Name, Rolle, Arbeitsplatz, Wohnung.
- **Darstellung:** gleicher `CharacterRig` wie der Spieler im Composite-Modus (2 Texturen pro Figur und Animation, gecacht).
- **Abgelöst in Phase 3:** Die feste Präsenz nach Uhrzeit (Phase 1) ist durch die Simulation ersetzt – NPCs gehen ihre Wege, arbeiten in Schichten, essen, treffen sich, schlafen; Tagesablauf nach Siedlungszeit ([LIVING_WORLD.md](LIVING_WORLD.md)).

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
Verbindliche Präzisierung (24.11.2026): mehrstufige, persistente Simulation ohne Einfrieren und ohne sichtbares Nachsimulieren – Architektur in [SIMULATION_ARCHITECTURE.md](SIMULATION_ARCHITECTURE.md) (Stufen S0–S3, `advance()`, Stufenwechsel).

| LOD | Wann | Umfang | Takt |
|---|---|---|---|
| Aktiv | sichtbar/nahe Spieler | Knoten, Navigation, Animation | jeder Frame |
| Hintergrund | gleiche Siedlung, nicht sichtbar | Bedürfnisse, Arbeit, Ortswechsel als Daten | jede Spielstunde |
| Entfernt | andere Siedlungen | Tagesbilanz, Ereignisse | jeder Spieltag / bei Bedarf |

## 7. Erinnerungen
Nur bedeutsame Ereignisse (Versprechen, Konflikte, Hilfe, Jobwechsel), max. ~30 je NPC, mit Gewicht und Verblassen.

## 8. Offene Fragen [OFFEN]
NPC-Altern/Geburt/Tod (spielerfreundlich gestalten), Obergrenze NPCs je Siedlung auf iPhone.
