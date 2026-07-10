import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var deepLinkRouter: DeepLinkRouter
    @StateObject private var groupViewModel = GroupViewModel()
    @State private var showCreateGroup = false
    @State private var showJoinGroup = false
    @State private var selectedGroup: Group?
    @State private var animateCards = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Header
                        headerSection

                        // Quick Actions
                        actionButtons

                        // Groups List
                        groupsList
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupView(groupViewModel: groupViewModel)
            }
            .sheet(isPresented: $showJoinGroup) {
                JoinGroupView(
                    groupViewModel: groupViewModel,
                    prefilledCode: deepLinkRouter.pendingInviteCode
                )
                .onDisappear { deepLinkRouter.pendingInviteCode = nil }
            }
            .onReceive(deepLinkRouter.$pendingInviteCode) { code in
                if code != nil { showJoinGroup = true }
            }
            .navigationDestination(item: $selectedGroup) { group in
                GroupDetailView(
                    group: group,
                    groupViewModel: groupViewModel
                )
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                    animateCards = true
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome back,")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)

                Text(authViewModel.currentUser?.displayName ?? "Driver")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            Spacer()

            // Profile / Sign Out
            Menu {
                Button("Sign Out", role: .destructive) {
                    authViewModel.signOut()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(AppTheme.backgroundElevated)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )

                    Text(authViewModel.currentUser?.initials ?? "?")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.primary)
                }
            }
        }
        .padding(.top, 60)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 14) {
            Button {
                showCreateGroup = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                    Text("Create Group")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(AppTheme.primaryGradient)
                )
            }

            Button {
                showJoinGroup = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 22))
                    Text("Join Group")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .foregroundColor(AppTheme.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.primary, lineWidth: 2)
                )
            }
        }
    }

    // MARK: - Groups List

    private var groupsList: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Caravans")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            if groupViewModel.groupService.userGroups.isEmpty {
                emptyState
            } else {
                ForEach(Array(groupViewModel.groupService.userGroups.enumerated()), id: \.element.id) { index, group in
                    GroupCardView(group: group) {
                        selectedGroup = group
                    }
                    .offset(y: animateCards ? 0 : 40)
                    .opacity(animateCards ? 1 : 0)
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.8)
                            .delay(Double(index) * 0.1),
                        value: animateCards
                    )
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "car.2.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.primaryGradient)

            Text("No caravans yet")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.white)

            Text("Create a group or join one with an invite code to get started.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .glassCard()
    }
}

// MARK: - Group Card

struct GroupCardView: View {
    let group: Group
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.primary.opacity(0.3), AppTheme.accent.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)

                    Image(systemName: "car.side.fill")
                        .font(.system(size: 24))
                        .foregroundColor(AppTheme.primary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)

                    HStack(spacing: 6) {
                        Image(systemName: "ticket.fill")
                            .font(.system(size: 10))
                        Text(group.inviteCode)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(AppTheme.textSecondary)

                    if group.isNavigating {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(AppTheme.success)
                                .frame(width: 6, height: 6)
                            Text("Navigating")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AppTheme.success)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textMuted)
            }
            .padding(16)
            .glassCard()
        }
        .buttonStyle(.plain)
    }
}
