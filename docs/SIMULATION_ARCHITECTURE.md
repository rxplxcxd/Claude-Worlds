# SIMULATION_ARCHITECTURE – Mehrstufige, persistente Weltsimulation

**Status: S0/S1 lokal UMGESETZT (Phase 3, 0.5.0)** – `advance()` ereignisgesteuert, Darstellung als Funktion des Zustands, Nachholen nach Abwesenheit, Persistenz: [LIVING_WORLD.md](LIVING_WORLD.md). S2/S3 (Kohorten, andere Siedlungen, Server) folgen mit Phase 8/12/13.

## 1. Grundsatz
Die Welt läuft in **Echtzeit** (UTC) weiter – auch ohne Zuschauer. Detailgrad und Rechenaufwand hängen von der **Relevanz** ab (Nähe zu Spielern, Beobachtung, wichtige Ereignisse). Der Zustand jeder Einheit ist zu jedem Zeitpunkt **berechenbar**, ohne die Zwischenzeit Schritt für Schritt nachzuspielen.

## 2. Stufen

| Stufe | Wo | Was wird simuliert | Takt |
|---|---|---|---|
| **S0 Nahbereich** | sichtbare Chunks der aktuellen Siedlung + Rand | einzelne NPCs als Knoten: Wege (Navigation), Animation, Interaktionen; Gebäude- und Ladenbetrieb | jeder Frame / 10 Hz Logik |
| **S1 Mittlere Entfernung** | übrige Chunks der Siedlung, Nachbarsiedlungen im Sichtbereich anderer Spieler | NPCs als **Daten**: Tagesplan mit Ortswechseln (Reisezeit statt Wegfindung), Bedürfnisse grob; Wirtschaft je Gebäude aggregiert | 1×/Spielminute |
| **S2 Große Entfernung** | andere Siedlungen der Region | Bevölkerung als **Kohorten** (Alter, Beruf, Zufriedenheit), Produktion/Verbrauch als Raten, Versorgung, Handel; wichtige Ereignisse (Brand, Wahl, Vertragsende) einzeln | stündlich |
| **S3 Sehr große Entfernung** | Rest des Planeten | **ereignisbasiert**: Zustand = letzter Schnappschuss + Raten + geplante Ereignisse; Auswertung bei Bedarf oder im täglichen Serverlauf | täglich / bei Zugriff |

Stufen gelten pro Siedlung bzw. Chunk und wechseln **dynamisch**.

## 3. Zustand ohne Nachsimulieren („analytisches Fortschreiben“)
Jede Einheit (Siedlung, Gebäude, Betrieb, Haushalt, NPC) hat:
```
state            letzter bestätigter Zustand
simulated_at     UTC-Zeitstempel dieses Zustands
rates            stückweise konstante Raten (Produktion, Verbrauch, Bedürfnisabbau …)
pending_events   geplante diskrete Ereignisse mit Zeitpunkt (Bau fertig, Vertrag endet, Lieferung …)
seed             für deterministische Zufälle (pro Einheit und Tag)
```
`advance(einheit, bis_zeit)`:
1. Ereignisse zwischen `simulated_at` und `bis_zeit` **in Zeitreihenfolge** abarbeiten; zwischen zwei Ereignissen Raten **geschlossen** integrieren (Bestand += Rate × Δt, begrenzt durch Lager/Kapazität → Begrenzung erzeugt selbst ein Ereignis).
2. Aufwand ∝ **Zahl der Ereignisse**, nicht ∝ vergangener Zeit → mehrere Tage in Millisekunden.
3. Ergebnis = konsistenter aktueller Zustand; neue `simulated_at`.

**Rückkehr eines Spielers:** Der Server ruft `advance(siedlung, jetzt)` auf, bevor er den Zustand sendet. Der Client setzt NPCs direkt an die Orte, die ihr Tagesplan **zum aktuellen Zeitpunkt** vorsieht (heute schon so umgesetzt: `Npc.place_for_hour`) – kein sichtbares Nachspielen.

## 4. Stufenwechsel (Promotion/Demotion)
- **Hochstufen (S2→S1→S0):** Aus aggregierten Kohorten + persistenten Einzelidentitäten (Name, Wohnung, Arbeit, Aussehen) werden Einzel-NPCs deterministisch abgeleitet (Seed); Position = Tagesplan zur aktuellen Zeit.
- **Herabstufen (S0→S1→S2):** Einzelzustände werden in Kohorten/Raten zusammengefasst; wichtige Individualdaten (Beziehungen, Erinnerungen, Verträge) bleiben am NPC-Datensatz.
- **Erhaltungsgrößen** (Geld, Waren, Einwohner) werden beim Wechsel exakt übertragen; Tests prüfen das.

## 5. Ereignisse und Verfahren
- Ereignis-Warteschlange je Region/Shard (sortiert nach Zeit) für S2/S3; S0/S1 lokal.
- Verfahren der Gesetzgebung ([LAW_ENGINE.md](LAW_ENGINE.md) §4), Verträge, Bauprojekte sind Ereignisquellen mit Fristen.
- Wichtige Ereignisse werden auch in fernen Stufen einzeln verarbeitet (Wahlen, Katastrophen, Vertragsbruch) und erzeugen Nachrichten.

## 6. Autorität, Persistenz, Mehrspieler
- **Mehrspieler:** Der Server ist autoritativ. Clients senden Absichten, erhalten bestätigte Zustände; clientseitige Vorhersage nur kosmetisch (Animation).
- **Persistenz:** Schnappschüsse + Ereignisprotokoll (Firestore/Server-Datenbank); `simulated_at` pro Einheit; idempotente Verarbeitung (Ereignis-IDs), damit Neustarts nichts doppelt zählen.
- **Shards:** Simulation nach Regionen/Zellen aufgeteilt (räumlicher Index aus [TERRITORY_SYSTEM.md](TERRITORY_SYSTEM.md) §3); Siedlungen mit Spielern laufen auf „heißen“ Instanzen, der Rest im Stapelbetrieb.
- **Gemeinsamer Code:** Datenklassen ohne Szenenbezug (`SettlementData`, `PlanetData`, `NpcRoster`, künftige Sim-Klassen) können auf einem Godot-Headless-Server laufen. [OFFEN]: Godot-Headless vs. eigener Dienst (z. B. Go/TypeScript) – entscheidet sich an der Last von Tausenden Siedlungen.
- **Determinismus:** Zufälle nur über `seed` (Einheit + Tag) → reproduzierbar, prüfbar.

## 7. Einzelspieler bis Phase 12
Dieselbe Logik läuft lokal: beim Start `advance(eigene Siedlung, jetzt)`; andere Siedlungen gibt es lokal nicht. So ist der Umstieg auf den Server ein Austausch des Ausführungsorts, nicht der Logik.

## 8. Risiken
- Aggregation ↔ Einzelsimulation erzeugen Sprünge (z. B. Zufriedenheit) → Erhaltungsgrößen und Glättung testen.
- Ereignisstürme (viele Fristen gleichzeitig) → Batch-Verarbeitung, Prioritäten.
- Serverkosten bei Tausenden Siedlungen → S3 strikt ereignisbasiert, Auswertung nur bei Bedarf.
- Uhrzeit: nur Serverzeit (UTC); lokale Zeitzonen nur für Darstellung und Siedlungsregeln ([ARCHITECTURE.md](ARCHITECTURE.md) §4).
