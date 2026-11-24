# TRADE_AND_LOGISTICS

**Status: [GEPLANT] – Phase 8.** Nicht implementiert.

## 1. Handelsroute
```
TradeRoute { route_id, origin_settlement_id, destination_settlement_id, path[] (Wegpunkte/Segmente),
             mode (road|truck|van|rail|freight_train|ship|air), capacity_per_day, duration_hours,
             cost_per_unit, partners[], usage_rights[] (transit_contract_ids), risks {weather, theft, breakdown},
             status }
```

## 2. Infrastruktur
Segmente (Straße, Schiene, Wasserweg, Luftkorridor) gehören Territorien; Zustand verfällt ohne Wartung.

## 3. Transitverträge
Durchfahrtsgenehmigung, Maut (pro Einheit/Fahrzeug), Wartungsbeteiligung, Laufzeit, Kündigungsfrist. Ohne Einigung → Routenplaner sucht Alternativen (Kosten/Zeit-Abwägung).

## 4. Simulation
Abstrahiert: Waren „reisen“ als Datensätze mit Ankunftszeit; nur in der aktiven Siedlung sichtbare Fahrzeuge (Penzilla Giant City Builder enthält Fahrzeuge).

## 5. Offene Fragen [OFFEN]
Piraterie/Diebstahl als Risiko (Ton beachten), Spieler als Spediteure.
