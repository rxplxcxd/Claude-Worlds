# POLITICAL_SYSTEM

**Status: [GEPLANT] – Phasen 8–9.** Nicht implementiert (Gemeindehaus zeigt nur Text).

## 1. Politische Einheiten
```
PoliticalEntity { entity_id (pol_*), name, kind (settlement|city_union|admin_community|political_union|state|country|confederation),
                  members[] (stl_*/pol_*), territory_ids[], constitution {decision_model, offices[], terms},
                  recognition {self_declared, internal, self_governing, international[] (anerkennende pol_*)},
                  laws[], budget, treasury, capital_settlement_id }
```

## 2. Zusammenschlüsse
Modelle mit unterschiedlichen Rechten: räumliches Zusammenwachsen, Stadtverbund, Verwaltungsgemeinschaft, politische Union, vollständige Fusion. Mehrparteien-Verhandlungen (3, 5, 10 Siedlungen) mit Vertrag, Abstimmung, Übergangsfrist.

## 3. Anerkennung als Staat/Land – Vorschlag Mindestanforderungen [OFFEN, Werte festzulegen]
| Kriterium | Vorschlag |
|---|---|
| Zusammenhängendes Territorium | ≥ 3 Regionen bzw. ≥ X km², definierte Grenzen |
| Bevölkerung | ≥ 5 000 dauerhaft (Spieler + NPC) |
| Siedlungen | ≥ 3, davon ≥ 1 Kleinstadt |
| Verwaltung | Verfassung, Ämter besetzt, Haushalt |
| Institutionen | Gericht/Schlichtung, Sicherheit, Gesundheit, Bildung |
| Versorgung | Wasser, Energie, Lebensmittel ≥ 90 % Deckung |
| Wirtschaft | positives Haushaltssaldo über 2 Spieljahre |
| Stabilität | keine ungelösten Gebietskonflikte |

Unterschieden werden: **Selbstbezeichnung** (frei, ohne Wirkung) → **interne Anerkennung** (Bevölkerung stimmt zu) → **Selbstverwaltung** (Kriterien erfüllt, systemisch geprüft) → **internationale Anerkennung** (durch andere anerkannte Länder, Weltrat).

## 4. Entscheidungsmodelle
Abstimmung der Siedlungsleitungen, Vertreter, Volksabstimmung, Parlament, vertragliche Zustimmung – festgelegt in der Verfassung der Einheit.

## 5. Ämter, Parteien, Wahlen, Gesetze, Steuern
Bürgermeister, Verwaltung, Parteien/Gruppen, periodische Wahlen, Gesetze mit messbaren Effekten (Steuersätze, Bauregeln, Öffnungszeiten), Haushalte, Genehmigungen, Diplomatie.

## 6. Offene Fragen [OFFEN]
Konkrete Schwellenwerte; Schutz vor „Ein-Spieler-Staaten“ mit NPC-Mehrheiten (Vorschlag: Mindestanteil menschlicher Beteiligung für internationale Anerkennung).
