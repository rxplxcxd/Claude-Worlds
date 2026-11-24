# WORLD_DESIGN

## 1. Setting [GEPLANT, Grundsatz bestätigt durch Masterprompt]
Ein fiktiver Planet (Arbeitsname **Aurel**, ID `pln_aurel`) nach einem großen gesellschaftlichen, politischen und wirtschaftlichen Zusammenbruch. Die Welt ist **im Wiederaufbau**, nicht leer: Es gibt Dörfer, Städte, Handelsplätze, Agrar- und Industrieregionen und neue politische Strukturen – daneben dünn besiedelte, unerschlossene Gebiete.

Tonalität: hoffnungsvoll statt düster. Ruinen sind Ressource und Geschichte, nicht Dauerbedrohung. „Aufbau-Optimismus“ ist der emotionale Kern.

## 2. Die Ursache des Zusammenbruchs – Optionen [OFFEN, Entscheidung durch Projektinhaber]

| Option | Kurzbeschreibung | Vorteile | Nachteile |
|---|---|---|---|
| **A. „Das Große Stillstehen“** – Zusammenbruch der vernetzten Infrastruktur (Energie-/Datennetze fielen über Jahre kaskadierend aus) | Hochtechnisierte Weltordnung zerfiel an ihrer eigenen Abhängigkeit | Erklärt Wissen ohne Technik, Mischung aus modernen Ruinen und Neuanfang; passt zu Energie-, Wasser-, Logistik-Gameplay; nicht gewaltzentriert | Etwas abstrakt; braucht gutes Storytelling |
| **B. Klimatische Umbrüche** – Jahrzehnte extremer Wetterlagen, verschobene Küsten | Völkerwanderungen, verlassene Regionen | Starke Geografie-Wirkung (Klimazonen, Wasser), Migration motiviert | Nähe zu realen Debatten, kann belehrend wirken |
| **C. Die Schuldenkrise der Welt** – Finanz- und Vertrauenskollaps, Staaten lösten sich auf | Institutionen verloren Legitimität | Perfekt für Wirtschafts-/Politik-Fokus; erklärt neue Währungen, Verträge, Räte | Wenig sichtbar in der Landschaft |
| **D. Kombination („Die Lange Stille“)** – Finanzkollaps löste Infrastrukturausfälle aus, verstärkt durch Wetterextreme | Mehrere Ursachen, keine einfache Schuld | Flexibel, regional unterschiedliche Geschichten möglich, offen für Lore-Entdeckungen | Muss konsistent dokumentiert werden |
| **E. Bewusst ungeklärt** | Spieler finden Fragmente, Gerüchte | Mysterium, Community-Theorien | Wenig Orientierung für Design |

**Empfehlung:** D mit offenen Details (Elemente von E): Grundlage „Die Lange Stille“, regionale Archive und Ruinen verraten nach und nach Hintergründe. Vermeidet Krieg/Seuche als Hauptmotiv (spielerfreundlicher Ton).

## 3. Weltidentität [GEPLANT]
- Eigene Kontinentformen, Namen und Kulturen; keine Kopie der Erde.
- Wiederkehrende Motive: Solar- und Windkraft, reaktivierte Bahnstrecken, Gemeinschaftswerkstätten, Tauschmärkte, Räte.
- Startregion **Ostmark-Ebene** (Kontinent West, `cnt_west`, `reg_ostmark`): fruchtbare Ebene mit Teichen – Siedlung **Lichtfeld** (Phase-1-Szene).

## 4. Kalender [OFFEN]
Aktuell 120 Spieltage pro Spieljahr (`GameClock.DAYS_PER_YEAR`). Abhängig vom gewünschten Weltrat-Rhythmus (z. B. 1 Spieljahr ≈ 1–2 Echtwochen in Multiplayer) festlegen.

## 5. Implementiert in Phase 1
Nur: Namen/IDs der Startsiedlung, Region und Welt in `lichtfeld.json`; Willkommenstext am Schwarzen Brett.
