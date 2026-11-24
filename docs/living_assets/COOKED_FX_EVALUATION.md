# Bewertung: Cooked FX – Stil „Cozy Chunky“ (The Cooked Works)

Geprüft am **24.11.2026**. Quelle: <https://the-cooked-works.itch.io/cooked-fx> (der Link in der Anfrage `thecookedworks.itch.io` existiert nicht; der Ersteller heißt `the-cooked-works`).

## 1. Paket und Bezug
| | |
|---|---|
| Paket | **Cooked FX – 40 Free Game Effects (5 Themes)**, kostenlos („Name your own price“, mit 0 € heruntergeladen – **kein Kauf**) |
| geladen | nur `Cooked_FX_FREE_Cozy_Chunky.zip` (3,7 MB) über den normalen Download-Ablauf der Seite |
| Sicherheitsprüfung | 129 Einträge: 126 PNG, 1 JSON, 2 PDF; keine absoluten Pfade, kein `..`, keine Symlinks, nichts Ausführbares; entpackt in einen eigenen leeren Ordner, nichts ausgeführt |
| Inhalt Cozy Chunky | 63 Animationen (40 Effekte, 19 davon als **Side**- und **Top-down**-Version, Blut in 3 Farben), horizontale Sprite-Strips, Zellen 128 px (1x) / 256 px (2x), **24 fps**, `anims.json` mit Frames/fps/Loop/Ansicht |
| Nicht verwechseln | **„Cooked FX 250 – Cozy Chunky“** (250 Effekte) ist **kostenpflichtig** (7,99 USD) → **nicht gekauft**, nur die Produktseite gelesen |
| Hinweis des Herstellers | „created with the help of generative AI (AI-written drawing code)… reviewed, corrected and curated“ |

## 2. Lizenz (LICENSE.pdf v1.0, Oktober 2026 – vollständig gelesen)
| Erlaubt | Nicht erlaubt |
|---|---|
| Nutzung in **unbegrenzt vielen** Projekten (Spiele, Websites …) | die Dateien **einzeln** weitergeben, verkaufen, teilen – original oder bearbeitet – **einschließlich Upload in ein Repository**, Asset-Store, Filesharing |
| **Bearbeiten** (umfärben, skalieren, zuschneiden, kombinieren, beliebig ändern) | Aufnahme in andere Asset-Pakete, Vorlagen, UI-Kits |
| fertige Produkte mit den Effekten verkaufen/verteilen | als eigene Arbeit ausgeben; Logo/Marke |
| „Using the files inside a finished project is fine even if a player could technically extract them.“ → **Web-Build erlaubt** | |
| Namensnennung **nicht** erforderlich (erwünscht: „Effects: Cooked FX by The Cooked Works“) | |

**Folgen für WORLDS:** Effekte **nie** ins öffentliche GitHub-Repository (wie Penzilla): privater Import nach `assets/thirdparty/cooked_fx/` (git-ignoriert, `tools/assets/import_cooked_fx.py`). Für einen öffentlichen Build bräuchte die CI eine private Quelle (wie der MEGA-Ordner für Penzilla). Freiwillige Namensnennung im Abspann vorgesehen.

## 3. Stilvergleich mit Penzilla (gemessen und gesichtet)
| Merkmal | Penzilla | Cozy Chunky | Bewertung |
|---|---|---|---|
| Kontur | dick, **#330022** (Pflaume), ~2,3 px in Spielgröße | dick, **#2B2230** (Grau-Violett), 4 px bei 1x → ~2 px bei Spielmaßstab 0,5 | **sehr ähnlich**; Farbangleich auf #330022 trivial (erlaubte Bearbeitung) |
| Schattierung | flache Cel-Flächen, 2–3 Töne, Glanzpunkt | flache Cel-Flächen, Glanzpunkte | **passt** |
| Palette | warm, gesättigt | warm, gesättigt (Feuer orange/gelb, Wasser hellblau, Rauch warmgrau) | **passt** |
| Weiche Anteile | keine Glows | Explosion, Stern, Pickup, Treffer: **halbtransparente Glüh-/Schockringe** (60–68 % der Fläche weich) | **anpassen**: weiche Anteile entfernen |
| Proportionen | knubbelig, rund | „chunky“, rund, comichaft | **passt** |
| Perspektive | **isometrisch 2:1** | Side-View (senkrecht) / Top-down (kreisförmig, von oben) | Side = für aufsteigende Effekte geeignet; Top-down **nur 2:1 gestaucht** brauchbar (sonst wirken Ringe wie stehende Scheiben) |
| Animation | Penzilla-Figuren ~12 fps, Welt ruhig | 24 fps, „Pop“-Bewegungen mit Überschwingen | für Belohnungen ideal; für **ruhige Dauer-Loops** (Feuer, Schlafen) 12–16 fps abspielen (im Profil „Leistung“ ohnehin) |

