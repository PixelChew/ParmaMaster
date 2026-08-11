import Foundation
import Observation

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

    func log(venue: VenueCandidate? = nil) {
        loggerRequest = LoggerRequest(entry: nil, venue: venue, mode: .new)
    }

    func edit(_ entry: ParmaEntry) {
        loggerRequest = LoggerRequest(entry: entry, venue: nil, mode: .edit)
    }

    func rateAgain(_ entry: ParmaEntry) {
        loggerRequest = LoggerRequest(entry: entry, venue: nil, mode: .rateAgain)
    }
}
