# TreadmillSync - Comprehensive Improvement Plan

## 🚨 Critical Issues Found

The code review revealed **8 critical bugs** that could cause:
- Data loss
- Double-counting steps
- App hangs
- Memory leaks
- Battery drain

Plus the **Bluetooth walkaway problem** you mentioned.

---

## 🎯 The Bluetooth Walkaway Problem

### The Issue:
**When you walk away with your phone while connected**, the treadmill's Bluetooth turns off (even though the unit stays on). When you return, **the treadmill won't auto-reconnect** because it's not advertising anymore - you must manually press the Bluetooth button.

### This Breaks:
- ✗ Seamless all-day tracking
- ✗ Auto-reconnection promises
- ✗ "Zero-touch" experience

### The Solution: **Smart Connection Management**

```swift
// 1. Detect when connection drops due to range (vs power off)
// 2. Show clear UI state: "Treadmill BLE off - press button to reconnect"
// 3. Add manual reconnect button
// 4. Educate user about this limitation
// 5. Consider warning before walking away
```

---

## 📋 Priority 1: Critical Bug Fixes

### 1. Fix Delta Calculation (Double-Counting Bug) 🐛

**Current Code** (DailySessionManager.swift:216-221):
```swift
private func delta<T: Comparable & Numeric>(current: T?, previous: T?) -> T? {
    guard let current else { return nil }
    guard let previous else { return current }
    let change = current - previous
    return change >= 0 ? change : current // ❌ BUG: Returns full current on reset
}
```

**Problem**: If treadmill resets mid-workout (e.g., 5000 steps → 0), this returns 0 (the full current value), adding ALL steps again. User ends up with 10,000 steps instead of 5,000.

**Fix**:
```swift
private func delta<T: Comparable & Numeric>(current: T?, previous: T?) -> T? {
    guard let current else { return nil }
    guard let previous else { return current }

    let change = current - previous

    // If values decreased, treadmill likely reset
    if change < 0 {
        // Log warning
        print("⚠️ Treadmill counter reset detected: \(previous) → \(current)")

        // Treat current as new baseline (don't add it)
        // The delta is 0, not current
        return 0
    }

    return change
}
```

**Impact**: Prevents massive over-counting when treadmill resets.

---

### 2. Add Scanning Timeout ⏱️

**Current Code** (TreadmillManager.swift:164-168):
```swift
centralManager.scanForPeripherals(withServices: [serviceUUID], options: options)
// ❌ Never stops scanning
```

**Problem**: Scans forever if treadmill isn't found. Drains battery.

**Fix**:
```swift
func startScanning() async {
    // ... existing code ...

    connectionState = .scanning
    centralManager.scanForPeripherals(withServices: [serviceUUID], options: options)

    // ✅ Add timeout
    try? await Task.sleep(for: .seconds(30))

    // If still scanning after 30 seconds, stop
    if case .scanning = connectionState {
        centralManager.stopScan()
        connectionState = .error("Treadmill not found. Make sure it's powered on and Bluetooth pairing is enabled (press BLE button if needed).")
        print("⏱️ Scan timeout after 30 seconds")
    }
}
```

**Impact**: Prevents battery drain, gives user clear feedback.

---

### 3. Add Connection Timeout ⏱️

**Current Code** (TreadmillManager.swift:193-209):
```swift
centralManager.connect(peripheral, options: nil)
try await withCheckedThrowingContinuation { continuation in
    connectionContinuation = continuation
}
// ❌ Waits forever
```

**Problem**: If treadmill doesn't respond, app hangs indefinitely.

**Fix**:
```swift
private func connect(to peripheral: CBPeripheral) async {
    self.peripheral = peripheral
    peripheral.delegate = self
    connectionState = .connecting

    do {
        print("🔌 Connecting to \(peripheral.name ?? "Unknown")...")
        centralManager.connect(peripheral, options: nil)

        // ✅ Add 10-second timeout
        try await withThrowingTimeout(seconds: 10) {
            try await withCheckedThrowingContinuation { continuation in
                connectionContinuation = continuation
            }
        }

        print("✅ Connected to treadmill")
        await discoverServices()
    } catch is TimeoutError {
        connectionState = .error("Connection timeout. Treadmill may be off or paired with another device.")
        print("❌ Connection timeout after 10 seconds")
        centralManager.cancelPeripheralConnection(peripheral)
    } catch {
        connectionState = .error("Connection failed: \(error.localizedDescription)")
        print("❌ Connection failed: \(error.localizedDescription)")
    }
}

// Helper
private func withThrowingTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

private struct TimeoutError: Error {}
```

