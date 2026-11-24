# WORLD_DESIGN

## 1. Verbindliche Grundregel: Der leere Planet [IMPLEMENTIERT als Regel, Festlegung durch Projektinhaber 24.11.2026]

> **Der Planet ist zu Beginn vollständig leer.** Es gibt Natur – Kontinente, Seen, Flüsse, Gebirge, Wälder, Klimazonen, Rohstoffe – aber **keine einzige Siedlung, kein Dorf, keine Stadt und keine NPC-Bevölkerung**.
> **Leben entsteht erst durch Spieler:** Die erste Siedlung wird vom ersten Spieler gegründet. Mit jeder weiteren Person wird die Welt voller und interessanter.
> **Es gibt keine Siedlungen, die nur aus NPCs bestehen.** Jede Siedlung hat einen menschlichen Gründer und mindestens einen menschlichen Bewohner.

Diese Regel **ersetzt** Abschnitt 2 des Masterprompts („Die Welt ist jedoch nicht leer: Es existieren bereits Siedlungen, Dörfer, Städte …“).

### Ablauf für neue Spieler
| Situation | Möglichkeiten |
|---|---|
| **Erster Spieler** (Planet leer) | Keine Wahl eines Wohnorts möglich, weil keiner existiert → **gründet zwingend eine Siedlung**. |
| **Jeder weitere Spieler** | **Entweder** in eine bestehende (von Spielern gegründete) Siedlung ziehen **oder** eine eigene Siedlung gründen. Beides gleichwertig. |

### Folgen für das Gesamtdesign
- Weltkarte (Phase 2): Planet wird **nur mit Natur** erzeugt; alle Regionen starten mit Erschließungsstatus `wild`. Keine vorplatzierten Siedlungen, Straßen oder Grenzen.
- Siedlungen, Territorien, politische Einheiten, Handelsrouten, Räte entstehen **ausschließlich** aus Spieleraktivität.
- NPCs existieren nur **innerhalb** von Spielersiedlungen (z. B. als Gründungsgemeinschaft, die mit dem Gründer kommt, oder als Zuzug). NPCs gründen **keine** Siedlungen.
- Der Weltrat und Staaten entstehen erst, wenn genug Spieler da sind – die Welt „wächst“ sichtbar mit der Community.

### Technische Umsetzung in Phase 1 [IMPLEMENTIERT]
- `data/world/genesis.json`: Anfangszustand des Planeten mit `"settlements": []` und Regeln (`initial_settlements: 0`, `settlement_requires_human_founder: true`, `npc_only_settlements_allowed: false`).
- `WorldState` (Autoload): Register aller Siedlungen. `found_settlement()` verweigert jede Gründung ohne menschlichen Gründer (`plr_…`); jede Siedlung hat `founder_player_id` und `resident_player_ids` (≥ 1 Mensch).
- Lichtfeld ist **keine vorhandene Siedlung** mehr, sondern eine **Gründungsvorlage** (`data/settlement_templates/founding_basic.json`). Beim ersten Start gründet der lokale Spieler daraus seine Siedlung (Toast: „Du hast Lichtfeld gegründet – die erste Siedlung auf Aurel.“).
- Tests: Planet startet leer · Gründung ohne Gründer/NPC-Gründung wird abgelehnt · erster Start gründet genau eine Siedlung mit dir als Gründer · Neustart verwendet dieselbe Siedlung.
- Noch **nicht** in Phase 1: Standortwahl auf dem Globus und Namenswahl (Phase 2/4) – bis dahin wird automatisch an einem festen Ort gegründet.

## 2. Setting und Hintergrundgeschichte [OFFEN – neu zu entscheiden]

Der Masterprompt beschreibt Wiederaufbau nach einem Zusammenbruch. Mit dem leeren Planeten muss die Geschichte erklären, **warum es keine Siedlungen gibt**. Optionen:

