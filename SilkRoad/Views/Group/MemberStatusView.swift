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
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: member.isLeader
                                ? [AppTheme.accent, AppTheme.primary]
                                : [AppTheme.backgroundElevated, AppTheme.backgroundCard],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)

                if member.isLeader {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                } else {
                    Text(memberInitials(member.displayName))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(member.displayName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)

                    if member.isLeader {
                        Text("LEADER")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(AppTheme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(AppTheme.accent.opacity(0.2))
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
                    .foregroundColor(Color(hex: member.status.colorHex))

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

            // Status indicator dot
            Circle()
                .fill(Color(hex: member.status.colorHex))
                .frame(width: 12, height: 12)
                .shadow(color: Color(hex: member.status.colorHex).opacity(0.5), radius: 4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.backgroundCard.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(hex: member.status.colorHex).opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func memberInitials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.prefix(1) ?? ""
        let last = parts.count > 1 ? parts.last!.prefix(1) : ""
        return "\(first)\(last)".uppercased()
    }
}
