import SwiftUI
import CoreLocation

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - App Theme

enum AppTheme {
    // Primary palette
    static let primary = Color(hex: "6C63FF")
    static let primaryDark = Color(hex: "4A42D4")
    static let accent = Color(hex: "E91E63")
    static let accentLight = Color(hex: "FF5C8D")

    // Background
    static let backgroundDark = Color(hex: "0D0D1A")
    static let backgroundCard = Color(hex: "1A1A3E")
    static let backgroundElevated = Color(hex: "252552")
    static let backgroundInput = Color(hex: "2A2A5A")

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "A0A0C0")
    static let textMuted = Color(hex: "6B6B8D")

    // Status
    static let success = Color(hex: "34C759")
    static let warning = Color(hex: "FF9500")
    static let danger = Color(hex: "FF3B30")

    // Gradients
    static let primaryGradient = LinearGradient(
        colors: [primary, accent],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let backgroundGradient = LinearGradient(
        colors: [backgroundDark, Color(hex: "1A1A3E"), backgroundDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardGradient = LinearGradient(
        colors: [backgroundCard.opacity(0.8), backgroundElevated.opacity(0.4)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - View Modifiers

struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(AppTheme.backgroundCard.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 8)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.primaryGradient)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundColor(AppTheme.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppTheme.primary, lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }
}

// MARK: - Date Extension

extension Date {
    var timeAgoDisplay: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var chatTimestamp: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            formatter.dateFormat = "h:mm a"
        } else if calendar.isDateInYesterday(self) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: self)
    }
}

// MARK: - CLLocationCoordinate2D

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

// MARK: - String

extension String {
    var isValidEmail: Bool {
        let emailRegex = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return range(of: emailRegex, options: .regularExpression) != nil
    }
}
