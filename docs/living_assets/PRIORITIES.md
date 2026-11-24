# Prioritätenliste für die spätere Integration

Reihenfolge nach **Wirkung auf das Spielerlebnis** im Verhältnis zu **Aufwand/Risiko**. Alle Punkte setzen die Freigabe des Produktionsstandards voraus; Punkte, die Spielmechanik berühren, zusätzlich die jeweilige Phase.

| Prio | Paket | Inhalt | Warum zuerst | Voraussetzung |
|---|---|---|---|---|
| 0 | **Performance-Grundlage** | Boden-Atlas, Figuren-Texturspeicher (PERFORMANCE.md O1–O3) | Zustände kosten zusätzliche Draw Calls/Speicher – vorher Luft schaffen | Freigabe der Optimierungen |
| 1 | **Verschleiß-Shader (Stufe 1)** für alle Gebäude, Möbel, Fahrzeuge | Zustände 1–5, 12 ohne neue Dateien | größter sichtbarer Effekt bei ~0 Speicher | Simulationswert `maintenance`/`dirt` (Phase 3/7) – vorher nur als statische Vielfalt (zufällige leichte Gebrauchsspuren) |
| 2 | **Wetter auf Böden + Wetter-Partikel** | Pfützen, Schnee, Frost, Regen, Schneefall | Echtzeit-Uhr existiert; Wetterdaten fehlen noch | Wettersystem (eigene Freigabe) |
| 3 | **Penzilla-Originalzustände** | BareTree, Lampe an/aus (vorhanden), Interior-State2, Fahrzeuglicht | null Ableitungsrisiko | – |
| 4 | **Schadens-Overlays (Stufe 2)** | Risse, kaputte Fenster, Dachlöcher für die ~20 genutzten Gebäude | Geschichte der Welt sichtbar | Schadens-/Ereignissystem |
| 5 | **Brand + Ausgebrannt** | Feuer-VFX + Variante 9 | starkes Storytelling | Brandereignisse (Phase 11) |
| 6 | **Zerstört/Ruine/Wiederaufbau** | Varianten 8, 10, 11, 12 + Bau-/Reparatur-VFX | Wiederaufbau ist Kernmotiv | Bau-/Abrisssystem (Phase 7) |
| 7 | **Innenräume** | Zustände für Möbel/Böden/Wände + zufällige Variation | erst mit begehbaren Innenräumen sinnvoll | Innenräume (eigene Phase) |
| 8 | **Fehlende Grafiken** | Baugerüst, Baumstumpf, Trümmerhaufen, zerrissene Markisen | keine Penzilla-Vorlage | eigene Zeichnung oder Kauf (nur nach Zustimmung) |

**Qualitätsprofile** (Ultra/Hoch/Leistung) werden mit Prio 1 eingeführt, damit ältere iPhones von Anfang an berücksichtigt sind.
