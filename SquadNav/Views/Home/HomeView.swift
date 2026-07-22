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
                AppTheme.backgroundDark
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
                    .font(AppFont.nunito(15, .semibold))
                    .foregroundColor(AppTheme.textSecondary)

                Text(authViewModel.currentUser?.displayName ?? "Driver")
                    .font(AppFont.fredoka(26, .semibold))
                    .foregroundColor(AppTheme.textPrimary)
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
                        .fill(AppTheme.primary)
                        .frame(width: 48, height: 48)

                    Text(authViewModel.currentUser?.initials ?? "?")
                        .font(AppFont.nunito(18, .extraBold))
                        .foregroundColor(.white)
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
                        .font(.system(size: 20))
                    Text("Create Squad")
                        .font(AppFont.nunito(15, .extraBold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(AppTheme.primary)
                )
            }

            Button {
                showJoinGroup = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 20))
                    Text("Join Squad")
                        .font(AppFont.nunito(15, .extraBold))
                }
                .foregroundColor(AppTheme.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(AppTheme.primary, lineWidth: 1.5)
                )
            }
        }
    }

    // MARK: - Groups List

    private var groupsList: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Caravans")
                .font(AppFont.fredoka(20, .semibold))
                .foregroundColor(AppTheme.textPrimary)

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
                .font(.system(size: 44))
                .foregroundColor(AppTheme.primary)

            Text("No caravans yet")
                .font(AppFont.nunito(18, .bold))
                .foregroundColor(AppTheme.textPrimary)

            Text("Create a squad or join one with an invite code to get started.")
                .font(AppFont.nunito(14, .semibold))
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
                        .fill(AppTheme.backgroundElevated)
                        .frame(width: 56, height: 56)

                    Image(systemName: "car.side.fill")
                        .font(.system(size: 22))
                        .foregroundColor(AppTheme.primary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(AppFont.nunito(17, .bold))
                        .foregroundColor(AppTheme.textPrimary)

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
