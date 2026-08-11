import Foundation
import Observation
import UserNotifications
import UIKit

/// Abstraction over visit-reminder delivery so the detection pipeline can be
/// unit tested without UserNotifications (audit findings A-04, T-01).
@MainActor
protocol VisitNotifying: AnyObject {
    var authorizationStatus: UNAuthorizationStatus { get }
    func scheduleVisitReminder(venue: VenueCandidate, existingEntry: ParmaEntry?) async throws
}

@MainActor
@Observable
final class NotificationService: VisitNotifying {
    private let center = UNUserNotificationCenter.current()
    var authorizationStatus: UNAuthorizationStatus = .notDetermined

    func refreshStatus() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            await refreshStatus()
            return granted
        } catch {
            await refreshStatus()
            return false
        }
    }

    func scheduleVisitReminder(venue: VenueCandidate, existingEntry: ParmaEntry?) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Parma Master"
        if let existingEntry {
            content.body = "Back at \(venue.name)? Update your parma rating."
            content.userInfo = ["entryID": existingEntry.id.uuidString]
        } else {
            content.body = "At \(venue.name)? Log your parma."
            content.userInfo = [
                "venue": try JSONEncoder().encode(venue).base64EncodedString()
            ]
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: "visit-\(venue.id)", content: content, trigger: nil)
        try await center.add(request)
    }
}

extension Notification.Name {
    static let parmaNotificationDeepLink = Notification.Name("ParmaMaster.NotificationDeepLink")
}

final class AppDelegate: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    /// Deep-link payload from a notification tapped before RootView's
    /// NotificationCenter subscription exists (cold start). RootView consumes
    /// it in its startup task; warm taps are handled via the posted
    /// notification and the stash is discarded.
    private static let pendingDeepLink = LockIsolated<[AnyHashable: Any]?>(nil)

    static func consumePendingDeepLink() -> [AnyHashable: Any]? {
        pendingDeepLink.withLock { value in
            let pending = value
            value = nil
            return pending
        }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        Self.pendingDeepLink.withLock { $0 = userInfo }
        NotificationCenter.default.post(
            name: .parmaNotificationDeepLink,
            object: nil,
            userInfo: userInfo
        )
        completionHandler()
    }
}
