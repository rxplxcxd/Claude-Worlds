# Prioritätenliste für die spätere Integration

Reihenfolge nach **Wirkung auf das Spielerlebnis** im Verhältnis zu **Aufwand/Risiko**. Produktionsstandard ist bestätigt, die Grafiken sind erzeugt (Schritt G); **vor jeder Veröffentlichung** der abgeleiteten Grafiken im Web-Build: Lizenzprüfung ([LICENSES.md](LICENSES.md) L1–L4). Punkte, die Spielmechanik berühren, brauchen zusätzlich die jeweilige Phase.

| Prio | Paket | Inhalt | Warum zuerst | Voraussetzung |
|---|---|---|---|---|
| V | **Lizenz** | PDF prüfen, Namensnennung „Graphics created by Penzilla Design“ im Spiel | Pflicht vor jeder Veröffentlichung abgeleiteter Grafiken | Projektinhaber stellt das PDF bereit |
| 0 | **Performance-Grundlage** | Boden-Atlas, Figuren-Texturspeicher (PERFORMANCE.md O1–O3) | Zustände kosten zusätzliche Draw Calls/Speicher – vorher Luft schaffen | Freigabe der Optimierungen |
| 1 | **Verschleiß-Shader (Stufe 1)** für alle Gebäude, Möbel, Fahrzeuge | Zustände 1–5, 12 ohne neue Dateien | größter sichtbarer Effekt bei ~0 Speicher | Simulationswert `maintenance`/`dirt` (Phase 3/7) – vorher nur als statische Vielfalt (zufällige leichte Gebrauchsspuren) |
| 2 | **Wetter auf Böden + Wetter-Partikel** | Pfützen, Schnee, Frost, Regen, Schneefall | Echtzeit-Uhr existiert; Wetterdaten fehlen noch | Wettersystem (eigene Freigabe) |
| 3 | **Penzilla-Originalzustände** | BareTree, Lampe an/aus (vorhanden), Interior-State2, Fahrzeuglicht | null Ableitungsrisiko | – |
| 4 | **Schadens-Overlays (Stufe 2)** | Risse, kaputte Fenster, Dachlöcher für die ~20 genutzten Gebäude | Geschichte der Welt sichtbar | Schadens-/Ereignissystem |
| 5 | **Brand + Ausgebrannt** | Feuer-VFX + Variante 9 | starkes Storytelling | Brandereignisse (Phase 11) |
| 6 | **Zerstört/Ruine/Wiederaufbau** | Varianten 8, 10, 11, 12 + Bau-/Reparatur-VFX | Wiederaufbau ist Kernmotiv | Bau-/Abrisssystem (Phase 7) |
| 7 | **Innenräume** | Zustände für Möbel/Böden/Wände + zufällige Variation | erst mit begehbaren Innenräumen sinnvoll | Innenräume (eigene Phase) |
| 8 | **Fehlende Grafiken** | Baugerüst (Bauzustand), Baumstumpf/gefällter Baum | keine Penzilla-Vorlage (zerrissene Markisen und Trümmer werden inzwischen erzeugt) | eigene Zeichnung oder Kauf (nur nach Zustimmung) |

**Qualitätsprofile** (Ultra/Hoch/Leistung) sind im `LivingComposer` umgesetzt und werden mit Prio 1 im Spiel eingeführt, damit ältere iPhones von Anfang an berücksichtigt sind.

**Technische Reihenfolge des Einbaus** (wenn freigegeben): (1) `VisualState` in den Gebäude-/Objektdatensatz von `WorldState` (Schema-Migration, Standard „intact/0“), (2) `LivingComposer.build()` statt einzelnem Sprite in `Building`/`Prop`, (3) Zustandsdateien in CI erzeugen (nur nach Lizenzklärung), (4) Atlanten je Kategorie, (5) Messung **im Spielbetrieb** (`context: spiel`) auf iPhone 15 Pro Max und älterem iPhone.
