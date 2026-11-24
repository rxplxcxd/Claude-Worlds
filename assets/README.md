# assets/

Zielordner für lizenzierte Asset-Dateien. **Aktuell leer**, da die Penzilla-Pakete noch nicht verfügbar sind (siehe `docs/ASSET_INVENTORY.md`).

Geplante Struktur (Originaldateien bleiben unverändert in `_source/`):

```
assets/
  _source/<paket>/        unveränderte Originale inkl. Lizenztexte (ggf. nicht öffentlich)
  characters/             Spielfigur (Ultimate Protagonist) – SpriteFrames
  buildings/              Außengebäude (Penzilla)
  environment/            Boden, Straßen, Vegetation, Requisiten (Penzilla)
  ui/                     Basic GUI – Theme
  interior/               Innenräume (Top-Down-Retro-Interior u. a.)
```

Einbindung: Pfad in `data/asset_manifest.json` beim passenden Schlüssel eintragen. Außen-Schlüssel (`exterior.*`) akzeptieren nur Quellen des Herstellers Penzilla.
