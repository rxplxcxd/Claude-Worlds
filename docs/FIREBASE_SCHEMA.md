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
worlds/{worldId}                                  name, seed, created_at, clock {game_minutes, real_ts}
worlds/{worldId}/continents/{continentId}
worlds/{worldId}/regions/{regionId}               terrain, climate, resources, development, territory_id
worlds/{worldId}/territories/{territoryId}
worlds/{worldId}/settlements/{settlementId}       name, region_id, stage, founder_player_id, resident_player_ids, founded_at, population_counts, summary
  ├─ buildings/{buildingId}                       type, grid, footprint, state, owner_id
  ├─ properties/{propertyId}                      parcel, owner_id, lease_contract_id
  ├─ infrastructure/{segmentId}
  ├─ inventories/{inventoryId}
  └─ snapshots/{snapshotId}                       komprimierter Zustand für Offline-Fortschreibung
worlds/{worldId}/npcs/{npcId}                     Kerndaten (Bedürfnisse/Tagesplan nur serverseitig)
  └─ memories/{memoryId}
worlds/{worldId}/businesses/{businessId}
worlds/{worldId}/contracts/{contractId}           parties (IDs), kind, terms, state
worlds/{worldId}/trade_routes/{routeId}
worlds/{worldId}/organizations/{orgId}
worlds/{worldId}/political_entities/{entityId}
  └─ laws/{lawId}
worlds/{worldId}/councils/{councilId}
  └─ sessions/{sessionId}
       └─ decisions/{decisionId}
worlds/{worldId}/events/{eventId}                 append-only Ereignisprotokoll (TTL für Altdaten)
worlds/{worldId}/world_snapshots/{snapshotId}
players/{playerId}                                profile, auth_uid, residence, settings
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