**Impact**: App no longer hangs, user gets feedback.

---

### 4. Fix Infinite Reconnection Loop 🔁

**Current Code** (TreadmillManager.swift:419-424):
```swift
nonisolated func centralManager(_ central: CBCentralManager,
                               didDisconnectPeripheral peripheral: CBPeripheral,
                               error: Error?) {
    Task { @MainActor in
        // ... cleanup ...

        // ❌ Reconnects forever
        if let peripheral = self.peripheral {
            central.connect(peripheral, options: nil)
        } else {
            await startScanning()
        }
    }
}
```

**Problem**: Tries to reconnect immediately and infinitely. If treadmill BLE is off (your walkaway scenario), this creates endless failed connection attempts.

**Fix**:
```swift
// Add properties
private var reconnectionAttempts = 0
private var lastDisconnectTime: Date?
private let maxReconnectionAttempts = 5

nonisolated func centralManager(_ central: CBCentralManager,
                               didDisconnectPeripheral peripheral: CBPeripheral,
                               error: Error?) {
    Task { @MainActor in
        print("❌ Disconnected from treadmill")

        pollTask?.cancel()
        pollTask = nil
        pendingQueries.removeAll()

        connectionState = .disconnected
        lastDisconnectTime = Date()

        // ✅ Exponential backoff with max attempts
        reconnectionAttempts += 1

        if reconnectionAttempts > maxReconnectionAttempts {
            print("⚠️ Max reconnection attempts reached. Stopping auto-reconnect.")
            connectionState = .error("Lost connection to treadmill. Tap 'Reconnect' or press the BLE button on treadmill and wait.")
            return
        }

        let backoffDelay = min(pow(2.0, Double(reconnectionAttempts)), 30.0) // Max 30 seconds
        print("🔄 Will retry connection in \(Int(backoffDelay)) seconds (attempt \(reconnectionAttempts)/\(maxReconnectionAttempts))")

        try? await Task.sleep(for: .seconds(backoffDelay))

        if let peripheral = self.peripheral {
            central.connect(peripheral, options: nil)
        } else {
            await startScanning()
        }
    }
}

// Reset on successful connection
nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    Task { @MainActor in
        reconnectionAttempts = 0 // ✅ Reset on success
        connectionContinuation?.resume()
        connectionContinuation = nil
    }
}
```

**Impact**: Prevents infinite loops, saves battery, provides better UX.

---

### 5. Fix Memory Leak 💾

**Current Code** (TreadmillSyncApp.swift:36-44):
```swift
NotificationCenter.default.addObserver(
    forName: .workoutCompleted,
    object: nil,
    queue: .main
) { notification in
    // ❌ Never removed
}
```

**Problem**: Observer lives forever, never deallocated.

**Fix**:
```swift
@main
struct TreadmillSyncApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var coordinator = WorkoutCoordinator.shared
    private var workoutObserver: NSObjectProtocol? // ✅ Store observer

    var body: some Scene {
        WindowGroup {
            MainView()
                .onAppear {
                    if workoutObserver == nil {
                        setupNotifications()
                    }
                    requestHealthAuthorization()
                }
                .onDisappear {
                    // ✅ Clean up
                    if let observer = workoutObserver {
                        NotificationCenter.default.removeObserver(observer)
                    }
                }
        }
    }

    private mutating func setupNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("✅ Notification permission granted")
            }
        }

        // ✅ Store observer so we can remove it
        workoutObserver = NotificationCenter.default.addObserver(
            forName: .workoutCompleted,
            object: nil,
            queue: .main
        ) { notification in
            if let stats = notification.object as? WorkoutStats {
                sendWorkoutCompletedNotification(stats: stats)
            }
        }
    }
}
```

**Impact**: Prevents memory leaks.

---

### 6. Validate Session Data on Load 🔒

**Current Code** (DailySessionManager.swift:92-99):
```swift
private init() {
    if let decoded = Self.loadState(forKey: storageKey) {
        currentSession = decoded.session // ❌ Could be from weeks ago!
        lastTreadmillData = decoded.lastSample
    } else {
        currentSession = DailySession.newSession()
        lastTreadmillData = nil
    }
}
```

