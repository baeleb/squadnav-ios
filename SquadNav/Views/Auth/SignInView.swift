import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var showSignUp = false
    @State private var animateIn = false

    var body: some View {
        ZStack {
            // Background
            AppTheme.backgroundGradient
                .ignoresSafeArea()

            // Animated background particles
            GeometryReader { geo in
                ForEach(0..<15, id: \.self) { i in
                    Circle()
                        .fill(AppTheme.primary.opacity(0.08))
                        .frame(width: CGFloat.random(in: 30...120))
                        .position(
                            x: CGFloat.random(in: 0...geo.size.width),
                            y: CGFloat.random(in: 0...geo.size.height)
                        )
                        .blur(radius: 20)
                }
            }
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    Spacer().frame(height: 60)

                    // Logo
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.primary.opacity(0.15))
                                .frame(width: 100, height: 100)
                                .blur(radius: 15)

                            Image(systemName: "car.2.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(AppTheme.primaryGradient)
                        }
                        .scaleEffect(animateIn ? 1.0 : 0.5)
                        .opacity(animateIn ? 1.0 : 0)

                        Text("SquadNav")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("Drive together, arrive together")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .offset(y: animateIn ? 0 : -20)

                    // Form
                    VStack(spacing: 16) {
                        // Email field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppTheme.textSecondary)
                                .textCase(.uppercase)

                            HStack {
                                Image(systemName: "envelope.fill")
                                    .foregroundColor(AppTheme.textMuted)
                                    .frame(width: 20)

                                TextField("", text: $email)
                                    .textContentType(.emailAddress)
                                    .autocapitalization(.none)
                                    .keyboardType(.emailAddress)
                                    .foregroundColor(.white)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(AppTheme.backgroundInput)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                    )
                            )
                        }

                        // Password field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppTheme.textSecondary)
                                .textCase(.uppercase)

                            HStack {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(AppTheme.textMuted)
                                    .frame(width: 20)

                                SecureField("", text: $password)
                                    .textContentType(.password)
                                    .foregroundColor(.white)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(AppTheme.backgroundInput)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                    )
                            )
                        }

                        // Error
                        if let error = authViewModel.error {
                            Text(error)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.danger)
                                .multilineTextAlignment(.center)
                                .transition(.opacity)
                        }

                        // Sign In button
                        Button {
                            Task {
                                await authViewModel.signInWithEmail(email: email, password: password)
                            }
                        } label: {
                            HStack {
                                if authViewModel.isSigningIn {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Sign In")
                                }
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(email.isEmpty || password.isEmpty || authViewModel.isSigningIn)
                        .opacity(email.isEmpty || password.isEmpty ? 0.6 : 1.0)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                    .glassCard()
                    .padding(.horizontal, 20)
                    .offset(y: animateIn ? 0 : 30)
                    .opacity(animateIn ? 1.0 : 0)

                    // Divider
                    HStack {
                        Rectangle()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 1)
                        Text("or continue with")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.textMuted)
                            .layoutPriority(1)
                        Rectangle()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 40)

                    // Social Sign-In
                    VStack(spacing: 12) {
                        // Google Sign-In
                        Button {
                            Task {
                                await authViewModel.signInWithGoogle()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "g.circle.fill")
                                    .font(.system(size: 22))
                                Text("Continue with Google")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(AppTheme.backgroundElevated)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                            )
                        }

                        // Apple Sign-In
                        SignInWithAppleButton(.signIn) { request in
                            let (_, hashedNonce) = authViewModel.prepareAppleSignIn()
                            request.requestedScopes = [.fullName, .email]
                            request.nonce = hashedNonce
                        } onCompletion: { result in
                            Task {
                                await authViewModel.handleAppleSignIn(result: result)
                            }
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 56)
                        .cornerRadius(16)
                    }
                    .padding(.horizontal, 20)
                    .offset(y: animateIn ? 0 : 20)
                    .opacity(animateIn ? 1.0 : 0)

                    // Sign Up link
                    Button {
                        showSignUp = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("Don't have an account?")
                                .foregroundColor(AppTheme.textSecondary)
                            Text("Sign Up")
                                .foregroundColor(AppTheme.primary)
                                .fontWeight(.semibold)
                        }
                        .font(.system(size: 15, design: .rounded))
                    }

                    Spacer().frame(height: 40)
                }
            }
        }
        .sheet(isPresented: $showSignUp) {
            SignUpView()
                .environmentObject(authViewModel)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animateIn = true
            }
        }
    }
}
