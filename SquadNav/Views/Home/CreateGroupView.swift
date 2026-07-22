import SwiftUI

struct CreateGroupView: View {
    @ObservedObject var groupViewModel: GroupViewModel
    @Environment(\.dismiss) var dismiss

    @State private var groupName = ""
    @State private var qrCodeData: Data?

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
                    Text("New Caravan")
                        .font(AppFont.fredoka(20, .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    Color.clear.frame(width: 28)
                }

                if groupViewModel.showCreateSuccess, let group = groupViewModel.createdGroup {
                    // Success State
                    successView(group: group)
                } else {
                    // Create Form
                    createForm
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.backgroundDark.ignoresSafeArea())
        .presentationDetents([.height(480), .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Create Form

    private var createForm: some View {
        VStack(spacing: 24) {
            // Icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(AppTheme.primary)
                    .frame(width: 64, height: 64)
                    .shadow(color: AppTheme.primary.opacity(0.3), radius: 12, y: 6)

                Image(systemName: "flag.checkered.2.crossed")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
            }

            Text("Give your caravan a name")
                .font(AppFont.nunito(15, .semibold))
                .foregroundColor(AppTheme.textSecondary)

            // Group name input
            VStack(alignment: .leading, spacing: 8) {
                Text("Caravan Name")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                    .textCase(.uppercase)

                TextField("", text: $groupName, prompt: Text("e.g. Road Trip 2025")
                    .foregroundColor(AppTheme.textMuted))
                    .font(AppFont.nunito(16))
                    .foregroundColor(AppTheme.textPrimary)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(AppTheme.backgroundInput)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(AppTheme.border, lineWidth: 1.5)
                            )
                    )
            }

            if let error = groupViewModel.error {
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.danger)
            }

            Button {
                Task {
                    await groupViewModel.createGroup(name: groupName)
                }
            } label: {
                HStack {
                    if groupViewModel.isCreating {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "plus.circle.fill")
                        Text("Create Caravan")
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty || groupViewModel.isCreating)
            .opacity(groupName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)
        }
        .padding(20)
        .glassCard()
    }

    // MARK: - Success View

    private func successView(group: Group) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundColor(AppTheme.success)

            Text("Caravan Created!")
                .font(AppFont.fredoka(24, .semibold))
                .foregroundColor(AppTheme.textPrimary)

            InviteShareView(group: group, groupViewModel: groupViewModel)

            Button("Done") {
                groupViewModel.showCreateSuccess = false
                dismiss()
            }
            .font(AppFont.nunito(16, .semibold))
            .foregroundColor(AppTheme.textSecondary)
        }
    }
}
