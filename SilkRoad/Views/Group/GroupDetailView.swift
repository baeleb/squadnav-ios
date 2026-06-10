import SwiftUI

struct GroupDetailView: View {
    let group: Group
    @ObservedObject var groupViewModel: GroupViewModel
    @StateObject private var navigationVM: NavigationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: GroupTab = .map
    @State private var showDestinationSearch = false

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
            AppTheme.backgroundGradient
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
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if groupViewModel.isLeader {
                        Button {
                            showDestinationSearch = true
                        } label: {
                            Label("Set Destination", systemImage: "mappin.and.ellipse")
                        }
                    }

                    Button(role: .destructive) {
                        Task {
                            await groupViewModel.leaveGroup(group)
                            if groupViewModel.error == nil {
                                dismiss()
                            }
                        }
                    } label: {
                        Label("Leave Group", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
        }
        .toolbarBackground(AppTheme.backgroundDark, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showDestinationSearch) {
            DestinationSearchView(navigationVM: navigationVM)
        }
        .fullScreenCover(isPresented: $navigationVM.showNavigation) {
            NavigationMapView(navigationVM: navigationVM, groupViewModel: groupViewModel)
        }
        .onAppear {
            groupViewModel.selectGroup(group)
            navigationVM.requestLocationPermission()
        }
        .onDisappear {
            groupViewModel.deselectGroup()
        }
        .onChange(of: groupViewModel.groupService.activeGroup?.isNavigating) { _, isNavigating in
            // Keep non-leader members in sync with the leader's navigation state.
            guard !groupViewModel.isLeader else { return }
            if isNavigating == true {
                Task { await navigationVM.joinNavigation() }
            } else if navigationVM.showNavigation {
                navigationVM.endNavigationLocally()
            }
        }
    }

    // MARK: - Group Header

    private var groupHeader: some View {
        HStack(spacing: 16) {
            // Invite code
            VStack(alignment: .leading, spacing: 2) {
                Text("Invite Code")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppTheme.textMuted)
                    .textCase(.uppercase)

                Text(group.inviteCode)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.primary.opacity(0.1))
            )

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
                    .background(Capsule().fill(AppTheme.primaryGradient))
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
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(selectedTab == tab ? AppTheme.primary : AppTheme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        selectedTab == tab ?
                            AnyView(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(AppTheme.primary.opacity(0.1))
                            )
                        : AnyView(Color.clear)
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(AppTheme.backgroundCard.opacity(0.5))
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

    var body: some View {
        ZStack {
            // Map placeholder
            Map {
                // Show member annotations
                ForEach(groupViewModel.groupService.members) { member in
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
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
            .colorScheme(.dark)

            // Overlay: destination info
            VStack {
                Spacer()

                if let activeGroup = groupViewModel.groupService.activeGroup,
                   let destName = activeGroup.destinationName {
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(AppTheme.accent)
                        Text(destName)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(AppTheme.backgroundCard.opacity(0.9))
                    )
                    .padding()
                }
            }
        }
    }
}

import MapKit
