# LAW_ENGINE – Eigentum, Befugnisse und regelbasierte Gesetzgebung

**Status: [GEPLANT]** – Grundlage: [DESIGN_DIRECTIVES.md](DESIGN_DIRECTIVES.md) §5–7. Umsetzung frühestens mit Phase 7 (Eigentum & Bauen: Berechtigungsprüfung) und Phase 9 (Gesetzgebung). Nichts davon ist implementiert.

## 1. Leitidee
Jede Veränderung der Welt ist eine **Handlung** (Absicht), die vor der Ausführung geprüft wird. Gesetze sind **Daten** (Regeln aus Bausteinen), keine Programmzeilen. Die Engine kennt nur einen festen, kleinen Satz von **Handlungstypen**, **Fakten** und **Wirkungen** – Spieler kombinieren diese frei.

```
Absicht ──▶ Berechtigungsprüfung ──▶ Ergebnis
            1. Weltregeln (unabänderlich)        ERLAUBT
            2. Eigentum & Nutzungsrechte          VERBOTEN (mit Begründung)
            3. Amt & Rolle                        ERLAUBT UNTER AUFLAGEN → Verfahren
            4. Gesetze aller Ebenen                 (Frist, Genehmigung, Abstimmung,
                                                    Entschädigung, Umsiedlung, Gebühr)
```

## 2. Berechtigungsprüfung (Phase 7 – vor jeder Gesetzgebung nötig)

### 2.1 Handlungstypen (Auszug, erweiterbar)
`building.construct · building.demolish · building.move · building.modify · parcel.split · parcel.merge · parcel.rezone · road.build · road.remove · road.reroute · infra.modify · admin.relocate · resident.evict · property.transfer · territory.expand · law.propose · law.enact · tax.set · office.appoint`

### 2.2 Rechteebenen
| Ebene | Beispiele | Änderbar durch |
|---|---|---|
| **Weltregeln** („Grundgesetz von Aurel“) | Kein Abriss fremden Eigentums ohne Verfahren; kein Entzug ohne Entschädigung; Bewohner werden nie obdachlos zurückgelassen; Grundrechte von Spielern | Nur Entwickler/Weltrat (Phase 10) |
| **Eigentum** (`PropertyRecord`) | Eigentümer, Miteigentum, Pacht, Miete, öffentlich | Kauf, Verkauf, Erbe, Enteignungsverfahren |
| **Ämter** (`Office`) | Bürgermeister, Bauamt, Rat, Polizei | Wahl, Ernennung, Verfassung |
| **Gesetze** (`Law`) | Bauordnung, Räumungsschutz, Denkmalschutz, Steuern | Gesetzgebungsverfahren der zuständigen Ebene |

### 2.3 Standardverhalten ohne eigene Gesetze (Vorschlag)
- Einwohner: nur eigenes Eigentum ändern; fremdes nie.
- Eigentümer: eigenes Gebäude umbauen/abreißen – **bewohnt** nur mit Ankündigungsfrist und Ersatzwohnung für Mieter.
- Bürgermeister: öffentliche Gebäude/Straßen ändern; private Gebäude nur über **Enteignungsverfahren** (Frist, Entschädigung zum Marktwert, Umsiedlung).
- Straßen mit Anliegern ohne andere Zufahrt: Abriss nur mit Ersatzweg.

## 3. Datenmodell der Gesetze

```
Law {
  law_id, jurisdiction_id (stl_/pol_), level (settlement|city|region|state|country),
  title, summary, status (draft|in_vote|enacted|suspended|repealed), version,
  enacted_at, valid_from, valid_until?, source_vote_id, authors[],
  rules: [Rule], effects: [Effect]
}
Rule {
  rule_id, priority,
  applies_to: [ActionType],                    // z. B. ["building.demolish"]
  scope: Scope,                                // Gebiete, Zonen, Gebäudearten, Rollen, Zeiträume
  when: Condition,                             // Ausdrucksbaum über Fakten
  decision: "allow" | "deny" | "require",
  requirements: [Requirement],                 // bei "require"
  exceptions: [Condition],
  sanctions: [Sanction],                       // bei Verstoß
  appeal: Appeal?                              // Einspruch
}
Condition = { op: and|or|not|eq|ne|gt|ge|lt|le|in|within|between|has_role|days_since, args: [...] }
Fact (typisierte, freigegebene Liste): actor.role, actor.residence_days, actor.is_owner,
  target.building.type, target.building.occupied, target.building.age_days, target.building.protected,
  target.parcel.zone, target.road.is_only_access, settlement.population, time.local_hour, time.weekday …
Requirement = notice_period{days} | permit{issuer_role} | vote{body, quorum, majority}
            | compensation{formula} | relocation{housing_standard} | fee{formula} | consent{party}
            | inspection{role} | waiting_period{days}
Sanction = fine{formula} | revoke_permit | suspend_office{days} | reputation{delta} | restore_order
Appeal = { who: [roles/parties], deadline_days, decided_by (court|council|higher_level), suspensive: bool }
Effect (dauerhafte Wirkungen statt Erlaubnisse) = tax{base, rate} | subsidy{target, amount}
            | opening_hours{building_types, hours} | speed_limit | zoning_rule{…} | building_code{…}
Trigger (ereignisgesteuert) = { on: event_type, when: Condition, do: Effect }   // z. B. Steuerstichtag
```

