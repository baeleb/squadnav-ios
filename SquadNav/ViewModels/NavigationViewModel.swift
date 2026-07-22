import Foundation
import Combine
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
    let liveActivityService: LiveActivityService

    // Internal (not private) purely as a test seam for SquadNavTests.
    var monitorTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    var isLeader: Bool {
        guard let userId = Auth.auth().currentUser?.uid else { return false }
        return groupService.activeGroup?.createdBy == userId
    }

    init(groupService: GroupService, chatService: ChatService) {
        self.groupService = groupService
        self.chatService = chatService
        self.caravanMonitor = CaravanMonitorService(groupService: groupService, chatService: chatService)
        self.liveActivityService = LiveActivityService(navigationService: navigationService)
        setupCallbacks()

        // Forward nested service changes so views observing this view model update.
        for serviceChange in [
            navigationService.objectWillChange,
            locationService.objectWillChange,
            caravanMonitor.objectWillChange
        ] {
            serviceChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    deinit {
        monitorTimer?.invalidate()
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

                let status: DriverStatus
                if self.navigationService.isConverging {
                    // Connector legs are far from the shared route by design;
                    // .rerouting tells the leader's monitor not to flag it.
                    status = .rerouting
                } else {
                    status = self.navigationService.navigationState.isOffRoute ? .offRoute : .onRoute
                }
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
                let arrivedState = NavigationActivityAttributes.ContentState(
                    instruction: "You've arrived",
                    nextInstruction: nil,
                    maneuverIconName: "flag.checkered",
                    distanceToManeuverMeters: 0,
                    distanceRemainingMeters: 0,
                    etaSeconds: 0,
                    isRerouting: false
                )
                await self.liveActivityService.endActivity(finalState: arrivedState)
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

    /// Leader clears the shared destination: removes it from Firestore
    /// (all members' maps update via the group listener) and drops the
    /// local route state.
    func clearDestination() async {
        guard isLeader, let groupId = groupService.activeGroup?.id else { return }
        selectedDestination = nil
        navigationService.stopNavigation()
        do {
            try await groupService.clearDestination(groupId: groupId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func startNavigation() async {
        guard let groupId = groupService.activeGroup?.id,
              let group = groupService.activeGroup else { return }

        // After a leader switch, this leader's local route is empty (the
        // original leader's setDestinationAndCalculateRoute populated it on
        // their device only). Load from the group's stored polyline first.
        if navigationService.routePolylineCoordinates.isEmpty,
           let polyline = group.routePolyline, !polyline.isEmpty,
           let lat = group.destinationLatitude, let lng = group.destinationLongitude {
            let destination = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            do {
                try await navigationService.setRouteFromPolyline(polyline, destination: destination)
            } catch {
                self.error = error.localizedDescription
            }
        }

        locationService.startTracking()
        navigationService.startNavigation()
        caravanMonitor.setRoute(coordinates: navigationService.routePolylineCoordinates)
        showNavigation = true
        liveActivityService.startActivity(
            destinationName: groupService.activeGroup?.destinationName ?? selectedDestination?.name ?? "Destination"
        )

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
        locationService.stopTracking()
        navigationService.stopNavigation()
        showNavigation = false
        stopCaravanMonitoring()
        Task { await liveActivityService.endActivity() }

        // Only the leader ends navigation for the whole group; a member
        // stopping locally must not flip the shared flag for everyone.
        guard isLeader, let groupId = groupService.activeGroup?.id else { return }

        do {
            try await groupService.stopNavigation(groupId: groupId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Joins an in-progress group navigation as a non-leader member,
    /// following the route the leader shared via Firestore.
    func joinNavigation() async {
        guard !showNavigation,
              let group = groupService.activeGroup,
              let lat = group.destinationLatitude,
              let lng = group.destinationLongitude else { return }

        let destination = CLLocationCoordinate2D(latitude: lat, longitude: lng)

        do {
            if let polyline = group.routePolyline, !polyline.isEmpty {
                try await navigationService.setRouteFromPolyline(
                    polyline,
                    destination: destination,
                    from: locationService.currentLocation?.coordinate
                )
            } else if let location = locationService.currentLocation {
                let route = try await navigationService.calculateRoute(
                    from: location.coordinate,
                    to: destination
                )
                navigationService.setRoute(route)
            } else {
                return
            }

            locationService.startTracking()
            navigationService.startNavigation()
            caravanMonitor.setRoute(coordinates: navigationService.routePolylineCoordinates)
            showNavigation = true
            liveActivityService.startActivity(
                destinationName: groupService.activeGroup?.destinationName ?? "Destination"
            )
            // Only one leader runs the monitor; this covers a new leader
            // joining mid-navigation after a switch.
            if isLeader {
                startCaravanMonitoring()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Tears down navigation locally when the leader ends it for the group.
    func endNavigationLocally() {
        locationService.stopTracking()
        navigationService.stopNavigation()
        stopCaravanMonitoring()
        showNavigation = false
        Task { await liveActivityService.endActivity() }
    }

    private func reroute() async {
        guard let location = locationService.currentLocation else { return }

        if isLeader {
            // Leader recalculates directly; selectedDestination is nil on
            // any device but the one that picked it, so fall back to the
            // group's Firestore destination.
            guard let destination = selectedDestination?.placemark.coordinate
                    ?? groupService.activeGroup?.destinationCoordinate else { return }
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
        } else {
            // Members converge back onto the shared route, unchanged for all.
            guard let destination = groupService.activeGroup?.destinationCoordinate else { return }
            do {
                try await navigationService.rerouteToSharedRoute(
                    from: location.coordinate,
                    destination: destination
                )
            } catch {
                self.error = "Rerouting failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Caravan Monitoring

    // Internal (not private) purely as a test seam for SquadNavTests.
    func startCaravanMonitoring() {
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
