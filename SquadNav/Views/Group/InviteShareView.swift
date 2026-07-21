import SwiftUI

/// Shared invite display: alphanumeric code + QR + share button.
/// Used by CreateGroupView's success state and GroupDetailView's
/// invite-code tap.
struct InviteShareView: View {
    let group: Group
    @ObservedObject var groupViewModel: GroupViewModel

    var body: some View {
        VStack(spacing: 24) {
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
            if let qrData = groupViewModel.generateQRCode(for: group),
               let uiImage = UIImage(data: qrData) {
                VStack(spacing: 8) {
                    Text("or scan QR code")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)

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
        }
        // No glassCard/padding here — callers provide the framing; wrapping
        // in a card inside a sheet produced a nested-box look.
    }
}
