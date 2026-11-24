# ASSET_INVENTORY

Legende: **[IMPLEMENTIERT]** · **[GEPLANT]** · **[OFFEN]**

## 1. Status der vorgegebenen Asset-Pakete

**Kein einziges Paket konnte heruntergeladen werden.** Es wurden keine Asset-Dateien geprüft, entpackt oder integriert. Folgende Schritte wurden tatsächlich durchgeführt (24.11.2026):

| # | Paket | Bereitgestellter Link | Ergebnis |
|---|---|---|---|
| 1 | Ultimate Protagonist | https://storage.to/pfDPS1D0I | ❌ nicht geladen |
| 2 | GiantCityBuilder | https://storage.to/4DrGboO8h | ❌ nicht geladen |
| 3 | Isometric RPG Buildings | https://storage.to/lxRphdPEO | ❌ nicht geladen |
| 4 | Basic GUI | https://storage.to/KAzmtRSF0 | ❌ nicht geladen |
| 5 | Top-Down-Retro-Interior | https://storage.to/vw1xE9UNW | ❌ nicht geladen |

**Verlauf:**
1. Erster Abruf: Netzwerkrichtlinie der Cloud-Umgebung blockierte `storage.to` (Proxy 403).
2. Nach Freigabe von `storage.to` in der Umgebung: Jede Seite liefert eine **Cloudflare-Bot-Prüfung** („Just a moment…“, HTTP 403, `cType: managed`), keine Datei und keine Downloadseite.
3. Versuch mit einem normalen Chromium-Browser: Die Prüfung benötigt zusätzlich `challenges.cloudflare.com`; nach dessen Freigabe wurde das weitere automatisierte Umgehen der Bot-Prüfung von der Sicherheitsrichtlinie der Agent-Umgebung untersagt. Dieser Weg wurde daher **bewusst nicht weiter verfolgt**.

**Benötigt vom Projektinhaber – eine der folgenden Bereitstellungen:**
- **Empfohlen:** Pakete (ZIP) in ein privates GitHub-Repository bzw. als **GitHub Release Asset** von `Claude-Worlds` hochladen (bei Größen > 100 MB Release Assets oder Git LFS verwenden), oder
- direkte Download-Links ohne Bot-Prüfung (z. B. itch.io-Download-Links aus dem Kaufkonto, Dropbox/Google-Drive-Direktlinks), oder
- die Dateien in eine neue Cloud-Sitzung hochladen.

> Hinweis: Lizenzbedingungen von Penzilla (Weitergabe/Redistribution) sollten vor einem öffentlichen Repository geprüft werden. Bei öffentlichem Repo nur die tatsächlich benötigten, exportierten Dateien einchecken oder ein privates Asset-Repository nutzen. **[OFFEN]**

## 2. Recherche-Ergebnisse zu den vorgegebenen Paketen (öffentliche Shopseiten, nicht die Dateien)

Alle fünf Pakete stammen nach Shop-Recherche vom Hersteller **Penzilla** (itch.io). Angaben unverifiziert, da die Dateien selbst nicht vorliegen:

| Paket | Shopseite | Bekannte Angaben |
|---|---|---|
| Ultimate Protagonist | https://penzilla.itch.io/ultimate-protagonist | Animierte Pixel-Art-Spielfigur; Download ca. 951 MB (`Ultimate_Protagonist.zip`); verwandte Pakete bieten 8 Richtungen für Top-Down/Isometrie |
| Giant City Builder | https://penzilla.itch.io/giant-city-builder | Isometrisches City-Builder-Tileset (Shop: „500+ isometric tiles“, inkl. ~50 Fahrzeuge) |
| Isometric RPG Buildings | https://penzilla.itch.io/isometric-rpg-village (vermutlich) | Handgezeichnete isometrische Häuser und Läden |
| Basic GUI | unbekannt | – |
| Top-Down-Retro-Interior | https://penzilla.itch.io/top-down-retro-interior | Top-Down-Innenraum-Pixel-Art |

