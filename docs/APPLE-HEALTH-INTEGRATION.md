# Apple Health / HealthKit Integration — Research & Plan

**Created:** April 7, 2026
**Status:** Research / Planning
**Author:** AI-assisted

---

## Overview

Replace or supplement Strava as the run-tracking data source by reading workout data directly from Apple Health (HealthKit). This would let users track runs with their Apple Watch native Workout app (or any app that writes to HealthKit) without needing Strava installed.

---

## What Data Is Available via HealthKit

| Data | HealthKit Type | Notes |
|------|---------------|-------|
| **Distance** | `HKQuantityType.distanceWalkingRunning` | Total + per-interval samples |
| **GPS Route** | `HKWorkoutRoute` → `CLLocation` objects | Full lat/long, altitude, speed, course, accuracy — thousands of points per run |
| **Heart Rate** | `HKQuantityType.heartRate` | Per-second samples from Apple Watch (or paired Bluetooth HR monitor) |
| **Pace** | Derived from distance + time samples | Not a native HealthKit type — calculated from distance intervals |
| **Calories** | `HKQuantityType.activeEnergyBurned` | Active calories burned during workout |
| **Duration** | `HKWorkout.duration` | Start-to-end time |
| **Elevation** | `CLLocation.altitude` from route data | Gain/loss calculable from the GPS route |
| **Cadence** | `HKQuantityType.runningStrideLength` / `runningSpeed` | Available on newer Apple Watches |

The data quality is comparable to what Strava provides — Apple Watch GPS + heart rate is the same hardware source Strava reads from when people use Strava on their Watch.

---

## Two Integration Models

### Model 1: Passive Read (Recommended Starting Point)

EOS doesn't start or control any workout. The user runs using Apple's native Workout app on their Watch (or Nike Run Club, etc.), and EOS reads the completed workout from HealthKit after the fact.

**How it works:**
1. User grants HealthKit read permission during onboarding (or in Profile settings)
2. `HKObserverQuery` fires when new workouts are written to HealthKit
3. EOS queries for `HKWorkout` objects of type `.running`
4. Pull distance, heart rate, route, duration from the workout
5. Verify workout happened within the user's deadline window
6. Credit the run distance toward their daily objective (same as Strava does today)

**Technical requirements:**
- `import HealthKit`
- `NSHealthShareUsageDescription` in Info.plist
- Request read authorization for: `HKWorkoutType`, `HKWorkoutRouteType`, `heartRate`, `distanceWalkingRunning`, `activeEnergyBurned`
- `HKObserverQuery` for background delivery of new workouts
- Background mode: "Background fetch" capability in Xcode

**Pros:**
- No Watch app needed — works with any workout source
- Simple implementation (read-only)
- Users don't need Strava installed
- Works on current iOS versions (iOS 14+)
- Apple Watch workouts are harder to fake than Strava (sensor data is hardware-signed)

**Cons:**
- User could use a third-party app to write fake workouts to HealthKit (mitigated by checking `sourceRevision`)
- No real-time tracking UI in EOS (user tracks in a separate app)
- Slight delay — workout data appears in HealthKit after the run ends

### Model 2: Active Workout Sessions (Full Experience)

EOS starts and controls a live workout session directly from the iPhone app, tracking GPS and receiving heart rate data from Apple Watch in real-time.

**How it works:**
1. User taps "Start Run" in EOS
2. `HKWorkoutSession` + `HKLiveWorkoutBuilder` start on iPhone
3. `CoreLocation` tracks GPS, Apple Watch streams heart rate
4. EOS shows live metrics (distance, pace, heart rate, time) with a Live Activity on the lock screen
5. User taps "End Run" — workout is saved to HealthKit
6. Distance credits toward daily objective

**Technical requirements:**
- Everything from Model 1, plus:
- `HKWorkoutSession` + `HKLiveWorkoutBuilder` + `HKLiveWorkoutDataSource`
- `CoreLocation` for GPS tracking
- Live Activities for lock screen display
- App Intents for Siri start/pause/resume/stop
- Crash recovery via `SceneDelegate` workout restoration
- **Requires iOS 19+** (announced WWDC25, ships fall 2025)

**Pros:**
- Full in-app tracking experience — no need for Apple Workout app or Strava
- Real-time pace/distance/HR display
- Live Activity on lock screen
- First-party data = highest cheat resistance
- Makes EOS a standalone run tracker

**Cons:**
- Requires iOS 19+ (limits user base initially)
- Significantly more complex to build
- Competes with Apple Workout / Strava on run-tracking UX
- Needs thorough testing for battery, GPS accuracy, background behavior

---

## Comparison: Strava vs HealthKit (Passive) vs HealthKit (Active)

