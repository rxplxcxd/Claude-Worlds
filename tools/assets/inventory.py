#!/usr/bin/env python3
"""Living Assets – step A: complete asset inventory (metadata only).

Usage:
    python3 -I tools/assets/inventory.py <dir_with_zips> [<project_root>]

Reads every file of the purchased packs directly from the ZIP archives
(nothing is extracted, nothing executed) plus the CC0 interior packs in
assets/interior/, and writes
    docs/living_assets/asset_inventory.csv   one row per file
    docs/living_assets/inventory_summary.json counts per pack/category
Only names and measurements are written – no image data – so the inventory
can live in the public repository without redistributing purchased assets.
"""
import csv
import io
import json
import os
import re
import sys
import zipfile

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))

PACKS = {
    "GiantCityBuilder.zip": ("penzilla_giant_city_builder", "Penzilla Giant City Builder", "Penzilla Standard License (kommerziell, keine Weitergabe der Rohdateien)"),
    "Isometric_RPG_Buildings.zip": ("penzilla_isometric_rpg_buildings", "Penzilla Isometric RPG Buildings", "Penzilla Standard License (kommerziell, keine Weitergabe der Rohdateien)"),
    "Basic_GUI_Bundle.zip": ("penzilla_basic_gui", "Penzilla Basic GUI Bundle", "Penzilla Standard License (angenommen; Lizenz-PDF fehlt)"),
    "Top-Down_Retro_Interior.zip": ("penzilla_top_down_retro_interior", "Penzilla Top-Down Retro Interior", "Penzilla Standard License (kommerziell, keine Weitergabe der Rohdateien)"),
    "Ultimate_Protagonist.zip": ("penzilla_ultimate_protagonist", "Penzilla Ultimate Protagonist", "Penzilla Standard License (kommerziell, keine Weitergabe der Rohdateien)"),
    "Stylized_GrassAndDirt.zip": ("stylized_grass_and_dirt", "Stylized Grass & Dirt (Hersteller unbekannt)", "unbekannt – nur UI-Hintergrund, nicht Außenwelt"),
}

# State groups (docs/living_assets/STATE_MATRIX.md).
STATE_GROUPS = {
    "gebaeude": "G-Gebäude (12 Zustände)",
    "gebaeudeteil": "T-Gebäudeteile",
    "boden_verkehr": "S-Straßen/Wege/Boden",
    "vegetation": "V-Vegetation",
    "stadtmoebel": "M-Stadtmöbel",
    "beleuchtung": "L-Beleuchtung",
    "fahrzeug": "F-Fahrzeuge",
    "zaun": "Z-Zäune",
    "deko": "D-Dekoration",
    "innen_moebel": "I-Innenausstattung",
    "innen_raum": "R-Böden/Wände/Türen/Fenster (innen)",
    "figur": "keine (Figuren: Kleidung/Animation statt Verfall)",
    "ui": "keine (Oberfläche)",
    "material": "keine (PBR-Material, nicht in der Außenwelt)",
    "wasser": "W-Wasser",
}


