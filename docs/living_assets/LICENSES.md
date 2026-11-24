# Lizenzen – verbindliche Auswertung

Stand **24.11.2026**. Grundlage: **`PenzillaDesign_StandardLicense.pdf`, „Updated Dec. 2024“** (3 Seiten, vom Projektinhaber bereitgestellt, vollständig gelesen) sowie `LICENSE.pdf` von Cooked FX. Keine Rechtsberatung; maßgeblich sind die Originaltexte. Das PDF selbst liegt **nicht** im Repository (privat beim Projektinhaber).

## 1. Penzilla Standard Licence – Kernaussagen (sinngemäß, Abschnittsnummern wie im PDF)

| Abschnitt | Inhalt | Bedeutung für WORLDS |
|---|---|---|
| General usage 1 – Royalty free | private und kommerzielle Projekte lizenzfrei, **sofern der Ersteller genannt wird**: Pflichtnennung **„Graphics created by Penzilla Design“** (optional Link zum Paket); sichtbar in Credits, Dokumentation oder einem anderen zugänglichen Ort im Projekt | **erfüllt seit 0.5.0**: Menü → *Mitwirkende & Lizenzen* + `CREDITS.md` |
| General usage 2 – Usage | erlaubt in Spielen, Animationen, Videos, **Websites**, Anwendungen | Web-Spiel (GitHub Pages, PWA) ist eine erlaubte Nutzungsart |
| General usage 3 | nicht in Logo oder Marke ohne Erlaubnis | WORLDS-Logo/Icon ist eigene Arbeit – einhalten |
| General usage 4 / Disclaimers 4 – Project limitation | **ein Projekt pro Kauf** (ein Spiel, ein Video oder eine Website); weitere kommerzielle Projekte erfordern weitere Käufe | WORLDS = **ein** Projekt; Testgalerien sind Teil desselben Projekts |
| Commercial 1 – Non-transferable | Lizenz gilt nur für den **ursprünglichen Käufer** | Käufer = Projektinhaber; Mitarbeit am selben Projekt ist Nutzung durch den Käufer |
| Commercial 2 – Redistribution | nur zur Nutzung; **kein Weiterverkauf und keine Weitergabe der enthaltenen Dateien** | keine Penzilla-Dateien (original oder bearbeitet) im öffentlichen Repository, keine Downloads einzelner Dateien |
| Commercial 3 | nicht in anderen Asset-Paketen, Vorlagen oder Design-Ressourcen | WORLDS ist kein Asset-Paket – einhalten (z. B. keine Veröffentlichung der Zustandsbilder als Sammlung) |
| Commercial 4 – Modifications | **Bearbeitungen erlaubt**, solange die Pflichtnennung in jedem öffentlichen Projekt steht; **die Bearbeitungen müssen vollständig und deutlich neben der Pflichtnennung aufgelistet werden** | Liste in `data/credits.json` (im Spiel angezeigt) und `CREDITS.md` – bei jeder neuen Bearbeitungsart ergänzen |
| Commercial 5 – Public projects | bei öffentlich verfügbaren Projekten **muss ein Link o. Ä. an PenzillaDesign@gmail.com gesendet werden** | **offen – nur der Projektinhaber** kann das tun (GitHub-Pages-Adresse senden) |
| Disclaimers 1 | Haftungsausschluss, Freistellung von Penzilla | zur Kenntnis |
| Disclaimers 3 – Support | Support nur für Unity | – |
| Disclaimers 6/10 – Revocation/Validity | Lizenz gilt unbefristet bei Einhaltung; Widerruf bei Verstoß | Einhaltung dokumentieren (diese Datei) |
| Disclaimers 8 | dänisches Recht | – |
| Disclaimers 9 – **AI** | Assets dürfen **nicht zur Erstellung von KI-/ML-Datensätzen oder -Modellen** verwendet werden | WORLDS erzeugt Zustände **regelbasiert** (Bildverarbeitung, kein Training, keine Datensätze). Keine Penzilla-Grafik in Trainingsdaten, Feinabstimmungen oder als Vorlage für Bild-Generatoren verwenden. |

## 2. Verbindliche Einordnung für WORLDS

