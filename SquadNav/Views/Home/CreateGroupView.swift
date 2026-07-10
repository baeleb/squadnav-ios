import SwiftUI

struct CreateGroupView: View {
    @ObservedObject var groupViewModel: GroupViewModel
    @Environment(\.dismiss) var dismiss

    @State private var groupName = ""
    @State private var qrCodeData: Data?

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Header
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(AppTheme.textMuted)
                    }
                    Spacer()
                    Text("New Caravan")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Color.clear.frame(width: 28)
                }
                .padding(.top, 20)

                if groupViewModel.showCreateSuccess, let group = groupViewModel.createdGroup {
                    // Success State
                    successView(group: group)
                } else {
                    // Create Form
                    createForm
                }

                Spacer()
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Create Form

    private var createForm: some View {
        VStack(spacing: 24) {
            // Car illustration
            ZStack {
                Circle()
                    .fill(AppTheme.primary.opacity(0.1))
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)

                Image(systemName: "flag.checkered.2.crossed")
                    .font(.system(size: 56))
                    .foregroundStyle(AppTheme.primaryGradient)
            }

            Text("Give your caravan a name")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)

            // Group name input
            VStack(alignment: .leading, spacing: 8) {
                Text("Caravan Name")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                    .textCase(.uppercase)

                TextField("", text: $groupName, prompt: Text("e.g. Road Trip 2025")
                    .foregroundColor(AppTheme.textMuted))
                    .font(.system(size: 17, design: .rounded))
                    .foregroundColor(.white)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(AppTheme.backgroundInput)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
            }

            if let error = groupViewModel.error {
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.danger)
            }

            Button {
                Task {
                    await groupViewModel.createGroup(name: groupName)
                }
            } label: {
                HStack {
                    if groupViewModel.isCreating {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "plus.circle.fill")
                        Text("Create Caravan")
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty || groupViewModel.isCreating)
            .opacity(groupName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)
        }
        .padding(24)
        .glassCard()
    }

    // MARK: - Success View

    private func successView(group: Group) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(AppTheme.success)

            Text("Caravan Created!")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            // Invite Code
            VStack(spacing: 8) {
                Text("Share this code with your drivers")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)

                Text(group.inviteCode)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.primary)
                    .tracking(8)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(AppTheme.primary.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(AppTheme.primary.opacity(0.3), lineWidth: 1)
                            )
                    )
            }

            // QR Code
            if let qrData = groupViewModel.generateQRCode(for: group) {
                VStack(spacing: 8) {
                    Text("or scan QR code")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)

                    if let uiImage = UIImage(data: qrData) {
                        Image(uiImage: uiImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.white)
                            )
                    }
                }
            }

            // Share button
            ShareLink(
                item: "Join my SquadNav caravan! Code: \(group.inviteCode)",
                subject: Text("Join my caravan"),
                message: Text("Use invite code \(group.inviteCode) to join my caravan on SquadNav!")
            ) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share Invite")
                }
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(AppTheme.primaryGradient)
                )
            }

            Button("Done") {
                groupViewModel.showCreateSuccess = false
                dismiss()
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(AppTheme.textSecondary)
        }
        .padding(24)
        .glassCard()
    }
}
