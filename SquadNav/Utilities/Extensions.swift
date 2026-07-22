import SwiftUI
import UIKit
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

    /// A color that switches between a light-appearance and dark-appearance hex value
    /// automatically, following the system appearance (no manual scheme plumbing needed).
    init(light: String, dark: String) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light))
        })
    }
}

// MARK: - App Theme
//
// "Flock" palette: warm cream/orange/teal in light appearance, rebased onto the
// mockup's dark-teal turn-by-turn surface for dark appearance. Token names are kept
// stable across the old theme so every call site keeps working; only the underlying
// values change.

enum AppTheme {
    // Primary palette
    static let primary = Color(light: "D9642F", dark: "F2894C")       // orange (CTAs, active states)
    static let primaryDark = Color(light: "C4592B", dark: "D9642F")   // pressed/darker orange
    static let accent = Color(light: "4E9A9B", dark: "6FB3B4")        // teal (secondary accent, icon tiles)
    static let accentLight = Color(light: "6FB3B4", dark: "8CC7C8")

    // Background
    static let backgroundDark = Color(light: "FBF3E8", dark: "16241F")      // app background
    static let backgroundCard = Color(light: "FFFFFF", dark: "24403F")      // elevated cards
    static let backgroundElevated = Color(light: "F2ECDD", dark: "2E4A48")  // icon tiles, avatar fills
    static let backgroundInput = Color(light: "FFFFFF", dark: "1C2F2D")     // text field fill
    static let border = Color(light: "E7DCC8", dark: "35524F")              // input/card hairline

    // Text
    static let textPrimary = Color(light: "3A2E22", dark: "F5EFE2")
    static let textSecondary = Color(light: "8A7A64", dark: "A9C9C5")
    static let textMuted = Color(light: "B3A48C", dark: "6E938F")

    // Status
    static let success = Color(light: "6FBE6A", dark: "7ED17A")   // on-route / arrived
    static let warning = Color(light: "D2A03D", dark: "E6B54F")   // stopped / idle / caution
    static let danger = Color(light: "E2603A", dark: "FF7A50")    // off-route / behind

    // Warm shadow — used in place of a flat black shadow everywhere in the new theme.
    static let shadowColor = Color(light: "3C280A", dark: "000000")

    // Deterministic per-member avatar colors (mockup's member-dot palette).
    static let memberPalette: [Color] = [
        Color(light: "D9642F", dark: "F2894C"),
        Color(light: "4E9A9B", dark: "6FB3B4"),
        Color(light: "6FBE6A", dark: "7ED17A"),
        Color(light: "D2A03D", dark: "E6B54F"),
        Color(light: "9B6B9E", dark: "B587B8"),
        Color(light: "C4592B", dark: "E07A4C"),
    ]

    /// Stable color for a member identity (Firestore uid or similar), independent of status.
    static func memberColor(for id: String) -> Color {
        let hash = id.unicodeScalars.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1.value) }
        return memberPalette[Int(hash % UInt64(memberPalette.count))]
    }

    // Gradients
    static let primaryGradient = LinearGradient(
        colors: [primary, Color(light: "F2894C", dark: "F2894C")],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let backgroundGradient = LinearGradient(
        colors: [backgroundDark, backgroundCard.opacity(0.6), backgroundDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardGradient = LinearGradient(
        colors: [backgroundCard.opacity(0.8), backgroundElevated.opacity(0.4)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Orange hero gradient for full-bleed CTA surfaces (onboarding welcome, invite reveal).
    static let heroGradient = LinearGradient(
        colors: [Color(hex: "F2894C"), Color(hex: "E9793A")],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - App Fonts
//
// Fredoka (display/headings) + Nunito (body/UI) — bundled under SquadNav/Resources/Fonts
// and registered via project.yml's UIAppFonts. No runtime fallback: these are always
// available once the app target builds.

enum AppFont {
    enum DisplayWeight { case medium, semibold, bold }
    enum BodyWeight { case regular, semibold, bold, extraBold }

    static func fredoka(_ size: CGFloat, _ weight: DisplayWeight = .semibold) -> Font {
        let name: String
        switch weight {
        case .medium: name = "Fredoka-Medium"
        case .semibold: name = "Fredoka-SemiBold"
        case .bold: name = "Fredoka-Bold"
        }
        return .custom(name, size: size)
    }

    static func nunito(_ size: CGFloat, _ weight: BodyWeight = .regular) -> Font {
        let name: String
        switch weight {
        case .regular: name = "Nunito-Regular"
        case .semibold: name = "Nunito-SemiBold"
        case .bold: name = "Nunito-Bold"
        case .extraBold: name = "Nunito-ExtraBold"
        }
        return .custom(name, size: size)
    }
}

// MARK: - View Modifiers

/// Flat, warm-shadowed card — replaces the old glassmorphic dark-blur treatment.
struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(AppTheme.backgroundCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
            )
            .shadow(color: AppTheme.shadowColor.opacity(0.1), radius: 10, x: 0, y: 4)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.nunito(17, .extraBold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(AppTheme.primary)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.nunito(17, .extraBold))
            .foregroundColor(AppTheme.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(AppTheme.primary, lineWidth: 1.5)
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
