import SwiftUI

struct JoinGroupView: View {
    @ObservedObject var groupViewModel: GroupViewModel
    var prefilledCode: String?
    @Environment(\.dismiss) var dismiss

    @State private var inviteCode = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(AppTheme.textMuted)
                    }
                    Spacer()
                    Text("Join Caravan")
                        .font(AppFont.fredoka(20, .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    Color.clear.frame(width: 28)
                }

                // Illustration
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(AppTheme.accent)
                        .frame(width: 64, height: 64)
                        .shadow(color: AppTheme.accent.opacity(0.3), radius: 12, y: 6)

                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                }

                // Invite code input
                VStack(spacing: 20) {
                    Text("Enter the 6-character invite code")
                        .font(AppFont.nunito(15, .semibold))
                        .foregroundColor(AppTheme.textSecondary)

                    // Code input
                    TextField("", text: $inviteCode, prompt: Text("ABC123")
                        .foregroundColor(AppTheme.textMuted))
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .tracking(8)
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(AppTheme.backgroundInput)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(
                                            inviteCode.count == 6 ? AppTheme.success : AppTheme.border,
                                            lineWidth: inviteCode.count == 6 ? 2 : 1.5
                                        )
                                )
                        )
                        .onChange(of: inviteCode) { _, newValue in
                            if newValue.count > 6 {
                                inviteCode = String(newValue.prefix(6))
                            }
                        }

                    // Character count
                    HStack(spacing: 4) {
                        ForEach(0..<6, id: \.self) { i in
                            Circle()
                                .fill(i < inviteCode.count ? AppTheme.primary : AppTheme.textMuted.opacity(0.3))
                                .frame(width: 8, height: 8)
                                .animation(.easeInOut(duration: 0.2), value: inviteCode.count)
                        }
                    }

                    if let error = groupViewModel.error {
                        Text(error)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.danger)
                            .transition(.opacity)
                    }
                }
                .padding(20)
                .glassCard()

                // Join button
                Button {
                    Task {
                        await groupViewModel.joinGroup(inviteCode: inviteCode)
                        if groupViewModel.error == nil {
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        if groupViewModel.isJoining {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Join Caravan")
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(inviteCode.count != 6 || groupViewModel.isJoining)
                .opacity(inviteCode.count == 6 ? 1.0 : 0.5)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.backgroundDark.ignoresSafeArea())
        .presentationDetents([.height(520), .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            if let prefilledCode {
                inviteCode = String(prefilledCode.prefix(6)).uppercased()
            }
        }
    }
}
