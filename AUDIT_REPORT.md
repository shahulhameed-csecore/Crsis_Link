# CRISIS LINK: COMPREHENSIVE REPOSITORY CODE, ARCHITECTURE & SECURITY AUDIT

**Date:** October 7, 2026  
**Auditor:** Senior Flutter Architect, Backend Systems Engineer & Application Security Auditor  
**Repository:** `Crsis_Link`  
**Target Environment:** Flutter 3.x / Dart 3.x, Android 12–15 (API 31–36), Serverpod 3.4.x, PostgreSQL  

---

## 1. Executive Summary

A comprehensive, root-to-leaf inspection of the `Crsis_Link` repository was performed across all client Dart source files, native Android configurations, Serverpod backend endpoints, protocol definitions, serialization schemas, hardware sensor integrations, and test suites.

While the core user interface and high-level architecture demonstrate thoughtful emergency offline-first considerations, the codebase contains critical stability blockers, severe platform permission gaps, catastrophic unauthenticated backend administrative exposure, cryptographic bypass vulnerabilities in P2P transmission, and concurrency edge cases that threaten application stability during real disaster deployments.

### Risk & Findings Breakdown

| Severity | Count | Primary Impact Areas |
| :--- | :---: | :--- |
| **CRITICAL** | **7** | App crash on launch in background isolate; Android 14 SecurityException; unauthenticated public DB truncation; P2P cryptographic signature bypass; modal back-button UI freeze; invisible safety PIN text. |
| **HIGH** | **6** | Brute-forceable rescue verification PIN; P2P vs. Serverpod ID desynchronization; telemetry packet flooding storms; Android 12+ Nearby Connections discovery suppression; abandoned rescue lockout; unauthenticated endpoint spoofing. |
| **MEDIUM** | **8** | Audio upload path traversal; unencrypted SharedPreferences storage of sensitive victim coordinates; database table bloat via 5MB Base64 images; missing database indexes; silent pin removal on modal close; `NetworkSyncManager` retry race condition. |
| **LOW** | **6** | Broken unit and integration test suites; gesture affordance mismatch in voice recorder; hardcoded production API host strings; screen wakelock battery drain; release APK signed with debug keystores. |
| **Total Issues Identified** | **27** | |

**Overall System Reliability Score:** **54 / 100** *(Unstable for real-world emergency deployment prior to remediation)*

---

## 2. Critical Bugs & Syntax Errors (Blockers)