**Problem**: Loads session from weeks/months ago without validation.

**Fix**:
```swift
private init() {
    if let decoded = Self.loadState(forKey: storageKey) {
        // ✅ Validate it's from today
        let sessionDate = decoded.session.startDate
        let isToday = calendar.isDateInToday(sessionDate)

        if isToday {
            currentSession = decoded.session
            lastTreadmillData = decoded.lastSample
            print("📂 Loaded today's session: \(decoded.session.totalSteps) steps")
        } else {
            print("⚠️ Loaded session is from \(sessionDate), resetting")
            currentSession = DailySession.newSession()
            lastTreadmillData = nil
        }
    } else {
        currentSession = DailySession.newSession()
        lastTreadmillData = nil
    }
}
```

**Impact**: Prevents loading stale data.

---

### 7. Add Save Timeout ⏱️

**Current Code** (MainView.swift:155-169):
```swift
private func saveWorkout() {
    guard !isSavingWorkout else { return }
    isSavingWorkout = true

    Task { @MainActor in
        do {
            try await coordinator.saveWorkout()
            // ❌ No timeout, button disabled forever if this hangs
        }
    }
}
```

**Problem**: If HealthKit hangs, button stays disabled forever.

**Fix**:
```swift
private func saveWorkout() {
    guard !isSavingWorkout else { return }
    isSavingWorkout = true

    Task { @MainActor in
        do {
            // ✅ 30-second timeout
            try await withTimeout(seconds: 30) {
                try await coordinator.saveWorkout()
            }
            showReviewSheet = false
            alertMessage = "Workout saved to Apple Health! 🎉"
        } catch is TimeoutError {
            alertMessage = "Save timeout. Please try again."
            print("❌ HealthKit save timeout after 30 seconds")
        } catch {
            alertMessage = error.localizedDescription
        }
        isSavingWorkout = false // ✅ Always re-enable button
    }
}
```

**Impact**: Button never stays stuck, user can retry.

---

### 8. Validate HealthKit Workout Data ✅

**Current Code** (HealthKitManager.swift:148-161):
```swift
for segment in session.activitySegments {
    let workoutSegment = HKWorkoutActivity(
        workoutConfiguration: configuration,
        start: segment.startTime,
        end: segment.endTime, // ❌ No validation
        //...
    )
}
```

**Problem**: Could create invalid HealthKit data (end < start, overlapping segments).

**Fix**:
```swift
func saveDailyWorkout(from session: DailySession) async throws {
    // ... existing auth checks ...

    // ✅ Validate session data
    try validateSession(session)

    // ... rest of function ...
}

private func validateSession(_ session: DailySession) throws {
    // Check segments are valid
    for segment in session.activitySegments {
        guard segment.endTime > segment.startTime else {
            throw HealthKitError.custom("Invalid segment: end time before start time")
        }

        let duration = segment.endTime.timeIntervalSince(segment.startTime)
        guard duration < 86400 else { // 24 hours
            throw HealthKitError.custom("Invalid segment: duration > 24 hours")
        }
    }

    // Check segments don't overlap
    let sorted = session.activitySegments.sorted { $0.startTime < $1.startTime }
    for i in 0..<(sorted.count - 1) {
        if sorted[i].endTime > sorted[i+1].startTime {
            throw HealthKitError.custom("Invalid segments: overlapping times")
        }
    }

    // Check data is reasonable
    guard session.totalSteps < 100000 else {
        throw HealthKitError.custom("Steps seem unreasonably high (\(session.totalSteps)). Please verify.")
    }

    guard session.totalDistanceMiles < 50 else {
        throw HealthKitError.custom("Distance seems unreasonably high (\(session.totalDistanceMiles) mi). Please verify.")
    }

    // Check distance/steps ratio is reasonable
    if session.totalSteps > 0 {
        let milesPerStep = session.totalDistanceMiles / Double(session.totalSteps)
        guard milesPerStep < 0.001 else { // Average step is ~2.5 feet = 0.00047 miles
            throw HealthKitError.custom("Distance/steps ratio seems wrong. Check treadmill calibration?")
        }
    }
}
```

**Impact**: Prevents saving invalid/unrealistic data to Health.

---

## 📋 Priority 2: Bluetooth Walkaway Solution

### The Problem (Again):
When you walk >30 feet away with phone, treadmill BLE turns off. **Manual button press required** to re-enable.

