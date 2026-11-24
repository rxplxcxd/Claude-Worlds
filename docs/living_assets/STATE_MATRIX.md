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
| 6 | Stark heruntergekommen | **Verfall ohne Gewalt:** stark ausgeblichen, großflächig abblätternder Putz (Ziegel sichtbar), **vernagelte Fenster**, Moos auf dem Dach, verrottetes/vergrautes Holz, Rost, Unkraut – **keine** frischen Risse, kein Schutt | lange vernachlässigt, Leerstand |
| 7 | Beschädigt | **frischer Schaden bei intakten Farben:** Risse ab Fensterecken, Sternrisse und Löcher im Glas, abgeplatzte Ecken, ein Dachloch mit Sparren, wenig frischer Schutt | Unfall, Sturm, Konflikt |
| 8 | Schwer beschädigt | **Teileinsturz** einer Ecke mit Balken, alle Fenster zerstört, großes Dachloch, Schuttkegel | schwerer Schaden |
| 9 | Ausgebrannt | **Mauern stehen, Dach weggebrannt** (Blick ins dunkle Innere, verkohlte Sparren), alles verkohlt, Rußfahnen, Stoff verkohlt | Brand beendet |
| 10 | Zerstört | **frischer Einsturz:** niedrige Mauerstümpfe, große Schutthaufen in den eigenen Farben, Balken, Staub – keine Pflanzen | Einsturz |
| 11 | Ruine | **alt:** stufig abgebrochenes Mauerwerk mit einer höheren Ecke, **kein Dach**, leere Öffnungen, verwittert/ausgeblichen, Schutt mit Gras, Efeu – **kein** Ruß, kein frischer Schutt | zerstört + lange ungenutzt |
| 12 | Restauriert | **Spuren der Vergangenheit je Reparaturgrad:** Grad 1 dezent (hellere Putzflicken, neue Dachziegel in anderem Ton, neue Bretter, Stoff-Flicken), Grad 2 deutlich (umrandete Flicken, viele neue Teile, neue Scheibe) | Wiederaufbau/Sanierung |

Zusätzlich (keine Stufe, sondern Ebene): **brennt** (E: Flammen, Rauch, Funken), **im Bau** (E: Gerüst/Staub/Baufortschritt – Gerüst-Grafik fehlt, siehe Prioritäten), **Wetter** (Schnee, Nässe, Frost), **Nutzung** (Licht an/aus, belebt).

## 1a. Kombinierbare Merkmale (ab Schritt G, verbindlich)
Ein Zustand ist **keine** einzelne Grafik, sondern eine **Kombination unabhängiger Merkmale**. Die 12 Grundzustände sind nur benannte Kombinationen („Presets“). Beispiel: *verschmutzt + beschädigt + teilweise ausgebrannt* = Shader Stufe 2 + Overlay `damage_1` + Overlay `fire_2` – ohne eigene Grafik.

| Merkmal | Stufen | Technik | Datei |
|---|---|---|---|
| `structure` | intact · partial · shell · collapsed · ruin (Gebäude); broken · burnt · wreck · dry · dead · algae · drained · frozen (je Profil) | eigene Basis-Variante | `base_<name>.png` |
| `wear` | 0–3 | Shader (0–3) + Overlay ab 2 (`wear_2`, `wear_3`) | `overlay_wear_N.png` |
| `damage` | 0–2 | Overlay | `overlay_damage_N.png` |
| `fire` | 0–2 (Rußspuren · teilweise ausgebrannt) | Overlay | `overlay_fire_N.png` |
| `overgrowth` | 0–2 | Overlay | `overlay_overgrowth_N.png` |
| `repair` | 0–2 (Reparaturspuren) | Overlay | `overlay_repair_N.png` |
| Wetter `snow` | 0–1 (nicht gespeichert, kommt von der Umwelt) | Overlay, auf Strukturvarianten eigenes Schnee-Overlay | `overlay_snow_1[@base].png` |