| Fall | Erlaubt? | Bedingungen |
|---|---|---|
| **Originalgrafiken im Spiel** (Web-Build, PWA, später App) | **ja** | Pflichtnennung sichtbar; ein Projekt; Projektinhaber ist Käufer |
| **Bearbeitungen** (Skalieren, Zusammensetzen, Einfärben, Zuschneiden) | **ja** | jede Bearbeitungsart in der Liste neben der Pflichtnennung (heute 6 Punkte) |
| **Abgeleitete Zustandsvarianten** (Living Assets) | **ja, als Bearbeitung** | in der Liste aufgeführt (Punkt 6); Originale bleiben unverändert; nur als Teil des Spiels, **nicht** als eigenständige Sammlung, nicht als Asset-Paket |
| **Veröffentlichung im Web (GitHub Pages)** | **ja** – Websites/Spiele sind erlaubte Nutzung; die Grafiken liegen im gepackten Spiel (`index.pck`), nicht als einzelne Downloads | Pflichtnennung im Spiel (✅ ab 0.5.0), **Link an Penzilla senden (offen)** |
| Penzilla-Dateien im **öffentlichen Git-Repository** | **nein** (Weitergabe der Dateien) | bleibt git-ignoriert; CI holt sie aus dem privaten MEGA-Ordner (Secret) |
| Kontaktbögen/Vorschaubilder mit Penzilla-Grafik öffentlich teilen | **nein** (außerhalb des Projekts = Weitergabe) | nur privat an den Projektinhaber |
| Verwendung in einem **zweiten** Projekt | **nein** | erfordert weiteren Kauf |
| Penzilla-Grafik in **KI-Training/-Datensätze** | **nein** | auch nicht als Vorlage für Bild-Generatoren |

### Bereits vorhandene Dateien im GitHub-Pages-Build
- Der seit Phase 1 veröffentlichte Build enthält die importierten Penzilla-Grafiken (verkleinert, RPG-Läden zusammengesetzt, Figurenebenen zugeschnitten) **gepackt in `index.pck`**. Das ist **Nutzung in einer Website/einem Spiel** und damit erlaubt.
- **Bis 0.4.2 fehlte die Pflichtnennung im Spiel** (es gab nur „Penzilla (penzilla.itch.io) – lizenziert“ im Menü und keine Bearbeitungsliste). Ab **0.5.0** steht beides im Menü → *Mitwirkende & Lizenzen*. Mit dem nächsten Deployment (Merge nach `main`) ist der öffentliche Build konform.
- Die abgeleiteten Living-Assets-Zustände sind **nicht** im öffentlichen Build (werden in der CI nicht erzeugt). Wenn sie später aufgenommen werden: Punkt 6 der Bearbeitungsliste ist bereits vorhanden.
- **Offen (Projektinhaber):** Link zum öffentlichen Spiel an PenzillaDesign@gmail.com senden (Commercial 5).

## 3. Cooked FX (The Cooked Works) – LICENSE.pdf v1.0, Oktober 2026
| Erlaubt | Nicht erlaubt |
|---|---|
| unbegrenzt viele Projekte, kommerziell; Bearbeitung jeder Art; fertige Produkte verteilen – „auch wenn ein Spieler die Dateien technisch extrahieren könnte“ | Dateien einzeln weitergeben/verkaufen – original oder bearbeitet –, **auch nicht in ein Repository**; Aufnahme in Asset-Pakete/Vorlagen; als eigene Arbeit ausgeben |
| Namensnennung **nicht** erforderlich (erwünscht: „Effects: Cooked FX by The Cooked Works“) | |

→ wie Penzilla behandeln: privat importiert (`assets/thirdparty/cooked_fx/`, git-ignoriert). Bewertung: [COOKED_FX_EVALUATION.md](COOKED_FX_EVALUATION.md). Hinweis: laut Hersteller KI-gestützt erstellt.

## 4. Weitere Quellen
- Kenney- und OpenGameArt-Effekte/-Möbel: CC0 (geprüft), siehe [VFX_SOURCES.md](VFX_SOURCES.md) und [ASSET_INVENTORY.md](../ASSET_INVENTORY.md) §5.
- „Stylized Grass & Dirt“ (Editor-Hintergrund): Hersteller/Lizenz im Paket nicht angegeben – vom Projektinhaber bereitgestellt; **Lizenz offen** (Projektinhaber).

## 5. Offene Punkte
| # | Punkt | Wer |
|---|---|---|
| L1 | ~~Lizenz-PDF bereitstellen~~ | ✅ erledigt (24.11.2026) |
| L2 | Link zum öffentlichen Spiel an PenzillaDesign@gmail.com senden | Projektinhaber |
| L3 | ~~Namensnennung + Bearbeitungsliste im Spiel~~ | ✅ 0.5.0 (nach Deployment öffentlich) |
| L4 | Bei neuen Bearbeitungsarten `data/credits.json` ergänzen | laufend |
| L5 | Lizenz „Stylized Grass & Dirt“ klären | Projektinhaber |
| L6 | Cooked FX: Entscheidung über Verwendung (KI-gestützte Herstellung), private CI-Quelle | Projektinhaber |
