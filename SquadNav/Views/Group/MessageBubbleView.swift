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
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.primary)
                }

                Text(message.text)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        BubbleShape(isCurrentUser: isCurrentUser)
                            .fill(
                                isCurrentUser
                                    ? AnyShapeStyle(AppTheme.primaryGradient)
                                    : AnyShapeStyle(AppTheme.backgroundElevated)
                            )
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
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(AppTheme.backgroundCard.opacity(0.5))
                )
            Spacer()
        }
    }

    // MARK: - Alert Message

    private var alertMessage: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppTheme.warning)

            Text(message.text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.warning.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.warning.opacity(0.3), lineWidth: 1)
                )
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
