# CONTRACT_SYSTEM

**Status: [GEPLANT] – Phasen 6–8.** Nicht implementiert.

## 1. Grundprinzip
> Abwesenheit **ohne** Verpflichtung ist kein Problem. Abwesenheit **trotz** Verpflichtung kann Konsequenzen haben – fair, nachvollziehbar, verhältnismäßig.

Keine Login-Pflichten, keine willkürlichen Verluste, keine verfallenden Häuser, keine grundlosen Kündigungen.

## 2. Vertragsmodell
```
Contract { contract_id, kind (employment|lease|sale|transit|supply|partnership|recruitment|service),
           parties[] {id, role}, terms {...}, start, end?, notice_period_days,
           obligations[] {who, what, schedule}, substitution_rules, penalties[], state, history[] }
```

## 3. Arbeitsverträge
Arbeitszeiten/Schichten, Aufgaben, Lohn, Urlaub, Krankheit, Fehlzeiten, Kündigungsfristen, Vertretungsregeln.

Eskalation bei Fehlzeiten (Vorschlag): 1. Fehlschicht → Lohnausfall für die Schicht, Hinweis · 2.–3. in 14 Tagen → Verwarnung, Vertrauensverlust · weitere → Vertragsänderung (weniger Schichten) oder Kündigung mit Frist. **Nie existenzbedrohend durch eine einzelne Schicht.**

Arten der Abwesenheit: freiwillig ohne Pflicht · trotz Pflicht · vereinbart (Urlaub, im Voraus eintragbar) · delegiert (Vertretung organisiert) · Notfall (Kulanzkontingent).

## 4. Vertretung
Reihenfolge: anderer Mitarbeiter → NPC-Springer → Bereitschaftsdienst → Leistung reduziert/Geschäft geschlossen.

## 5. Spielerbetriebene Unternehmen
Persönlich betriebener Laden bleibt geschlossen, wenn der Spieler fehlt; mit Personal/Vertretung bleibt er offen.

## 6. Kritische öffentliche Dienste
Feuerwehr, Medizin, Sicherheit haben **Mindestbesetzung durch NPCs**; Spieler erhöhen Kapazität/Qualität, aber ihr Fehlen führt nie zum Totalausfall.

## 7. Persönliche Bedürfnisse
Wohnen, Ernährung, Gesundheit, Familie, Kinder, Fahrzeuge, Freizeit – spielerisch, ohne dauerhaften Schaden durch Offline-Zeit (z. B. Familie versorgt Kinder automatisch).

## 8. Eigentum, Miete, Räumung [GEPLANT – ergänzt 24.11.2026]
Mit der Gestaltungsfreiheit ([DESIGN_DIRECTIVES.md](DESIGN_DIRECTIVES.md) §5–6) werden Verträge zur Grundlage von Nutzungsrechten: Kauf/Verkauf von Grundstücken und Gebäuden, Miet- und Pachtverträge, Entschädigungs- und Umsiedlungsvereinbarungen bei Abriss oder Enteignung. Welche Fristen, Entschädigungen und Ersatzwohnungen gelten, bestimmt die Gesetzgebung ([LAW_ENGINE.md](LAW_ENGINE.md)); die Weltregeln garantieren Mindeststandards (kein entschädigungsloser Entzug, niemand bleibt ohne Unterkunft).
