# Versionen von WORLDS

## Eine Quelle
`data/version.json` ist die **einzige** Stelle, an der die Version festgelegt wird:

| Feld | Bedeutung | Beispiel |
|---|---|---|
| `product` | sichtbare Produktversion (Spieler:innen, Ladebildschirm, Menü) | `v0.1` |
| `technical` | technische Version (Spielstand-/Engine-Kompatibilität, `project.godot` → `application/config/version`) | `0.6.0` |
| `channel` | Entwicklungsstand / später Veröffentlichung | `Entwicklungsstand` |
| `history` | Liste aller Produktversionen mit Datum, technischer Version und Kurzbeschreibung | – |

`tools/version/sync_version.py` überträgt `technical` nach `project.godot` (ein Test prüft die Gleichheit). Mit `--build <web_dir> <commit>` schreibt es zusätzlich
- `data/build_info.json` (vom Spiel gelesen: Commit, Build-Zeit – nicht im Repository),
- `<web_dir>/version.json` (vom **Ladebildschirm** gelesen, bevor die Engine startet).
Die GitHub-Action ruft das bei jedem Build mit dem Commit-SHA auf. So ist jeder veröffentlichte Build eindeutig einer Version **und** einem Commit zugeordnet.

## Wo sie sichtbar ist
- **Ladebildschirm (Web/PWA):** unten „WORLDS v0.1 · Build 0.6.0 (Commit)“ (Skript im HTML-Kopf der Web-Vorlage, liest `version.json`).
- **Menü:** Titel „WORLDS v0.1 · Menü“ und unten die vollständige Zeile mit Kanal, technischer Version und Commit.
- Code: `WorldsVersion.short_label()` / `full_label()` (`scripts/core/worlds_version.gd`).

## Klarstellung des Projektinhabers (25.11.2026)
- Die **sichtbare Produktversion** beginnt mit **v0.1** und steht auf dem Ladebildschirm und im Menü.
- Sie wird **nicht** erhöht, nur weil weitergearbeitet wurde – eine neue Produktversion gibt es erst für einen vom Projektinhaber **freigegebenen** Entwicklungsstand.
- Die **technische Build-Version** (`technical`, z. B. 0.8.0) und der Commit des Builds werden unabhängig davon geführt und zeigen jeden Arbeitsstand an.

| Produktversion | Technische Builds | Stand |
|---|---|---|
| v0.1 | 0.6.0, 0.7.0, 0.8.0, 0.8.1, 0.9.0, 0.10.0, 0.11.0 | Living World, Phase 4, Gameplay-Polishing, Concordium – Abnahme ausstehend |

## Strategie
- Die sichtbare Reihe beginnt am 25.11.2026 mit **v0.1** (Stand: Living World vertieft, Weltautorität, Phase 4 in Arbeit, Gameplay-Polishing).
- **v0.2, v0.3 …**: jeder vom Projektinhaber abgenommene, relevante Entwicklungsstand (in der Regel eine abgeschlossene Phase oder ein größeres Arbeitspaket). Kleine Korrekturen dazwischen erhöhen nur `technical` (z. B. 0.6.1), nicht die Produktversion.
- `technical` folgt Semantic Versioning: Minor bei neuen Systemen/Speicherschema, Patch bei Korrekturen.
- **v1.0** erst mit der Freigabe zum regulären Spielbetrieb (dann werden auch die Entwicklungshinweise im Spiel entfernt bzw. in eine Versionsübersicht verschoben – siehe ROADMAP).

## Verhältnis zur bisherigen Historie
Bis 0.5.0 gab es nur technische Versionen (CHANGELOG, `project.godot`); **Git-Tags existierten nicht**. Nichts wurde umbenannt oder umgeschrieben: 0.1.0–0.5.0 bleiben als technische Versionen im CHANGELOG. Die sichtbare Produktreihe ist neu und beginnt bei v0.1 = technisch 0.6.0.
Empfehlung: bei jeder Produktversion einen Git-Tag `v0.x` auf den abgenommenen Commit setzen (ab v0.1, nach Freigabe durch den Projektinhaber).
