//
//  TreadmillSyncApp.swift
//  TreadmillSync
//
//  Main app entry point with scene lifecycle support
//

import SwiftUI
import UserNotifications

@main
struct TreadmillSyncApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var coordinator = WorkoutCoordinator.shared
    @State private var notificationObserver: NSObjectProtocol?

    var body: some Scene {
        WindowGroup {
            TabRootView()
                .onAppear {
                    if notificationObserver == nil {
                        setupNotifications()
                    }
                    requestHealthAuthorization()
                }
                .onDisappear {
                    cleanupNotifications()
                }
        }
    }

    private func setupNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("✅ Notification permission granted")
            } else if let error = error {
                print("❌ Notification permission error: \(error.localizedDescription)")
            }
        }

        // Listen for workout completion and store observer
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .workoutCompleted,
            object: nil,
            queue: .main
        ) { notification in
            if let stats = notification.object as? WorkoutStats {
                sendWorkoutCompletedNotification(stats: stats)
            }
        }
        print("✅ Notification observer registered")
    }

    private func cleanupNotifications() {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
            print("✅ Notification observer removed")
        }
    }

    private func requestHealthAuthorization() {
        Task {
            do {
                try await HealthKitManager.shared.requestAuthorization()
                print("✅ HealthKit authorization granted")
            } catch {
                print("⚠️ HealthKit authorization needed - will prompt in app")
            }
        }
    }

    private func sendWorkoutCompletedNotification(stats: WorkoutStats) {
        let content = UNMutableNotificationContent()
        content.title = "Workout Saved! 🎉"
        content.body = stats.formattedSummary
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Notification error: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        print("\n🚀 TreadmillSync Launched")
        print("   Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
        print("   Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")")

        // BLE state restoration is handled automatically by TreadmillManager
        // via CBCentralManager's restoration identifier

        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self

        return configuration
    }
}

// MARK: - SceneDelegate

class SceneDelegate: NSObject, UIWindowSceneDelegate, ObservableObject {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        print("📱 Scene will connect")
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        print("📱 Scene became active")
    }

    func sceneWillResignActive(_ scene: UIScene) {
        print("📱 Scene will resign active")
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        print("📱 Scene entered background")
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        print("📱 Scene will enter foreground")
    }
}
