import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var serviceSession: CLServiceSession?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var backgroundUpdatesRequested = false

    var authorizationStatus: CLAuthorizationStatus
    var latestLocation: CLLocation?
    var lastErrorMessage: String?
    var onLocationUpdate: ((CLLocation) -> Void)?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 75
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = true
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
    }

    var servicesEnabled: Bool { CLLocationManager.locationServicesEnabled() }

    func refreshAuthorizationStatus() {
        authorizationStatus = manager.authorizationStatus
    }

    func requestWhenInUse() {
        serviceSession = CLServiceSession(authorization: .whenInUse)
        manager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAndStartBackgroundUpdates() {
        backgroundUpdatesRequested = true
        if authorizationStatus == .notDetermined {
            requestWhenInUse()
            return
        }
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else { return }
        serviceSession = CLServiceSession(authorization: .always)
        manager.requestAlwaysAuthorization()
        if authorizationStatus == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = false
            manager.startUpdatingLocation()
        }
    }

    func startForegroundUpdates() {
        backgroundUpdatesRequested = false
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        serviceSession = CLServiceSession(authorization: .whenInUse)
        manager.startUpdatingLocation()
    }

    func stopUpdates() {
        manager.stopUpdatingLocation()
        backgroundUpdatesRequested = false
        manager.allowsBackgroundLocationUpdates = false
        serviceSession?.invalidate()
        serviceSession = nil
    }

    func currentLocation() async throws -> CLLocation {
        if let latestLocation, Date.now.timeIntervalSince(latestLocation.timestamp) < 60 {
            return latestLocation
        }
        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    private func receive(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 250 else { return }
        latestLocation = location
        lastErrorMessage = nil
        if let locationContinuation {
            self.locationContinuation = nil
            locationContinuation.resume(returning: location)
        }
        onLocationUpdate?(location)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways, backgroundUpdatesRequested {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = false
            manager.startUpdatingLocation()
        }
        if authorizationStatus == .denied || authorizationStatus == .restricted {
            lastErrorMessage = "Location access is off. You can still search for venues manually."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last { receive(location) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let locationContinuation {
            self.locationContinuation = nil
            locationContinuation.resume(throwing: error)
        }
        lastErrorMessage = "Your location could not be determined."
    }
}

enum LocationActivityMode: Equatable {
    case stopped
    case foreground
    case background
}

enum LocationActivityPolicy {
    static func mode(
        locationUseEnabled: Bool,
        remindersEnabled: Bool,
        authorizationStatus: CLAuthorizationStatus,
        sceneIsActive: Bool
    ) -> LocationActivityMode {
        guard locationUseEnabled else { return .stopped }
        if remindersEnabled, authorizationStatus == .authorizedAlways {
            return .background
        }
        return sceneIsActive ? .foreground : .stopped
    }
}