def classify(pack, path):
    """Returns (category, subcategory, state_group key, perspective)."""
    name = os.path.basename(path)
    low = path.lower()
    if pack == "GiantCityBuilder.zip":
        top = path.split("/")[0]
        if top == "Tiles":
            if "water" in low:
                return "Boden", "Wasser", "wasser", "isometrisch 2:1 (512×292 Kachel)"
            for k, sub in [("grassroad", "Feldweg"), ("road", "Straße"), ("sidewalk", "Gehweg"), ("rail", "Schiene"), ("pipe", "Leitung"), ("concreet", "Platz/Beton")]:
                if k in low:
                    return "Straßen & Wege", sub, "boden_verkehr", "isometrisch 2:1 (512×292 Kachel)"
            return "Boden", re.sub(r"[_\d]+$", "", os.path.splitext(name)[0]), "boden_verkehr", "isometrisch 2:1 (512×292 Kachel)"
        if top in ("Appartments", "Houses"):
            return "Gebäude", "Wohnen", "gebaeude", "isometrisch 2:1"
        if top == "Public":
            return "Gebäude", "Öffentlich/Industrie", "gebaeude", "isometrisch 2:1"
        if top == "Restaurants":
            return "Gebäude", "Gastronomie", "gebaeude", "isometrisch 2:1"
        if top == "Shopping":
            return "Gebäude", "Handel/Gewerbe", "gebaeude", "isometrisch 2:1"
        if top == "Plants":
            return "Vegetation", "Bäume/Büsche/Pflanzen", "vegetation", "isometrisch 2:1"
        if top == "Fences":
            return "Zäune", "Zaun/Mauer", "zaun", "isometrisch 2:1"
        if top == "Vehicles":
            if "animation" in low:
                return "Fahrzeuge", "Animation (Licht/Räder)", "fahrzeug", "isometrisch 2:1"
            return "Fahrzeuge", "Fahrzeug", "fahrzeug", "isometrisch 2:1"
        if top == "DecorItems":
            if "animation" in low:
                return "Dekoration", "Animation", "deko", "isometrisch 2:1"
            if "lamp" in low or "light" in low:
                return "Beleuchtung", "Straßenlaterne/Leuchte", "beleuchtung", "isometrisch 2:1"
            for k in ["bench", "seat", "trash", "hydrant", "sign", "mailbox", "busstop", "pole", "bin", "phone", "parking", "electrical"]:
                if k in low:
                    return "Stadtmöbel", k.capitalize(), "stadtmoebel", "isometrisch 2:1"
            return "Dekoration", "Deko", "deko", "isometrisch 2:1"
        return "Sonstiges", top, "deko", "isometrisch 2:1"
    if pack == "Isometric_RPG_Buildings.zip":
        if path.startswith("Icons"):
            return "UI-Icons", path.split("/")[1], "ui", "flach (Icon)"
        if "Tent" in path:
            return "Gebäude", "Zelt", "gebaeude", "isometrisch (RPG-Raster, Steigung 0,603)"
        for k, sub in [("roof", "Dach"), ("window", "Fenster"), ("door", "Tür"), ("outerwall", "Fassade"), ("innerwall", "Innenwand"),
                       ("beam", "Balken"), ("floor", "Boden"), ("fabric", "Markise"), ("storetype", "Ladenschild"), ("sign", "Schild"),
                       ("chimney", "Schornstein"), ("snow", "Schnee-Ebene"), ("display", "Schaufenster")]:
            if k in low:
                return "Gebäudeteile", sub, "gebaeudeteil", "isometrisch (RPG-Raster, Steigung 0,603)"
        return "Gebäudeteile", "Sonstiges", "gebaeudeteil", "isometrisch (RPG-Raster)"
    if pack == "Basic_GUI_Bundle.zip":
        return "Oberfläche", path.split("/")[0], "ui", "flach"
    if pack == "Top-Down_Retro_Interior.zip":
        if "Furniture" in name or "SmallItems" in name:
            return "Innenausstattung", "Möbel & Gegenstände (Sammelblatt 16 px)", "innen_moebel", "Top-Down, Pixel Art 16 px"
        return "Innenraum", "Böden/Wände/Türen/Fenster (Sammelblatt 16 px)", "innen_raum", "Top-Down, Pixel Art 16 px"
    if pack == "Ultimate_Protagonist.zip":
        parts = path.split("/")
        return "Figuren", parts[1] + (" / " + parts[2] if len(parts) > 3 else ""), "figur", "isometrisch, 5 Richtungsreihen"
    if pack == "Stylized_GrassAndDirt.zip":
        return "Material (PBR)", path.split("/")[1] if "/" in path else "Blender", "material", "Draufsicht, kachelbar"
    return "Sonstiges", "", "deko", "?"


def animation_info(pack, path, w, h):
    if pack == "Ultimate_Protagonist.zip" and path.lower().endswith(".png"):
        frames = max(1, round(w / 460))
        rows = max(1, round(h / 460))
        return f"{frames} Frames × {rows} Richtungen (460 px)"
    if "animation" in path.lower():
        frame_h = h
        frames = max(1, round(w / frame_h)) if frame_h else 1
        return f"Sprite-Sheet ~{frames} Frames"
    return ""


def godot_compat(path):
    ext = os.path.splitext(path)[1].lower()
    if ext in (".png", ".jpg", ".jpeg", ".webp"):
        return "ja (Texture2D)"
    if ext == ".svg":
        return "ja (SVG-Import als Textur)"
    if ext == ".blend":
        return "nein (Blender-Datei, 3D)"
    return "prüfen"


