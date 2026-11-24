# MIGRATION_SYSTEM

**Status: [GEPLANT] – Phasen 8 & 13.** Nicht implementiert.

## 1. Umzüge
Voraussetzungen/Faktoren: Wohnraum am Ziel, Umzugskosten, laufende Arbeits-/Mietverträge (Kündigungsfristen), Eigentum (behalten, vermieten, verkaufen), Beziehungen, Zugangs-/Aufenthaltsrechte der Zieleinheit.

Ablauf: Antrag/Entscheidung → Fristen klären → Reise (Spielzeit, abhängig von Distanz/Transport) → Ankunft (neue Wohnadresse, Melderegister).

## 2. Gründe (für NPC-Utility und Spieler-Information)
Arbeit, Löhne, Mieten, Lebensqualität, Infrastruktur, Beziehungen/Familie, Politik, Wirtschaft, Geschäftschancen, Bildung, Sicherheit, persönliche Ziele.

## 3. Anwerbung durch Spieler
```
RecruitmentOffer { offer_id, issuer_id (Spieler/Unternehmen/Siedlung), target (person_id | public),
                   settlement_id, package { job_contract_template?, housing {rent_free_months?, discount?},
                   relocation_bonus?, welcome_package?, land_grant?, equity_share?, long_term_support? },
                   conditions[] (z. B. Mindestaufenthalt), valid_until, state (open|accepted|declined|expired) }
```
Angebote sind annehmbar/ablehnbar, zeitlich begrenzt, an Bedingungen geknüpft. **Keine manipulativen Mechaniken**, kein Zwang; Spam-Schutz (Limit je Absender/Zeitraum), Meldefunktion.

## 4. Kommunikation [GEPLANT, Phase 13]
Privatnachrichten, Profile, Kontakte, Siedlungs-/Regional-/Handels-/Diplomatie-/Organisationskanäle, globale Kanäle – über Realtime Database, moderiert.