### Multi-Layered Solution:

#### 1. Detect "BLE Off" State
```swift
// TreadmillManager.swift
enum ConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case connected
    case disconnectedBLEOff  // ✅ New state
    case error(String)
}

// In didDisconnectPeripheral:
nonisolated func centralManager(_ central: CBCentralManager,
                               didDisconnectPeripheral peripheral: CBPeripheral,
                               error: Error?) {
    Task { @MainActor in
        // Check if this is a range disconnect
        if let error = error as? CBError {
            if error.code == .connectionTimeout {
                // Likely walked away
                connectionState = .disconnectedBLEOff
                print("📡 Connection lost - treadmill BLE may be off")
                return
            }
        }

        // Normal disconnect handling...
    }
}
```

#### 2. Add Manual Reconnect Button
```swift
// MainView.swift - in ConnectionStatusCard
if case .disconnectedBLEOff = state {
    VStack(spacing: 12) {
        Text("Treadmill Bluetooth is off")
            .font(.headline)
            .foregroundStyle(.orange)

        Text("Press the BLE button on your treadmill to re-enable pairing, then tap Reconnect below.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

        Button(action: {
            Task {
                await coordinator.treadmillManager.startScanning()
            }
        }) {
            Label("Reconnect", systemImage: "arrow.clockwise")
                .font(.headline)
        }
        .buttonStyle(.borderedProminent)
    }
    .padding()
}
```

#### 3. Add Proximity Warning
```swift
// WorkoutCoordinator.swift
private func monitorConnectionQuality() {
    // Monitor RSSI (signal strength)
    Task {
        while !Task.isCancelled {
            if let peripheral = treadmillManager.peripheral {
                peripheral.readRSSI()
            }
            try? await Task.sleep(for: .seconds(5))
        }
    }
}

// In CBPeripheralDelegate:
func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
    let signalStrength = RSSI.intValue

    // RSSI typically ranges from -30 (very close) to -100 (far)
    if signalStrength < -80 && signalStrength > -100 {
        // Weak signal, about to disconnect
        print("⚠️ Weak Bluetooth signal (RSSI: \(signalStrength))")
        showProximityWarning()
    } else if signalStrength < -90 {
        print("❌ Very weak signal (RSSI: \(signalStrength)) - disconnection imminent")
    }
}
```

#### 4. Add Onboarding Education
```swift
// OnboardingView.swift - add new page
struct BluetoothLimitationsPage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 70))
                    .foregroundStyle(.orange)

                Text("Important: Stay Close")
                    .font(.title.bold())

                Text("Your phone must stay within Bluetooth range (~30 feet) of the treadmill.")
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 12) {
                    WarningRow(text: "Walking away turns off treadmill's Bluetooth")
                    WarningRow(text: "You'll need to press the BLE button to reconnect")
                    WarningRow(text: "Keep your phone on your desk while walking")
                }

                Text("Tip: Leave your phone on a desk/table near the treadmill for best results.")
                    .font(.callout)
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
            }
        }
    }
}
```

---

## 📋 Priority 3: UX & Polish Improvements

### 1. Add Minimum Threshold for "Today's Session" Card
```swift
// MainView.swift
if sessionManager.currentSession.hasData &&
   sessionManager.currentSession.totalSteps >= 100 { // ✅ Minimum 100 steps
    TodaySessionCard(...)
}
```

### 2. Show Data Freshness
```swift
// MainView.swift - TodaySessionCard
if let updated = session.lastUpdated {
    let timeSince = Date().timeIntervalSince(updated)
    let freshness = timeSince < 60 ? "Just now" :
                    timeSince < 300 ? "\(Int(timeSince/60))m ago" :
                    "Updated \(updated, style: .time)"

    Text(freshness)
        .font(.caption)
        .foregroundStyle(timeSince < 300 ? .green : .secondary)
}
```

### 3. Add Connection Quality Indicator
```swift
// ConnectionStatusCard
if state.isConnected, let rssi = treadmillManager.currentRSSI {
    HStack(spacing: 4) {
        Image(systemName: signalIcon(for: rssi))
            .foregroundStyle(signalColor(for: rssi))
        Text(signalLabel(for: rssi))
            .font(.caption)
    }
}

private func signalIcon(for rssi: Int) -> String {
    switch rssi {
    case -30...0: return "wifi.circle.fill"
    case -60..<(-30): return "wifi.circle"
    case -80..<(-60): return "wifi.slash.circle"
    default: return "wifi.exclamationmark.circle"
    }
}
```

