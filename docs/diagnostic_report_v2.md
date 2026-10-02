# Crsis_Link — Phase 2 Diagnostic Report

**Audit Date:** 2026-10-01  
**Auditor:** Principal Software Architect (Phase 2)  
**Scope:** Post-BUG-01 through BUG-09 fix validation; dead code cleanup regression check; memory & lifecycle verification.

---

## Executive Summary

The Phase 1 bug fixes (BUG-01 through BUG-09) and dead code cleanup (DEAD-01 through DEAD-06) have been successfully applied. The core WebSocket lifecycle, shared state architecture, and SOS pin rendering are architecturally sound. This Phase 2 audit identifies **3 remaining logical gaps**, **2 performance/memory risk areas**, and **4 recommended next-step improvements** to bring the application to production-grade quality.

---

## Section 1: Remaining Logical Disconnects

### 1.1 — `claimRescue` Does Not Optimistically Update the Local Pin Color (MEDIUM)

**File:** `lib/presentation/screens/home_map_screen.dart` — Line 797

**Observation:** When a volunteer taps "ACCEPT RESCUE" and the `claimRescue` call succeeds, the modal closes and an `AlertsManager` ledger entry is created. However, the `SosAlert` object inside `MapPinsManager` is NOT locally updated. Its `status` field stays `'OPEN'` locally until the WebSocket broadcast from the server delivers the updated `SosAlert` back to the volunteer's device.

**Impact:** The pin on the volunteer's map stays **red** for a brief moment after a successful claim, only turning **green** once the server's `sos_broadcasts` WebSocket echo arrives. This creates a visible flicker and fails the "instant feedback" UX contract.

**Root Cause:** The `claimRescue` success block calls `AlertsManager().addSelfRescueEvent()` but never calls `MapPinsManager().addOrUpdatePin(updatedAlert)` with a locally-mutated copy that sets `status = 'CLAIMED'`.

**Fix:** In the `claimRescue` success block, construct a local copy of `alert` with `status = 'CLAIMED'` and `volunteerDeviceId = AuthManager.deviceId`, then pass it to `MapPinsManager().addOrUpdatePin(...)` before closing the modal.

---

### 1.2 — `_AudioPlayerButton` Stream Listeners Are Not Cancelled (HIGH)

**File:** `lib/presentation/screens/home_map_screen.dart` — Lines 893–910

**Observation:** `_AudioPlayerButtonState.initState()` subscribes to three `AudioPlayer` streams directly via `.listen()`:
- `_audioPlayer.onPlayerStateChanged`
- `_audioPlayer.onDurationChanged`
- `_audioPlayer.onPositionChanged`

None of these `StreamSubscription` objects are stored in variables. This means **they are never cancelled** in `dispose()`. The only cleanup performed is `_audioPlayer.dispose()`.

**Impact:** If a user opens and closes a SOS pin detail modal multiple times, a new `_AudioPlayerButton` is created each time, resulting in accumulating orphaned stream subscriptions. This is a genuine **memory leak** and can cause `setState` calls on disposed `State` objects, triggering exceptions.

**Fix:** Capture each `.listen()` return value into a `StreamSubscription?` field, and cancel all three in `dispose()`.

---

### 1.3 — `streamOpened` Listener on `sos_broadcasts` Is Never Removed (MEDIUM)

**File:** `crsis_link_server/lib/src/endpoints/sos_endpoint.dart` — Lines 17–24

**Observation:** In `streamOpened`, the server registers a broadcast listener on the `sos_broadcasts` channel with an anonymous callback. This listener is **never stored** and therefore **never explicitly removed** in `streamClosed`. The `streamClosed` method only removes the targeted `sos_device_$deviceId` listener.

**Impact:** On client reconnect, a **second listener** is registered on the same session's `sos_broadcasts` channel, causing **duplicate message delivery**. The anonymous closure also holds a strong reference to the `session` object, preventing garbage collection.

**Fix:** Store the `sos_broadcasts` listener callback in `_sessionListeners` (using a composite key like `"${sessionId}_broadcast"`). Remove it explicitly in `streamClosed`.

---

### 1.4 — `getActiveAlerts` Returns ALL Alerts Without Location Filtering (LOW)

**File:** `crsis_link_server/lib/src/endpoints/sos_endpoint.dart` — Line 132

**Observation:** On app startup, `HomeMapScreen` calls `getActiveAlerts()` which returns **every single active `SosAlert`** in the database regardless of geographic distance. The 5km Haversine filter only applies to new `broadcastSos` calls, not to historical/initial loads.

