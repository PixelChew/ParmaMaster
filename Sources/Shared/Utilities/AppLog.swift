import Foundation
import os

/// Central loggers so previously-silent failure paths are diagnosable in the
/// field. Use `Logger`'s privacy annotations for anything user-identifying.
enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "ParmaMaster"

    static let location = Logger(subsystem: subsystem, category: "location")
    static let detection = Logger(subsystem: subsystem, category: "detection")
    static let backup = Logger(subsystem: subsystem, category: "backup")
    static let data = Logger(subsystem: subsystem, category: "data")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
}
