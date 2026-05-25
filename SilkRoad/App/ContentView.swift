import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        Group {
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
            LinearGradient(
                colors: [
                    Color(hex: "0D0D1A"),
                    Color(hex: "1A1A3E"),
                    Color(hex: "0D0D1A")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "car.2.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "6C63FF"), Color(hex: "E91E63")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .scaleEffect(pulse ? 1.1 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: pulse
                    )

                Text("Silk Road")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .onAppear { pulse = true }
        }
    }
}