**Beispiel** – „Bewohnte Häuser dürfen nur nach Ankündigung, Umsiedlung oder Entschädigung abgerissen werden“:
```json
{ "applies_to": ["building.demolish"], "scope": {"building_types": ["house", "apartment"]},
  "when": {"op": "eq", "args": ["target.building.occupied", true]},
  "decision": "require",
  "requirements": [{"type": "notice_period", "days": 14},
                   {"any_of": [{"type": "relocation", "housing_standard": "equal"},
                               {"type": "compensation", "formula": "market_value * 1.2"}]}],
  "appeal": {"who": ["occupants", "owner"], "deadline_days": 7, "decided_by": "council", "suspensive": true} }
```

## 4. Verfahren
`require` startet ein **Verfahren** (`Procedure`) mit Zustandsautomat:
`beantragt → Frist läuft → (Einspruch → Entscheidung) → Auflagen erfüllt → ausgeführt` bzw. `abgelehnt/verfallen`. Verfahren sind persistent, laufen in Echtzeit (UTC-Zeitstempel) weiter, auch wenn niemand online ist ([SIMULATION_ARCHITECTURE.md](SIMULATION_ARCHITECTURE.md)), und benachrichtigen Betroffene.

## 5. Ebenen und Vorrang
- Ebenen: Siedlung → Stadt → Region (politisch) → Staat → Land; darüber Weltregeln.
- **Kompetenzordnung**: Jede Ebene darf nur bestimmte Handlungstypen regeln (in ihrer Verfassung festgelegt; Standard: Bau/Zonen lokal, Steuern je Ebene, Grundrechte nur Land/Welt).
- **Vorrang**: Weltregel > höhere Ebene > niedrigere Ebene. Eine niedrigere Ebene darf **strenger** sein, wenn die höhere das erlaubt (Öffnungsklausel); ein Verbot der höheren Ebene kann unten nicht aufgehoben werden.
- **Konfliktauflösung** innerhalb einer Ebene: höhere `priority`, dann spezifischerer `scope`, dann `deny` vor `allow`. Konflikte werden **beim Beschluss** erkannt und angezeigt.

## 6. Sicherheit und Leistung
- Kein frei programmierbarer Code: Ausdrucksbäume mit **Tiefen- und Kostenlimit**, nur freigegebene Fakten/Wirkungen → keine Endlosschleifen, kein Missbrauch.
- **Statische Prüfung** beim Entwurf (Typen, unerreichbare Regeln, Widersprüche) und **Vorschau** („Was wäre wenn?“ auf echten Daten der Siedlung).
- Auswertung **serverseitig**; Index der Regeln nach `applies_to` + Gebiet → pro Handlung nur wenige Regeln.
- Gesetze sind versioniert; jede Entscheidung protokolliert die angewandte Version (Nachvollziehbarkeit, Einspruch).

## 7. Bedienung
Spieler schreiben keine Ausdrücke: ein **Baukasten** mit Vorlagen („Räumungsschutz“, „Denkmalschutz“, „Nachtruhe“, „Steuer“), Satzbausteinen („Wenn … dann … außer …“), Klartext-Zusammenfassung und Vorschau. Eine **Gesetzesbibliothek** erlaubt das Übernehmen bewährter Gesetze anderer Siedlungen.

## 8. Exploits und Schutz
| Risiko | Schutz |
|---|---|
| Diskriminierende/enteignende Gesetze | Weltregeln (Grundrechte, Entschädigungspflicht), Einspruch an höhere Ebene |
| Rückwirkende Gesetze | `valid_from` ≥ Beschluss; laufende Verfahren nach altem Recht |
| Abstimmungsmanipulation (Zweitaccounts, NPC-Mehrheiten) | Wahlrecht an Wohndauer/Aktivität; NPCs stimmen bei Spielerangelegenheiten nicht oder nur gewichtet ab ([POLITICAL_SYSTEM.md](POLITICAL_SYSTEM.md) §6) |
| Gesetzes-Spam | Antragslimits, Unterstützerquorum |
| Amtsmissbrauch | Amtshandlungen laufen durch dieselbe Prüfung; Sanktionen, Abwahl |

## 9. Bezug zu anderen Systemen
Eigentum/Verträge: [CONTRACT_SYSTEM.md](CONTRACT_SYSTEM.md) · Ämter, Wahlen, Ebenen: [POLITICAL_SYSTEM.md](POLITICAL_SYSTEM.md) · Bauen: [SETTLEMENT_SYSTEM.md](SETTLEMENT_SYSTEM.md) §9 · Rat: [COUNCIL_SYSTEM.md](COUNCIL_SYSTEM.md).
