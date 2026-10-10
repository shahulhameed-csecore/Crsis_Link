# Architecture Audit Report: Crisis Link

## 1. Overview
This report verifies whether the Crisis Link application code aligns with the intended architecture:
*   **Online Mode:** Send SOS to the server → Server broadcasts to users within a 5km radius.
*   **Offline Mode:** Store SOS in Hive → Use a store-and-forward method to sync when online.

After thoroughly auditing the codebase, **I can confirm that the core structural components for this architecture are present in your code.** 

Below is a detailed breakdown of how each part is currently implemented, along with the criteria required for it to function correctly.

---

## 2. Online Flow Verification (Server & 5km Radius)
**Requirement:** If online, it sends the SOS message to the server, and the server broadcasts to people within a 5km radius.

**Current Implementation:**
*   **Client-Side Sending:** When a user presses the SOS button, the app attempts to send an RPC request to the server using `AuthManager.client.sos.broadcastSos(...)`. 
*   **Server-Side Logic:** In the Serverpod backend (`SosEndpoint.dart`), the `broadcastSos` method receives the SOS.
*   **5km Radius Enforcement:** The server successfully implements a spatial filter. It uses the Haversine formula (`_calculateDistance`) to measure the distance between the sender and all other active devices in the `_deviceLocations` cache. It explicitly contains the following code:
    ```dart
    if (distance <= 5000) { // 5km radius
      await session.messages.postMessage('sos_device_$targetDeviceId', savedAlert);
    }
    ```
**Verdict:** ✅ **Implemented.** The server successfully enforces the 5km radius rule.

---

## 3. Offline Flow Verification (Hive & Store-and-Forward)
**Requirement:** If offline, it stores the message in Hive, and then uses a store-and-forward method.

**Current Implementation:**
*   **Hive Storage:** If the connection check fails (or if the Serverpod client throws an exception), the app falls back to `OfflineCacheManager.saveAlert(alert)`. This manager successfully opens a secure Hive box (`offline_sos_box`) and writes the alert to the local disk.
*   **Store-and-Forward:** The app has a `NetworkSyncManager` that listens to connectivity changes. When the device regains connection, it triggers `uploadPendingAlerts()`.
    *   This function retrieves all unsynced alerts from Hive: `OfflineCacheManager.getUnsyncedAlerts()`.
    *   It loops through them in small batches and attempts to forward them to the server.
    *   If successful, it marks them as synced (`alert.isSynced = true`).

**Verdict:** ✅ **Implemented.** The Hive local storage and store-and-forward mechanisms are present and structurally sound.

---

## 4. Criteria Required for this Architecture to Work
For this architecture to function reliably, the following criteria must be met by the code:

1.  **Accurate Network Detection (Criteria 1):** The app must correctly identify whether it is online or offline *before* deciding where to route the SOS. (Note: We recently fixed a bug where the `connectivity_plus` package was returning a list instead of a single value, which previously caused this check to fail and force the app into offline mode).
2.  **Idempotency / Duplicate Prevention (Criteria 2):** Because of the store-and-forward method, the server might receive the same SOS multiple times if the network is spotty. The backend must check the unique `clientAlertId` to ensure it doesn't process the same alert twice. Your code successfully does this in the `db.transaction`.
3.  **Heartbeat Location Tracking (Criteria 3):** For the 5km radius to work, the server needs to know where everyone is *before* the SOS is sent. Your app meets this criteria by having a `_heartbeatTimer` in `home_map_screen.dart` that pings the server with the user's location every 12 seconds.
4.  **Local Storage Management (Criteria 4):** The local Hive box cannot grow infinitely. Your code handles this by automatically deleting the oldest synced alerts once the box reaches 1,000 items, preventing storage exhaustion.

## Conclusion
The architectural skeleton you described is heavily present in the codebase. The app is structurally designed to handle the online spatial routing (5km) and the offline Hive store-and-forward mechanism perfectly.
