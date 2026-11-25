# Innenräume, Türen, Animationen und Interaktionen (v0.1)

## 1. Animationsbibliothek
### 1.1 Vorhandene Penzilla-Animationen (geprüft am Paket „Ultimate Protagonist“)
Alle 18 Ordner haben **5 Blickrichtungen** (Zeilen S, SW, W, NW, N – gemessen: in den Zeilen 1 und 2 liegt das Gesicht links der Körpermitte); Osten entsteht durch Spiegeln → 8 Richtungen. 460×460-px-Einzelbilder, Alphakanal mit weichen Kanten.

| Animation | Frames | im Spiel | Einsatz |
|---|---|---|---|
| Idle / IdleHoldingTool | 8 | ✔ | Stehen, Grundlage vieler Clips |
| Walk / WalkHoldingTool | 6 | ✔ | Gehen (Schrittfrequenz folgt der Geschwindigkeit) |
| Run (mit/ohne Werkzeug) | 4 | ✔ | NPCs, die zu spät zur Schicht kommen |
| Interact / InteractHoldingTool | 3 | ✔ | Greifen, Benutzen, Tür öffnen, Essen, Trinken, Grüßen |
| Sit / SitHoldingTool | 4 | ✔ | Hinsetzen (Boden-Sitzpose; auf Bänken auf Sitzhöhe) |
| GetUp / GetUpHoldingTool | 4 | ✔ | Aufstehen, Aufheben (mit Sit kombiniert) |
| Dig | 6 | ✔ | Arbeit mit Schaufel (Hof) |
| Swing | 6 | ✔ | Arbeit mit Hammer/Axt (Bau, Handwerk) |
| Damage / DamageHoldingTool | 2 | ✔ | Zusammenzucken, Verletzung (Ebene „Sleeves“ fehlt im Paket) |
| Die | 6 | ✔ (Frames 0–5 als „Hinlegen“) | Schlafen auf der Matratze, Liege in der Praxis |
| Fish | 6 | importiert | Angeln (Gewässer/Freizeit, sobald Gewässer begehbar sind) |
| SwordAttack | 6 | nicht genutzt | keine Kampfsysteme (Phase 11) |

### 1.2 Eigene Animationen („Clips“, `data/character_catalog.json → clips`)
Fehlende Bewegungen werden **aus den Original-Penzilla-Einzelbildern** zusammengesetzt (eigene Bildfolge, Bildrate, Gesichtsausdruck, kleine Kopf-/Körperverschiebungen, Ereignismarken). Dadurch bleiben Kontur, Proportion, Farbe und Perspektive exakt im Penzilla-Stil.
28 Clips: greet, wave, talk, gesture, nod, shake_head, laugh, cheer, tired, yawn, upset, flinch, hurt_idle, eat, drink, use, look_at, pick_up, put_down, tend, open_door, close_door, sit_down, stand_up, lie_down, fish, walk_hurt, walk_tired.
**Ehrlich:** Eine echte Wink-Pose mit erhobenem Arm gibt es im Paket nicht; „wave/greet“ nutzt die ausgestreckte Hand aus „Interact“. Neue, frei gezeichnete Posen (z. B. Arm über dem Kopf) brauchen neue Einzelbilder für alle 14 Ebenen × 5 Richtungen – das System nimmt sie ohne Umbau auf (neuer Animationsordner + Eintrag im Katalog).

### 1.3 Ein System für Spieler und NPCs
- `CharacterRig.play(name)` spielt Penzilla-Animationen und Clips gleichermaßen (Segmente, Wiederholung, Halten, Ereignisse `clip_event`).
- **Spieler:** `Player.perform(action)` – erst Position/Pose einnehmen (Sitzen/Liegen), dann Clip; Bewegung unterbricht Gesten; aus Sitzen/Liegen steht man erst auf.
- **NPCs:** `Npc.apply_render` (Zustandsautomat) + Tabellen `activity_clips` (z. B. am Platz: sprechen, gestikulieren, lachen je nach Stimmung; auswärts essen: essen/trinken; Hof: knien und pflegen, aufheben; müde: gähnen; krank: langsames Gehen mit müdem Gesicht). Begrüßen des Spielers, wenn er näherkommt; Begrüßung beim Zusammentreffen.
- **Objektaktionen** (`data/anim/actions.json`): eine Definition für Spieler und NPCs – Clip, Pose, Rückmeldung, Entwicklungshinweis.