| Option | Kurzbeschreibung | Vorteile | Nachteile |
|---|---|---|---|
| **A. Neue Welt nach dem Zusammenbruch** – Die alte Heimatwelt ist zusammengebrochen; Menschen kommen nach und nach auf den unberührten Planeten **Aurel** und beginnen neu. | Jede Ankunft = ein neuer Spieler. | Erklärt den leeren Planeten perfekt; „Neuanfang“ als Kernmotiv; Zuzug neuer Spieler ist Teil der Geschichte; keine Ruinen nötig | Weniger „Wiederaufbau“, mehr „Aufbau“ |
| **B. Verlassene Erde-ähnliche Welt** – Nach der „Langen Stille“ lebten Überlebende lange in Schutzräumen/abseits; der Planet ist menschenleer, Natur hat sich alles zurückgeholt. | Spieler sind die Ersten, die zurückkehren. | Ruinen als Entdeckung & Ressource, Wiederaufbau-Motiv bleibt | Ruinen dürfen nicht wie bestehende Siedlungen wirken; mehr Asset-Bedarf |
| **C. Mischung A+B** – Aurel war früher besiedelt (vor Jahrhunderten), ist heute leer; die Neuankömmlinge stammen aus der zusammengebrochenen alten Welt. | Wenige uralte Spuren als Lore. | Geheimnis + Neuanfang, Ruinen sparsam einsetzbar | Komplexer |

**Empfehlung: A** (ggf. später um vereinzelte uralte Spuren aus C ergänzen). Sie passt am saubersten zur Regel „Leben entsteht erst durch Spieler“.

Tonalität: hoffnungsvoll, Aufbau-Optimismus, keine Dauerbedrohung.

## 3. Weltidentität [GEPLANT]
- Eigene Kontinentformen, Namen und Kulturen; keine Kopie der Erde.
- Natur ist reich und vielfältig: Seen, Flüsse, Küsten, Gebirge, Wälder, Ebenen, Wüsten, Tundra, Rohstoffvorkommen.
- Regionennamen sind zunächst geografische Arbeitsnamen; **[OFFEN]**: Dürfen Gründer Regionen/Orte benennen?
- Phase-1-Gründungsort: Ostmark-Ebene (`reg_ostmark`) auf Kontinent West (`cnt_west`) – fester Platzhalter bis zur Standortwahl.

## 4. Kalender [OFFEN]
Aktuell 120 Spieltage pro Spieljahr (`GameClock.DAYS_PER_YEAR`). Abhängig vom Weltrat-Rhythmus festlegen.

## 5. Offene Fragen zur Grundregel [OFFEN – Entscheidung durch Projektinhaber]
1. **Was passiert mit einer Siedlung, wenn alle menschlichen Bewohner sie verlassen oder dauerhaft inaktiv sind?** Ohne Regel entstünde genau die verbotene „NPC-only“-Siedlung. Optionen: (a) „ruhend“ – eingefroren, keine Entwicklung, kann von einem Spieler übernommen/wiederbelebt werden; (b) Gründer bleibt Eigentümer, Siedlung ruht bis zur Rückkehr; (c) NPCs ziehen in andere Spielersiedlungen, Siedlung verfällt langsam zu einer Ruine. *Empfehlung: (b) mit Übergang in (a) nach langer Inaktivität* – passt zu „keine Bestrafung für Pausen“.
2. **Gründungsgemeinschaft:** Bleibt es bei 20–50 NPCs, die *mit* dem Gründer kommen (Masterprompt 4.2)? *Annahme bis zur Entscheidung: ja* – es ist eine Spielersiedlung, keine NPC-Siedlung.
3. **Darf ein Spieler mehrere Siedlungen gründen?** *Vorschlag: eine aktive Gründung gleichzeitig* (verhindert, dass ein Spieler den Planeten mit leeren Gründungen „besetzt“).
4. **Mindestabstand zwischen Gründungen?** *Vorschlag: ja*, damit Neuankömmlinge freie Standorte finden.
