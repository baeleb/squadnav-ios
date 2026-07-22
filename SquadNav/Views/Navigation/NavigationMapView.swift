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
    // Width of the pane, measured via GeometryReader; drives the
    // compact-vs-stacked bar decision.
    @State private var paneWidth: CGFloat = 390
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
                .presentationDetents([.height(64), .height(104), .medium], selection: $paneDetent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationBackground(AppTheme.backgroundDark)
                .interactiveDismissDisabled()
        }
    }

    // MARK: - Caravan Pane

    private var isPaneExpanded: Bool {
        paneDetent == .medium
    }

    private var caravanPane: some View {
        VStack(spacing: 0) {
            // Merged status + tab bar — the minimized state. Compact
            // single row when values fit the measured width; stacked
            // status-over-tabs (full-size values) when they'd overflow.
            GeometryReader { geo in
                SwiftUI.Group {
                    if needsStackedBar(width: geo.size.width) {
                        stackedBar
                    } else {
                        compactBar
                    }
                }
                .onAppear { paneWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, w in paneWidth = w }
            }
            .frame(height: minBarHeight)
            .background(AppTheme.backgroundCard.opacity(0.5))
            // Keep the minimized detent matched to the bar's current
            // layout (compact 64 / stacked 104): re-pin on layout change
            // and don't let a drag-down rest at the wrong height.
            .onChange(of: minBarHeight) { _, h in
                if !isPaneExpanded { paneDetent = .height(h) }
            }
            .onChange(of: paneDetent) { _, d in
                if !isPaneExpanded && d != .height(minBarHeight) {
                    paneDetent = .height(minBarHeight)
                }
            }

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

    // MARK: - Directional Markers

    /// Current user's first name, from their member doc (falls back to "You").
    private var currentUserFirstName: String {
        groupViewModel.groupService.members
            .first { $0.id == groupViewModel.currentUserId }?
            .displayName.components(separatedBy: " ").first ?? "You"
    }

    /// Degrees clockwise from north. Course (direction of travel) is the
    /// right signal while driving; compass heading is the fallback when
    /// course is invalid (-1), e.g. standing still.
    private var currentUserHeadingDegrees: Double {
        if let course = navigationVM.locationService.currentLocation?.course, course >= 0 {
            return course
        }
        return navigationVM.locationService.heading?.trueHeading ?? 0
    }

    /// Navigation-style triangle pointing in the travel direction with the
    /// driver's first name underneath. "location.north.fill" points up at
    /// 0°, and rotation is clockwise-positive — matching compass degrees.
    private func directionalMarker(name: String, headingDegrees: Double, color: Color) -> some View {
        ZStack(alignment: .bottom) {
            Image(systemName: "location.north.fill")
                .font(.system(size: 24))
                .foregroundColor(color)
                .rotationEffect(.degrees(headingDegrees))
                .shadow(color: color.opacity(0.6), radius: 5)

            Text(name)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(0.7)))
                .offset(y: 18)
        }
    }

    /// Compact initials badge for other caravan members — no
    /// directionality, no name label underneath.
    private func initialsMarker(name: String, color: Color) -> some View {
        let initials = name.components(separatedBy: " ")
            .compactMap { $0.first }
            .prefix(2)
            .map(String.init)
            .joined()
            .uppercased()

        return ZStack {
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
                .shadow(color: color.opacity(0.5), radius: 4)
            Text(initials.isEmpty ? "?" : initials)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }

    // MARK: - Adaptive Bar Layout

    /// Minimized bar height: short when compact, tall when stacked.
    private var minBarHeight: CGFloat {
        needsStackedBar(width: paneWidth) ? 104 : 64
    }

    /// Estimates whether the compact single-row bar overflows `width`:
    /// sums estimated text widths of the status values + tab icons.
    private func needsStackedBar(width: CGFloat) -> Bool {
        let state = navigationVM.navigationService.navigationState
        let onRoute = groupViewModel.groupService.members.filter { $0.status == .onRoute }.count
        let total = groupViewModel.groupService.members.count
        let values = [state.formattedETA, state.formattedDistance, "\(onRoute)/\(total)"]

        let pillFont = UIFont.systemFont(ofSize: 13, weight: .bold)
        let pillsWidth: CGFloat = values
            .map { max(52, ($0 as NSString).size(withAttributes: [.font: pillFont]).width + 20) }
            .reduce(0, +)
        let tabsWidth: CGFloat = 3 * 48 + 12 // three icons + divider

        return pillsWidth + tabsWidth > width
    }

    /// Compact: one row, abbreviated labels.
    private var compactBar: some View {
        HStack(spacing: 0) {
            statusPill(label: "ETA", value: navigationVM.navigationService.navigationState.formattedETA)
            statusPill(label: "DIST", value: navigationVM.navigationService.navigationState.formattedDistance)
            caravanStatusPill

            Divider()
                .frame(height: 28)
                .overlay(Color.white.opacity(0.15))

            paneTabButtons(showLabels: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Stacked: status on top, tabs below, full-size values.
    private var stackedBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                statusPillLarge(label: "ETA", value: navigationVM.navigationService.navigationState.formattedETA)
                statusPillLarge(label: "DISTANCE", value: navigationVM.navigationService.navigationState.formattedDistance)
                caravanStatusPillLarge
            }
            .frame(height: 50)

            Divider()
                .overlay(Color.white.opacity(0.08))

            HStack(spacing: 0) {
                paneTabButtons(showLabels: true)
            }
            .frame(height: 54)
        }
    }

    // MARK: - Pane Tab Buttons

    @ViewBuilder
    private func paneTabButtons(showLabels: Bool) -> some View {
        ForEach(CaravanPaneTab.allCases, id: \.self) { tab in
            Button {
                if paneTab == tab && isPaneExpanded {
                    // Tapping the active tab again collapses.
                    paneDetent = .height(minBarHeight)
                } else {
                    paneTab = tab
                    paneDetent = .medium
                }
            } label: {
                if showLabels {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16))
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(paneTab == tab && isPaneExpanded ? AppTheme.primary : AppTheme.textMuted)
                    .frame(maxWidth: .infinity)
                } else {
                    Image(systemName: tab.icon)
                        .font(.system(size: 18))
                        .foregroundColor(paneTab == tab && isPaneExpanded ? AppTheme.primary : AppTheme.textMuted)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Pane Status Pills

    private func statusPill(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(AppTheme.textMuted)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var caravanStatusPill: some View {
        let onRoute = groupViewModel.groupService.members.filter { $0.status == .onRoute }.count
        let total = groupViewModel.groupService.members.count

        return VStack(spacing: 2) {
            Text("CRVN")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(AppTheme.textMuted)
            HStack(spacing: 3) {
                Circle()
                    .fill(onRoute == total ? AppTheme.success : AppTheme.warning)
                    .frame(width: 6, height: 6)
                Text("\(onRoute)/\(total)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // Large variants for the stacked (overflow) layout — full labels and
    // values, no shrinking, since there's a whole row to work with.

    private func statusPillLarge(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(AppTheme.textMuted)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var caravanStatusPillLarge: some View {
        let onRoute = groupViewModel.groupService.members.filter { $0.status == .onRoute }.count
        let total = groupViewModel.groupService.members.count

        return VStack(spacing: 3) {
            Text("CARAVAN")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(AppTheme.textMuted)
            HStack(spacing: 4) {
                Circle()
                    .fill(onRoute == total ? AppTheme.success : AppTheme.warning)
                    .frame(width: 8, height: 8)
                Text("\(onRoute)/\(total)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity)
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

            // Current user — live directional triangle (replaces the
            // native UserAnnotation dot + full-name label). Driven by
            // course (direction of travel), falling back to compass.
            // Title is "": a non-empty title renders a duplicate
            // plain-text label alongside our capsule.
            if let location = navigationVM.locationService.currentLocation {
                Annotation("", coordinate: location.coordinate) {
                    directionalMarker(
                        name: currentUserFirstName,
                        headingDegrees: currentUserHeadingDegrees,
                        color: Color(hex: "34C759")
                    )
                }
            }

            // Other caravan members — compact initials circle, no
            // directionality, no name label (skip never-located phantoms
            // at 0,0 and self, rendered live above)
            ForEach(groupViewModel.groupService.members.filter {
                ($0.latitude != 0 || $0.longitude != 0) && $0.id != groupViewModel.currentUserId
            }) { member in
                Annotation("", coordinate: member.coordinate) {
                    initialsMarker(
                        name: member.displayName,
                        color: Color(hex: member.status.colorHex)
                    )
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
