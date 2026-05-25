import Foundation
import MapKit
import CoreLocation
import FirebaseAuth

@MainActor
class NavigationViewModel: ObservableObject {
    @Published var isSearching = false
    @Published var searchResults: [MKMapItem] = []
    @Published var selectedDestination: MKMapItem?
    @Published var error: String?
    @Published var showNavigation = false

    let navigationService = NavigationService()
    let locationService = LocationService()
    let groupService: GroupService
    let chatService: ChatService
    let caravanMonitor: CaravanMonitorService

    private var monitorTimer: Timer?

    init(groupService: GroupService, chatService: ChatService) {
        self.groupService = groupService
        self.chatService = chatService
        self.caravanMonitor = CaravanMonitorService(groupService: groupService, chatService: chatService)
        setupCallbacks()
    }

    private func setupCallbacks() {
        // Location updates → navigation engine
        locationService.onLocationUpdate = { [weak self] location in
            Task { @MainActor [weak self] in
                self?.navigationService.updateLocation(location)
            }
        }

        // Location updates → Firestore
        locationService.onShouldUploadToFirestore = { [weak self] location in
            Task { @MainActor [weak self] in
                guard let self,
                      let groupId = self.groupService.activeGroup?.id else { return }

                let status: DriverStatus = self.navigationService.navigationState.isOffRoute ? .offRoute : .onRoute
                try? await self.groupService.updateMemberLocation(
                    groupId: groupId,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    heading: self.locationService.heading?.trueHeading ?? 0,
                    speed: location.speed,
                    status: status,
                    stepIndex: self.navigationService.navigationState.currentStepIndex
                )
            }
        }

        // Off-route callback
        navigationService.onOffRoute = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      let groupId = self.groupService.activeGroup?.id,
                      let userName = Auth.auth().currentUser?.displayName else { return }
                try? await self.chatService.sendSystemAlert(
                    groupId: groupId,
                    text: "⚠️ \(userName) has gone off route!"
                )
                // Attempt reroute
                await self.reroute()
            }
        }

        // Arrival callback
        navigationService.onArrived = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      let groupId = self.groupService.activeGroup?.id,
                      let userName = Auth.auth().currentUser?.displayName else { return }
                try? await self.chatService.sendSystemMessage(
                    groupId: groupId,
                    text: "🏁 \(userName) has arrived at the destination!"
                )
            }
        }
    }

    // MARK: - Search

    func searchDestination(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }

        isSearching = true

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query

        if let location = locationService.currentLocation {
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 100_000,
                longitudinalMeters: 100_000
            )
        }

        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()
            searchResults = response.mapItems
        } catch {
            searchResults = []
        }

        isSearching = false
    }

    // MARK: - Navigation Flow

    func setDestinationAndCalculateRoute(_ mapItem: MKMapItem) async {
        guard let location = locationService.currentLocation,
              let groupId = groupService.activeGroup?.id else { return }

        selectedDestination = mapItem
        let destination = mapItem.placemark.coordinate

        do {
            let route = try await navigationService.calculateRoute(
                from: location.coordinate,
                to: destination
            )
            navigationService.setRoute(route)

            // Encode and store route in Firestore for all drivers
            let encodedPolyline = navigationService.encodeCurrentRoute()
            try await groupService.setDestination(
                groupId: groupId,
                latitude: destination.latitude,
                longitude: destination.longitude,
                name: mapItem.name ?? "Destination",
                routePolyline: encodedPolyline
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    func startNavigation() async {
        guard let groupId = groupService.activeGroup?.id else { return }

        locationService.startTracking()
        navigationService.startNavigation()
        caravanMonitor.setRoute(coordinates: navigationService.routePolylineCoordinates)
        showNavigation = true

        do {
            try await groupService.startNavigation(groupId: groupId)
            try await chatService.sendSystemMessage(
                groupId: groupId,
                text: "🚗 Navigation has started! All drivers, follow the route."
            )
        } catch {
            self.error = error.localizedDescription
        }

        // Start monitoring caravan members periodically
        startCaravanMonitoring()
    }

    func stopNavigation() async {
        guard let groupId = groupService.activeGroup?.id else { return }

        locationService.stopTracking()
        navigationService.stopNavigation()
        showNavigation = false
        stopCaravanMonitoring()

        do {
            try await groupService.stopNavigation(groupId: groupId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func reroute() async {
        guard let location = locationService.currentLocation,
              let destination = selectedDestination?.placemark.coordinate else { return }

        do {
            let route = try await navigationService.calculateRoute(
                from: location.coordinate,
                to: destination
            )
            navigationService.setRoute(route)
            navigationService.startNavigation()
        } catch {
            self.error = "Rerouting failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Caravan Monitoring

    private func startCaravanMonitoring() {
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let groupId = self.groupService.activeGroup?.id else { return }

                let members = self.groupService.members
                let leader = members.first { $0.isLeader }

                await self.caravanMonitor.evaluateMembers(
                    members: members,
                    leaderLocation: leader,
                    groupId: groupId
                )
            }
        }
    }

    private func stopCaravanMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    // MARK: - Permissions

    func requestLocationPermission() {
        locationService.requestPermission()
    }
}
