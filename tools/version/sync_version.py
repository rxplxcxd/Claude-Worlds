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


SW_INSTALL = "self.addEventListener('install', (event) => {"
SW_ACTIVATE = "self.addEventListener('activate', (event) => {"


def patch_web(web, info):
    """Makes a new published version reach installed PWAs without clearing
    caches by hand (docs/BUILD_AND_DEPLOYMENT.md, "Updates"):
      * the page carries its build id; it compares it with version.json from
        the server (no-store) and, if it is stale, clears the old caches and
        reloads once,
      * the service worker activates at once (skipWaiting, clients.claim)
        and fetches the page itself network-first (no-cache revalidation),
      * the cache name contains the build id.
    Idempotent: a second run replaces the previous build id."""
    build = info["build"]
    html = os.path.join(web, "index.html")
    if os.path.exists(html):
        t = open(html, encoding="utf-8").read()
        t = re.sub(r"var WORLDS_BUILD='[^']*'", "var WORLDS_BUILD='%s'" % build, t)
        t = re.sub(r"var WORLDS_TECH='[^']*'", "var WORLDS_TECH='%s'" % info["technical"], t)
        open(html, "w", encoding="utf-8").write(t)
    sw = os.path.join(web, "index.service.worker.js")
    if os.path.exists(sw):
        t = open(sw, encoding="utf-8").read()
        t = re.sub(r"const CACHE_VERSION = '[^']*';", "const CACHE_VERSION = '%s';" % build, t)
        if "/*worlds-update*/" not in t:
            t = t.replace(SW_INSTALL, SW_INSTALL + "\n\tself.skipWaiting(); /*worlds-update*/", 1)
            # install from the network, not from the browser's HTTP cache (could hold the old page)
            t = t.replace("cache.addAll(CACHED_FILES)", "cache.addAll(CACHED_FILES.map((u) => new Request(u, { cache: 'reload' })))", 1)
            t = t.replace(SW_ACTIVATE, SW_ACTIVATE + "\n\tevent.waitUntil(self.clients.claim()); /*worlds-update*/", 1)
            # the page itself: network first (revalidated), cache only when offline
            t = t.replace("\t\t\t\tif (isNavigate) {",
                          "\t\t\t\tif (isNavigate) { /*worlds-update*/\n"
                          "\t\t\t\t\ttry { const fresh = await fetch(new Request(event.request.url, { cache: 'no-cache', credentials: 'same-origin' })); if (fresh && fresh.ok) { cache.put(event.request, fresh.clone()); return fresh; } } catch (e) { /* offline: fall back to the cache */ }", 1)
        open(sw, "w", encoding="utf-8").write(t)


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
        now = datetime.datetime.now(datetime.timezone.utc)
        info = {"product": v["product"], "technical": v["technical"], "channel": v.get("channel", ""), "commit": commit[:10],
                "built_at": now.strftime("%Y-%m-%d %H:%M UTC")}
        # one id per published build: the page, the service worker and version.json agree on it
        info["build"] = "%s-%s-%s" % (v["technical"], commit[:10], now.strftime("%Y%m%d%H%M%S"))
        json.dump(info, open(os.path.join(ROOT, "data", "build_info.json"), "w", encoding="utf-8"), indent=1)
        if web:
            os.makedirs(web, exist_ok=True)
            json.dump(info, open(os.path.join(web, "version.json"), "w", encoding="utf-8"), indent=1)
            patch_web(web, info)
        print("build info:", info)
    return 0


if __name__ == "__main__":
    sys.exit(main())
