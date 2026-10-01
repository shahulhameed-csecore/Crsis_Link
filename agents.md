# Crsis_Link: AI Agent Master Context & Rules

## 1. Project Overview
- **App Name:** Crsis_Link
- **Goal:** Real-time, low-bandwidth community dispatch system for natural disasters.
- **Tech Stack:** Flutter (Frontend), Serverpod (Backend), PostgreSQL, Redis.
- **Deployment:** Render (Backend), Android Release APK (Frontend).

## 2. Design System (Strict Adherence)
- **Emergency Red:** #E50914 (Primary active badges, SOS buttons)
- **Pitch Black:** #080808 (Fullscreen backgrounds, high-contrast CTA)
- **Clean Background:** #F8F9FA
- **Surface Cards:** #FFFFFF with #EDEDED border (16px radius, zero heavy shadows)
- **Typography:** Archivo Black/Bebas Neue (Headers), Inter (Body).
- **Buttons:** Rounded Capsule style (BorderRadius.circular(50)).

## 3. Architecture & Coding Rules
- **Error Handling:** Never swallow exceptions silently. Log them and show clean, user-friendly UI snackbars.
- **Backend Security:** All endpoints handling user data or SOS pins must be protected by authentication.
- **State Management:** Keep the presentation layer separate from domain logic. 
- **Demo Mode:** Ensure authentication flows are frictionless (1-tap login) for hackathon judges. Bypass email OTP verification.

## 4. Current Status & Build Rules
- The app must be compiled as a standalone production APK (`flutter build apk --release`) that connects to the live Render backend.
- Network security configs must allow `usesCleartextTraffic="true"` and include `INTERNET` permissions.
- Do not rely on `flutter run` for final testing; the app must function independently when installed on an Android device.
