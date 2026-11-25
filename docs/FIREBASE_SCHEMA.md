# FIREBASE_SCHEMA

**Status: [GEPLANT].** Phase 1 nutzt **kein** Firebase (lokal, Singleplayer). Keine Zugangsdaten im Repository.

## 1. Rolle von Firebase
Daten- und Authentifizierungsgrundlage – **nicht** der Simulationsserver.
- **Authentication:** anonym → E-Mail/Passwort (Kontoverknüpfung), später weitere Anbieter.
- **Cloud Firestore:** Stammdaten, Snapshots, Verträge, Protokolle.
- **Realtime Database:** Präsenz, temporärer Status, Chat.
- **Storage (optional):** Profilbilder, Wappen/Flaggen.

Öffentliche Web-Konfiguration (apiKey, projectId …) ist kein Geheimnis und darf in den Client; Admin-/Service-Account-Schlüssel niemals.

## 1a. Genese
`worlds/{worldId}` wird mit Planet, Kontinenten und Regionen (nur Natur) angelegt; die Unterkollektion `settlements` ist **leer**. Ein Siedlungsdokument entsteht ausschließlich durch eine serverseitig geprüfte Gründungsanfrage eines authentifizierten Spielers und enthält Pflichtfelder `founder_player_id`, `resident_player_ids` (≥ 1), `founded_at`.

## 2. Firestore-Struktur (Vorschlag)
Kleine Dokumente, Unterkollektionen für wachsende Listen, Schreibvorgänge bündeln.

```
worlds/{worldId}                                  name, seed, created_at (UTC); Zeit = Server-UTC, keine eigene Spielzeit
(Geografie: NICHT in Firestore – gebackene Dateien data/world/planet, gleich für alle; nur veränderliche Felder:)
worlds/{worldId}/regions/{regionId}               development, territory_id (nur sobald ≠ Genesis)
worlds/{worldId}/territories/{territoryId}        owner_entity_id, kind, geometry (sphärisches Polygon), area_km2, cover_l8[] (Index-Zellen inkl. 21-km-Puffer),
                                                  status (provisional|active|dormant), version, claimed_at, last_active_at
  └ history/{changeId}                            Grenzänderungen (Erweiterung, Vertrag, Fusion)
worlds/{worldId}/expansion_claims/{claimId}       territory_id, geometry, state, deadlines, objections[]
worlds/{worldId}/settlements/{settlementId}       name, region_id, stage, founder_player_id, resident_player_ids, founded_at_unix (UTC), timezone (IANA), utc_offset_minutes_at_founding, position {lat, lon}, region_id, continent_id, territory_id, population_counts, summary
  ├─ chunks/{chunkId}                             version, terrain, parcels, buildings, road_segments, zones (Siedlungszustand, ADR-17)
  ├─ buildings/{buildingId}                       type, grid, footprint, state, owner_id
  ├─ properties/{propertyId}                      parcel, owner_id, lease_contract_id
  ├─ infrastructure/{segmentId}
  ├─ inventories/{inventoryId}
  └─ snapshots/{snapshotId}                       komprimierter Zustand für Offline-Fortschreibung
worlds/{worldId}/npcs/{npcId}                     settlement_id, name, role, workplace_id, home_id, appearance {slot: {option, color}} (Phase 1 lokal: record.npcs[]); Bedürfnisse/Tagesplan nur serverseitig
  └─ memories/{memoryId}
worlds/{worldId}/businesses/{businessId}
worlds/{worldId}/contracts/{contractId}           parties (IDs), kind, terms, state
worlds/{worldId}/trade_routes/{routeId}
worlds/{worldId}/organizations/{orgId}
worlds/{worldId}/political_entities/{entityId}
  └─ laws/{lawId}                                 rules[], effects[], level, status, version (LAW_ENGINE.md §3)
worlds/{worldId}/procedures/{procedureId}         action, actor, target, requirements, state, deadlines (Verfahren)
worlds/{worldId}/properties/{propertyId}          parcel/building, owner, shares, leases
worlds/{worldId}/councils/{councilId}
  └─ sessions/{sessionId}
       └─ decisions/{decisionId}
worlds/{worldId}/events/{eventId}                 append-only Ereignisprotokoll (TTL für Altdaten)
worlds/{worldId}/world_snapshots/{snapshotId}
players/{playerId}                                profile, auth_uid, residence, settings, display_name, appearance {slot: {option, color}} (Phase 1 lokal: LocalProfile.character)
  └─ relationships/{otherId}
resources/{goodId}                                Stammdaten (global, read-only)
```
Beziehungen: als Unterkollektion pro Person (Kante je Dokument) statt großer Arrays.

## 3. Realtime Database
```
presence/{playerId}: {online, last_changed, settlement_id}
status/{settlementId}/{playerId}: {activity, position (grob)}
chat/{channelId}/{messageId}
```

## 4. Security Rules – Grundsätze (Entwurf)
```js
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {
    // Standard: alles verboten
    match /{document=**} { allow read, write: if false; }

    // Eigenes Profil lesen/teilweise schreiben (keine Spielwerte wie Geld!)
    match /players/{playerId} {
      allow read: if request.auth != null;
      allow update: if request.auth.uid == resource.data.auth_uid
                    && request.resource.data.diff(resource.data).affectedKeys()
                         .hasOnly(['profile', 'settings']);
    }
    // Weltdaten: lesen für Angemeldete, schreiben nur Server (Admin SDK umgeht Rules)
    match /worlds/{worldId}/{rest=**} {
      allow read: if request.auth != null;
      allow write: if false;
    }
  }
}
```
Spielrelevante Werte (Geld, Ressourcen, Eigentum, Verträge, Abstimmungen) schreibt **ausschließlich** der autoritative Server.

## 5. Offene Fragen [OFFEN]
Godot-Anbindung im Web: JavaScriptBridge zum Firebase-JS-SDK vs. REST-API (Empfehlung: JS-SDK über `JavaScriptBridge` für Auth/Realtime; Server per WebSocket). Serverplattform (Cloud Run/Container mit Godot-Headless oder eigener Simulationskern).


## 6. Weltautorität und Firestore [VORBEREITET 0.6.0 – Umsetzung Phase 12/13]
Firestore ist **Speicher**, nicht der Simulationsserver:
| Pfad (Vorschlag) | Inhalt | Schreiber |
|---|---|---|
| `worlds/{w}/settlements/{s}` | Snapshot des Siedlungsdatensatzes (`npcs`, `core`, `lifecycle`, `visual_states`, `nav_changes`, `region_factors`, `climate`) | nur der Simulationsdienst |
| `worlds/{w}/settlements/{s}/log/{seq}` | Befehle (`command_id`, Absender, Art, Daten, Zeit) | nur der Simulationsdienst (nach Prüfung) |
| `worlds/{w}/commands/{command_id}` | eingehende Befehle der Clients | Clients (nur eigene, Security Rules) |
Ablauf: Client schreibt Befehl → Dienst prüft (`WorldAuthority.submit`: Rechte, Regeln, Idempotenz) → wendet an, schreibt Protokoll + Snapshot → Clients lesen Snapshots. Kontolöschung ersetzt Spieler-IDs in Siedlungsdaten durch Pseudonyme (`plr_deleted_…`).
