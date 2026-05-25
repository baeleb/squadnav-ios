import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss

    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    private var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }

    private var formValid: Bool {
        !displayName.isEmpty && email.isValidEmail && password.count >= 6 && passwordsMatch
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    // Header
                    VStack(spacing: 8) {
                        HStack {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(AppTheme.textMuted)
                            }
                            Spacer()
                        }

                        Text("Create Account")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("Join the caravan")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .padding(.top, 20)

                    // Form
                    VStack(spacing: 16) {
                        // Name
                        FormField(
                            label: "Display Name",
                            icon: "person.fill",
                            text: $displayName,
                            contentType: .name
                        )

                        // Email
                        FormField(
                            label: "Email",
                            icon: "envelope.fill",
                            text: $email,
                            contentType: .emailAddress,
                            keyboardType: .emailAddress,
                            autocapitalization: false
                        )

                        // Password
                        FormField(
                            label: "Password",
                            icon: "lock.fill",
                            text: $password,
                            isSecure: true,
                            contentType: .newPassword
                        )

                        if !password.isEmpty && password.count < 6 {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(AppTheme.warning)
                                Text("Password must be at least 6 characters")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(AppTheme.warning)
                                Spacer()
                            }
                        }

                        // Confirm Password
                        FormField(
                            label: "Confirm Password",
                            icon: "lock.shield.fill",
                            text: $confirmPassword,
                            isSecure: true,
                            contentType: .newPassword
                        )

                        if !confirmPassword.isEmpty && !passwordsMatch {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(AppTheme.danger)
                                Text("Passwords do not match")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(AppTheme.danger)
                                Spacer()
                            }
                        }

                        // Error
                        if let error = authViewModel.error {
                            Text(error)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.danger)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                    .glassCard()

                    // Sign Up button
                    Button {
                        Task {
                            await authViewModel.signUpWithEmail(
                                email: email,
                                password: password,
                                displayName: displayName
                            )
                            if authViewModel.error == nil {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            if authViewModel.isSigningIn {
                                ProgressView().tint(.white)
                            } else {
                                Text("Create Account")
                            }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!formValid || authViewModel.isSigningIn)
                    .opacity(formValid ? 1.0 : 0.5)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Reusable Form Field

struct FormField: View {
    let label: String
    let icon: String
    @Binding var text: String
    var isSecure: Bool = false
    var contentType: UITextContentType = .name
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
                .textCase(.uppercase)

            HStack {
                Image(systemName: icon)
                    .foregroundColor(AppTheme.textMuted)
                    .frame(width: 20)

                if isSecure {
                    SecureField("", text: $text)
                        .textContentType(contentType)
                        .foregroundColor(.white)
                } else {
                    TextField("", text: $text)
                        .textContentType(contentType)
                        .keyboardType(keyboardType)
                        .autocapitalization(autocapitalization ? .words : .none)
                        .foregroundColor(.white)
                }
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
    }
}