**Konsequenzen für die Integration [GEPLANT]:**
- Ultimate Protagonist (951 MB) ist für Web viel zu groß → nur benötigte Animationen/Richtungen als Sprite-Sheets/`SpriteFrames` exportieren, Texturgröße für iPhone begrenzen (≤ 2048 px Atlas).
- Kachelmaß des Giant City Builder prüfen; `Iso.TILE_W/TILE_H` (128×64) und die Manifest-Felder `anchor`/`scale` sind dafür vorgesehen.
- Lizenztexte aus den Archiven übernehmen (`assets/<paket>/LICENSE*`) – **Lizenzrechte werden nicht erfunden**.

## 3. Asset-Inventar (Dateien)

| Datei | Quelle | Format | Kategorie | Auflösung | Animationen | Godot-Kompatibilität | Verwendung | Lizenz |
|---|---|---|---|---|---|---|---|---|
| *(keine Dateien vorhanden)* | – | – | – | – | – | – | – | – |

Selbst erstellte Projektdateien:

| Datei | Herkunft | Verwendung | Lizenz |
|---|---|---|---|
| `icon.svg` | Für WORLDS erstellt | Projekt-/App-Icon | Projekt-eigen |
| `web/icons/icon-{144,180,192,512}.png` | aus `icon.svg` gerendert (`tools/render_icons.js`) | PWA-/Home-Screen-Icons | Projekt-eigen |

## 4. Platzhalter-Register [IMPLEMENTIERT]

Alle sichtbaren Grafiken sind **prozedurale Platzhalter** (Code, keine Bilddateien). Sie werden über `data/asset_manifest.json` einzeln ersetzt – ohne Codeänderung, sobald `path` gesetzt ist.

| Logischer Schlüssel | Platzhalter in | Ziel-Paket |
|---|---|---|
| `character.player` | `scripts/player/player_visual.gd` | Ultimate Protagonist |
| `exterior.ground.tileset` | `scripts/world/ground_layer.gd` | Giant City Builder |
| `exterior.building.*` (11 Typen) | `scripts/buildings/building.gd` | Isometric RPG Buildings / Giant City Builder |
| `exterior.prop.*` (9 Typen) | `scripts/world/prop.gd` | Giant City Builder / Isometric RPG Buildings |
| `ui.theme` | `scripts/ui/ui_theme.gd` | Basic GUI |
| `interior.tileset.retro` | – (Innenräume nicht in Phase 1) | Top-Down-Retro-Interior |

Der HUD-Hinweis „Platzhaltergrafik · Penzilla-Assets ausstehend“ verschwindet automatisch, sobald alle Einträge aufgelöst sind. Das Menü zeigt den Asset-Status.

## 5. Art Direction

### Außenbereiche – ausschließlich Penzilla [IMPLEMENTIERT als technische Regel]
- `art_direction.exterior_allowed_vendors = ["penzilla"]` im Manifest.
- `AssetRegistry` verweigert jede `exterior.*`-Datei eines anderen Herstellers (Test: „guard blocks non-Penzilla exterior asset“).
- Es wurden **keine fremden Außen-Assets** verwendet; die Platzhalter sind stilneutral und als solche markiert.

### Innenbereiche – freiere Wahl, Pixel Art erlaubt [GEPLANT]
- `interior.*` darf andere, ordnungsgemäß lizenzierte Hersteller verwenden (Test vorhanden).
- Übergänge Außen→Innen (Kamera-Schnitt mit Überblendung, einheitliches HUD, angeglichene Farbpalette/Beleuchtung, Pixel-Art mit Nearest-Filter in eigener Szene) werden mit dem ersten Innenraum umgesetzt.

