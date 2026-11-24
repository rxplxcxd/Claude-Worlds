# PERFORMANCE

## 1. Zielplattform
iPhone (iOS Safari, WebGL 2, begrenzter Speicher ~1–1,5 GB pro Tab, thermisches Drosseln). Ein Desktop-Build ist **kein** ausreichender Nachweis.

## 2. Maßnahmen in Phase 1 [IMPLEMENTIERT]
| Maßnahme | Wirkung |
|---|---|
| GL Compatibility Renderer, keine 3D-Szene | geringste GPU-Last |
| Web-Export ohne Threads | kein SharedArrayBuffer, stabil auf iOS |
| Boden-Zeichenbefehle werden **einmal** aufgezeichnet (Canvas-Befehle gecacht) | keine Skriptkosten pro Frame – **aber** die GPU zeichnet weiterhin jeden Frame alle Kacheln, ohne Culling und mit Batch-Brüchen bei Texturwechseln (Korrektur 24.11.2026, siehe §6.1) |
| Gebäude/Props zeichnen nur bei Änderung (`queue_redraw` beim Aufbau) | keine Per-Frame-Zeichnung |
| Laternen, NPCs und Figuren haben schlanke `_process` (Licht, Frame-Wechsel, Blinzeln); NPC-Präsenz nur alle 0,5 s geprüft | geringe Skriptlast |
| Figuren im **Composite-Modus**: Ebenen per SubViewport einmal zu 2 Texturen pro Animation zusammengesetzt, gecacht (gleiches Aussehen = gleicher Cache) | ~3 Sprites statt ~12 je Figur; 12 NPCs + Spieler ≈ 39 Sprites |
| Figuren-Ebenen beim Import auf 40 % verkleinert und quantisiert (151 Dateien ≈ 3,8 MB) | Download/Speicher klein |
| Verdeckung: **ein** gemeinsames Shader-Material, Stärke im Modulate-Alpha | Batching bleibt erhalten |
| Laternenlicht: Verlaufs-Texturen + additive Polygone statt `Light2D` | keine Licht-Passes im Compatibility-Renderer |
| Straßenmobiliar/NPC-Plätze einmal beim Aufbau berechnet | keine Laufzeitkosten |
| Spielfigur zeichnet nur beim Laufen neu | |
| Kollision: einfache Polygone, kein Navigationsmesh | |
| Tag/Nacht per `CanvasModulate` (1 Uniform) | keine 2D-Lichter |
| MSAA aus, Antialiasing nur an Linien | |
| Lokale Speicherung nur bei Änderungen (Gründung, Figur) und beim Verlassen | wenige IndexedDB-Schreibvorgänge |
| Logische Auflösung 960×540 / 540×960 | UI lesbar, Rendering skaliert mit Pixeldichte |

**Phase 2 (Globus):**

| Maßnahme | Wirkung |
|---|---|
| Planet gebacken statt erzeugt | Laden 81–130 ms (Desktop/Chromium) statt ~1,4 s Erzeugung |
| Planet wird erst beim Öffnen der Karte / Gründen geladen | Start in der Siedlung kostet nichts zusätzlich |
| Globus = 1 Kugel (96×48 Segmente) + Atmosphäre + Sternenkugel, unbeleuchteter Shader | 3 Draw-Calls; 7 Texturzugriffe pro Pixel |
| Texturen 512×256 (Farbe RGB8, Höhe L8, IDs RGB8) + LUT 158×1 | < 1 MB Grafikspeicher |
| Beschriftung in einem `_draw()` mit Überlappungs-Ausdünnung | keine Label-Knoten pro Region |
| Siedlungsszene beim Öffnen der Karte angehalten (`PROCESS_MODE_DISABLED`) und ausgeblendet | keine doppelte Last |

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

## 6. Weg zu 60 FPS auf dem iPhone [ANALYSE + PLAN, nicht umgesetzt]

Ausgangslage: Der Projektinhaber hat in ersten Tests **~30 FPS** gemessen (Gerät/Szene noch zu dokumentieren). Ziel: **60 FPS** bei gleicher Bildqualität. Belastbar sind nur Messungen auf dem **echten iPhone**.

