# Eigene VFX (projekteigen)

Alle Dateien in diesem Ordner sind **eigene Arbeit**, prozedural erzeugt von `tools/assets/make_vfx.py` (keine fremde Vorlage, keine Penzilla-Pixel). Sie dürfen im öffentlichen Repository liegen und weitergegeben werden.

| Datei | Inhalt |
|---|---|
| `vfx_atlas.png` + `vfx_atlas.json` | Animationen (96-px-Frames): Flamme, Rauch dunkel/hell, Funken, Regentropfen, Schneeflocke, Staub, Blatt, Spritzer, Reparatur, Belohnungsstern, Trümmer |
| `grime_field.png` | kachelbares Feld für den Verschleiß-Shader `shaders/living_wear.gdshader` |

Neu erzeugen: `python3 -I tools/assets/make_vfx.py .` – Quellen und Lizenzen externer Effekte: [docs/living_assets/VFX_SOURCES.md](../../docs/living_assets/VFX_SOURCES.md).
