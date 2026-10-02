# Phase 5 Codebase Audit: Crsis_Link

## 1. Network & Resilience Gaps
* **Timeout Handling:** 
  The `broadcastSos` invocations in `home_map_screen.dart` (Line 402) and `sos_screen.dart` (Line 200) lack explicit `.timeout(Duration(...))` guards. Furthermore, the generic `catch (e)` blocks do not identify `TimeoutException` or `SocketException`. This leaves the UI vulnerable to infinite hanging during a backend cold-start, or surfacing unhandled raw stack traces when offline.
* **Offline Mode Negligence:**
  The Flutter client attempts to drop pins and mutate backend state without verifying active internet availability. If a user loses connectivity in an emergency, the app will throw a backend transport error rather than cleanly presenting a localized "No Internet Connection" fallback UI.

## 2. Security & Rate Limiting Vulnerabilities
* **SOS Spamming:** 
  The `broadcastSos` backend endpoint in `crsis_link_server/lib/src/endpoints/sos_endpoint.dart` (Line 97) has no rate-limiting or cooldown window mechanisms (e.g., validating the timestamp of the last broadcast by the `deviceId`). This allows malicious vectors to rapidly spam the endpoint, exhausting PostgreSQL connections by constantly forcing database row invalidations inside transactions.
* **Audio Size/Format Validation:** 
  The server accepts `audioUrl` as a generic string and distributes it to the spatial grid without performing backend validation on file extension, MIME type, or maximum file size constraints during the upload phase.

## 3. UI/Input Edge Cases
* **Keyboard Overflows:** 
  In the `_showSosModal` methods of both `home_map_screen.dart` (Line 345) and `sos_screen.dart` (Line 133), the modal attempts to shift upward when the on-screen keyboard appears using `MediaQuery.of(ctx).viewInsets.bottom` padding. However, the child `Column` is **not** wrapped in a `SingleChildScrollView`. On smaller devices, this will result in a fatal `RenderFlex overflowed` crash when the keyboard obscures the screen.
* **Whitespace Payloads:**
  *Good news:* The client text controllers successfully implement `.trim().isEmpty` checks (e.g., `home_map_screen.dart` Line 407), properly mitigating empty or whitespace-only SOS payload strings. No regression found here.