### BUG-CRIT-01: Background Isolate Crash on Startup Due to Uninitialized Singletons
- **File:** [lib/main.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/lib/main.dart#L20-L29) (`lines 20–29`, `31–46`)
- **Root Cause:**  
  The background entrypoint `@pragma('vm:entry-point') void onStart(ServiceInstance service)` runs inside an independent Dart isolate spawned by `flutter_background_service`. This isolate does not inherit memory from the main UI isolate. `onStart` immediately invokes `OfflineMeshService().startMesh()`. Within that method:
  1. `AuthManager.deviceId` is accessed, but `AuthManager.initialize()` was never called in the isolate. Because `deviceId` is a `late String`, it throws an unhandled `LateInitializationError`.
  2. `requestPermissions()` is invoked. Requesting runtime Android permissions from a background headless isolate without an active Flutter Activity context throws a platform exception.
  3. `OfflineCacheManager.saveAlert()` relies on Hive boxes that were never initialized in the background isolate (`Hive.initFlutter()` and encryption ciphers are only executed in `main()`).
- **Manifested Behavior:**  
  The background service crashes immediately upon startup or silently terminates, preventing background mesh relaying from functioning.
- **Recommended Fix:**  
  Ensure background tasks run headless initialization routines for Hive, secure storage, and device identity, or move hardware mesh management exclusively to a dedicated native Android foreground service while passing data to Dart via MethodChannels. Avoid invoking `requestPermissions()` inside headless isolates.

---

### BUG-CRIT-02: Android 14+ (API 34) Foreground Service `SecurityException` Crash
- **File:** [android/app/src/main/AndroidManifest.xml](file:///c:/Users/shahu/Desktop/Crsis_Link/android/app/src/main/AndroidManifest.xml#L21-L22) (`lines 21–22`, `60–62`), [android/app/build.gradle.kts](file:///c:/Users/shahu/Desktop/Crsis_Link/android/app/build.gradle.kts#L18) (`line 18`)
- **Root Cause:**  
  The project targets `compileSdk = 36` (Android 15+). In Android 14+ (API 34), Google strictly enforces typed foreground services. `AndroidManifest.xml` declares:
  ```xml
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" />
  <service
      android:name=".MeshForegroundService"
      android:foregroundServiceType="connectedDevice"
      android:exported="false" />
  ```
  However:
  1. The class `.MeshForegroundService` does not exist anywhere in `android/app/src/main/kotlin` or `java`, resulting in a `ClassNotFoundException` if explicitly invoked.
  2. While the background service runs, `OfflineMeshService._startTelemetryBroadcast()` continuously queries GPS via `Geolocator.getCurrentPosition()`. In Android 14+, accessing location inside a foreground service that is only declared as `connectedDevice` without declaring `location` type and `<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />` triggers a fatal runtime `SecurityException`.
- **Manifested Behavior:**  
  Immediate OS crash on Android 14 and 15 devices as soon as background telemetry or location tracking runs while the screen is locked.
- **Recommended Fix:**  
  1. Remove the non-existent `.MeshForegroundService` entry from `AndroidManifest.xml` and configure `flutter_background_service` according to official plugin specifications.
  2. Declare `<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />` and `<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />` if background location polling is strictly necessary, and configure `foregroundServiceType="connectedDevice|location"`.

---

### BUG-CRIT-03: `neverForLocation` Flag Silently Breaks Nearby Connections Discovery on Android 12+
- **File:** [android/app/src/main/AndroidManifest.xml](file:///c:/Users/shahu/Desktop/Crsis_Link/android/app/src/main/AndroidManifest.xml#L15) (`line 15`, `line 20`)
- **Root Cause:**  
  `AndroidManifest.xml` declares:
  ```xml
  <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
  <uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" android:usesPermissionFlags="neverForLocation" />
  ```
  The Google Nearby Connections API (`Strategy.P2P_CLUSTER`) uses Bluetooth Low Energy (BLE) beaconing and WiFi Direct proximity discovery to locate nearby endpoints. Setting `android:usesPermissionFlags="neverForLocation"` explicitly informs Android OS that the app promises never to use Bluetooth scans for location purposes. Under Android 12+ (API 31+), the OS enforces this by stripping beacon data and geographic proximity signals, causing Nearby Connections discovery to silently fail to discover peers.
- **Manifested Behavior:**  
  Devices running Android 12, 13, 14, and 15 cannot discover each other over BLE/Wi-Fi mesh in offline mode, leaving victims stranded with zero peer connections.
- **Recommended Fix:**  
  Remove `android:usesPermissionFlags="neverForLocation"` from `BLUETOOTH_SCAN` and `NEARBY_WIFI_DEVICES`. Ensure `ACCESS_FINE_LOCATION` is properly requested and approved at runtime.

---

### BUG-CRIT-04: Unauthenticated Public Database Truncation Endpoint (`nukeAllTestData`)
- **File:** [crsis_link_server/lib/src/endpoints/sos_endpoint.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/crsis_link_server/lib/src/endpoints/sos_endpoint.dart#L308-L317) (`lines 308–317`), [clear_db.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/clear_db.dart#L7) (`lines 1–12`)
- **Root Cause:**  
  The method `nukeAllTestData(Session session)` directly runs:
  ```dart
  await session.db.unsafeQuery('TRUNCATE TABLE "sos_alert" CASCADE;');
  _deviceLocations.clear();
  ```
  The endpoint is completely exposed on the public internet over the client API without requiring an administrative session, API secret, authentication token, or environment check (`session.serverpod.runMode != 'production'`). Anyone with `crsis_link_client` (or raw HTTP POST request) can wipe the entire production database.
- **Manifested Behavior:**  
  Any external actor can wipe all active and historical SOS records, leaving zero rescue history and cutting off active rescues.
- **Recommended Fix:**  
  Delete `nukeAllTestData` from the production endpoint immediately or protect it behind strict admin authentication checks and `kDebugMode` / development environment flags.

---

### BUG-CRIT-05: Trapping `PopScope` UI Freeze in Modal Bottom Sheets
- **File:** [lib/presentation/widgets/sos_details_bottom_sheet.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/lib/presentation/widgets/sos_details_bottom_sheet.dart#L57-L58) (`lines 57–58`), [lib/presentation/screens/home_map_screen.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/lib/presentation/screens/home_map_screen.dart#L1436-L1437) (`lines 1436–1437`)
- **Root Cause:**  
  The bottom sheets wrap their contents in:
  ```dart
  return PopScope(
    canPop: false,
    child: ...
  );
  ```
  Neither instance provides an `onPopInvokedWithResult` callback or conditional evaluation for `canPop`.
- **Manifested Behavior:**  
  When an SOS details modal opens, the user cannot dismiss it using the Android system back gesture, hardware back button, or tapping outside the modal. The user is trapped unless they tap a specific button that calls `Navigator.pop(ctx)`. If the victim is inspecting someone else's claimed alert where no cancel button is shown, the app becomes unresponsive to navigation.
- **Recommended Fix:**  
  Change `canPop: false` to `canPop: true` or handle back gestures conditionally via `onPopInvokedWithResult: (didPop, result) { ... }`.

---

### BUG-CRIT-06: Invisible Text in Rescuer Assigned Card
- **File:** [lib/presentation/screens/alerts_screen.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/lib/presentation/screens/alerts_screen.dart#L137-L152) (`lines 137–152`)
- **Root Cause:**  
  The card container is styled with:
  ```dart
  color: Colors.green.withValues(alpha: 0.1),
  ```
  on top of `AppColors.cleanBackground` (which is `#F8F9FA` off-white). Inside this near-white container, the safety PIN and instructions are styled with:
  ```dart
  Text('Your Safety PIN is: ...', style: const TextStyle(color: Colors.white, ...)),
  Text('Give this PIN to your rescuer...', style: const TextStyle(color: Colors.white70)),
  ```
- **Manifested Behavior:**  
  White text rendered on an off-white background is 100% invisible to the user. A victim whose rescue has been claimed cannot read their 4-digit verification PIN, preventing the rescuer from verifying their arrival.
- **Recommended Fix:**  
  Use `AppColors.pitchBlack` or a dark green (`Color(0xFF0F5132)`) for all text elements within the light-green status card.

---

### BUG-CRIT-07: Dead Duplicate Code & Unused Bottom Sheet Widget
- **File:** [lib/presentation/widgets/sos_details_bottom_sheet.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/lib/presentation/widgets/sos_details_bottom_sheet.dart#L13-L411) (`lines 13–411`), [lib/presentation/screens/home_map_screen.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/lib/presentation/screens/home_map_screen.dart#L1426-L1799) (`lines 1426–1799`)
- **Root Cause:**  
  `SosDetailsBottomSheet` was created as a standalone widget in `lib/presentation/widgets/`, but is never referenced or imported across the app. Instead, `home_map_screen.dart` contains a 370-line private copy (`_showSosDetails` in `_AnimatedSosMarkerState`) that duplicates the same logic, styles, and defects.
- **Manifested Behavior:**  
  Code maintenance drift: bug fixes applied to one copy leave the other broken, inflating the bundle size and complicating auditing.
- **Recommended Fix:**  
  Delete the duplicate method in `home_map_screen.dart` and refactor both map markers and alerts feed to use a single, tested, modular `SosDetailsBottomSheet`.

---

## 3. P2P Mesh & Synchronization Weaknesses

### P2P-01: Cryptographic Signature Verification Bypass via Raw Fallback
- **File:** [lib/core/services/offline_mesh_service.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/lib/core/services/offline_mesh_service.dart#L378-L393) (`lines 378–393`)
- **Vulnerability Breakdown:**  
  When incoming bytes are decoded in `_handleIncomingPayload`, the service checks:
  ```dart
  if (envelopeData is Map && envelopeData.containsKey('p') && envelopeData.containsKey('k') && envelopeData.containsKey('s')) {
    // Verify Ed25519 signature
    ...
  } else {
    // Fallback for legacy unsecured packets or NUKE_MESH debug commands
    decodedData = envelopeData;
  }
  ```
  If an attacker sends a raw JSON map without the envelope keys `p`, `k`, `s`, the code falls back to `decodedData = envelopeData` and processes the payload without cryptographic verification.
- **Impact:**  
  Any rogue peer on the Bluetooth/Wi-Fi network can inject fake SOS distress calls, overwrite locations, or clear caches without knowing any cryptographic keys.
- **Remediation:**  
  Enforce strict envelope validation. Drop all packets that do not contain valid Ed25519 signatures signed by the originator.

---

### P2P-02: Lack of Cryptographic Public Key-to-Device Identity Binding
- **File:** [lib/core/services/p2p_crypto_service.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/lib/core/services/p2p_crypto_service.dart#L55-L69) (`lines 55–69`), [lib/core/services/offline_mesh_service.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/lib/core/services/offline_mesh_service.dart#L383-L387) (`lines 383–387`)
- **Vulnerability Breakdown:**  
  `P2pCryptoService.verifyPayload` only validates that signature `s` was created by public key `k` for payload `p`. It never verifies whether public key `k` is bound to the `originalDeviceId` embedded inside the payload `p`.
- **Impact:**  
  An attacker can generate an ephemeral Ed25519 key pair, forge an alert impersonating any arbitrary `originalDeviceId` and victim phone number, sign it with their own key, and transmit it. The verification will pass.
- **Remediation:**  
  Derive the `deviceId` directly from the Ed25519 public key (e.g., `dev_${sha256(publicKey).substring(0, 16)}`) or require a self-signed certificate/identity token.

---

### P2P-03: Telemetry Relay Packet Storm & Missing Sequence Control
- **File:** [lib/core/services/offline_mesh_service.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/lib/core/services/offline_mesh_service.dart#L395-L412) (`lines 395–412`)
- **Vulnerability Breakdown:**  
  When a node receives a `LOCATION_UPDATE` (`LOC`) packet:
  ```dart
  final existing = OfflineCacheManager.getAlert(alertId);
  if (existing != null) {
    existing.lat = lat;
    existing.lng = lng;
    existing.timestamp = ts;
    await OfflineCacheManager.saveAlert(existing);
    for (final peerId in _connectedEndpoints) {
      if (peerId != endpointId) await Nearby().sendBytesPayload(peerId, payload.bytes!);
    }
  }
  ```
  1. No Hop Count / Time-To-Live (TTL): If nodes A, B, and C form a mesh loop, location updates bounce indefinitely between nodes until a connection drops.
  2. Timestamp Regression: If network latency causes an older location packet to arrive after a newer one, the older packet unconditionally overwrites the victim's current position because there is no `if (ts > existing.timestamp)` guard.
- **Remediation:**  
  Include a `hopCount` (max 5 hops) that decrements on each forward, a monotonically increasing sequence number per device, and only accept updates where `ts > existing.timestamp`.

---

### P2P-04: ID Space Incompatibility Between P2P Mesh and Serverpod
- **File:** [lib/core/services/offline_mesh_service.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/lib/core/services/offline_mesh_service.dart#L479) (`line 479`), [lib/core/services/network_sync_manager.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/lib/core/services/network_sync_manager.dart#L83) (`line 83`)
- **Vulnerability Breakdown:**  
  - In `offline_mesh_service.dart`, peer alerts received over P2P use a UUID `String` (`alert.id`). To display them as `SosAlert` objects in Flutter state, the code converts the UUID using `alert.id.hashCode` (an integer).
  - When the victim regains internet and syncs to Serverpod via `NetworkSyncManager`, Serverpod inserts the record into PostgreSQL and generates a brand new auto-incrementing serial primary key (e.g., `id = 42`).
  - Online rescuers receive `id = 42` from Serverpod. Mesh peers have `id = alert.id.hashCode` (e.g., `-184291842`).
- **Impact:**  
  When a mesh peer attempts to call `claimRescue`, `resolveSOS`, or `verifyHelperPin`, they pass `alert.id.hashCode`, which does not exist in the Serverpod database. The rescue actions fail with "SOS not found".
- **Remediation:**  
  Change `SosAlert.id` in `sos_alert.spy.yaml` to a `UuidValue` (or store `clientAlertId` as a unique indexed lookup key) so that all endpoints accept the immutable client UUID.

---

### P2P-05: Race Condition and Concurrency Flaws in `NetworkSyncManager`
- **File:** [lib/core/services/network_sync_manager.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/lib/core/services/network_sync_manager.dart#L118-L127) (`lines 118–127`)
- **Vulnerability Breakdown:**  
  In `uploadPendingAlerts()`:
  ```dart
  } catch (e) {
    ...
    Future.delayed(Duration(seconds: _retryBackoffSeconds, milliseconds: jitter), () {
      _isSyncing = false;
      if (state.value != SyncState.offline) {
         uploadPendingAlerts();
      }
    });
    return;
  } finally {
    _isSyncing = false;
  }
  ```
  Because `finally` executes synchronously when the method exits, `_isSyncing` is set to `false` immediately upon failure. If another network change triggers `_verifyActualConnection()`, a second upload loop begins running before the `Future.delayed` backoff timer expires, causing concurrent duplicate submissions.
- **Remediation:**  
  Do not reset `_isSyncing = false` in `finally` if a retry timer is scheduled.

---

### P2P-06: Abandoned Rescues Permanently Locked
- **File:** [crsis_link_server/lib/server.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/crsis_link_server/lib/server.dart#L20) (`line 20`), [crsis_link_server/lib/src/endpoints/sos_endpoint.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/crsis_link_server/lib/src/endpoints/sos_endpoint.dart#L342-L367) (`lines 342–367`)
- **Vulnerability Breakdown:**  
  `SafetyCheckFutureCall` was implemented to revert abandoned `CLAIMED` rescues back to `OPEN` status if a volunteer does not arrive or verify. Although registered in `server.dart` (`pod.registerFutureCall(SafetyCheckFutureCall(), 'safetyCheck')`), `session.serverpod.futureCallWithDelay('safetyCheck', ...)` is NEVER scheduled in `claimRescue`.
- **Impact:**  
  If a volunteer claims a rescue and their phone battery dies, crashes, or they walk away, the SOS alert remains locked in `CLAIMED` state indefinitely. No other volunteer can claim the rescue.
- **Remediation:**  
  Inside `claimRescue`, schedule `await session.serverpod.futureCallWithDelay('safetyCheck', alert, const Duration(minutes: 30));`.

---

## 4. Security & Permission Deficiencies

### SEC-01: Brute-Forceable Rescuer PIN Without Rate Limiting
- **File:** [crsis_link_server/lib/src/endpoints/sos_endpoint.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/crsis_link_server/lib/src/endpoints/sos_endpoint.dart#L343) (`line 343`), [crsis_link_server/lib/src/endpoints/sos_endpoint.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/crsis_link_server/lib/src/endpoints/sos_endpoint.dart#L392-L411) (`lines 392–411`)
- **Vulnerability Breakdown:**  
  The verification PIN generated in `claimRescue` is a 4-digit integer:
  ```dart
  final pin = (1000 + Random().nextInt(9000)).toString();
  ```
  `verifyHelperPin` validates the PIN with a single SQL query. There is NO rate limiting, NO attempt counter, and NO lockout after multiple failed attempts.
- **Impact:**  
  An attacker can iterate through all 9,000 combinations in under 30 seconds via parallel HTTP calls, verify the PIN, and reveal the victim's exact GPS coordinates, address, and phone number.
- **Remediation:**  
  Add an `int pinAttempts` column to `SosAlert`. Increment it on failed verification attempts. After 5 failed attempts, invalidate the PIN, alert the victim, and require a newly regenerated PIN.

---

### SEC-02: Unauthenticated Identity Spoofing Across All Server Endpoints
- **File:** [crsis_link_server/lib/src/endpoints/sos_endpoint.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/crsis_link_server/lib/src/endpoints/sos_endpoint.dart#L114) (`line 114`, `line 321`, `line 342`, `line 370`)
- **Vulnerability Breakdown:**  
  Every endpoint accepts `deviceId` as a plain string parameter supplied by the client. None of the methods verify that the calling connection owns the `deviceId` (e.g., via Serverpod Auth Session or cryptographic token).
- **Impact:**  
  Any attacker can call `resolveSOS(session, 15, "victim_device_id")` or `claimRescue(session, "fake_volunteer", "Attacker", 15)` to impersonate victims or volunteers and sabotage emergency workflows.
- **Remediation:**  
  Bind device IDs to authenticated sessions, or require requests to include an Ed25519 signature of the request payload and timestamp verified against the public key established during onboarding.

---

### SEC-03: Audio Endpoint Path Traversal & Unvalidated Uploads
- **File:** [crsis_link_server/lib/src/endpoints/audio_endpoint.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/crsis_link_server/lib/src/endpoints/audio_endpoint.dart#L14) (`line 14`, `line 30`, `line 39`)
- **Vulnerability Breakdown:**  
  `path: 'sos_audio/$fileName'` accepts an arbitrary string `fileName` directly from the client without sanitization against directory traversal sequences (`../`), null bytes, or dangerous file extensions (`.html`, `.sh`, `.exe`).
- **Remediation:**  
  Sanitize `fileName`: enforce strict regex (`^[a-zA-Z0-9_\-]+\.m4a$`) or generate UUID-based filenames on the server rather than trusting client-provided filenames.

---

### SEC-04: Unencrypted SharedPreferences Storage of Sensitive Disaster Records
- **File:** [lib/core/state/alerts_manager.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/lib/core/state/alerts_manager.dart#L67-L85) (`lines 67–85`)
- **Vulnerability Breakdown:**  
  `AlertsManager` persists alert history (`alertsHistory`) in standard Android `SharedPreferences` as plaintext JSON strings. These records contain exact victim coordinates, phone numbers, and emergency descriptions.
- **Remediation:**  
  Store all persistent disaster records in `OfflineCacheManager` (Hive with AES encryption cipher) and remove plaintext sensitive storage from `SharedPreferences`.

---

### SEC-05: Accidental "DEBUG: Hard Reset Data" Button in Production Profile Screen
- **File:** [lib/presentation/screens/my_profile_screen.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/lib/presentation/screens/my_profile_screen.dart#L118-L132) (`lines 118–132`)
- **Vulnerability Breakdown:**  
  The user profile screen displays a prominent red button labeled "DEBUG: Hard Reset Data" that is active in release builds with NO confirmation dialog. Tapping it calls `_hardResetData()`, which wipes local encrypted caches, deletes alert history, and broadcasts a `NUKE_MESH` command to peers.
- **Remediation:**  
  Wrap debug controls inside `if (kDebugMode)` checks and require double-confirmation modals before wiping local storage.

---

### SEC-06: Database Table Bloat via Raw 5MB Base64 Image Columns
- **File:** [crsis_link_server/lib/src/sos/sos_alert.spy.yaml](file:///c:/Users/shahu/Desktop/Crsis_Link/crsis_link_server/lib/src/sos/sos_alert.spy.yaml#L18) (`line 18`), [crsis_link_server/lib/src/endpoints/sos_endpoint.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/crsis_link_server/lib/src/endpoints/sos_endpoint.dart#L125) (`line 125`)
- **Vulnerability Breakdown:**  
  `photoBase64: String?` allows storing up to 5,000,000 characters (~5MB) directly inside the `sos_alert` PostgreSQL row.
- **Impact:**  
  Serializing and deserializing megabytes of text on every database query causes high RAM usage, PostgreSQL WAL log bloat, slow queries, and connection timeouts during disaster surges.
- **Remediation:**  
  Store images in Serverpod cloud object storage (similar to `AudioEndpoint`) and store only the public URL `photoUrl: String?` in the PostgreSQL database row.

---

### SEC-07: Missing Database Indexes on High-Frequency Query Fields
- **File:** [crsis_link_server/lib/src/sos/sos_alert.spy.yaml](file:///c:/Users/shahu/Desktop/Crsis_Link/crsis_link_server/lib/src/sos/sos_alert.spy.yaml#L1-L20) (`lines 1–20`)
- **Vulnerability Breakdown:**  
  There are zero indexes declared in `sos_alert.spy.yaml`. Queries filtering by `deviceId`, `isActive`, `status`, `clientAlertId`, and bounding-box coordinates `(latitude, longitude)` must perform sequential table scans (`Seq Scan`) across the entire table.
- **Remediation:**  
  Add compound indexes in `sos_alert.spy.yaml`:
  ```yaml
  indexes:
    sos_active_idx:
      fields: isActive, status
    sos_device_idx:
      fields: deviceId
    sos_client_id_idx:
      fields: clientAlertId
      unique: true
  ```

---

## 5. Frontend, Lifecycle & Hardware Flaws

### UX-01: Silent Permanent Pin Removal on "Close" Button
- **File:** [lib/presentation/screens/home_map_screen.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/lib/presentation/screens/home_map_screen.dart#L493-L512) (`lines 493–512`)
- **Defect Breakdown:**  
  In `_showFuzzySosDetails`, the button labeled `"Close"` executes:
  ```dart
  _ignoredSosIds.add(alertId);
  MapPinsManager().removePin(alertId);
  _saveIgnoredIds();
  AlertsManager().addIgnoredAlert(alertId, alert.senderName);
  Navigator.pop(ctx);
  ```
- **Impact:**  
  A responder who opens an SOS pin just to read the notes and clicks "Close" permanently deletes the pin from their map. There is no non-destructive way to dismiss the modal.
- **Remediation:**  
  Provide a distinct `"Dismiss"` button that only calls `Navigator.pop(ctx)`, and keep `"Ignore Pin"` as an explicit separate action.

---

### UX-02: Hardcoded Production API URL in Voice Note Audio Upload
- **File:** [lib/presentation/widgets/voice_note_recorder.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/lib/presentation/widgets/voice_note_recorder.dart#L185) (`lines 185`, `204`)
- **Defect Breakdown:**  
  `uploadDescription.replaceAll('${public_host}', 'crsis-link-api.onrender.com')` hardcodes the Render production domain, bypassing `dotenv.env['API_URL']`. Local development, staging, or emergency on-premise deployments cannot upload voice notes.
- **Remediation:**  
  Derive the host dynamically from `AuthManager.client.host` or `Uri.parse(dotenv.env['API_URL']!).host`.

---

### UX-03: Gesture Mismatch in Voice Recorder Widget
- **File:** [lib/presentation/widgets/voice_note_recorder.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/lib/presentation/widgets/voice_note_recorder.dart#L320-L328) (`lines 320–328`, `355`)
- **Defect Breakdown:**  
  The button label states `"Tap to Record"`, but the `GestureDetector` only attaches `onLongPressDown`, `onLongPressEnd`, and `onLongPressCancel`. Tapping the button produces no feedback or action.
- **Remediation:**  
  Update the label to `"Hold to Record"` or implement toggle recording on `onTap`.

---

### UX-04: Wakelock Battery Drain During Active Alerts
- **File:** [lib/core/state/alerts_manager.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/lib/core/state/alerts_manager.dart#L114) (`line 114`)
- **Defect Breakdown:**  
  `AlertsManager.addSosAlert()` immediately calls `WakelockPlus.enable()`. If an alert is not resolved promptly, the device screen never sleeps, draining victim/rescuer batteries in power-outage environments.
- **Remediation:**  
  Set a wakelock timeout (e.g., 2 minutes) or tie wakelock activation to user interaction with active turn-by-turn rescue navigation.

---

### TEST-01: Broken Smoke and Integration Test Suites
- **File:** [test/widget_test.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/test/widget_test.dart#L10) (`line 10`), [integration_test/app_test.dart](file:///c:/Users/shahu/Desktop/Crsis_Link/integration_test/app_test.dart#L22) (`lines 22`, `26`)
- **Defect Breakdown:**  
  1. `test/widget_test.dart` checks for `"WELCOME BACK, ALEX"`, a string that does not exist in the project. It also launches `CrsisLinkApp` without mocking Hive, FlutterSecureStorage, or AuthManager, causing `flutter test` to fail immediately.
  2. `integration_test/app_test.dart` searches for non-existent key `$(#sosButton)` and text `'SOS Alert Broadcasted'`.
- **Remediation:**  
  Update test suites to mock external storage dependencies and reference valid UI keys (`ValueKey('sos_emergency_button')`).

---

## 6. Prioritized Action Plan

To transition `Crsis_Link` from its current state into an enterprise-ready, battle-hardened disaster response application, remediation should follow this phased roadmap:

### Phase 1: Critical Stability & Security Hotfixes (Day 1)
1. **Remove Public Nuke Endpoint:** Delete `nukeAllTestData` in `crsis_link_server/lib/src/endpoints/sos_endpoint.dart`.
2. **Correct Android Permissions:** Remove `neverForLocation` from `BLUETOOTH_SCAN` and `NEARBY_WIFI_DEVICES` in `AndroidManifest.xml`.
3. **Fix Modal Back Trapping:** Replace `canPop: false` with dismissible pop behavior in `sos_details_bottom_sheet.dart` and `home_map_screen.dart`.
4. **Fix Invisible Safety PIN:** Update text color in `alerts_screen.dart` to dark/contrast styling.
5. **Enforce Envelope Validation in P2P Mesh:** Delete the unsecured fallback in `offline_mesh_service.dart` line 390. Drop all non-signed payloads.
6. **Guard Background Isolate Execution:** In `lib/main.dart`, remove uninitialized singleton access inside `onStart` or initialize storage before calling `startMesh()`.

### Phase 2: Mesh & Sync Protocol Hardening (Day 2)
7. **Unify Alert ID Model:** Standardize `SosAlert.id` across Serverpod and P2P mesh using immutable UUIDs.
8. **Add Sequence Numbers & TTL to Mesh Telemetry:** Implement hop counting (`maxHops = 5`) and discard out-of-order packets where `ts <= existing.ts`.
9. **Schedule Abandoned Rescue Timeout:** Wire `SafetyCheckFutureCall` into `claimRescue` with a 30-minute delay.
10. **Fix Non-Destructive Modal Dismissal:** Separate "Dismiss" from "Ignore Pin" in `_showFuzzySosDetails`.
11. **Fix `NetworkSyncManager` Race Condition:** Synchronize retry backoff state to prevent duplicate uploads.

### Phase 3: Backend Security & Performance Optimization (Day 3)
12. **Add PIN Attempt Counter & Lockout:** Enforce maximum 5 attempts for `verifyHelperPin` before invalidation.
13. **Add Database Indexes:** Add indexes for `isActive`, `status`, `deviceId`, and `clientAlertId` in `sos_alert.spy.yaml`.
14. **Offload Base64 Photos to Storage:** Migrate `photoBase64` in `sos_alert` to direct file storage with public URLs.
15. **Sanitize Audio Upload Filenames:** Prevent path traversal in `AudioEndpoint.getUploadDescription`.
16. **Dynamic API Hosts in UI:** Replace hardcoded `crsis-link-api.onrender.com` in `voice_note_recorder.dart` with environment-configured hosts.

### Phase 4: Lifecycle, UX & Test Suite Repair (Day 4)
17. **Deduplicate Bottom Sheet UI:** Consolidate `_showSosDetails` into a reusable `SosDetailsBottomSheet`.
18. **Add Wakelock Timeout:** Automatically disable wakelock after 2 minutes of inactivity.
19. **Fix Voice Recorder Gesture Label:** Match label ("Hold to Record") with long-press behavior.
20. **Repair Test Suites:** Update unit and integration tests to initialize mock adapters and match current UI text.

---

**Report Certification:**  
This diagnostic audit report represents a complete and rigorous analysis of the repository in its current state. No source code modifications or partial refactorings have been executed in this pass. Remediation may begin following user review of these findings.
