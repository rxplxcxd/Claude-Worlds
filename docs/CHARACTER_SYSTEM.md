# CHARACTER_SYSTEM

**Status: [IMPLEMENTIERT, Phase 1]** – modularer Charakter, Charakter-Editor, Speicherung, Nutzung durch Spieler und NPCs.

## 1. Grundlage: Penzilla Ultimate Protagonist
Das Paket enthält neben 8 fertigen Figuren einen **Baukasten in Ebenen** (`CustomizableCharacter`): Körper, Gesicht, Haare/Kopfbedeckungen, Oberteile, Ärmel, Overall, Hosen, Schuhe, Halsketten, Taschen, Schals, Fliegen, Werkzeuge – je Animation als Sheet mit 5 Richtungsreihen (S, SO, O, NO, N; Westen = gespiegelt). Frame 460×460 px.

**Import** (`tools/assets/import_character.py`, privat, Ergebnis git-ignoriert): schneidet Frames auf den Figurenbereich (`[50,45,370,445]`), verkleinert auf 40 %, quantisiert PNG, repariert leere Einzelframes (z. B. Mütze Richtung NW), normalisiert Tippfehler der Dateinamen. Verwendete Animationen: Stehen (8 Frames, 7 fps), Gehen (6, 10 fps), Benutzen (3, einmalig), Stehen mit Werkzeug (8).

## 2. Katalog (`data/character_catalog.json`, Autoload `CharacterCatalog`)
Enthält **nur Namen, Regeln und Farben, keine Bilddaten**.

| Slot | Optionen |
|---|---|
| Körper | 5 Hauttöne |
| Gesicht | normal, fröhlich, müde, grimmig (+ Blinzeln automatisch) |
| Frisur & Kopfbedeckung | kurz, lang, lockig, wellig, Zopf, Dutt, Irokese, Stacheln, Mütze, Strohhut, keine – Haare in 10 Farben, Mütze 5, Strohhut 2 |
| Haarschleife | 4 Farben |
| Oberteil / Ärmel | Hemd, Kleid (je 16 Farben), lange Ärmel (16) |
| Unterteil | Hose (8), Overall (15) |
| Schuhe | schwarz, braun, beige, blau, rot, gelb |
| Extras | Tasche (5), Schal (5), Fliege (4), Halskette (Gold, Silber, Kupfer, Platin, Eisen) |
| Werkzeug | Hammer, Schaufel, Gießkanne, Axt – nur für Rollen, nicht im Editor |

**Farben:** Penzillas eigene Farbvarianten werden reproduziert, indem die weißen „Blank“-Ebenen mit gemessenen Multiplikatoren eingefärbt werden (Messfehler p90 ≤ 5,5 von 255). Dadurch genügt 1 Satz Ebenen statt aller Farbdateien. Wo Penzilla keine Blank-Ebene liefert (Gesichter, Schuhe, Ketten), werden die Originalvarianten verwendet.

**Outfits:** Gründer:in, Stadt, Werkstatt, Land, Gemütlich, Festlich. **Rollen** (NPCs): siehe NPC_SYSTEM.md §0a.

**Datenformat (Aussehen):**
```json
{"body": {"option": "default", "color": "skin3"}, "face": {"option": "happy"},
 "head": {"option": "ponytail", "color": "color6"}, "top": {"option": "shirt", "color": "green"}, ...}
```
Klein, versionierbar, server-/Firestore-tauglich (`players/{id}.appearance`, `npcs/{id}.appearance`). `normalize()` füllt fehlende Slots und verwirft unbekannte Werte → alte Spielstände bleiben gültig.

## 3. Darstellung (`CharacterRig`, `CharacterComposer`)
- Ebenen-Reihenfolge laut Katalog (`layer_order`): Werkzeug hinten → Körper → Gesicht → Overall → Hose → Schuhe → Oberteil → Ärmel → Kette → Tasche → Schal → Fliege → Haare → Schleife → Werkzeug.
- Drei Teile mit gemeinsamem Frame-Takt: **unter dem Gesicht / Gesicht / über dem Gesicht** (Gesicht separat → Blinzeln alle 2,5–6 s).
- **Composite-Modus** (Spieler, NPCs): die Teile werden per SubViewport einmal zu je einer Textur pro Animation zusammengesetzt und gecacht (vormultipliziertes Alpha). Wenige Draw-Calls je Figur.
- **Stacked-Modus** (Editor): jede Ebene einzeln → Änderungen sind sofort sichtbar.
- Richtung: 8 Facings → 5 Reihen + Spiegelung um den Fußpunkt (kein seitliches Springen). Werkzeug-Rollen nutzen automatisch „Stehen mit Werkzeug“.
- Maßstab: Figuren mit 62 % des Gebäudemaßstabs (wirken neben den City-Builder-Gebäuden stimmig).

## 4. Charakter-Editor (`scripts/ui/character_editor.gd`)
- **Erreichbar:** beim allerersten Start (vor der Siedlungsgründung) und jederzeit über Menü → „Figur bearbeiten“.
- **Bühne** in der Mitte: Figur auf Penzilla-Grasplattform, Hintergrund aus *Stylized Grass & Dirt* (nur UI). Lebendige Vorschau: Atmen/Idle mit Blinzeln, Drehen per Pfeiltasten (Penzilla-GUI-Icons) oder Wischen, „Drehen“ (Auto-Rotation), Animationswahl Stehen / Gehen / Benutzen.
- **Bedienfeld:** Kategorien Körper, Haare, Oberteil, Unterteil, Schuhe, Extras, Outfits; je Slot Vorschaukarten mit der **eigenen Figur** in der jeweiligen Option, Farbfelder, Outfits als Karten.
- **Aktionen:** Zufall, Rückgängig (40 Schritte), Zurücksetzen, Abbrechen (nur beim Bearbeiten), Fertig. Name eingeben (virtuelle Tastatur auf iOS).
- **Responsiv:** Querformat Bühne links / Bedienfeld rechts; Hochformat Bühne oben / Bedienfeld unten.

## 5. Speicherung
`LocalProfile.character` (JSON im Abschnitt `character` von `user://worlds_local.cfg`) + Anzeigename. Wird nach „Fertig“ sofort gespeichert und auf die Spielfigur angewendet; bleibt nach Neuladen erhalten (im Browser getestet). Später: `players/{player_id}.appearance` in Firestore, Änderung als Absicht an den Server.

## 6. Grenzen / Offen
- Werkzeuge im Editor nicht wählbar (Rollen-/Berufsbezug, kommt mit Phase 3/6).
- Rennen, Sitzen, Graben usw. sind importierbar, aber noch nicht im Spiel.
- [OFFEN] Freischaltbare Kleidung (Wirtschaft, Phase 6) – Katalog ist dafür vorbereitet (Option = ID).
