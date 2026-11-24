# PERFORMANCE

## 1. Zielplattform
iPhone (iOS Safari, WebGL 2, begrenzter Speicher ~1–1,5 GB pro Tab, thermisches Drosseln). Ein Desktop-Build ist **kein** ausreichender Nachweis.

## 2. Maßnahmen in Phase 1 [IMPLEMENTIERT]
| Maßnahme | Wirkung |
|---|---|
| GL Compatibility Renderer, keine 3D-Szene | geringste GPU-Last |
| Web-Export ohne Threads | kein SharedArrayBuffer, stabil auf iOS |
| Boden wird **einmal** gezeichnet (Canvas-Befehle gecacht) | 784 Kacheln ohne Kosten pro Frame |
| Gebäude/Props zeichnen nur bei Änderung (`queue_redraw` beim Aufbau) | keine Per-Frame-Zeichnung |
| Nur Laternen haben `_process` (Lichtstärke) | minimale Skriptlast |
| Spielfigur zeichnet nur beim Laufen neu | |
| Kollision: einfache Polygone, kein Navigationsmesh | |
| Tag/Nacht per `CanvasModulate` (1 Uniform) | keine 2D-Lichter |
| MSAA aus, Antialiasing nur an Linien | |
| Lokale Speicherung nur stündlich (Spielzeit) | wenige IndexedDB-Schreibvorgänge |
| Logische Auflösung 960×540 / 540×960 | UI lesbar, Rendering skaliert mit Pixeldichte |

Gemessen (lokal, Headless-Chromium mit Software-GL/SwiftShader): Start ohne Konsolenfehler in Desktop-, iPhone-Hoch- und -Querformat-Emulation. **Echte FPS-Werte auf dem iPhone fehlen** → Menü „Leistungsanzeige“ beim Test einschalten. **[OFFEN]**

## 3. Simulations- und Darstellungs-LOD [GEPLANT]
| Stufe | Umfang | Technik |
|---|---|---|
| **Aktiv** (aktuelle Siedlung, Umkreis des Spielers) | volle Szene, Navigation, Animation, Interaktion | Godot-Knoten |
| **Nah** (restliche Siedlung, Nachbarorte) | reduzierte Darstellung, NPCs als Daten mit Stunden-Takt | Daten + Sprites ohne Logik |
| **Fern** (andere Siedlungen der Region) | abstrahierte Simulation (Tagesbilanz) | reine Daten |
| **Weit** (andere Kontinente) | ereignisbasierte Fortschreibung | Ereignisse/Snapshots |

Regeln: Das Öffnen der Weltkarte lädt **keine** Siedlungsszenen; die Karte zeigt aggregierte Daten. Offline-Zeit wird analytisch fortgeschrieben (z. B. Produktion = Rate × Δt, begrenzt durch Lager/Personal), nicht Sekunde für Sekunde simuliert.

## 4. Budgets (Richtwerte für spätere Phasen) [GEPLANT]
- ≤ 150 Draw Calls in der aktiven Siedlung, Sprite-Atlanten ≤ 2048×2048.
- ≤ 60 aktive animierte NPCs gleichzeitig sichtbar; weitere als Hintergrund-NPCs.
- Texturen gesamt ≤ 128 MB GPU auf iPhone.
- Downloadgröße Erststart ≤ 60 MB.

## 5. Offene Optimierungen [OFFEN]
- Eigene Web-Export-Templates ohne 3D/unnötige Module (wasm deutlich kleiner).
- Ladeanzeige/Startbild im PWA-Stil.
- Messung auf echten Geräten (iPhone SE/älter als Untergrenze festlegen).
