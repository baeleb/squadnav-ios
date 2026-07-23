import SwiftUI

struct MessageBubbleView: View {
    let message: Message
    let isCurrentUser: Bool

    var body: some View {
        SwiftUI.Group {
            switch message.type {
            case .text:
                textBubble
            case .system:
                systemMessage
            case .alert:
                alertMessage
            }
        }
    }

    // MARK: - Text Bubble

    private var textBubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isCurrentUser { Spacer(minLength: 60) }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                if !isCurrentUser {
                    Text(message.senderName)
                        .font(AppFont.nunito(11, .bold))
                        .foregroundColor(AppTheme.memberColor(for: message.senderId))
                }

                Text(message.text)
                    .font(AppFont.nunito(15))
                    .foregroundColor(isCurrentUser ? .white : AppTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.top, 9)
                    .padding(.bottom, 11)
                    .background(
                        BubbleShape(isCurrentUser: isCurrentUser)
                            .fill(isCurrentUser ? AnyShapeStyle(AppTheme.primary) : AnyShapeStyle(AppTheme.backgroundCard))
                    )

                Text(message.timestamp.chatTimestamp)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.textMuted)
            }

            if !isCurrentUser { Spacer(minLength: 60) }
        }
    }

    // MARK: - System Message

    private var systemMessage: some View {
        HStack {
            Spacer()
            Text(message.text)
                .font(AppFont.nunito(12, .semibold))
                .foregroundColor(AppTheme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(AppTheme.backgroundCard)
                )
            Spacer()
        }
    }

    // MARK: - Alert Message

    private var alertMessage: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.warning.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.warning)
            }

            Text(message.text)
                .font(AppFont.nunito(13, .bold))
                .foregroundColor(AppTheme.textPrimary)

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.backgroundCard)
                .shadow(color: AppTheme.shadowColor.opacity(0.06), radius: 8, x: 0, y: 2)
        )
    }
}

// MARK: - Bubble Shape

struct BubbleShape: Shape {
    let isCurrentUser: Bool

    func path(in rect: CGRect) -> Path {
        let cornerRadius: CGFloat = 18
        let tailSize: CGFloat = 6

        var path = Path()

        if isCurrentUser {
            path.addRoundedRect(in: CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width - tailSize,
                height: rect.height
            ), cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        } else {
            path.addRoundedRect(in: CGRect(
                x: rect.minX + tailSize,
                y: rect.minY,
                width: rect.width - tailSize,
                height: rect.height
            ), cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        }

        return path
    }
}
