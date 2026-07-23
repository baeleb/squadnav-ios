import SwiftUI

struct GroupDetailView: View {
    let group: Group
    @ObservedObject var groupViewModel: GroupViewModel
    @StateObject private var navigationVM: NavigationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: GroupTab = .map
    @State private var showSuccessorPicker = false
    @State private var showInviteSheet = false
    @State private var showDeleteConfirmation = false

    enum GroupTab: String, CaseIterable {
        case map = "Map"
        case chat = "Chat"
        case files = "Files"
        case members = "Members"

        var icon: String {
            switch self {
            case .map: return "map.fill"
            case .chat: return "bubble.left.and.bubble.right.fill"
            case .files: return "folder.fill"
            case .members: return "person.3.fill"
            }
        }
    }

    init(group: Group, groupViewModel: GroupViewModel) {
        self.group = group
        self.groupViewModel = groupViewModel
        self._navigationVM = StateObject(wrappedValue: NavigationViewModel(
            groupService: groupViewModel.groupService,
            chatService: groupViewModel.chatService
        ))
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundDark
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Group info header
                groupHeader

                // Tab bar
                tabBar

                // Tab content
                tabContent
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(group.name)
                    .font(AppFont.nunito(17, .bold))
                    .foregroundColor(AppTheme.textPrimary)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        // A leader leaving a non-empty group must name a
                        // successor first, or the group goes leaderless.
                        if groupViewModel.isLeader && !otherMembers.isEmpty {
                            showSuccessorPicker = true
                        } else {
                            Task {
                                await groupViewModel.leaveGroup(group)
                                if groupViewModel.error == nil {
                                    dismiss()
                                }
                            }
                        }
                    } label: {
                        Label("Leave Group", systemImage: "rectangle.portrait.and.arrow.right")
                    }

                    if groupViewModel.isLeader {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete Group", systemImage: "trash.fill")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
        }
        .confirmationDialog(
            "Choose the next leader",
            isPresented: $showSuccessorPicker,
            titleVisibility: .visible
        ) {
            ForEach(otherMembers) { member in
                Button(member.displayName) {
                    Task {
                        await groupViewModel.transferLeadershipAndLeave(group, to: member)
                        if groupViewModel.error == nil {
                            dismiss()
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You're the leader. Pick who takes over before you leave.")
        }
        .alert("Delete \"\(group.name)\"?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete for Everyone", role: .destructive) {
                Task {
                    await groupViewModel.deleteGroup(group)
                    if groupViewModel.error == nil {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("This permanently deletes the group, its chat, files, and member data for everyone. This cannot be undone.")
        }
        .toolbarBackground(AppTheme.backgroundDark, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showInviteSheet) {
            ZStack {
                AppTheme.backgroundDark.ignoresSafeArea()
                VStack(spacing: 20) {
                    Spacer()
                    InviteShareView(group: group, groupViewModel: groupViewModel)
                    Spacer()
                }
                .padding(.horizontal, 20)
            }
            .presentationDetents([.height(460)])
            .presentationDragIndicator(.hidden)
        }
        .fullScreenCover(isPresented: $navigationVM.showNavigation) {
            NavigationMapView(navigationVM: navigationVM, groupViewModel: groupViewModel)
        }
        .onAppear {
            groupViewModel.selectGroup(group)
            navigationVM.requestLocationPermission()
            navigationVM.locationService.startTracking()
        }
        .onDisappear {
            navigationVM.locationService.stopTracking()
            groupViewModel.deselectGroup()
        }
        .onChange(of: groupViewModel.groupService.activeGroup?.isNavigating) { _, isNavigating in
            // Keep everyone in sync, including a new leader who took over
            // mid-navigation: they need to join just like any other member.
            if isNavigating == true {
                guard !navigationVM.showNavigation else { return }
                Task { await navigationVM.joinNavigation() }
            } else if navigationVM.showNavigation {
                navigationVM.endNavigationLocally()
            }
        }
    }

    /// Members other than the current user (successor candidates).
    private var otherMembers: [MemberLocation] {
        groupViewModel.groupService.members.filter { $0.id != groupViewModel.currentUserId }
    }

    // MARK: - Group Header

    private var groupHeader: some View {
        HStack(spacing: 16) {
            // Invite code (tap → full invite view: code + QR + share)
            Button {
                showInviteSheet = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Invite Code")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.textMuted)
                        .textCase(.uppercase)

                    HStack(spacing: 6) {
                        Text(group.inviteCode)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(AppTheme.primary)
                        Image(systemName: "qrcode")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textMuted)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.primary.opacity(0.1))
                )
            }
            .buttonStyle(.plain)

            Spacer()

            // Members count
            HStack(spacing: 6) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 12))
                Text("\(groupViewModel.groupService.members.count)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundColor(AppTheme.textSecondary)

            // Navigation status
            if let activeGroup = groupViewModel.groupService.activeGroup,
               activeGroup.isNavigating {
                HStack(spacing: 4) {
                    Circle()
                        .fill(AppTheme.success)
                        .frame(width: 8, height: 8)
                    Text("Navigating")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.success)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(AppTheme.success.opacity(0.15))
                )
            } else if groupViewModel.isLeader && groupViewModel.groupService.activeGroup?.hasDestination == true {
                Button {
                    Task { await navigationVM.startNavigation() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10))
                        Text("Start")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(AppTheme.primary))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(GroupTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18))

                        Text(tab.rawValue)
                            .font(AppFont.nunito(11, .bold))
                    }
                    .foregroundColor(selectedTab == tab ? AppTheme.primary : AppTheme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        selectedTab == tab ?
                            AnyView(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(AppTheme.primary.opacity(0.12))
                            )
                        : AnyView(Color.clear)
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(AppTheme.backgroundCard)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .map:
            GroupMapPreview(navigationVM: navigationVM, groupViewModel: groupViewModel)
        case .chat:
            if let groupId = group.id {
                ChatView(
                    chatService: groupViewModel.chatService,
                    groupId: groupId
                )
            }
        case .files:
            if let groupId = group.id {
                FilesView(
                    fileService: groupViewModel.fileService,
                    groupId: groupId
                )
            }
        case .members:
            MemberStatusView(members: groupViewModel.groupService.members)
        }
    }
}