| | Strava (Current) | HealthKit Passive | HealthKit Active Session |
|---|---|---|---|
| **User starts run in** | Strava app | Any app (Apple Workout, etc.) | EOS app directly |
| **Data arrives via** | Webhook from Strava API | `HKObserverQuery` on-device | `HKLiveWorkoutBuilder` real-time |
| **GPS route** | Yes (via API) | Yes (`HKWorkoutRoute`) | Yes (CoreLocation + HealthKit) |
| **Heart rate** | Yes (if Watch used) | Yes (if Watch used) | Yes (if Watch/BT monitor) |
| **Pace / distance** | Yes | Yes | Yes (real-time) |
| **Backend needed** | Yes (webhook receiver) | No (all on-device) | No (all on-device) |
| **Works without Strava** | No | Yes | Yes |
| **Cheat resistance** | Medium (API data) | Medium-High (Watch sensor data) | High (EOS controls the session) |
| **watchOS app needed** | No | No | No (as of iOS 19) |
| **Min iOS version** | Any | iOS 14+ | iOS 19+ |
| **Live tracking UI** | No (in Strava) | No | Yes |
| **Requires user install** | Strava app | Nothing extra | Nothing extra |

---

## Anti-Cheat Considerations

This matters for EOS since real money is at stake.

### Apple Watch workouts are hard to fake
- Sensor data (heart rate, motion, GPS) is written by Watch hardware, not user-editable
- Workouts created by the native Workout app carry Apple's hardware bundle ID

### Checking workout authenticity
- Every `HKWorkout` has a `sourceRevision` property showing which app/device created it
- Filter to only trust workouts from: `com.apple.health` or Apple Watch hardware bundle IDs
- Reject workouts written by untrusted third-party apps

### GPS route validation
- `HKWorkoutRoute` GPS data includes accuracy metadata and timestamps
- Fake routes show anomalies: perfect accuracy, no drift, teleporting between points, unrealistic speeds
- Can apply the same 4:00/mile pace anti-cheat currently used with Strava

### Existing Strava anti-cheat (for reference)
- Pace floor at 4:00/mile — anything faster is rejected
- Distance comes from Strava's processed activity data
- Webhook delivers data server-side, harder for client to manipulate

---

## Recommended Rollout Plan

### Phase 1: HealthKit as Alternative to Strava (Passive Read)
- Add HealthKit permission request (onboarding + profile settings)
- Let users choose their tracking source: Strava or Apple Health
- Read completed running workouts from HealthKit
- Apply same distance-crediting logic as Strava webhook
- Source verification: only accept Apple Watch / native Workout app workouts
- Keep Strava as an option for users who prefer it

### Phase 2: Enhanced HealthKit Features
- Show heart rate data from runs in the app
- Display GPS route map for completed runs
- Add elevation gain to run stats
- Use heart rate + GPS data for richer competition leaderboards

### Phase 3: Active Workout Sessions (iOS 19+)
- "Start Run" button in EOS
- Live tracking with distance, pace, heart rate
- Live Activity on lock screen
- Siri integration ("Hey Siri, start my RunMatch run")
- Workout recovery after app crash
- This phase makes Strava fully optional

---

## Info.plist Keys Required

```xml
<key>NSHealthShareUsageDescription</key>
<string>RunMatch reads your running workouts to track your daily goals and competitions.</string>

<key>NSHealthUpdateUsageDescription</key>
<string>RunMatch saves your workout data to Apple Health.</string>
```

## HealthKit Entitlement

Add "HealthKit" capability in Xcode → Signing & Capabilities.

## Key Frameworks

```swift
import HealthKit

// Phase 1: Read workouts
HKHealthStore
HKWorkout
HKWorkoutRoute
HKObserverQuery
HKSampleQuery
HKWorkoutRouteQuery

// Phase 3: Active sessions (iOS 19+)
HKWorkoutSession
HKLiveWorkoutBuilder
HKLiveWorkoutDataSource
```

---

## Impact on Current Codebase

### What changes:
- `OnboardingView.swift` — add HealthKit permission screen (alongside or replacing Strava screen)
- `ContentView.swift` — add HealthKit manager class, workout observer, run credit logic
- `StripeConfig.swift` or new config — tracking source preference (strava vs healthkit)
- `Info.plist` — HealthKit usage descriptions
- `Eos.xcodeproj` — HealthKit capability + entitlement

### What stays the same:
- Backend endpoints — run distance still credited the same way
- Database schema — `objective_sessions` tracking is source-agnostic
- Competition scoring — distance is distance regardless of source
- Stakes/payout system — unchanged

### What could be removed (eventually):
- Strava dependency for users on Apple Watch
- "Powered by Strava" branding requirement (for HealthKit-only users)
- Strava OAuth flow complexity
