# Simplified TreadmillSync

This is a simplified version of TreadmillSync that focuses on **on-demand** syncing rather than automatic background operation.

## How It Works

**Simple workflow:**
1. At the end of your workday, open the app
2. Tap "Connect & Sync Workout"
3. The app:
   - Scans for your treadmill
   - Connects via Bluetooth
   - Fetches current steps, distance, and calories
   - Saves the workout to Apple Health
   - Disconnects

**That's it!** No background modes, no continuous polling, just a simple button press when you're done working.

## Key Differences from Full Version

| Feature | Full Version | Simplified Version |
|---------|--------------|-------------------|
| Background BLE | ✅ Auto-connects | ❌ Manual connection |
| Continuous Polling | ✅ Every 1.5 seconds | ❌ One-time fetch |
| Auto Workout Start/Stop | ✅ Automatic | ❌ Manual button press |
| Daily Session Tracking | ✅ Accumulates all day | ❌ Single snapshot |
| Background Modes Required | ✅ Yes | ❌ No |
| Complexity | High | Low |

## Files

**Simplified version files:**
- `SimpleTreadmillSync.swift` - Single manager class (BLE + HealthKit combined)
- `SimpleMainView.swift` - Simple UI with one button
- `SimpleTreadmillSyncApp.swift` - App entry point
- `SimpleInfo.plist` - Info.plist without background modes

**To use the simplified version:**
1. Replace `TreadmillSyncApp.swift` with `SimpleTreadmillSyncApp.swift`
2. Replace `Info.plist` with `SimpleInfo.plist`
3. Update your Xcode project to use `SimpleMainView` as the root view
4. Remove Background Modes capability from your project

## Setup in Xcode

### 1. Update Main App File

In your Xcode project:
1. Delete or rename `TreadmillSyncApp.swift`
2. Rename `SimpleTreadmillSyncApp.swift` to `TreadmillSyncApp.swift`

Or update the `@main` annotation:
```swift
// In SimpleTreadmillSyncApp.swift, this is already the entry point
@main
struct SimpleTreadmillSyncApp: App {
    var body: some Scene {
        WindowGroup {
            SimpleMainView()
        }
    }
}
```

### 2. Update Info.plist

Replace your Info.plist with SimpleInfo.plist, or manually remove:
- `UIBackgroundModes` array
- `UIApplicationSceneManifest` (optional - simplifies further)

### 3. Remove Background Modes Capability

In Xcode:
1. Select your target
2. Go to **Signing & Capabilities**
3. Remove the **Background Modes** capability
4. Keep **HealthKit** capability

### 4. Build and Run

That's it! The app now works as a simple on-demand sync tool.

## Usage

### First Time Setup

1. Launch the app
2. Tap "Connect & Sync Workout"
3. Grant Bluetooth and HealthKit permissions when prompted
4. Turn on your treadmill

### Daily Use

1. Work at your treadmill desk throughout the day
2. At the end of the day, open the app
3. Make sure your treadmill is still on
4. Tap "Connect & Sync Workout"
5. Wait for the sync to complete (usually 5-10 seconds)
6. Check Apple Health app to see your saved workout

## Advantages

✅ **Simpler** - Only 3 files instead of 10+
✅ **No Background Modes** - Easier App Store approval
✅ **Less Battery** - No continuous BLE connection
✅ **Easier to Understand** - All logic in one manager class
✅ **More Control** - You decide when to sync

## Limitations

❌ **Manual Operation** - You must open the app and tap the button
❌ **End-of-Day Only** - Can't track multiple sessions throughout the day
❌ **No Background Sync** - App must be open during sync
❌ **Treadmill Must Stay On** - Treadmill needs to be powered on when you sync

## When to Use Which Version

**Use the Simplified Version if:**
- You want a simple "end of day" sync button
- You don't mind opening the app when you're done
- You want minimal complexity
- You don't need App Store background mode justification

**Use the Full Version if:**
- You want true "zero-touch" experience
- You want workouts to save automatically
- You walk multiple sessions throughout the day
- You want the app to work entirely in the background

## Code Overview

### SimpleTreadmillSync.swift

One class that does everything:
- Manages CBCentralManager for Bluetooth
- Scans and connects to treadmill
- Sends handshake sequence
- Fetches steps, distance, calories
- Saves to HealthKit as a workout
- Disconnects when done

### SimpleMainView.swift

Simple SwiftUI view with:
- One "Connect & Sync Workout" button
- Status display (scanning, connecting, fetching, saving, success/error)
- Data display (steps, distance, calories)
- Progress indicator while syncing

That's it! Much simpler than the full version's multi-manager architecture.

## Troubleshooting

**"Bluetooth is not powered on"**
- Enable Bluetooth in iOS Settings

**"HealthKit permission required"**
- Grant permission when prompted, or go to Settings → Health → Data Access & Devices

**"Treadmill not found"**
- Make sure treadmill is powered on
- Make sure you're within Bluetooth range (~30 feet)
- Try again

**Sync takes a long time**
- Normal sync takes 5-10 seconds
- If it times out after 10 seconds, try again
- Make sure treadmill is responding (try pressing buttons on console)

## Future Enhancements

Possible improvements:
- Remember last sync time and calculate workout duration
- Support multiple syncs per day (accumulate throughout day)
- Add a history view of past syncs
- Add ability to edit workout before saving
- Support manual entry if treadmill is off

For now, the simplified version focuses on doing one thing well: syncing your daily steps to Apple Health with a single button press.
