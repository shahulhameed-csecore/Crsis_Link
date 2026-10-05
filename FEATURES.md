# Crsis_Link: Technical Feature & Value Documentation

## 1. Executive Summary

**Crsis_Link** is an Emergency Disaster Networking Platform engineered to save lives when traditional infrastructure fails. Built on a high-performance stack utilizing **Flutter** for cross-platform resilience and **Serverpod** with **PostgreSQL** for real-time data handling, the application bridges communication gaps during critical incidents. By leveraging Google's **nearby_connections** API and a local Hive database, Crsis_Link creates a robust, decentralized store-and-forward mesh network. This ensures that even in complete cellular dead zones, life-saving SOS signals can hop between devices until they reach the cloud and dispatch help.

---

## 2. Core Features & Real-World Utility

### Instant SOS & Live Tracking
- **What it does:** Allows a victim to instantly broadcast their exact coordinates and distress message to nearby volunteers, updating their position in real-time on a live radar map.
- **Technical Implementation Details:** 
  - **Frontend:** State is managed via `MapPinsManager`, a lightweight `ValueNotifier` that dynamically updates active `SosAlert` pins on the UI without rebuilding the entire tree.
  - **Backend:** The `SosEndpoint` in Serverpod manages an in-memory `_deviceLocations` cache via WebSockets (`StreamingSession`). When an SOS is triggered, the server calculates Haversine distances to target devices and posts the alert exclusively to dynamic channels (`sos_device_$targetDeviceId`) within a 5km radius.
- **Why it is helpful in a disaster:** Provides immediate situational awareness. The spatial filtering (5km radius) guarantees relevance, preventing alert fatigue and ensuring that only volunteers close enough to actually help are notified.

### Offline Store-and-Forward Mesh Network
- **What it does:** Forms a decentralized, peer-to-peer communication bridge when cellular and Wi-Fi networks collapse, allowing distress signals to travel across devices.
- **Technical Implementation Details:**
  - Built on `nearby_connections` utilizing the `P2P_CLUSTER` strategy to allow devices to simultaneously act as both clients and servers.
  - `OfflineMeshService` manages endpoints and handles incoming payloads. When a payload is received, it undergoes strict mesh validation (e.g., stripping invalid GPS bounds, truncating malicious strings).
  - Valid alerts are cached in a local **Hive** database via `OfflineCacheManager` as a first-in, first-out (FIFO) queue and then continuously re-broadcasted to newly discovered peers.
- **Why it is helpful in a disaster:** Creates a resilient "bucket brigade." If a user is trapped underground without signal, their phone will transmit the SOS via Bluetooth/WiFi Direct to passersby. The alert hops device-to-device until it reaches the edge of the disaster zone.

### Smart Synchronization Bridge
- **What it does:** Autonomously detects when a device regains cellular or Wi-Fi connectivity and offloads its local mesh queue to the global servers.
- **Technical Implementation Details:**
  - `NetworkSyncManager` listens to `Connectivity().onConnectivityChanged`.
  - Upon detecting a valid connection, it triggers `uploadPendingAlerts()`, pulling the queue from `OfflineCacheManager.getUnsyncedAlerts()`.
  - It attempts to POST each alert via `AuthManager.client.sos.broadcastSos`. If the backend returns a duplicate entry or rate limit exception (meaning another peer already uploaded the packet), the device smartly marks the local alert as synced to prevent redundant network spam.
- **Why it is helpful in a disaster:** Requires zero user intervention. Victims and volunteers do not need to constantly check their signal bars—the app silently and efficiently bridges the offline mesh queue to the cloud the millisecond connectivity is restored.

### Atomic Rescue Coordination
- **What it does:** Facilitates the "Claim, Verify, and Complete" dispatch flow, ensuring structured and collision-free volunteer coordination.
- **Technical Implementation Details:**
  - The Serverpod backend implements strict atomic state transitions utilizing raw SQL `unsafeQuery` locks. 
  - For example, `claimRescue` executes: `UPDATE "sos_alert" SET "status" = 'CLAIMED'... WHERE "id" = $sosId AND "status" = 'OPEN' RETURNING *;`. The `WHERE` clause guarantees only one volunteer can claim the alert at the database level.
  - Generates a secure, randomized 4-digit PIN that the rescuer must present to the victim to formally verify the rescue (`verifyHelperPin`).
- **Why it is helpful in a disaster:** Prevents the "bystander effect" and dispatch collisions. By locking the SOS to a specific volunteer, it stops multiple rescuers from rushing to a single victim while leaving others stranded.

---

## 3. System Architecture & Data Flow

**Tracing an SOS from a Dead Zone to Dispatch:**

1. **Trigger:** An offline victim taps SOS.
2. **Mesh Broadcast:** `OfflineMeshService` saves the alert to the local Hive DB and broadcasts the serialized payload over `nearby_connections` to local peers.
3. **Peer Relay:** A passerby's device receives the payload, adds it to its own Hive DB, and relays it to other peers in the chain.
4. **Cloud Bridge:** A peer device walks into a connected zone. `NetworkSyncManager` detects the network and automatically uploads the Hive queue to the Render-hosted Serverpod database.
5. **Backend Processing:** `SosEndpoint` sanitizes the payload, rate-limits, and inserts the alert into PostgreSQL via atomic transactions.
6. **WebSocket Spatial Broadcast:** The server pulls in-memory device locations, calculates a bounding-box and Haversine distance, and pushes the event down WebSocket streams only to volunteers within a 5km radius.

---

## 4. Extreme Disaster Resilience (Chaos Engineering)

Crsis_Link is hardened against unpredictable edge cases and malicious interference often present during chaotic emergencies:

- **Strict Payload Validation:** To prevent Denial of Service (DoS) attacks and storage overflows in the mesh network, payloads are aggressively sanitized. Messages are truncated (500 chars), phones to 20 chars, and photos capped at ~5MB. Impossible GPS coordinates (e.g., latitude > 90) are completely dropped before instantiation.
- **Debouncers & Rate Limiting:** UI and background services (like the `_isToggling` lock in `OfflineMeshService`) prevent panicked button mashing. The Serverpod backend enforces a 30-second temporal rate limit on new SOS broadcasts.
- **Database Consistency & Optimization:** 
  - Uses atomic transactions to wrap the deactivation of old pins and insertion of new ones, preventing "phantom pins" if the server crashes mid-operation.
  - Implements a pre-filter bounding box query (`±0.045°` logic) at the PostgreSQL level, drastically reducing the dataset before the heavy Haversine distance math runs in the application layer, ensuring the server stays fast under high load.