### 4. Add Retry Button in Error State
```swift
// ConnectionStatusCard
if case .error(let message) = state {
    VStack(spacing: 12) {
        Text(message)
        Button(action: retry) {
            Label("Retry", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderedProminent)
    }
}
```

### 5. Add Workout Editing (Simple)
```swift
// SessionReviewSheet.swift
@State private var editedSteps: Int
@State private var editedDistance: Double
@State private var editedCalories: Int
@State private var isEditing = false

var body: some View {
    // ... existing code ...

    Button("Edit Values") {
        isEditing.toggle()
    }

    if isEditing {
        Form {
            Stepper("Steps: \(editedSteps)", value: $editedSteps, in: 0...100000, step: 100)
            Stepper("Distance: \(String(format: "%.2f", editedDistance)) mi",
                    value: $editedDistance, in: 0...50, step: 0.1)
            Stepper("Calories: \(editedCalories)", value: $editedCalories, in: 0...5000, step: 10)
        }
    }
}
```

---

## 📋 Priority 4: Delightful Features

### 1. Daily Goal Progress
```swift
// Add to DailySessionManager
var dailyGoal: Int { UserDefaults.standard.integer(forKey: "dailyStepGoal") }

var goalProgress: Double {
    guard dailyGoal > 0 else { return 0 }
    return min(Double(currentSession.totalSteps) / Double(dailyGoal), 1.0)
}

// In MainView
if sessionManager.dailyGoal > 0 {
    GoalProgressView(
        current: sessionManager.currentSession.totalSteps,
        goal: sessionManager.dailyGoal,
        progress: sessionManager.goalProgress
    )
}
```

### 2. Milestone Celebrations
```swift
// WorkoutCoordinator.swift
private var lastCelebratedMilestone: Int = 0

private func checkMilestones(_ steps: Int) {
    let milestones = [1000, 5000, 10000, 15000, 20000]

    for milestone in milestones where steps >= milestone && lastCelebratedMilestone < milestone {
        celebrate(milestone: milestone)
        lastCelebratedMilestone = milestone
        break
    }
}

private func celebrate(milestone: Int) {
    // Haptic
    let generator = UINotificationFeedbackGenerator()
    generator.notificationOccurred(.success)

    // Notification
    let content = UNMutableNotificationContent()
    content.title = "Milestone Reached! 🎉"
    content.body = "You've walked \(milestone) steps today!"
    content.sound = .default

    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
}
```

### 3. Smart Data Smoothing
```swift
// BLEDataParser.swift
private var smoothedSpeed: Double?
private let smoothingFactor: Double = 0.3

private func parseSpeed(bytes: [UInt8]) -> Double? {
    // ... existing parsing ...

    // Apply exponential smoothing
    if let smoothed = smoothedSpeed {
        speed = smoothingFactor * speed + (1 - smoothingFactor) * smoothed
    }
    smoothedSpeed = speed

    return speed
}
```

### 4. Quick Metrics Toggle
```swift
// SettingsView.swift
@AppStorage("showMetric") private var showMetric = false

Toggle("Use Metric Units", isOn: $showMetric)

// Helper
func formatDistance(_ miles: Double, metric: Bool) -> String {
    if metric {
        let km = miles * 1.60934
        return String(format: "%.2f km", km)
    } else {
        return String(format: "%.2f mi", miles)
    }
}
```

---

## 🎨 Priority 5: Visual Polish

### 1. Animated Number Transitions
```swift
// MainView.swift
struct AnimatedNumber: View {
    let value: Int
    @State private var displayValue: Int = 0

    var body: some View {
        Text("\(displayValue)")
            .font(.system(size: 64, weight: .bold, design: .rounded))
            .contentTransition(.numericText())
            .onChange(of: value) { oldValue, newValue in
                withAnimation(.spring(duration: 0.5)) {
                    displayValue = newValue
                }
            }
            .onAppear {
                displayValue = value
            }
    }
}
```

### 2. Pulse Effect for Live Stats
```swift
// LiveStatsCard
Circle()
    .fill(.green)
    .frame(width: 8, height: 8)
    .overlay(
        Circle()
            .stroke(.green, lineWidth: 2)
            .scaleEffect(isAnimating ? 1.5 : 1.0)
            .opacity(isAnimating ? 0 : 1)
    )
    .onAppear {
        withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) {
            isAnimating = true
        }
    }
```

