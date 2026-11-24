# ROADMAP

Phasen werden **nur nach ausdrücklicher Freigabe durch den Projektinhaber** begonnen.

| Phase | Name | Status |
|---|---|---|
| 1 | World Foundation | **Implementiert, Abnahme ausstehend** (iPhone-Test durch Projektinhaber; Penzilla-Assets fehlen) |
| 2 | World Geography | geplant |
| 3 | Living World | geplant |
| 4 | Settlement Foundation | geplant |
| 5 | Social Life | geplant |
| 6 | Economy | geplant |
| 7 | Property & Construction | geplant |
| 8 | Inter-Settlement Systems | geplant |
| 9 | Government & Politics | geplant |
| 10 | Councils & World Governance | geplant |
| 11 | Conflict & Society | geplant |
| 12 | Multiplayer Foundation (bis ~50 Spieler) | geplant |
| 13 | Persistent Multiplayer Universe | geplant |

## Phase 1 – Abnahmekriterien

| # | Kriterium | Stand |
|---|---|---|
| 1 | Projekt korrekt importierbar | ✅ lokal + CI |
| 2 | Szene startet zuverlässig | ✅ Headless, Chromium (Desktop/iPhone-Emulation), keine Fehler |
| 3 | Assets korrekt dargestellt | ⚠️ nur Platzhalter – Penzilla-Pakete nicht verfügbar |
| 4 | Spielfigur steuerbar | ✅ Tastatur, Joystick, Tippen (automatisiert getestet) |
| 5 | Kamera funktioniert | ✅ getestet |
| 6 | Touch-Eingaben funktionieren | ✅ automatisiert + Chromium-Touch-Emulation; ⏳ echtes iPhone |
| 7 | HUD sichtbar und bedienbar | ✅ |
| 8 | Webexport erfolgreich | ✅ lokal + CI |
| 9 | PWA-Grundlage vorhanden | ✅ Manifest, Service Worker, Icons, iOS-Meta |
| 10 | Build-Workflow funktioniert | ✅ CI-Lauf #1 grün |
| 11 | Deployment nachvollziehbar | ✅ Workflow + Doku; ⏳ Pages-Aktivierung/Merge nach `main` durch Projektinhaber |
| 12 | Verwendete Assets dokumentiert | ✅ ASSET_INVENTORY.md |
| 13 | Art-Direction-Regeln eingehalten | ✅ keine Fremd-Außenassets; technischer Wächter |
| 14 | Bekannte Fehler dokumentiert | ✅ siehe unten |

### Bekannte Fehler / Einschränkungen Phase 1
1. Penzilla-Assets fehlen → Platzhaltergrafik (Download durch Cloudflare-Prüfung blockiert).
2. Tippen-zum-Gehen nutzt gerade Linien; hinter Hindernissen bleibt die Figur stehen (Pfadfindung = Phase 3).
3. Y-Sortierung per Grundflächenmittelpunkt; bei sehr großen Gebäuden können später Sortierfehler auftreten.
4. Innenräume noch nicht begehbar („Betreten“ zeigt Info).
5. Keine Audio-Ausgabe.
6. Node-20-Deprecation-Hinweis in GitHub Actions (nicht blockierend).
7. Echte iPhone-Leistung unbekannt.

## Voraussetzungen für Phase 2
- Abnahme Phase 1, Bereitstellung der Penzilla-Pakete.
- Entscheidungen: Hintergrundgeschichte (WORLD_DESIGN.md), Planetengröße/Kontinentzahl, Globus als 3D-Szene (Compatibility) oder 2D-Projektion (GEOGRAPHY_SYSTEM.md).
