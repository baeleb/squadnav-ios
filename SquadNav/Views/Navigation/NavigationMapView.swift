import SwiftUI
import MapKit

struct NavigationMapView: View {
    @ObservedObject var navigationVM: NavigationViewModel
    @ObservedObject var groupViewModel: GroupViewModel
    @Environment(\.dismiss) var dismiss

    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var showEndConfirmation = false
    @State private var showCaravanPane = true
    @State private var paneTab: CaravanPaneTab = .chat
    @State private var paneDetent: PresentationDetent = .height(64)
    // Camera follows the user only after the brief full-route intro.
    @State private var followUser = false

    enum CaravanPaneTab: String, CaseIterable {
        case chat = "Chat"
        case files = "Files"
        case members = "Members"

        var icon: String {
            switch self {
            case .chat: return "bubble.left.and.bubble.right.fill"
            case .files: return "folder.fill"
            case .members: return "person.3.fill"
            }
        }
    }

    var body: some View {
        ZStack {
            // Full screen map
            mapView

            // Overlay UI
            VStack(spacing: 0) {
                // Top: Maneuver banner
                ManeuverBannerView(
                    navigationState: navigationVM.navigationService.navigationState
                )

                Spacer()

                // Bottom: Info bar
                bottomBar
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showEndConfirmation = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 60)
                }
                Spacer()
            }

