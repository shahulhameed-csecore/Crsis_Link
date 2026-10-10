# Implementation Plan: Map-Based SOS Online/Offline Routing

## Section 1: Root Cause Analysis
The issue where an online map-based SOS falsely falls back to the "Offline Mesh" mode is caused by a structural flaw in the error-handling logic inside `home_map_screen.dart`.

### The Core Flaw: Exception Masking
In `home_map_screen.dart`, the code currently checks for internet and then executes this logic:
```dart
if (!isOnline) {
  throw ServerpodClientException('Force Offline', 0);
}

final response = await AuthManager.client.sos.broadcastSos(...)
```
Both the intentional offline trigger (the `throw`) and the actual `broadcastSos` RPC call share the exact same `try-catch` block. 

When the `broadcastSos` RPC call is made, the Serverpod client wraps **all** network and server errors into a `ServerpodClientException`. This means:
1. **Actual Offline Status:** Handled by `ServerpodClientException('Force Offline', 0)`.
2. **Backend Server Crash (HTTP 500):** Throws `ServerpodClientException`.
3. **Validation Rejection (HTTP 400):** Throws `ServerpodClientException` (e.g., if the generated `clientAlertId` was somehow malformed, or if a parameter exceeded limits).

Because the `catch` block intercepts *all* `ServerpodClientException` instances and blindly routes them to the `OfflineCacheManager`, any legitimate backend rejection or server crash is falsely reported to the user as "Offline: SOS saved and broadcasting to nearby devices." The server error is completely masked.

*(Note: The parameters passed from `home_map_screen.dart` to `broadcastSos` exactly match the generated client signature, so there are no type mismatches causing local exceptions prior to the network call).*

## Section 2: Proposed Fixes

To fix this, we must completely decouple the Online execution path from the Offline execution path in `home_map_screen.dart`, mirroring the strict split we recently implemented in `sos_screen.dart`.

### Step-by-Step Logic Changes (Client-Side: `home_map_screen.dart`)
1. **Remove the Catch-All Exception Block:** Strip away the overarching `try... on ServerpodClientException` block wrapping the broadcast logic inside `_showSosModal`.
2. **Implement an Explicit IF/ELSE Split:**
   * Evaluate `isOnline` using the exact same robust `Connectivity().checkConnectivity().any(...)` and `google.com` ping logic used in `sos_screen.dart`.
   * **IF `isOnline == true`:**
     * Create an isolated `try...catch` block.
     * Optionally call `updateLocation` to ensure the server's spatial cache is primed before broadcasting.
     * Await `broadcastSos(...)`.
     * If it succeeds, update the map pins and show a Green SnackBar.
     * If the `catch` block is triggered, **display the exact server error** in a Red SnackBar (e.g., `Server Error: $e`) and **do not** proceed to the offline flow.
   * **ELSE (`isOnline == false`):**
     * Execute the offline flow: save the alert to `OfflineCacheManager`, toggle `OfflineMeshService`, and broadcast the new alert to peers.
     * Show the Orange SnackBar indicating the P2P Mesh fallback.

### Step-by-Step Logic Changes (Server-Side: `sos_endpoint.dart`)
1. **Enforce Explicit Rate Limiting (Optional but Recommended):** The server code currently has a comment `// 1. Lock and check rate limit inside the transaction`, but there is no actual rate limit exception thrown (e.g., preventing a user from spamming SOS 50 times a minute). Implementing an explicit `throw Exception('Rate limit exceeded')` would allow the client to catch and display it accurately via the new unmasked client logic.
2. **Validate Return Types:** Ensure that any `ArgumentError` thrown by the strict sanitization checks (like audio URL length) is gracefully handled or formatted so the new client-side UI can display a readable error rather than a raw 500 trace.
