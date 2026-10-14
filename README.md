# 🚨 Crsis_Link: Resilient Dual-Mode Emergency SOS Network
> **Built for the Serverpod Hackathon**  
> *When cellular towers collapse, emergency communication shouldn't.*

[![Serverpod](https://img.shields.io/badge/Serverpod-3.4.13-blue.svg?style=flat-square&logo=dart)](https://serverpod.dev)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B.svg?style=flat-square&logo=flutter)](https://flutter.dev)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791.svg?style=flat-square&logo=postgresql)](https://www.postgresql.org)
[![Docker](https://img.shields.io/badge/Docker-Ready-2496ED.svg?style=flat-square&logo=docker)](https://www.docker.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg?style=flat-square)](LICENSE)

---

## 📌 Executive Summary

During natural disasters (earthquakes, cyclones, catastrophic flooding, armed conflicts), **telecom towers and ISP backbones are the first points of failure**. Traditional emergency services (911/112 calls, SMS, WhatsApp, cloud SOS apps) fail entirely without active cellular backhaul.

**Crsis_Link** is an infrastructure-agnostic, dual-mode crisis response ecosystem. It operates in two synchronized realms:
1. **Online Mode (Serverpod Cloud Core):** Full cloud coordination with ultra-low latency WebSocket broadcasting, geospatial clustering, cryptographic audit trails, and instant rescue dispatches.
2. **Offline Mode (Autonomous P2P Mesh):** When internet connectivity vanishes, the app silently transitions to an ad-hoc, decentralized Bluetooth LE and Wi-Fi Direct mesh network, hopping distress packets across nearby peer devices without a single byte of internet.

---

## 🌪️ The Problem vs. The Crsis_Link Solution

| The Crisis Reality | Traditional SOS Apps | Crsis_Link Hybrid Solution |
| :--- | :--- | :--- |
| **Tower Blackouts & Jammed Networks** | ❌ Fail completely; network timeouts leave victims stranded. | ✅ **Zero-Internet P2P Mesh** bounces packets peer-to-peer until reaching a rescuer or edge gateway. |
| **Rescuer Coordination Confusion** | ❌ Multiple volunteers rush to the same victim while others die waiting. | ✅ **State-Synced Claiming & PIN Verification:** Only one volunteer can claim an SOS; mutual 4-digit PIN verification confirms physical contact. |
| **Bandwidth Degradation** | ❌ Heavy multi-megabyte image uploads choke and crash on 2G edge networks. | ✅ **Smart Base64 Payloads & Audio Chunks:** Highly compressed micro-payloads sent over Serverpod RPC or chunked over BLE. |
| **Data Synchronization** | ❌ Offline data is lost or trapped on the isolated device. | ✅ **Autonomous Hive Store & Forward:** Offline actions queue locally and automatically reconcile with Serverpod upon signal recovery. |

---

## 🏗️ System Architecture

```
                       ┌──────────────────────────────────────────────────┐
                       │               CRISIS_LINK CLIENT                 │
                       │            (Flutter / Android Engine)            │
                       └───────────┬──────────────────────────┬───────────┘
                                   │                          │
                 Connectivity = ONLINE?                       │ Connectivity = OFFLINE?
                                   │                          │
                                   ▼                          ▼
        ┌────────────────────────────────────┐     ┌────────────────────────────────────┐
        │        ONLINE SERVERPOD CORE       │     │        OFFLINE P2P MESH CORE       │
        ├────────────────────────────────────┤     ├────────────────────────────────────┤
        │ • Serverpod RPC & Endpoints        │     │ • Nearby Connections API           │
        │ • Real-time WebSockets Stream      │     │ • Bluetooth LE + Wi-Fi Direct      │
        │ • PostgreSQL Spatial Storage       │     │ • Multi-hop Packet Propagation     │
        │ • Global Verification Pin Ledger   │     │ • Ed25519 Cryptographic Signatures │
        │ • Base64 Micro-Photo Transport     │     │ • Local Hive Persistence Queue     │
        │ • In-App Version Config Endpoint   │     │ • Broadcast Kill Signals           │
        └─────────────────┬──────────────────┘     └─────────────────┬──────────────────┘
                          │                                          │
                          └─────────────────► ◄──────────────────────┘
                                    Automatic State Synchronization
```

### 1. The Strict Dual-Routing Guardrail
All critical actions (SOS Dispatches, Claiming Rescues, Verifying PINs, Resolving Alerts) adhere to a deterministic branching pattern:
```dart
final connectivity = await Connectivity().checkConnectivity();
final isOnline = connectivity.any((r) => r != ConnectivityResult.none);

if (isOnline) {
  // 1. Direct Serverpod Cloud RPC
  await AuthManager.client.sos.resolveSOS(targetId, deviceId, signature, publicKey);
} else {
  // 2. Air-Gapped Mesh Packet Propagation
  await OfflineMeshService().broadcastSosCleared(targetId);
  await OfflineCacheManager.saveLocalResolution(targetId);
}
```

### 2. Autonomous P2P Mesh Packet Protocol
When air-gapped, distress packets are structured as compact, binary-safe JSON frames signed with device-specific cryptographic keys:
```json
{
  "t": "SOS",
  "i": "client-uuid-883921",
  "d": "victim-device-id",
  "n": "John Doe",
  "lat": 13.0827,
  "lng": 80.2707,
  "m": "Trapped under debris, 2 injured",
  "p": "data:image/jpeg;base64,...",
  "pin": "4821",
  "ts": 1728834920
}
```
* **Deduplication Engine:** Every node records incoming `clientAlertId` hashes to drop cyclic echoes.
* **Kill Switch Propagation:** Once a victim is marked rescued, a `CLEAR` frame floods the mesh, wiping the local red pins from all nearby screens.

---

## ⚡ The Serverpod Advantage

Building a high-concurrency, disaster-grade backend with traditional microservices stacks (e.g., Node.js + Express + WebSocket libraries + Prisma ORM) creates fragmented models and brittle serialization. **Serverpod revolutionized this project:**

### 1. True End-to-End Type Safety (Dart across Client & Cloud)
* The exact data structures defined in Serverpod's `spy.yaml` specifications (`SosAlert`, `RescueAcceptedEvent`, `SosBroadcastResponse`) generate identical, strongly typed classes on both the backend and Flutter app.
* Zero runtime mapping bugs; breaking changes are caught immediately at compile-time.

### 2. Built-in Streaming & Real-Time WebSockets
* Disaster alerts cannot wait for HTTP polling. Serverpod's native streaming architecture allows the mobile app to listen to WebSocket broadcast streams effortlessly:
```dart
_sosSubscription = AuthManager.client.sos.stream.listen((event) {
  if (event is SosAlert) MapPinsManager().addOrUpdatePin(event);
  if (event is RescueAcceptedEvent) AlertsManager().addRescueEvent(event);
  if (event is SosResolvedEvent) MapPinsManager().removePin(event.clientAlertId);
});
```

### 3. Integrated PostgreSQL Schema & ORM Management
* Serverpod automatically converted our geospatial schemas, verification hashes, and timestamps into relational PostgreSQL tables without writing raw SQL migration scripts.

### 4. Zero-Cost Maintenance & Native Production Readiness
* Utilizing Serverpod’s lean Docker composition and Dockerized PostgreSQL instance enabled deployment on cloud providers like **Render** with instant health-checking and negligible memory footprint (~40MB RAM).

---

## 📱 Key Features

* **📡 Disaster Radar & Interactive Map:** Powered by `flutter_map` with dynamic clustering, pulse rings, and offline tile caching.
* **🤝 Mutual Authentication Rescue PIN:** Prevents troll rescues and false reports. Rescuers must meet victims in person and enter their unique 4-digit PIN to decrypt coordinates and complete the rescue.
* **📸 Base64 Zero-Dependency Photo Viewer:** Bypasses fragile public cloud storage buckets by directly encoding high-compression JPEG captures into payload strings that render instantly across both online and mesh networks.
* **🎙️ Audio Voice Note Recorder:** Victims trapped under rubble can record voice notes that volunteers can stream or play locally.
* **🧭 Rescue Compass:** Real-time spatial heading and distance calculations directly pointing volunteers towards the victim's location.
* **🔄 Zero-Store In-App Auto Updater:** A custom `ConfigEndpoint` and client service that alerts users when a newer APK version is available and forces an in-app upgrade without Google Play dependency.

---

## 🛠️ Tech Stack

### Backend (Serverpod Core)
* **Serverpod 3.4.13:** High-performance Dart server framework.
* **PostgreSQL 16:** Relational database for SOS alerts, audit trails, and device state.
* **Docker & Docker Compose:** Containerized environment orchestration.

### Mobile Frontend (Flutter App)
* **Flutter SDK (Channel Stable):** Cross-platform mobile engine.
* **`nearby_connections`:** Google Nearby Connections API for offline Bluetooth/Wi-Fi Direct mesh.
* **`flutter_map` & `latlong2`:** OpenStreetMap-based interactive geospatial visualizer.
* **`hive` & `sqflite`:** High-speed offline caching and packet queuing.
* **`cryptography` & `p2p_crypto_service`:** Ed25519 digital signatures to prevent rogue distress broadcasts.
* **`package_info_plus` & `url_launcher`:** In-app version verification and direct APK downloads.

---

## 🚀 Installation & Local Development

### Prerequisites
* [Flutter SDK](https://docs.flutter.dev/get-started/install) (`>= 3.22.0`)
* [Dart SDK](https://dart.dev/get-dart) (`>= 3.4.0`)
* [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Running)
* [Serverpod CLI](https://serverpod.dev/docs/getting-started):
  ```bash
  dart pub global activate serverpod_cli
  ```

---

### Step 1: Clone the Repository
```bash
git clone https://github.com/your-username/Crsis_Link.git
cd Crsis_Link
```

---

### Step 2: Start the Serverpod Backend
1. Navigate to the server folder and boot the PostgreSQL container:
   ```bash
   cd crsis_link_server
   docker compose up --build -d
   ```
2. Generate all client bindings and models:
   ```bash
   serverpod generate
   ```
3. Run the Serverpod server:
   ```bash
   dart run bin/main.dart
   ```
   *The server will start on `http://localhost:8080` (Web API) and `http://localhost:8081` (WebSockets).*

---

### Step 3: Run the Flutter Mobile App
1. Return to the root directory and create/verify your `.env` file:
   ```env
   API_URL=http://10.0.2.2:8080/ # Use 10.0.2.2 for Android Emulator or your LAN IP for physical device
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Launch on an Android physical device or emulator:
   ```bash
   flutter run
   ```

---

### Step 4: Building the Release APK
To compile the standalone, zero-cable distribution APK:
```bash
flutter build apk --release
```
The compiled binary will be generated at:
`build/app/outputs/flutter-apk/app-release.apk`

---

## 🏆 Hackathon Submission Highlights

* **Resilience Under Pressure:** Demonstrates real-world utility during critical natural disasters when traditional infrastructure is completely wiped out.
* **Architectural Rigor:** Clean separation of concerns between Serverpod's RPC layer, WebSocket streaming engine, and local P2P mesh discovery.
* **Production Polish:** Seamless offline/online switching, real-time compass guidance, wakelock management, mutual PIN authentication, and self-updating mechanics.

---

