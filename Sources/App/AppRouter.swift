import Foundation
import Observation
import SwiftUI
import UIKit

enum AppTab: Hashable {
    case home
    case log
    case insights
    case settings
    case search
}

enum LoggerMode {
    case new
    case edit
    case rateAgain
}

struct LoggerRequest: Identifiable {
    let id = UUID()
    var entry: ParmaEntry?
    var venue: VenueCandidate?
    var mode: LoggerMode
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab = AppTab.home
    var loggerRequest: LoggerRequest?
    var presentedDetails: ParmaEntry?
    /// Root-level Areas sheet. Prefer this over Insights-local presentation so Home
    /// deep links get a system sheet animation (TabView selection itself does not animate).
    var showingAreasList = false

    func selectTab(_ tab: AppTab) {
        selectedTab = tab
    }

    func showAreasList() {
        selectedTab = .insights
        showingAreasList = true
    }

    func log(venue: VenueCandidate? = nil) {
        loggerRequest = LoggerRequest(entry: nil, venue: venue, mode: .new)
    }

    func edit(_ entry: ParmaEntry) {
        loggerRequest = LoggerRequest(entry: entry, venue: nil, mode: .edit)
    }

    func rateAgain(_ entry: ParmaEntry) {
        loggerRequest = LoggerRequest(entry: entry, venue: nil, mode: .rateAgain)
    }

    func presentDetails(_ entry: ParmaEntry) {
        presentedDetails = entry
    }

    func dismissDetails() {
        presentedDetails = nil
    }

    func openLogEntry(_ entry: ParmaEntry) {
        selectedTab = .log
        presentedDetails = entry
    }

    func openHomeLogger(venue: VenueCandidate) {
        selectedTab = .home
        loggerRequest = LoggerRequest(entry: nil, venue: venue, mode: .new)
    }
}