### 6.1 Wahrscheinliche Ursachen im heutigen Code (Analyse, noch nicht gemessen)
| # | Befund | Warum teuer |
|---|---|---|
| 1 | **Volle Geräteauflösung:** `canvas_items`-Streckung + HiDPI (Standard) → auf einem iPhone mit 3× Pixeldichte ≈ 2532 × 1170 Pixel | Pixel-Füllrate; große transparente Gebäude-Sprites, Bodenkacheln mit transparenten Rändern, additive Lichter, Durchsicht-Shader → viel Überzeichnung |
| 2 | **Boden = ein einziges CanvasItem** mit allen Kacheln, abwechselnde Texturen (Gras, Straßen-Varianten, Gehweg, Platten) | Kein Culling (das Objekt ist immer „sichtbar“), Batches brechen bei jedem Texturwechsel → viele Draw-Calls |
| 3 | **Einzeltexturen** für jedes Gebäude/Prop (kein Atlas); Y-Sortierung mischt sie | Texturwechsel → Draw-Calls |
| 4 | Jede Laterne/NPC/Figur hat `_process` (Licht-Modulation, Blickrichtung, Animation) | Bei Hunderten Objekten Skriptlast pro Frame |
| 5 | Verdeckungsprüfung iteriert pro Frame über alle Verdecker | wächst mit der Stadtgröße |
| 6 | 2D-Texturen werden verlustfrei importiert (RGBA8 im Grafikspeicher), Mipmaps +33 % | Speicher/Bandbreite; VRAM-Kompression ist im Export zwar aktiviert, greift aber nur für als „VRAM“ importierte Texturen |
| 7 | Globus-Shader mit ~11 Texturzugriffen pro Pixel auf voller Auflösung | Füllrate beim Kartenöffnen |

### 6.2 Maßnahmen (nach erwartetem Nutzen)
| Maßnahme | Technik in Godot 4 (Compatibility) | Qualität |
|---|---|---|
| **Dynamische Auflösung** | Szene in einem `SubViewport` mit Skalierung 0,67–1,0 rendern, UI in voller Auflösung darüber; Skalierung nach gemessener Frame-Zeit regeln (z. B. 2× statt 3× Pixeldichte) | UI bleibt scharf; Welt leicht weicher, bei Retina kaum sichtbar |
| **Boden in Chunks** (16 × 16 Kacheln) **+ Textur-Atlas** – oder `TileMapLayer` mit Atlas-Quelle | Culling pro Chunk, 1 Batch pro Chunk; optional statische Chunks einmal in eine Textur „backen“ | unverändert |
| **Sprite-Atlanten** für Gebäude/Props beim Import (2048²) | weniger Texturwechsel | unverändert |
| **Frustum-Culling** | 2D-Culling von Godot greift pro CanvasItem automatisch – Voraussetzung sind kleine Objekte (Chunks); `VisibleOnScreenNotifier2D` stoppt `_process`/Animation außerhalb | unverändert |
| **Occlusion Culling** | In 2D-Isometrie bringt klassisches Occlusion Culling wenig; stattdessen Innenräume/verdeckte Ebenen gar nicht erst laden | – |
| **Rendering-LOD** | Weit herausgezoomt: NPCs als einfache Sprites ohne Ebenen-Zusammensetzung, Straßenmobiliar ausblenden, Lichtkegel weglassen | bei kleiner Darstellung nicht sichtbar |
| **Simulations-LOD** | Nur sichtbare NPCs animieren (S0), Rest als Daten (S1) – [SIMULATION_ARCHITECTURE.md](SIMULATION_ARCHITECTURE.md) | unverändert |
| **Effiziente NPC-Verarbeitung** | Zentrale Aktualisierung in Gruppen statt `_process` je NPC (z. B. 1/4 der NPCs pro Frame), gemeinsame Animationsuhr, Composite-Texturen (vorhanden) | unverändert |
| **Licht/„Schatten“** | Keine `Light2D`/Schatten (bewusst); Laternenlicht als Verlaufs-Sprites (vorhanden); Helligkeit über einen globalen Shader-Parameter statt `_process` pro Laterne | unverändert |
| **Texturkompression** | Große Gebäude-/Bodentexturen als VRAM (ETC2/ASTC) importieren und Kanten prüfen; UI und Figuren verlustfrei | geringe Artefakte möglich → Sichtprüfung |
| **Speicher** | Atlanten, nur benötigte Chunks laden, Globus-Texturen beim Schließen freigeben, Composite-Cache begrenzen (LRU) | – |
| **Bildrate begrenzen im Leerlauf** | Globus/Menüs: Rendering drosseln, wenn sich nichts bewegt (Akku, Wärme) | – |

### 6.3 Messplan
1. **Messanzeige im Spiel** (Erweiterung der FPS-Anzeige): Frame-Zeit, Draw-Calls, Objekte, Texturspeicher (`Performance`-Monitore), Auflösung.
2. **Testszenen:** Standard-Siedlung, 1-km-Stresstest (10 000 Kacheln, 300 Gebäude, 100 NPCs), Globus.
3. **Messung auf dem iPhone** (Safari, ggf. Web-Inspector über einen Mac): je Maßnahme vorher/nachher, Wärmeverhalten nach 10 Minuten.
4. Erst messen, dann optimieren – die Reihenfolge in 6.2 ist eine begründete Vermutung, kein Messergebnis.

Hinweis: iOS-Safari liefert `requestAnimationFrame` typischerweise mit 60 Hz; 60 FPS ist damit die realistische Obergrenze im Browser.
