# BUILD_AND_DEPLOYMENT

## 1. Werkzeuge [IMPLEMENTIERT]
- **Godot 4.7.2 Stable** (offizielles Release von GitHub). Kein C#, keine Plugins.
- Export-Templates: nur `web_nothreads_release.zip` / `web_nothreads_debug.zip` werden benötigt.

## 2. Lokaler Build
```bash
godot --headless --path . --import
godot --headless --path . res://tests/test_runner.tscn          # Exitcode 0 = ok
mkdir -p build/web
godot --headless --path . --export-release "Web" build/web/index.html
node tools/serve_and_shoot.js build/web build/shots              # optional: Browser-Smoke-Test (Playwright)
```
`build/` ist in `.gitignore`.

## 3. Web-Export-Einstellungen (`export_presets.cfg`) [IMPLEMENTIERT]
| Einstellung | Wert | Grund |
|---|---|---|
| Renderer | GL Compatibility (WebGL 2) | einzig sinnvoller Web-Renderer, iOS-tauglich |
| `variant/thread_support` | **false** | keine SharedArrayBuffer/COOP/COEP nötig → GitHub Pages & iOS Safari |
| `vram_texture_compression/for_mobile` | true (ETC2/ASTC) | Speicher auf iPhone |
| `html/canvas_resize_policy` | 2 (adaptiv) | volle Fläche, Pixeldichte |
| `progressive_web_app/enabled` | true | Manifest + Service Worker + Offline-Seite |
| `progressive_web_app/display` | standalone | App-Gefühl vom Home-Bildschirm |
| `progressive_web_app/orientation` | any | Hoch- und Querformat |
| `progressive_web_app/ensure_cross_origin_isolation_headers` | false | ohne Threads nicht nötig |
| Icons | 144/180/512 aus `web/icons/` | Android/iOS |
| `html/head_include` | iOS-Meta-Tags, Theme-Farbe, Touch-CSS | Standalone-Modus, kein Gummiband-Scrollen |
| `include_filter` | `data/*.json` | JSON-Daten werden ins PCK gepackt |

**PWA-Dateien** (`index.manifest.json`, `index.service.worker.js`, `index.offline.html`, Icons) werden von Godot beim Export **erzeugt**, inklusive automatischer Cache-Versionierung. Deshalb gibt es kein handgepflegtes `web/manifest.json` / `service-worker.js` (würde mit jedem Godot-Update auseinanderlaufen). Quellen liegen in `web/icons/` und `export_presets.cfg`.

## 4. GitHub Actions (`.github/workflows/web.yml`) [IMPLEMENTIERT, in CI verifiziert]
Ablauf bei jedem Push / Pull Request:
1. Godot 4.7.2 + Web-Templates laden (gecacht).
2. `--import`
3. **Testsuite** (`tests/test_runner.tscn`) – Build bricht bei Fehlern ab.
4. Web-Export + Prüfung, dass `wasm`, `pck`, Manifest und Service Worker existieren.
5. Build als **Artefakt** (`worlds-web-<sha>`, 14 Tage) – auch für Feature-Branches herunterladbar.
6. **Deployment nach GitHub Pages nur von `main`** (Standard-Branch) oder manuell (`workflow_dispatch`).

Erster Lauf auf `claude/worlds-phase-1-foundation-5131yh`: Build, Tests, Export, Artefakt ✅; Deployment korrekt übersprungen (kein `main`).

## 5. GitHub Pages einrichten (einmalig, durch Projektinhaber) [OFFEN]
1. Repository → **Settings → Pages → Build and deployment → Source: „GitHub Actions“**.
2. Phase-1-Branch nach `main` mergen (Pull Request) **oder** Workflow manuell starten: *Actions → Build & Deploy (Web) → Run workflow* (Branch wählen). Hinweis: Die Umgebung `github-pages` erlaubt standardmäßig nur Deployments vom Standard-Branch; für Feature-Branches ggf. unter *Settings → Environments → github-pages* freigeben.
3. URL: `https://rxplxcxd.github.io/Claude-Worlds/`

## 6. iPhone-Test (durch Projektinhaber) [OFFEN]
1. URL in **Safari** öffnen, ~40 MB Download abwarten (erster Start).
2. Prüfen: Start, Joystick, Tippen-zum-Gehen, Ziehen, Pinch-Zoom, Interaktions-Taste, Menü, Hoch-/Querformat.
3. **PWA:** Teilen → „Zum Home-Bildschirm“ → vom Icon starten (Vollbild ohne Safari-Leisten).
4. Menü → „Leistungsanzeige (FPS)“ einschalten und FPS notieren.
5. Probleme bitte mit iPhone-Modell, iOS-Version, Hoch/Quer und Screenshot melden.

## 7. Bekannte Hinweise
- GitHub meldet eine Node-20-Deprecation-Warnung für `actions/*@v4` (läuft auf Node 24 weiter). Aktualisierung auf neuere Hauptversionen bei Bedarf.
- `index.wasm` ist ~39,5 MB unkomprimiert (GitHub Pages liefert komprimiert aus). Eine reduzierte Engine-Build-Variante (eigene Templates ohne 3D) ist eine spätere Optimierung (PERFORMANCE.md).
