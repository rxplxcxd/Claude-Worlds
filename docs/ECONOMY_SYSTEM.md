# ECONOMY_SYSTEM

**Status: [GEPLANT] – Phase 6.** Nicht implementiert (Marktstand/Handelsposten zeigen nur Text).

## 1. Kernobjekte
```
Good       { good_id, category (food|water|energy|material|raw|tool|machine|industrial|consumer|medical), unit, perishable_days? }
Inventory  { owner_id, location_id, items {good_id: qty}, capacity }
Business   { business_id, name, owner_ids[] + shares, type, settlement_id, building_id,
             employees[], recipes[], inventory_id, cash, prices {}, status (open|closed|bankrupt), founded }
Recipe     { inputs {good: qty}, outputs {good: qty}, labor_hours, building_type, duration }
Market     { settlement_id, orders[] (bid/ask), last_prices {}, price_history }
```

## 2. Preise
Lokale Märkte mit Angebot/Nachfrage (Orderbuch oder vereinfachte Preiskurve je Gut). Preisänderung pro Spieltag begrenzt (Stabilität, verhindert Ausnutzung).

## 3. Arbeit & Löhne
Arbeitsverträge (CONTRACT_SYSTEM). Lohn = Basis × Qualifikation × lokale Knappheit.

## 4. Unternehmen
Gründung erfordert Kapital, Grundstück/Gebäude, Genehmigung, Personal, Rohstoffe, Infrastruktur. Unternehmen wachsen, eröffnen Filialen, geraten in Schwierigkeiten oder schließen. Später: Anteile, Investoren, Dividenden, Bewertung.

## 5. Steuern & öffentliche Haushalte
Siedlungen erheben Steuern (POLITICAL_SYSTEM) und finanzieren öffentliche Dienste.

## 6. Anti-Exploit / Multiplayer
Alle Geldflüsse werden serverseitig gebucht (doppelte Buchführung, unveränderliches Transaktionslog). Clients senden nur Absichten.

## 7. Offene Fragen [OFFEN]
Eine Weltwährung vs. regionale Währungen (Vorschlag: zunächst eine Währung „Kredit“, regionale Währungen ab Phase 9), Tiefe der Produktionsketten.