// MARK: - Group Map Preview

struct GroupMapPreview: View {
    @ObservedObject var navigationVM: NavigationViewModel
    @ObservedObject var groupViewModel: GroupViewModel
    @State private var searchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var cameraPosition: MapCameraPosition = .automatic
    // Last-known heading; course/heading are nil in simulator when idle.
    @State private var displayedHeading: Double = 0

    // Members who have never uploaded a location sit at the default (0,0) —
    // Gulf of Guinea — and drag the camera into the ocean. (lastUpdated can't
    // be used as the signal: @ServerTimestamp writes a value at creation.)
    // Self is excluded — rendered live above with the directional triangle.
    private var locatedMembers: [MemberLocation] {
        groupViewModel.groupService.members.filter {
            ($0.latitude != 0 || $0.longitude != 0) && $0.id != groupViewModel.currentUserId
        }
    }

    /// Current user's first name, from their member doc (falls back to "You").
    private var currentUserFirstName: String {
        groupViewModel.groupService.members
            .first { $0.id == groupViewModel.currentUserId }?
            .displayName.components(separatedBy: " ").first ?? "You"
    }

    /// Degrees clockwise from north; course when moving, compass otherwise.
    private var currentUserHeadingDegrees: Double {
        displayedHeading
    }

    /// Navigation-style triangle pointing in the travel direction with the
    /// driver's first name underneath (matches NavigationMapView's style).
    private func directionalMarker(name: String, color: Color) -> some View {
        ZStack(alignment: .bottom) {
            Image(systemName: "location.north.fill")
                .font(.system(size: 24))
                .foregroundColor(color)
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

    // Route to draw: prefer the local engine's coordinates (just
    // calculated); fall back to decoding the polyline stored on the group
    // doc, which is the only source after view recreation and the only
    // source on devices that didn't set the destination.
    private var routeCoordinates: [CLLocationCoordinate2D] {
        let local = navigationVM.navigationService.routePolylineCoordinates
        if !local.isEmpty { return local }
        guard let polyline = groupViewModel.groupService.activeGroup?.routePolyline,
              !polyline.isEmpty else { return [] }
        return RouteEncoder.decode(polyline: polyline)
    }

    var body: some View {
        ZStack {
            // Map placeholder
            Map(position: $cameraPosition) {
                // Route polyline (from local engine or the shared group doc)
                if !routeCoordinates.isEmpty {
                    MapPolyline(coordinates: routeCoordinates)
                        .stroke(
                            LinearGradient(
                                colors: [AppTheme.primary, AppTheme.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 5
                        )
                }

                // Current user — UserAnnotation suppresses the default
                // blue dot that Annotation("", coordinate:) doesn't.
                UserAnnotation { userLocation in
                    directionalMarker(
                        name: currentUserFirstName,
                        color: AppTheme.primary
                    )
                    .rotationEffect(Angle(degrees: userLocation.heading?.trueHeading ?? displayedHeading))
                }

                // Show member annotations
                ForEach(locatedMembers) { member in
                    Annotation(member.displayName, coordinate: member.coordinate) {
                        VStack(spacing: 2) {
                            Image(systemName: member.isLeader ? "car.top.radiowaves.front.fill" : "car.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Circle().fill(Color(hex: member.status.colorHex)))
                                .shadow(color: Color(hex: member.status.colorHex).opacity(0.5), radius: 8)

                            Text(member.displayName.components(separatedBy: " ").first ?? "")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
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
                            .font(.system(size: 30))
                            .foregroundColor(AppTheme.accent)
                            .shadow(color: AppTheme.accent.opacity(0.5), radius: 8)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
            .mapControls {
                MapCompass()
            }
            // Fly the camera to the destination when it gets set (search
            // pick on this device, or set from another device) and on
            // appear if one already exists.
            .onChange(of: groupViewModel.groupService.activeGroup?.destinationLatitude) { _, _ in
                flyToDestination()
            }
            .onChange(of: groupViewModel.groupService.activeGroup?.destinationLongitude) { _, _ in
                flyToDestination()
            }
            .onAppear { flyToDestination() }
            .onChange(of: navigationVM.locationService.currentLocation) { _, location in
                if let course = location?.course, course >= 0 {
                    displayedHeading = course
                }
            }
            .onChange(of: navigationVM.locationService.heading) { _, heading in
                if let h = heading?.trueHeading, displayedHeading == 0 {
                    displayedHeading = h
                }
            }

            // Overlay: leader destination search (replaces the old
            // ellipsis-menu DestinationSearchView sheet)
            VStack(spacing: 0) {
                if groupViewModel.isLeader {
                    destinationSearchBar

                    if !searchText.isEmpty && !navigationVM.searchResults.isEmpty {
                        destinationSearchResults
                    }
                }

                Spacer()
            }

            // Overlay: destination info
            VStack {
                Spacer()

                if let activeGroup = groupViewModel.groupService.activeGroup,
                   let destName = activeGroup.destinationName {
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(AppTheme.accent)
                        Text(destName)
                            .font(AppFont.nunito(14, .bold))
                            .foregroundColor(AppTheme.textPrimary)
                        Spacer()

                        // Leader can clear the destination for everyone
                        if groupViewModel.isLeader {
                            Button {
                                Task { await navigationVM.clearDestination() }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(AppTheme.textMuted)
                            }
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(AppTheme.backgroundCard)
                            .shadow(color: AppTheme.shadowColor.opacity(0.1), radius: 10, x: 0, y: 4)
                    )
                    .padding()
                }
            }
        }
    }

    /// Moves the camera to the group's destination (5 km frame), if any;
    /// a cleared destination returns the camera to the user.
    private func flyToDestination() {
        guard let activeGroup = groupViewModel.groupService.activeGroup,
              let lat = activeGroup.destinationLatitude,
              let lng = activeGroup.destinationLongitude else {
            cameraPosition = .userLocation(fallback: .automatic)
            return
        }
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                latitudinalMeters: 5000,
                longitudinalMeters: 5000
            ))
        }
    }

    // MARK: - Destination Search (leader only)

    private var destinationSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppTheme.textMuted)

            TextField("Search destination...", text: $searchText)
                .font(AppFont.nunito(15))
                .foregroundColor(AppTheme.textPrimary)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    navigationVM.searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppTheme.textMuted)
                }
            }

            if navigationVM.isSearching {
                ProgressView()
                    .tint(AppTheme.primary)
                    .scaleEffect(0.8)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.backgroundCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
                .shadow(color: AppTheme.shadowColor.opacity(0.1), radius: 10, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .onChange(of: searchText) { _, newValue in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if !Task.isCancelled {
                    await navigationVM.searchDestination(query: newValue)
                }
            }
        }
    }

    private var destinationSearchResults: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(navigationVM.searchResults.prefix(5), id: \.self) { mapItem in
                    Button {
                        let item = mapItem
                        searchText = ""
                        navigationVM.searchResults = []
                        Task { await navigationVM.setDestinationAndCalculateRoute(item) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(AppTheme.accent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(mapItem.name ?? "Unknown")
                                    .font(AppFont.nunito(14, .bold))
                                    .foregroundColor(AppTheme.textPrimary)
                                if let address = mapItem.placemark.formattedAddress {
                                    Text(address)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(AppTheme.textSecondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()
                        }
                        .padding(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
        }
        .frame(maxHeight: 260)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.backgroundCard)
                .shadow(color: AppTheme.shadowColor.opacity(0.1), radius: 10, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }
}

import MapKit