**Impact:** In a multi-region deployment, a user in Chennai will see all active SOS pins from Mumbai on app startup, defeating the purpose of the spatial filter.

**Fix:** Accept an optional `lat/lng` parameter in `getActiveAlerts()` and apply the Haversine filter server-side before returning results.

---

## Section 2: Performance & Memory Leak Risks

### 2.1 — `AlertsManager` Notifications List Has No Size Cap

**File:** `lib/core/state/alerts_manager.dart`

**Observation:** The `AlertsManager` singleton accumulates alert history indefinitely in memory. There is no cap, eviction, or TTL on the notifications list.

**Risk Level:** LOW on a single session, MEDIUM for long-running sessions (multi-hour use during a disaster scenario where hundreds of alerts are generated).

**Recommendation:** Implement a max-size cap (e.g., keep only the latest 100 notifications). New notifications should evict the oldest when the limit is exceeded.

---

### 2.2 — `_deviceLocations` Server Cache Has No TTL or Eviction

**File:** `crsis_link_server/lib/src/endpoints/sos_endpoint.dart` — Line 9

**Observation:** The `_deviceLocations` static map is populated by `updateLocation()` REST calls and cleared only when WebSocket `streamClosed` fires. Clients that call `updateLocation()` via HTTP without ever opening a WebSocket stream, or that experience an unclean disconnect (network drop), leave stale entries in the cache indefinitely.

**Impact:** Stale entries keep receiving SOS notifications they should not receive, and the cache grows unboundedly over time on a busy server.

**Fix:** Store a timestamp alongside each device entry. A `Timer.periodic` cleanup job should remove entries older than ~5 minutes.

---

## Section 3: Recommended Next Steps

### Priority 1 — High (Fix Before Production) 🔴

| ID | Task | File |
|----|------|------|
| FIX-A | Cancel `_AudioPlayerButton` stream subscriptions in `dispose()` | `home_map_screen.dart` |
| FIX-B | Store and remove the `sos_broadcasts` anonymous listener in `streamClosed` | `sos_endpoint.dart` |

### Priority 2 — Medium (Fix Soon) 🟡

| ID | Task | File |
|----|------|------|
| FIX-C | Add optimistic `MapPinsManager.addOrUpdatePin()` after successful `claimRescue` | `home_map_screen.dart` |
| FIX-D | Add `lat/lng` parameter to `getActiveAlerts()` for spatial filtering on startup | `sos_endpoint.dart` |

### Priority 3 — Low (Hardening) 🟢

| ID | Task | File |
|----|------|------|
| FIX-E | Add TTL eviction to `_deviceLocations` via `Timer.periodic` | `sos_endpoint.dart` |
| FIX-F | Cap `AlertsManager` notifications list to 100 items | `alerts_manager.dart` |
| FIX-G | Add a "Clear Alerts" button on the Profile screen | `my_profile_screen.dart` |

---

## Architecture Verification Checklist ✅

The following were fully verified as **correct and clean** during this audit:

- ✅ **WebSocket handshake:** `_initStreaming()` correctly gates on `StreamingConnectionStatus.connected` before calling `_bindStream()`. No race condition.
- ✅ **No legacy auth:** Zero `@RequireAuth` annotations found in the Serverpod backend. Zero `serverpod_auth_email_flutter` imports in `lib/`.
- ✅ **Marker rebuilds:** `_AnimatedSosMarker` correctly uses `ValueKey('${alert.id}_${alert.status}')` and implements `didUpdateWidget` — visual status transitions are guaranteed.
- ✅ **Alerts reactivity:** `AlertsScreen` uses `ValueListenableBuilder` on `AlertsManager()` with zero boilerplate.
- ✅ **HomeMapScreen dispose:** All four lifecycle items cleaned up — `_sosSubscription`, `MapPinsManager` listener, streaming status listener, connectivity monitor listener.
- ✅ **VoiceNoteRecorder dispose:** `_timer`, `_pulseController`, and `_recorder` all properly disposed.
- ✅ **Auto-navigation bridge:** `SosScreen` → `MapPinsManager.addOrUpdatePin()` → `MainNavigation.jumpToMap()` bridge is working.
- ✅ **`completeRescue` backend:** Correctly broadcasts `SosResolvedEvent` (fixed in BUG-09), clearing the victim's map.
- ✅ **Haversine filter:** `broadcastSos` correctly excludes the sender's own `deviceId` from the 5km broadcast.

---

*Report generated by Phase 2 automated audit. Last updated: 2026-10-01.*