## 2. Türen
- `data/doors/doors.json`: für alle 19 Gebäudegrafiken von Hand vermessene Türen mit Typ: **Einzeltür** (Scharnier links/rechts), **Doppeltür** (Rathaus), **Glasschiebetür** (Praxis), **Rolltor** (Depot, Garage der Wache); der Handelsposten ist offen.
- `tools/assets/make_doors.py` erzeugt daraus 6 Öffnungsbilder je Tür aus den Original-Pixeln: Das Türblatt schwenkt um das Scharnier entlang der Wandneigung ein (wird schmaler und dunkler), Schiebetüren gleiten auseinander, Rolltore rollen hoch; dahinter erscheint der dunkle Innenraum. Ausgabe privat (`assets/penzilla/doors/`).
- Synchron: NPCs greifen zur Tür (Clip „open_door“, Phase 0,3–0,55 des Durchgangs) – erst dann öffnet sie sich; die Person geht hindurch und verblasst im Türrahmen; die Tür schließt sich, wenn sie drinnen ist. Beim Herauskommen öffnet sie sich zuerst. Der Spieler: Griff → Tür öffnet → Hineingehen → Innenraum → Tür schließt draußen.
- Die **Navigation** führt zur gezeichneten Tür (Seite und Position je Gebäudetyp, `nav_by_type`).
- Fahrzeug- und Bustüren: als Typen vorgesehen (`vehicle_hinged`, `bus_folding` im Konzept); Fahrzeuge gibt es im Spiel noch nicht.

## 3. Innenräume
- **Isometrisch**, etwas steiler als draußen (Raute 1,45 : 1). Die Retro-Interior-Tafeln sind frontal gezeichnet: Böden, Wände, Fenster, Bilder und Innentüren werden auf die isometrischen Flächen **projiziert**, Möbel stehen als frontale Sprites auf isometrischen Grundflächen (Kollision = Raute). Hinterwände sichtbar, Vorderwände aufgeschnitten.
- **Form folgt dem Gebäude:** Häuser fast quadratisch, Läden schmal, Werkstatt lang, Rathaus groß mit Verwaltungsflügel, **Praxis L-förmig**; Eingang auf derselben Seite wie draußen.
- Betretbar: **Spielerhaus** (Matratze, Bad mit Toilette, Waschbecken, Dusche, einfache Küche mit altem Herd und Kühlschrank, Umzugskisten), **Bäckerei, Gemischtwaren, Schmiede, Rathaus** (Verwaltungsschalter öffnet die Verwaltung), **Praxis, Hofladen, Werkstatt**. Personal im Dienst (aus dem Dienstplan) steht dort.
- Bewusst unfertig: Matratze statt Bett, alter Herd, Kisten statt Schrank – mit Hinweis, was später gekauft/gebaut werden kann (`upgrade`, Phase 6/7). Layouts sind Daten (`data/interiors/layouts.json`), Möbel austauschbar.
- Raumwechsel: Position draußen gemerkt, Innenraum geladen (weit außerhalb der Stadt im selben Weltbaum, die Siedlung lebt weiter), Spieler am Eingang, Kamera auf den Raum begrenzt, Licht innen (tags Tageslicht, nachts Lampenlicht); beim Verlassen zurück an die Haustür.
- Interaktionsknopf nur am Objekt: Innenraum-Objekte haben ihre Grundfläche + kleinen Rand als Interaktionsbereich; Ausgang nur an der Türmatte; draußen hat jedes Gebäude eine kleine Türfläche („Betreten“), der Gebäudekörper ist nur per Antippen erreichbar.

## 4. Kollisionen, Größen, Sortierung
- Straßenlaternen: Mast auf ≈ 4,5 m (2,6 × Personenhöhe), Leuchte menschengroß; Leuchtenkopf liegt immer über dem Kopf der Figuren (keine Sortierfehler mehr).
- Komplexe Grundrisse (`data/buildings/footprints.json`): Praxis mit Parkplatz, Wache mit Vorplatz und Pflasterweg, offener Markt – mehrere Kollisionspolygone statt einer Raute; Parkflächen als Daten für spätere Fahrzeuge.
- Tiefensortierung: alle Figuren, Gebäude, Laternen und Bäume nach Fußpunkt sortiert; Türbilder werden mit dem Gebäude durchsichtig, wenn die Figur dahinter steht.
- Bekannt: Penzilla-Gebäude sind im Verhältnis zu den Figuren miniaturhaft (Türen kleiner als eine Person). Eine Neuskalierung aller Gebäude wäre ein großer Eingriff in das Stadtbild – offen zur Entscheidung.
