import SwiftUI

struct MemberStatusView: View {
    let members: [MemberLocation]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(members) { member in
                    memberCard(member: member)
                }
            }
            .padding(16)
        }
        .background(AppTheme.backgroundDark)
    }

    private func memberCard(member: MemberLocation) -> some View {
        let identityColor = AppTheme.memberColor(for: member.id ?? member.displayName)
        let statusColor = Color(hex: member.status.colorHex)

        return HStack(spacing: 14) {
            // Avatar — flat, unique color per member identity
            ZStack {
                Circle()
                    .fill(identityColor)
                    .frame(width: 48, height: 48)

                Text(memberInitials(member.displayName))
                    .font(AppFont.nunito(16, .extraBold))
                    .foregroundColor(.white)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(member.displayName)
                        .font(AppFont.nunito(16, .bold))
                        .foregroundColor(AppTheme.textPrimary)

                    if member.isLeader {
                        Text("LEADER")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(AppTheme.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(AppTheme.primary.opacity(0.15))
                            )
                    }
                }

                HStack(spacing: 12) {
                    // Status badge
                    HStack(spacing: 4) {
                        Image(systemName: member.status.iconSystemName)
                            .font(.system(size: 10))
                        Text(member.status.displayLabel)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(statusColor)

                    // Speed
                    if member.speed > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "speedometer")
                                .font(.system(size: 10))
                            Text(member.formattedSpeed)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(AppTheme.textMuted)
                    }

                    // Last updated (nil while a server timestamp is pending,
                    // which means the update happened just now)
                    Text((member.lastUpdated ?? Date()).timeAgoDisplay)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textMuted)
                }
            }

            Spacer()

            // Status pill
            Text(member.status.displayLabel)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(statusColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(statusColor.opacity(0.15)))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.backgroundCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
                .shadow(color: AppTheme.shadowColor.opacity(0.06), radius: 8, x: 0, y: 2)
        )
    }

    private func memberInitials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.prefix(1) ?? ""
        let last = parts.count > 1 ? parts.last!.prefix(1) : ""
        return "\(first)\(last)".uppercased()
    }
}
