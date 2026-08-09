<img src="docs/icon.png" width="100" />

# ScaleBridge

A native iOS app that bridges QN/Yolanda Bluetooth body-composition scales with Apple Health.

Step on your scale — ScaleBridge captures weight, body fat, muscle, water, BMI, bone, and more in one shot, writes them to Apple Health, and tracks your trends over time.

## Screenshots

<p float="left">
  <img src="docs/screenshots/home.png" width="22%" />
  <img src="docs/screenshots/history.png" width="22%" />
  <img src="docs/screenshots/metric-detail.png" width="22%" />
  <img src="docs/screenshots/reading-detail.png" width="22%" />
</p>

## Features

- **Bluetooth pairing** — auto-connects to QN/Yolanda smart scales (the same hardware used by many white-label apps)
- **Full body composition** — 22 metrics: weight, body fat, muscle %, water %, BMI, lean mass, bone, muscle mass, protein, skeletal muscle, subcutaneous fat, visceral fat, mineral salt, BMR, metabolic age, health score, obesity degree, best visual weight, standard weight, weight control, fat control, muscle control
- **Apple Health sync** — primary profile's readings flow into HealthKit automatically
- **Multi-profile** — add a profile for each family member; the app logs to the right person based on weight
- **Google cloud backup** — sign in with Google to back up profiles, readings, and settings to Firestore; syncs automatically after each weigh-in and restores everything on a new device
- **Range gauge** — each metric shows a Low / Normal / High / Very High band with a goal hint ("Decrease by 4.3% to reach normal")
- **Trend charts** — history view with per-metric charts across W / M / 6M / Y / All ranges
- **iOS 26 design** — Liquid Glass tab bar, native system colors, SF Symbols throughout

## Requirements

- iOS 26+
- Xcode 26+
- A QN/Yolanda-compatible Bluetooth body-composition scale — tested with the **HealthifyMe Smart Scale**

## Building

1. Clone the repo
2. Open `ScaleBridge.xcodeproj` in Xcode
3. Select your device as the build target (Bluetooth requires a real device)
4. Add a `GoogleService-Info.plist` from your own Firebase project
5. Build & run — SPM resolves Firebase and GoogleSignIn automatically

## Body Composition Algorithms

The body composition formulas (body fat %, lean mass, BMR via Katch-McArdle, metabolic age) are derived from the [openScale](https://github.com/oliexdev/openScale) project. openScale is the reference open-source implementation for QN/Yolanda scale parsing and body composition math.

## License

ScaleBridge is licensed under the [GNU General Public License v3.0](LICENSE), consistent with its dependency on openScale (GPL v3).
