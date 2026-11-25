#!/usr/bin/env python3
"""Keeps the version single-sourced (data/version.json).

Usage:
    python3 tools/version/sync_version.py            # project.godot ← technical version
    python3 tools/version/sync_version.py --build [<web_dir>] [<commit>]
        additionally writes data/build_info.json (read by the game) and, if a
        web export dir is given, <web_dir>/version.json (read by the loading
        screen before the engine starts).
"""
import datetime
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main():
    v = json.load(open(os.path.join(ROOT, "data", "version.json"), encoding="utf-8"))
    pg = os.path.join(ROOT, "project.godot")
    text = open(pg, encoding="utf-8").read()
    new = re.sub(r'config/version="[^"]*"', 'config/version="%s"' % v["technical"], text)
    if new != text:
        open(pg, "w", encoding="utf-8").write(new)
        print("project.godot → %s" % v["technical"])
    if "--build" in sys.argv:
        args = [a for a in sys.argv[1:] if a != "--build"]
        web = args[0] if args else ""
        commit = args[1] if len(args) > 1 else ""
        if not commit:
            try:
                commit = subprocess.check_output(["git", "rev-parse", "--short=10", "HEAD"], cwd=ROOT, text=True).strip()
            except Exception:
                commit = "lokal"
        info = {"product": v["product"], "technical": v["technical"], "channel": v.get("channel", ""), "commit": commit[:10],
                "built_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")}
        json.dump(info, open(os.path.join(ROOT, "data", "build_info.json"), "w", encoding="utf-8"), indent=1)
        if web:
            os.makedirs(web, exist_ok=True)
            json.dump(info, open(os.path.join(web, "version.json"), "w", encoding="utf-8"), indent=1)
        print("build info:", info)
    return 0


if __name__ == "__main__":
    sys.exit(main())