Regeln: Overlays werden gegen das **intakte Original** erzeugt und für jede Strukturvariante **vorab beschnitten** (`overlay_X@partial.png`), damit nichts über eingestürzten Teilen schwebt. Welche Overlays auf welcher Basis erlaubt sind, steht im Manifest (`allowed`); Zeichenreihenfolge: Abnutzung → Reparatur → Schaden → Brand → Bewuchs → Schnee. Laufzeit: `scripts/living/visual_state.gd` + `living_composer.gd`.

| Preset | structure | wear | damage | fire | overgrowth | repair |
|---|---|---|---|---|---|---|
| 01 Neu / 02 Gepflegt | intact | 0 | – | – | – | – |
| 03 Benutzt / 04 Leicht verschmutzt | intact | 1 | – | – | – | – |
| 05 Vernachlässigt | intact | 2 | – | – | – | – |
| 06 Stark heruntergekommen | intact | 3 | – | – | 1 | – |
| 07 Beschädigt | intact | 1 | 1 | – | – | – |
| 08 Schwer beschädigt | partial | 1 | 2 | – | – | – |
| 09 Ausgebrannt | shell | – | – | – | – | – |
| 10 Zerstört | collapsed | – | – | – | – | – |
| 11 Ruine | ruin | – | – | – | – | – |
| 12 Restauriert | intact | 0 | – | – | – | 1 (oder 2) |

## 1b. Zustände je Funktion (produziert)
Nicht jedes Asset braucht alle Zustände; entschieden wird nach **Funktion** (`tools/assets/living_assets.json`, Profile in `living_traits.PROFILES`):

| Profil | Assets | Basen | Overlays |
|---|---|---|---|
| building | 19 Gebäude (Wohnen, öffentlich, Gewerbe inkl. RPG-Läden) | partial, shell, collapsed, ruin | wear 2/3, damage 1/2, fire 1/2, overgrowth 1/2, repair 1/2, snow |
| tent | Zelt | shell (verbrannt), collapsed (zusammengefallen) | wear 2/3, damage 1, fire 1, repair 1 (Flicken), snow |
| prop | Hydrant, Mülleimer, Briefkasten, Schaltkasten, Schilder, Wasserturm, Strommast, Haltestelle, Schubkarre | broken (umgestürzt/zerbrochen) | wear 2/3 (Rost, Lackabplatzer), damage 1 (Dellen, Glasbruch), overgrowth 1, snow |
| prop_flammable | Bank, Kisten, Marktstand, Karren, Infotafel, Garten | broken, burnt | wie prop |
| lamp | 3 Laternen | broken (umgestürzt) | wear 2/3, damage 1 (Glas kaputt → aus), snow |
| vehicle | Auto, Krankenwagen, Bus (noch nicht im Spiel) | burnt, wreck | wear 2 (alt/rostig), wear 3 (verlassen), damage 1, snow |
| tree | 8 Laubbäume, 3 Tannen, 4 Büsche | dry, dead, burnt | snow |
| crop | 2 Feldpflanzen | dry, dead, burnt | – |
| fountain | Brunnen | algae, drained, frozen | wear 2, damage 1, overgrowth 1, snow |
| Bodenfamilien | Asphalt (9 Kacheln), Gehweg/Beton, Weg (9), Gras, Erde, Wasser | – | je Familie **gemeinsame** Overlays: verschmutzt, rissig, Schlaglöcher, Pfützen, Schlamm, Schnee, Frost, Laub, Müll, trocken, gefroren, Algen |
| interior | Penzilla-Möbel- und Kleinteil-Blätter (Pixel Art) | abgenutzt, verschmutzt, kaputt, verbrannt (je Möbelstück) | – (Nutzung: Penzilla-State2) |

## 2. Gruppen je Kategorie (Konzept aus Schritt B)

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
