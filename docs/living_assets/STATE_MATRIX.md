# Zustandsmatrix – Living Assets

Einheitliches Zustandskonzept für alle Assets. Nicht jede Kategorie braucht alle 12 Zustände; jede Gruppe nutzt eine **Teilmenge** plus **Wetter-** und **Nutzungsvarianten**.

**Umsetzungstechnik** je Zelle: **S** = Shader auf dem Original (Stufe 1, keine Zusatzdatei) · **O** = Overlay (Stufe 2, nur veränderte Pixel) · **V** = eigene Variante (Stufe 3) · **P** = vorhandenes Penzilla-Original (z. B. BareTree, Interior-State2) · **E** = Effekt (VFX, animiert) · – = nicht sinnvoll.

## 1. Die 12 Grundzustände

| # | Zustand | Bedeutung | Typische Ursache (Simulation) |
|---|---|---|---|
| 1 | Neu | frisch gebaut/gestrichen, leicht gesättigt | Bau abgeschlossen (< 7 Tage) |
| 2 | Gepflegt | Original-Penzilla-Look | regelmäßige Instandhaltung |
| 3 | Normal benutzt | erste Gebrauchsspuren | normale Nutzung |
| 4 | Leicht verschmutzt | flache Schmutzflecken, Laufspuren unter Fenstern | Instandhaltung hinkt leicht nach |
| 5 | Vernachlässigt | ausgeblichen, Flecken, abblätternde Farbe | länger keine Instandhaltung |
| 6 | Stark heruntergekommen | + Risse, einzelne kaputte Fenster, Dachloch | lange vernachlässigt, Leerstand |
| 7 | Beschädigt | Risse, kaputte Fenster, Dachlöcher | Unfall, Sturm, Konflikt |
| 8 | Schwer beschädigt | + eingestürzte Ecke, Trümmer | schwerer Schaden |
| 9 | Ausgebrannt | verkohlt, Ruß, Fenster schwarz, Dachstuhl offen | Brand beendet |
| 10 | Zerstört | Mauerreste, Trümmer | Einsturz |
| 11 | Ruine | Reste, ausgebleicht, überwuchert | zerstört + lange ungenutzt |
| 12 | Restauriert | wie neu, sichtbar ausgebesserte Stellen | Wiederaufbau/Sanierung |

Zusätzlich (keine Stufe, sondern Ebene): **brennt** (E: Flammen, Rauch, Funken), **im Bau** (E: Gerüst/Staub/Baufortschritt – Gerüst-Grafik fehlt, siehe Prioritäten), **Wetter** (Schnee, Nässe, Frost), **Nutzung** (Licht an/aus, belebt).

## 2. Gruppen je Kategorie

| Gruppe (Inventar) | Anzahl Dateien | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | Wetter/Nutzung |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **G – Gebäude** (Wohnen, öffentlich, Gewerbe, Gastronomie) | 404 | S | P | S | S | S | S+O | O | V | V | V | V | S | Schnee V/O, Licht (Fenster nachts) S, brennt E |
| **T – Gebäudeteile** (RPG-Ebenen: Wand, Dach, Tür, Fenster, Markise, Schild) | 248 | S | P | S | S | S | O | O | V | V | – | – | S | Markise: zerrissen V, Schild verblasst S |
| **S – Straßen/Wege/Boden** | 82 | – | P | S | S (verschmutzt) | – | O (Risse) | O (Schlaglöcher) | O (Trümmer) | O (Ruß) | – | O (überwuchert) | S | Pfützen O, Schlamm O, Schnee O, Frost O, Nässe S |
| **V – Vegetation** | 82 | S (gesund) | P | – | – | O/S (trocken) | – | – | – | V (verbrannt) | V (gefällt/Stumpf)* | – | – | abgestorben **P** (BareTree1–3), Schnee V, Herbst S, Wind E (Blätter) |
| **M – Stadtmöbel** (Bank, Hydrant, Schild, Mülleimer, Haltestelle) | 54 | S | P | S | S | S (verwittert) | V (rostig) | V (beschädigt) | – | V | V (umgestürzt/zerbrochen) | – | S | Schnee O |
| **L – Beleuchtung** (Laternen, Leuchten) | 6 + Lampenteile | S | P | S | S | S | V (rostig) | V (Glas kaputt, Funken E) | – | V | V (umgestürzt) | – | S | an/aus **P** (On/Off), flackernd E |
| **F – Fahrzeuge** | 116 | – | P | S (verschmutzt) | S | V (verlassen) | V | V | – | V (ausgebrannt) | V (Wrack) | – | – | Licht-/Radanimation **P** (AnimationSheets) |
| **Z – Zäune** | 33 | – | P | S | S | S | O (Lücken) | O | – | V | V | – | – | Schnee O |
| **D – Dekoration** | 82 | – | P | S | S | S | – | O | – | V | – | – | – | Animation **P** (Windrad, Ventilator) |
| **I – Innenausstattung** (Möbel, Küche, Bad, Geräte) | 486 (+ Sammelblätter) | – | P | S | S (verschmutzt) | S (abgenutzt) | – | V (kaputt) | – | V (verbrannt) | – | – | – | **in Benutzung P** (Penzilla FurnitureState2: Licht an, Kamin brennt, Kühlschrank offen, Spüle voll), Farbvarianten P |
| **R – Raum** (Böden, Wände, Türen, Fenster innen) | 3 Sammelblätter | – | P | S | S | S (Flecken) | O (Wasserflecken, abblätternd) | O (Löcher) | – | V | – | – | – | Türen offen/zu **P** |
| Figuren, Oberfläche, PBR-Material | 6 154 | Figuren erhalten **keine** Verfallszustände (Kleidung/Animation statt dessen); UI und PBR-Material ohne Zustände |

\* Stumpf/gefällter Baum: keine Penzilla-Vorlage → später eigene Variante oder weiteres Penzilla-Paket.

## 3. Grundregeln
1. **Original vor Ableitung:** Existiert in Penzilla eine passende Grafik (BareTree, StreetLampOn/Off, FurnitureState2, Türen offen, Fahrzeug-Lichtanimation), wird sie verwendet.
2. **Kleine Veränderungen** (Schmutz, Ausbleichen) per **Shader**, **lokale Schäden** per **Overlay**, **Formänderungen** (Einsturz, Ausbrennen, Umstürzen) als **eigene Variante**.
3. **Effekte** (Feuer, Rauch, Regen, Schnee, Funken, Staub) sind **eigene Penzilla-artige VFX** (assets/vfx) und überlagern jeden Zustand.
4. Ein Zustand ist eine **Darstellung** des Simulationszustands, kein eigenes Spielsystem (siehe [TECHNICAL_INTEGRATION.md](TECHNICAL_INTEGRATION.md) §5).