def used_in_game(root):
    """Maps archive paths to manifest keys of files already imported."""
    used = {}
    sel = json.load(open(os.path.join(HERE, "penzilla_selection.json"), encoding="utf-8"))
    for rel, spec in sel["files"].items():
        used[(sel["packs"][spec[0]], spec[1])] = rel
    for rel, spec in sel.get("composed", {}).items():
        for layer in spec["layers"]:
            used[(sel["packs"][spec["pack"]], spec["dir"] + "/" + layer)] = rel + " (zusammengesetzt)"
    cat = json.load(open(os.path.join(root, "data", "character_catalog.json"), encoding="utf-8"))
    return used, cat


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    src = os.path.abspath(sys.argv[1])
    root = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else os.path.dirname(os.path.dirname(HERE))
    out_dir = os.path.join(root, "docs", "living_assets")
    os.makedirs(out_dir, exist_ok=True)
    used, _cat = used_in_game(root)
    rows = []
    summary = {}
    for pack, (source_id, label, license_text) in PACKS.items():
        zpath = os.path.join(src, pack)
        if not os.path.exists(zpath):
            print("missing", pack)
            continue
        zf = zipfile.ZipFile(zpath)
        for info in zf.infolist():
            if info.is_dir():
                continue
            path = info.filename
            if ".." in path or path.startswith("/"):
                continue  # never trust archive paths
            w = h = 0
            if path.lower().endswith((".png", ".jpg", ".jpeg")):
                try:
                    with zf.open(info) as fh:
                        im = Image.open(io.BytesIO(fh.read(65536)) if info.file_size > 65536 and path.lower().endswith(".png") else fh)
                        w, h = im.size
                except Exception:
                    with zf.open(info) as fh:
                        w, h = Image.open(io.BytesIO(fh.read())).size
            cat, sub, group, persp = classify(pack, path)
            usage = used.get((pack, path), "")
            if not usage and pack == "Ultimate_Protagonist.zip" and "CustomaizableCharacter" in path and any(a in path for a in ("/Idle/", "/Walk/", "/Interact/", "/IdleHoldingTool/")):
                usage = "Figuren-Baukasten (import_character.py)"
            rows.append({
                "datei": path, "paket": label, "quelle_id": source_id, "kategorie": cat, "unterkategorie": sub,
                "breite": w, "hoehe": h, "perspektive": persp, "animation": animation_info(pack, path, w, h),
                "im_spiel": usage, "verwendungszweck": _purpose(cat, sub), "godot": godot_compat(path),
                "lizenz": license_text, "zustandsgruppe": STATE_GROUPS[group],
                "bytes": info.file_size,
            })
            key = f"{label} | {cat}"
            summary[key] = summary.get(key, 0) + 1
    # CC0 interior packs already in the repository.
    for dp, _, fns in os.walk(os.path.join(root, "assets", "interior")):
        for fn in fns:
            if not fn.lower().endswith(".png"):
                continue
            p = os.path.join(dp, fn)
            w, h = Image.open(p).size
            rel = os.path.relpath(p, root)
            pack_label = "Kenney Roguelike Indoors (CC0)" if "roguelike" in p else ("Kenney Furniture Kit (CC0)" if "furniture" in p else "OpenGameArt Interior 16x16 (CC0)")
            rows.append({
                "datei": rel, "paket": pack_label, "quelle_id": "cc0_interior", "kategorie": "Innenausstattung", "unterkategorie": "Möbel/Raum",
                "breite": w, "hoehe": h, "perspektive": "isometrisch (Renders)" if "isometric" in p else "Top-Down Pixel Art",
                "animation": "", "im_spiel": "", "verwendungszweck": "Innenräume (geplant)", "godot": "ja (Texture2D)",
                "lizenz": "CC0 1.0 (gemeinfrei)", "zustandsgruppe": STATE_GROUPS["innen_moebel"], "bytes": os.path.getsize(p),
            })
            key = f"{pack_label} | Innenausstattung"
            summary[key] = summary.get(key, 0) + 1
    rows.sort(key=lambda r: (r["paket"], r["kategorie"], r["datei"]))
    with open(os.path.join(out_dir, "asset_inventory.csv"), "w", newline="", encoding="utf-8") as f:
        wr = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        wr.writeheader()
        wr.writerows(rows)
    with open(os.path.join(out_dir, "inventory_summary.json"), "w", encoding="utf-8") as f:
        json.dump({"files": len(rows), "by_pack_and_category": dict(sorted(summary.items()))}, f, indent=1, ensure_ascii=False)
    print(f"{len(rows)} Dateien inventarisiert → {out_dir}")
    return 0


def _purpose(cat, sub):
    return {
        "Gebäude": "Außenwelt: Gebäude",
        "Gebäudeteile": "Gebäude-Baukasten (Ebenen)",
        "Straßen & Wege": "Außenwelt: Verkehrsflächen",
        "Boden": "Außenwelt: Boden",
        "Vegetation": "Außenwelt: Natur",
        "Stadtmöbel": "Außenwelt: Straßenmobiliar",
        "Beleuchtung": "Außenwelt: Licht",
        "Fahrzeuge": "Außenwelt: Verkehr/Deko",
        "Zäune": "Außenwelt: Grundstücksgrenzen",
        "Dekoration": "Außenwelt: Deko",
        "Innenausstattung": "Innenräume",
        "Innenraum": "Innenräume",
        "Figuren": "Spielfigur/NPCs",
        "Oberfläche": "HUD/Menüs",
        "UI-Icons": "HUD/Menüs",
        "Material (PBR)": "Editor-Hintergrund",
    }.get(cat, "")


if __name__ == "__main__":
    sys.exit(main())
