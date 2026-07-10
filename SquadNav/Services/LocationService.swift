import Foundation
import CoreLocation
import Combine

@MainActor
class LocationService: NSObject, ObservableObject {
    @Published var currentLocation: CLLocation?
    @Published var heading: CLHeading?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let locationManager = CLLocationManager()
    private var lastFirestoreUpdate: Date?

    // Throttle Firestore updates
    private let updateInterval: TimeInterval = 3.0
    private let minimumDistance: CLLocationDistance = 10.0
    private var lastUploadedLocation: CLLocation?

    var onLocationUpdate: ((CLLocation) -> Void)?
    var onShouldUploadToFirestore: ((CLLocation) -> Void)?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .automotiveNavigation
        locationManager.distanceFilter = 5
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func requestAlwaysPermission() {
        locationManager.requestAlwaysAuthorization()
    }

    func startTracking() {
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }

    func stopTracking() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }

    private func shouldUploadToFirestore(location: CLLocation) -> Bool {
        guard let lastUpdate = lastFirestoreUpdate,
              let lastLocation = lastUploadedLocation else {
            return true
        }

        let timeSinceLastUpdate = Date().timeIntervalSince(lastUpdate)
        let distanceSinceLastUpdate = location.distance(from: lastLocation)

        return timeSinceLastUpdate >= updateInterval || distanceSinceLastUpdate >= minimumDistance
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            self.currentLocation = location
            self.onLocationUpdate?(location)

            if self.shouldUploadToFirestore(location: location) {
                self.lastFirestoreUpdate = Date()
                self.lastUploadedLocation = location
                self.onShouldUploadToFirestore?(location)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            self.heading = newHeading
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[LocationService] Error: \(error.localizedDescription)")
    }
}
