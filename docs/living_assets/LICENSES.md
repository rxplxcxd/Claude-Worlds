# Lizenzen – Penzilla-Grafiken und abgeleitete Zustände

Stand **24.11.2026**. Ziel: dokumentieren, **welche Bearbeitungen und welche Weitergabe im Rahmen des Spiels erlaubt sind**, was belegt und was noch offen ist. Keine Rechtsberatung – maßgeblich ist der Lizenztext von Penzilla.

## 1. Was geprüft wurde

| Quelle | Inhalt | Belegt? |
|---|---|---|
| Produktseiten auf itch.io (Giant City Builder, Isometric RPG Buildings, Top-Down Retro Interior, Ultimate Protagonist/Hero Creator, Giant Basic GUI) – am 24.11.2026 abgerufen | Abschnitt „**Royalty free and commercial use – Once purchased (see also licence)**“; jede Seite listet als Download-Datei für Käufer **`PenzillaDesign_StandardLicense.pdf` (86 kB)** | ja, Seitentext |
| Heruntergeladene ZIP-Archive (MEGA-Ordner des Projektinhabers) | **keine** Lizenzdatei enthalten – das PDF ist ein **separater** Download auf itch.io | ja, geprüft (Dateiliste aller 6 Archive) |
| Antwort von Penzilla in den Kommentaren (itch.io, Beitrag 13196728, Top-Down Retro Interior) | „Yes, you can use it for commercial projects, as long as you credit me with ‚Graphics created by Penzilla Design'." · „Redistribution (like in logos, asset packs, or reselling) is not allowed." · „The license is for one project per purchase." · „The pack must be purchased at the suggested price for commercial use to be allowed." | ja, wörtlich gelesen |
| Weitere Kommentare auf dem Penzilla-Profil | sinngemäß: Änderungen mit Namensnennung erlaubt; Originaldateien nicht weitergeben oder in andere Asset-Pakete aufnehmen | **nur sinngemäß** (Zusammenfassung, nicht wörtlich geprüft) |

**Das Lizenz-PDF selbst liegt weiterhin nicht vor.** Es kann nur vom Käufer heruntergeladen werden: itch.io → *My Library* → jeweiliges Paket → `PenzillaDesign_StandardLicense.pdf`. Bitte ablegen (z. B. im privaten MEGA-Ordner) – **nicht** ins öffentliche Repository, falls das PDF selbst nicht zur Weitergabe bestimmt ist.

## 2. Einordnung nach heutigem Kenntnisstand

| Handlung | Einschätzung | Grundlage |
|---|---|---|
| Penzilla-Grafik im eigenen kommerziellen Spiel verwenden | **erlaubt** (nach Kauf zum Mindestpreis) | Seitentext + Penzilla-Antwort |
| Grafiken **bearbeiten** (Zustände: Schmutz, Schäden, Ruinen, Schnee …) für die Nutzung **im Spiel** | **sehr wahrscheinlich erlaubt** (sinngemäße Aussage „Modifications are allowed with proper credit") – **bis zur Prüfung des PDF als offen markiert** | Kommentar (sinngemäß) |
| Namensnennung | **erforderlich**: „Graphics created by Penzilla Design" (bei Bearbeitungen „Based on graphics by Penzilla Design") → Abspann/Impressum im Spiel nötig (**noch nicht umgesetzt**) | Penzilla-Antwort |
| Rohdateien oder abgeleitete Einzeldateien **weitergeben** (Asset-Paket, öffentliches Repository, Download) | **nicht erlaubt** | „Redistribution … is not allowed" |
| Grafiken als Teil eines **ausgelieferten Spiels** (Web-Build) | übliche Nutzung „im Projekt" – **aber:** in einem Web-Build sind die Bilddateien technisch abrufbar. Ob das als Weitergabe gilt, regelt nur das PDF → **offen** | – |
| Nutzung in mehreren Projekten | eine Lizenz **pro Projekt** – WORLDS gilt als **ein** Projekt | Penzilla-Antwort |

## 3. Was das Projekt heute tut (Schutzmaßnahmen)
1. **Keine** Penzilla-Datei und **keine** abgeleitete Zustandsdatei im öffentlichen Repository: `assets/penzilla/` ist git-ignoriert; Kontaktbögen und Materialkarten liegen nur im privaten Arbeitsordner bzw. wurden direkt an den Projektinhaber übergeben.
2. Im Repository stehen nur **Metadaten** (Dateinamen, Maße, Kategorien im Inventar) und **Werkzeuge** (Python-Skripte, die aus den gekauften Archiven lokal/in CI erzeugen).
3. Die **Originaldateien bleiben unverändert** (nur gelesen); alle Zustände sind separate, neu erzeugte Dateien.
4. Eigene VFX (`assets/vfx/`) sind **projekteigen** und frei verwendbar.

## 4. Offene Punkte (vor einer Veröffentlichung der abgeleiteten Grafiken)
| # | Punkt | Wer |
|---|---|---|
| L1 | `PenzillaDesign_StandardLicense.pdf` herunterladen und bereitstellen | Projektinhaber |
| L2 | PDF prüfen: Bearbeitung erlaubt? Auslieferung in einem **Web-Build** (abrufbare PNGs) erlaubt? Pflicht zur Verschlüsselung/Packung? | gemeinsam, nach L1 |
| L3 | Namensnennung „Graphics created by Penzilla Design / Based on graphics by Penzilla Design" im Spiel (Abspann/Info) | Umsetzung nach Freigabe |
| L4 | **Bereits heute** veröffentlicht der GitHub-Pages-Build die importierten Penzilla-Grafiken als Teil des Web-Spiels (seit Phase 1). Die **abgeleiteten Zustände** sind dort **nicht** enthalten (werden in CI nicht erzeugt). Vor dem Aufnehmen der Zustände in den öffentlichen Build L2 klären. | Entscheidung Projektinhaber |
| L5 | Bei Bedarf Penzilla direkt fragen (Kontakt laut Seite: PenzillaDesign@gmail.com) – **nur durch den Projektinhaber** | Projektinhaber |

## 5. Weitere Quellen
- Kenney- und OpenGameArt-Effekte: CC0 (geprüft, siehe [VFX_SOURCES.md](VFX_SOURCES.md)), nicht eingebunden.
- CC0-Innenausstattung (Kenney, OpenGameArt): siehe [ASSET_INVENTORY.md](../ASSET_INVENTORY.md) §5.
- „Stylized Grass & Dirt": Hersteller/Lizenz unbekannt (nur Editor-Hintergrund) – siehe ASSET_INVENTORY.
