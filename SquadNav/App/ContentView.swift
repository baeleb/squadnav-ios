import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        SwiftUI.Group {
            if authViewModel.isLoading {
                LaunchView()
            } else if authViewModel.currentUser != nil {
                HomeView()
                    .environmentObject(authViewModel)
            } else {
                SignInView()
                    .environmentObject(authViewModel)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: authViewModel.currentUser != nil)
    }
}

// MARK: - Launch Screen

struct LaunchView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            AppTheme.backgroundDark.ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(AppTheme.primary)
                        .frame(width: 64, height: 64)
                        .shadow(color: AppTheme.primary.opacity(0.35), radius: 14, y: 8)

                    SquadGlyph()
                        .frame(width: 30, height: 30)
                }
                .scaleEffect(pulse ? 1.06 : 1.0)
                .animation(
                    .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                    value: pulse
                )

                Text("SquadNav")
                    .font(AppFont.fredoka(32, .semibold))
                    .foregroundColor(AppTheme.textPrimary)
            }
            .onAppear { pulse = true }
        }
    }
}

/// Three-circle "squad" mark used on the launch/welcome screens — one lead
/// circle plus two supporting circles, matching the Flock wordmark glyph.
struct SquadGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: w * 0.36, height: w * 0.36)
                    .position(x: w * 0.16, y: h * 0.68)
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: w * 0.36, height: w * 0.36)
                    .position(x: w * 0.84, y: h * 0.68)
                Circle()
                    .fill(Color.white)
                    .frame(width: w * 0.44, height: w * 0.44)
                    .position(x: w * 0.5, y: h * 0.38)
            }
        }
    }
}