### Bekannte Lücken in der Außenwelt [OFFEN – nach Sichtung der Pakete]
Erst nach Erhalt der Pakete feststellbar. Erwartete Kandidaten: Wasserwerk, Solarfeld/Energiestation, Notfallposten, Gewächshaus (passend zum „Wiederaufbau“-Setting). Lösungsweg: zuerst andere Penzilla-Pakete prüfen (z. B. *Free City Builder*, *Medieval City Builder*, die laut Hersteller kompatibel sind), Kauf nur nach Zustimmung; kein Fremdstil.

## 6. Recherche: zusätzliche Interior-Assets

Nur Recherche – **nichts gekauft, nichts heruntergeladen**. Lizenzen vor Verwendung auf der jeweiligen Seite verifizieren.

| Paket | Quelle / Link | Stil | Inhalt | Technische Eignung | Lizenz | Preis | Empfehlung |
|---|---|---|---|---|---|---|---|
| **Top-Down-Retro-Interior** (bereits gekauft) | https://penzilla.itch.io/top-down-retro-interior | Pixel Art, Top-Down | Wohnräume, Möbel | Gut, gleicher Hersteller wie Außenwelt | Penzilla-Kauflizenz (Datei prüfen) | gekauft | **Erste Wahl** |
| Penzilla Ultimate Interior Pack (isometrisch) | https://penzilla.itch.io/ultimate-interior-pack | Isometrisch, Penzilla | Innenraum-Kacheln & Requisiten | Sehr gut: gleiche Perspektive wie Außenwelt → nahtloser Übergang | Kommerziell (Penzilla) | ca. 10 USD (Shopangabe) | **Empfehlung für Kauf nach Zustimmung**, falls Retro-Interior perspektivisch nicht passt |
| LimeZu Modern Interiors | https://limezu.itch.io/moderninteriors | Pixel Art 16×16, Top-Down | Sehr umfangreich: Wohnung, Küche, Bad, Büro, Läden, Krankenhaus, Schule … | Gut (PNG-Sheets, Godot-tauglich) | Kommerziell erlaubt, keine Weitergabe/Weiterverkauf (Entwickleraussage) | ab ca. 1,50 USD (Pay-what-you-want-Minimum, Shopangabe) | Starke Option für viele Raumtypen (Phase 7+) |
| Kenney Furniture Kit | https://www.kenney.nl/assets/furniture-kit | 3D-Renders, isometrisch + Top-Down | ~140 Möbel (Küche, Bad, Wohnen) | Gut (PNG-Renders, 4 Winkel) | **CC0** | kostenlos | Kostenloser Lückenfüller / Prototyping |
| Kenney Roguelike Indoor Pack | https://opengameart.org/content/roguelike-indoor-pack | Pixel Art, Top-Down | Innenraum-Tiles, Möbel | Gut | **CC0** | kostenlos | Prototyping |
| Top-Down Interior 16×16 (OpenGameArt) | https://opengameart.org/node/114339 | Pixel Art 16×16 | Innenraum-Tiles | Gut | **CC0** (laut Seite) | kostenlos | Prototyping |
| Bitglow Pixel Interior | https://bitglow.itch.io/pixel-interior | Pixel Art 16×16 | Möbel | Gut | Eigene Lizenz: kommerziell erlaubt, keine Weitergabe | kostenlos | Optional |
| Pocket Witch Interior (Faultbox) | https://faultbox.itch.io/interior | Pixel Art | Innenraum | Gut | CC BY 4.0 (Namensnennung) | kostenlos | Nur mit Credits |
| LPC House Interior | https://opengameart.org/content/lpc-house-interior-and-decorations | Pixel Art 32×32 | Wohnräume | Mittel (LPC-Stil) | CC-BY-SA / GPL (Share-alike!) | kostenlos | **Nicht empfohlen** (Share-alike-Pflichten) |

**Empfehlung:** 1) gekauftes Top-Down-Retro-Interior sichten; 2) falls die Perspektive zur isometrischen Außenwelt zu stark bricht: Penzilla Ultimate Interior Pack (Kauf nur nach Zustimmung); 3) Kenney-CC0 für Prototypen.
