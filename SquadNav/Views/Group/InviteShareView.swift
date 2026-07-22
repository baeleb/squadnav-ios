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
                    .font(AppFont.nunito(14, .semibold))
                    .foregroundColor(AppTheme.textSecondary)

                Text(group.inviteCode)
                    .font(AppFont.fredoka(32, .semibold))
                    .foregroundColor(AppTheme.primary)
                    .tracking(6)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(AppTheme.backgroundCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .strokeBorder(AppTheme.primary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                            )
                    )
            }

            // QR Code
            if let qrData = groupViewModel.generateQRCode(for: group),
               let uiImage = UIImage(data: qrData) {
                VStack(spacing: 8) {
                    Text("or scan QR code")
                        .font(AppFont.nunito(14, .semibold))
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
                .font(AppFont.nunito(16, .extraBold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(AppTheme.primary)
                )
            }
        }
        // No glassCard/padding here — callers provide the framing; wrapping
        // in a card inside a sheet produced a nested-box look.
    }
}