### Side-View vs. Top-down getrennt
| Ansicht | Effekte | Eignung für die isometrische Welt |
|---|---|---|
| **Side** | fire, smoke, water (Fontäne), explosion, leaves, rocks, dust, poof, coins, confetti, hit | **gut** für alles, was **aufsteigt/fällt** (Flammen, Rauch, Fontäne, Münzen im Bogen) – senkrecht wirkt in Isometrie korrekt |
| **Top-down** | water (Ring), dust (Ring), rocks/leaves (Streuung), coins (Streuung), smoke, explosion, footstep | **nur gestaucht (Höhe 50 %)**: dann liegen Kräuselringe, Staubringe, Trümmer und Münzen **auf dem Boden** – überzeugend. Ungestaucht falsch |
| ohne Ansicht | star, heart, level_up, pickup, sleep, stun, burn | **gut** (UI-/Status-Effekte schweben über Objekten) |

## 4. Relevante Effekte für WORLDS
| WORLDS-Bedarf | Cozy-Chunky-Effekt | Anpassung | Empfehlung |
|---|---|---|---|
| Feuer (Brand) | `fire_side` (Loop), `burn` (Loop) | Kontur | **verwenden** – wirkt flacher und Penzilla-näher als unsere eigene Flamme |
| Rauch | `smoke_side`, `smoke_top` | Kontur; top gestaucht | **verwenden** (Kamin, Brandrauch) |
| Explosion | `explosion_side/top` | Kontur, **Glow entfernen**, top gestaucht | **verwenden** (Gas, Einsturz – spätere Phasen) |
| Wasser/Spritzer | `water_side` (Fontäne), `water_top` (Ring) | Kontur; Ring gestaucht | **verwenden** (Brunnen, Pfützen, Löschwasser) |
| Funken/Treffer | `hit_side` | Glow entfernen | eingeschränkt (Werkstatt-Funken; eher unsere eigenen Funken) |
| Staub, Bau, Trümmer | `dust_top`, `poof_side`, `rocks_top` | gestaucht | **verwenden** (Bauen, Abriss, Schritte) |
| Natur | `leaves_side/top` | Kontur | verwenden (Wind, Baum fällen) |
| Belohnungen | `coins_side/top`, `star`, `confetti_side`, `heart`, `level_up`, `pickup` | Stern/Pickup Glow entfernen; Münzen top gestaucht | **verwenden** (UI/Belohnungen) |
| Status | `sleep` (Zzz), `stun` | – | verwenden (schlafende Bewohner, Verwirrung) |
| **nicht** verwenden | Blut, Schwerthiebe, Mündungsfeuer, Magie (Feuerball, Eis, Blitz, Heilung, Schild), Portal | – | passen nicht zum Setting (Lebens-/Stadtsimulation) |

## 5. Testgalerie
- **Godot**, animiert: Web-Build mit `?gallery=cookedfx` (`scripts/tools/cooked_fx_gallery.gd`) – je Zeile Penzilla-Asset mit **Original** | **angepasst** | **eigene WORLDS-VFX**: Feuer+Rauch am Haus, Fontäne+Kräuselring am Brunnen, Explosion+Trümmer am Marktplatz, Belohnungen am Baum, Schlafen/Staub/Blätter am Haus. Läuft ohne Fehler (Chromium).
- Statischer Vergleich in Spielgröße (privat übergeben, nicht im Repository).

## 6. Entscheidung (Empfehlung)
**Cozy Chunky ist als ergänzender VFX-Stil für WORLDS geeignet** – mit drei festen Anpassungen (Konturfarbe #330022, keine weichen Glows, Top-down 2:1 gestaucht) und nur für die Effekte in §4 „verwenden“. Unsere eigenen VFX bleiben für Wetter (Regen, Schnee), Reparatur-Funkeln und als Rückfall, solange die Cooked-FX-Dateien im öffentlichen Build nicht verfügbar sind.

Noch **nicht** integriert (wie gewünscht). Offen für den Projektinhaber:
1. Ist ein **KI-gestützt erstelltes** Asset-Paket für WORLDS akzeptabel?
2. Private Bereitstellung für die CI (z. B. im MEGA-Ordner neben den Penzilla-Paketen), damit der öffentliche Build die Effekte enthalten kann.
3. Freiwillige Namensnennung „Effects: Cooked FX by The Cooked Works“ im Abspann (vorgesehen).
