import Foundation
import Observation
import UserNotifications
import UIKit

@MainActor
@Observable
final class NotificationService {
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
        NotificationCenter.default.post(
            name: .parmaNotificationDeepLink,
            object: nil,
            userInfo: response.notification.request.content.userInfo
        )
        completionHandler()
    }
}