            // Alerts overlay
            if let latestAlert = navigationVM.caravanMonitor.alerts.last {
                alertBanner(alert: latestAlert)
            }
        }
        .ignoresSafeArea()
        .alert("End Navigation?", isPresented: $showEndConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("End", role: .destructive) {
                Task {
                    await navigationVM.stopNavigation()
                    dismiss()
                }
            }
        } message: {
            Text("This will stop navigation for your car. Other drivers will be notified.")
        }
        // Pull-up caravan pane: fully minimized to just the tab row by
        // default; tapping a tab expands it, user can drag it back down.
        .sheet(isPresented: $showCaravanPane) {
            caravanPane
                .presentationDetents([.height(64), .medium], selection: $paneDetent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationBackground(AppTheme.backgroundDark)
                .interactiveDismissDisabled()
        }
    }

    // MARK: - Caravan Pane

    private var isPaneExpanded: Bool {
        paneDetent != .height(64)
    }

    private var caravanPane: some View {
        VStack(spacing: 0) {
            // Tab row — always visible, this is the minimized state.
            // Tapping a tab expands the pane to show its content.
            HStack(spacing: 0) {
                ForEach(CaravanPaneTab.allCases, id: \.self) { tab in
                    Button {
                        if paneTab == tab && isPaneExpanded {
                            // Tapping the active tab again collapses.
                            paneDetent = .height(64)
                        } else {
                            paneTab = tab
                            paneDetent = .medium
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 16))
                            Text(tab.rawValue)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(paneTab == tab && isPaneExpanded ? AppTheme.primary : AppTheme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }
            }
            .frame(height: 64)
            .background(AppTheme.backgroundCard.opacity(0.5))

            // Content only exists when expanded — keeps the minimized
            // state to just the tab row and avoids pushing overlays
            // (like the file preview sheet) out over the pane edge.
            if isPaneExpanded {
                SwiftUI.Group {
                    switch paneTab {
                    case .chat:
                        if let groupId = groupViewModel.groupService.activeGroup?.id {
                            ChatView(chatService: groupViewModel.chatService, groupId: groupId)
                        }
                    case .files:
                        if let groupId = groupViewModel.groupService.activeGroup?.id {
                            FilesView(fileService: groupViewModel.fileService, groupId: groupId)
                        }
                    case .members:
                        MemberStatusView(members: groupViewModel.groupService.members)
                    }
                }
            }
        }
    }

    // MARK: - Map

    private var mapView: some View {
        Map(position: $mapCameraPosition) {
            // Route polyline
            if !navigationVM.navigationService.routePolylineCoordinates.isEmpty {
                MapPolyline(coordinates: navigationVM.navigationService.routePolylineCoordinates)
                    .stroke(
                        LinearGradient(
                            colors: [AppTheme.primary, AppTheme.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 6
                    )
            }

            // Current user location
            UserAnnotation()

            // Other caravan members (skip never-located phantoms at 0,0 —
            // lastUpdated can't be the signal, @ServerTimestamp sets it at creation)
            ForEach(groupViewModel.groupService.members.filter { $0.latitude != 0 || $0.longitude != 0 }) { member in
                Annotation(member.displayName, coordinate: member.coordinate) {
                    VStack(spacing: 2) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: member.status.colorHex))
                                .frame(width: 36, height: 36)
                                .shadow(color: Color(hex: member.status.colorHex).opacity(0.6), radius: 6)

                            Image(systemName: member.isLeader ? "crown.fill" : "car.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        }

                        Text(member.displayName.components(separatedBy: " ").first ?? "")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.7)))
                    }
                }
            }

            // Destination pin
            if let activeGroup = groupViewModel.groupService.activeGroup,
               let lat = activeGroup.destinationLatitude,
               let lng = activeGroup.destinationLongitude {
                Annotation("Destination", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
                    Image(systemName: "flag.checkered.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(AppTheme.accent)
                        .shadow(color: AppTheme.accent.opacity(0.5), radius: 8)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
        .mapControls {
            MapCompass()
            MapUserLocationButton()
        }
        .colorScheme(.dark)
        // Follow the user while navigating — recenter on every location
        // tick. Gated on the full-route intro finishing (see onAppear).
        .onChange(of: navigationVM.locationService.currentLocation) { _, location in
            guard followUser, let location else { return }
            mapCameraPosition = .region(MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 1200,
                longitudinalMeters: 1200
            ))
        }
        .onAppear {
            // Intro: frame the entire route for 3s, then zoom into the
            // follow-the-user navigation view.
            fitRouteInCamera()
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation(.easeInOut(duration: 0.8)) {
                    followUser = true
                    if let location = navigationVM.locationService.currentLocation {
                        mapCameraPosition = .region(MKCoordinateRegion(
                            center: location.coordinate,
                            latitudinalMeters: 1200,
                            longitudinalMeters: 1200
                        ))
                    }
                }
            }
        }
    }

    /// Frames the whole route polyline (with 30% padding) for the intro.
    private func fitRouteInCamera() {
        let coords = navigationVM.navigationService.routePolylineCoordinates
        guard !coords.isEmpty else { return }

        var minLat = coords[0].latitude, maxLat = coords[0].latitude
        var minLng = coords[0].longitude, maxLng = coords[0].longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLng = min(minLng, c.longitude); maxLng = max(maxLng, c.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.3, 0.005),
            longitudeDelta: max((maxLng - minLng) * 1.3, 0.005)
        )
        mapCameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 24) {
            // ETA
            VStack(spacing: 2) {
                Text("ETA")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppTheme.textMuted)
                    .textCase(.uppercase)
                Text(navigationVM.navigationService.navigationState.formattedETA)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            Divider()
                .frame(height: 36)
                .overlay(Color.white.opacity(0.15))

            // Distance
            VStack(spacing: 2) {
                Text("Distance")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppTheme.textMuted)
                    .textCase(.uppercase)
                Text(navigationVM.navigationService.navigationState.formattedDistance)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            Divider()
                .frame(height: 36)
                .overlay(Color.white.opacity(0.15))

            // Caravan status
            VStack(spacing: 2) {
                Text("Caravan")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppTheme.textMuted)
                    .textCase(.uppercase)

                HStack(spacing: 4) {
                    let onRoute = groupViewModel.groupService.members.filter { $0.status == .onRoute }.count
                    let total = groupViewModel.groupService.members.count

                    Circle()
                        .fill(onRoute == total ? AppTheme.success : AppTheme.warning)
                        .frame(width: 8, height: 8)

                    Text("\(onRoute)/\(total)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(AppTheme.backgroundCard.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 20, y: -5)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    // MARK: - Alert Banner

    private func alertBanner(alert: CaravanAlert) -> some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: alert.status.iconSystemName)
                    .foregroundColor(Color(hex: alert.status.colorHex))

                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.memberName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text(alert.status.displayLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: alert.status.colorHex))
                }

                Spacer()

                Button {
                    navigationVM.caravanMonitor.clearAlerts()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppTheme.textMuted)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.backgroundCard.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(hex: alert.status.colorHex).opacity(0.4), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.top, 100)

            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.4), value: navigationVM.caravanMonitor.alerts.count)
    }
}