### 3. Confetti on Save Success
```swift
// SessionReviewSheet.swift
@State private var showConfetti = false

// After successful save:
withAnimation {
    showConfetti = true
}

// Add confetti view:
if showConfetti {
    ConfettiView()
        .allowsHitTesting(false)
}
```

---

## 📊 Summary of Improvements

### Critical Bugs Fixed: 8
1. ✅ Delta calculation (prevents double-counting)
2. ✅ Scanning timeout (prevents battery drain)
3. ✅ Connection timeout (prevents app hangs)
4. ✅ Infinite reconnection (adds backoff + max attempts)
5. ✅ Memory leak (removes notification observer)
6. ✅ Stale session data (validates date on load)
7. ✅ Save timeout (re-enables button)
8. ✅ Invalid workout data (validates before save)

### BLE Walkaway Solution: 4 Parts
1. ✅ Detect "BLE Off" state
2. ✅ Manual reconnect button
3. ✅ Proximity warning (RSSI monitoring)
4. ✅ Onboarding education

### UX Improvements: 5
1. ✅ Minimum threshold for session card
2. ✅ Data freshness indicator
3. ✅ Connection quality indicator
4. ✅ Retry button in error state
5. ✅ Simple workout editing

### Delight Features: 4
1. ✅ Daily goal progress
2. ✅ Milestone celebrations
3. ✅ Smart data smoothing
4. ✅ Metric/Imperial toggle

### Visual Polish: 3
1. ✅ Animated number transitions
2. ✅ Pulse effect for live indicator
3. ✅ Confetti on save success

---

## 🚀 Implementation Order

### Sprint 1: Critical Bugs (1 day)
- Fix delta calculation
- Add timeouts (scan, connect, save)
- Fix infinite reconnection
- Fix memory leak
- Validate session data on load
- Validate workout data before save

### Sprint 2: BLE Walkaway (1 day)
- Add disconnectedBLEOff state
- Add manual reconnect button
- Add RSSI monitoring
- Add proximity warning
- Add onboarding education page

### Sprint 3: UX Polish (1 day)
- Minimum threshold for cards
- Data freshness indicators
- Connection quality indicator
- Retry buttons
- Simple workout editing

### Sprint 4: Delight (1 day)
- Daily goal tracking
- Milestone celebrations
- Data smoothing
- Metric/Imperial toggle

### Sprint 5: Visual Polish (1 day)
- Animated transitions
- Pulse effects
- Confetti
- Refined color palette
- Micro-interactions

---

## 📝 Testing Checklist

After implementing improvements:

### Critical Bug Tests:
- [ ] Treadmill reset mid-workout → Steps don't double-count
- [ ] Scan for 30+ seconds → Times out with clear message
- [ ] Connect to offline treadmill → Times out, doesn't hang
- [ ] Disconnect 10+ times → Stops after 5 attempts, shows retry button
- [ ] App restart → Only loads today's session, not old data
- [ ] Save with invalid segments → Shows validation error
- [ ] HealthKit save hangs → Times out, button re-enables

### BLE Walkaway Tests:
- [ ] Walk 50 feet away → Enters "BLE Off" state
- [ ] Press treadmill BLE button → Can manually reconnect
- [ ] Walk close to edge of range → Shows proximity warning
- [ ] First-time user → Sees education about staying close

### UX Tests:
- [ ] Walk 50 steps → Card doesn't show (under minimum)
- [ ] Walk 200 steps → Card shows
- [ ] Data updates → Freshness indicator updates
- [ ] Connection weak → Signal indicator shows warning
- [ ] Error state → Retry button visible and works
- [ ] Edit workout values → Changes persist to Health

### Delight Tests:
- [ ] Set goal to 5000 → Progress bar shows correctly
- [ ] Reach 10,000 steps → Celebration notification appears
- [ ] Speed changes rapidly → Smoothed nicely in UI
- [ ] Toggle metric → All distances show in km

### Visual Tests:
- [ ] Steps count up → Number animates smoothly
- [ ] Live indicator → Pulses continuously
- [ ] Save workout → Confetti appears
- [ ] All animations → Smooth 60fps

---

Ready to implement? I can help build any of these improvements!
