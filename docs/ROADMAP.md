# ROADMAP

Phasen werden **nur nach ausdrücklicher Freigabe durch den Projektinhaber** begonnen.

| Phase | Name | Status |
|---|---|---|
| 1 | World Foundation | **Freigegeben** (Projektinhaber startete Phase 2 am 24.11.2026); iPhone-Test weiterhin offen |
| 2 | World Geography | **Implementiert (0.3.0), Abnahme ausstehend** |
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
| 3 | Assets korrekt dargestellt | ✅ alle 6 Pakete geprüft und je nach Eignung integriert (ASSET_INVENTORY §2); im veröffentlichten Build erst nach Setzen des Secrets `MEGA_ASSETS_URL` |
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
| 15 | Charakter-Editor (modular, lebendige Vorschau, Speicherung, im Spiel genutzt) | ✅ Browser + Tests (inkl. Bearbeiten-Ablauf); ⏳ iPhone |
| 16 | NPC-Rollenkleidung, dauerhaft | ✅ |
| 17 | Stadtbild nach Platzierungsregeln, Laternen mit Ausleger und Licht | ✅ |
| 18 | Figur hinter Gebäuden sichtbar | ✅ |
| 19 | Echtzeituhr mit automatischer Zeitzone/Sommerzeit | ✅ (Berlin, New York geprüft) |
| 20 | QA-Prüfliste | ✅ [QA_CHECKLIST.md](QA_CHECKLIST.md) |

### Bekannte Fehler / Einschränkungen Phase 1
1. Veröffentlichter Build zeigt Platzhalter, bis das Secret `MEGA_ASSETS_URL` gesetzt ist (Lizenzschutz, siehe ASSET_INVENTORY).
2. Tippen-zum-Gehen nutzt gerade Linien; hinter Hindernissen bleibt die Figur stehen (Pfadfindung = Phase 3).
3. Y-Sortierung per Grundflächenmittelpunkt; bei sehr großen Gebäuden können später Sortierfehler auftreten.
4. Innenräume noch nicht begehbar („Betreten“ zeigt Info); Top-Down Retro Interior + CC0-Pakete liegen bereit.
4a. NPCs wechseln den Ort ohne Weg (erscheinen am Arbeitsplatz/zu Hause); Präsenz nach Lokalzeit des Spielers statt Siedlungszeitzone.
4b. RPG-Läden sind im Detailmaßstab etwas größer als City-Builder-Häuser (bewusst, ADR-10); RPG-Häuser 2×2/3×3 noch ungenutzt.
4c. Sonnenmodell nutzt feste Breite 51° N bis Siedlungen echte Koordinaten haben (Phase 2).
5. Keine Audio-Ausgabe.
6. Node-20-Deprecation-Hinweis in GitHub Actions (nicht blockierend).
7. Echte iPhone-Leistung unbekannt.

### Designänderung 24.11.2026: Leerer Planet
Planet startet ohne Siedlungen; Siedlungen nur durch Spielergründung; keine NPC-only-Siedlungen. In Phase 1 als Regel umgesetzt (genesis.json, WorldState, Gründungsvorlage, Tests). Phase 2 muss die Planetengenese ohne Siedlungen und die Standortwahl für Gründungen liefern.

## Phase 2 – World Geography: Umfang und Stand

| Masterprompt-Punkt | Stand |
|---|---|
| Planetenmodell | ✅ Aurel, deterministisch erzeugt und gebacken (Seed 777, Generator v2) |
| Kontinente | ✅ 5 Kontinente + Inseln |
| Regionen | ✅ 157 Regionen mit Gelände, Klima, Wasser, Rohstoffen, Erschließung |
| Geografische Koordinaten | ✅ Breite/Länge, Großkreisdistanz, Zellraster |
| Weltkarte | ✅ Globus mit Infotafel, Ebenenschalter „Gebiete“ |
| Erste Globusdarstellung | ✅ 3D-Kugel, Küsten, Grenzen, Atmosphäre, Sterne |
| Zoomstufen | ✅ planetar → kontinental → regional → lokal (Siedlung betreten) |
| Siedlungsstandorte | ✅ Standortwahl + Bewertung bei der Gründung, Marker, Migration alter Spielstände |
| Territorien | ✅ Gründung beansprucht die Region; Anzeige, Regeln (keine fremde Region, Mindestabstand) |

### Bekannte Einschränkungen Phase 2
1. Lokale Siedlungskarte ist überall gleich (Vorlage), unabhängig von Region/Küste/Fluss → Phase 4.
2. Ein Gebiet = eine Region; kein Wachstum, keine Grenzen zwischen Siedlungen → Phase 4/9.
3. 49-km-Zellen wirken in der regionalen Zoomstufe grob (Grenzen als Treppenlinien).
4. Nur eine lokale Siedlung (Singleplayer); „Beitreten“ fremder Siedlungen erst mit Mehrspieler (Phase 12).
5. Kein Tag/Nacht-Schatten auf dem Globus.
6. Globus-Leistung auf echtem iPhone ungemessen.

## Voraussetzungen für Phase 3 (Living World)
- Abnahme Phase 2 (insb. Planetengröße, Gründungsregeln – GEOGRAPHY_SYSTEM.md §7).
- Entscheidungen: NPC-Anzahl je Siedlung auf dem iPhone (Leistungsbudget), Tagesablauf nach Siedlungszeitzone, offene Fragen WORLD_DESIGN.md §5 (verlassene Siedlungen).
