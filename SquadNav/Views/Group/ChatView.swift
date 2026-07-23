import SwiftUI
import FirebaseAuth

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool

    init(chatService: ChatService, groupId: String) {
        self._viewModel = StateObject(wrappedValue: ChatViewModel(
            chatService: chatService,
            groupId: groupId
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.chatService.messages) { message in
                            MessageBubbleView(
                                message: message,
                                isCurrentUser: message.senderId == viewModel.currentUserId
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: viewModel.chatService.messages.count) { _, _ in
                    if let lastId = viewModel.chatService.messages.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            // Input bar
            inputBar
        }
        .background(AppTheme.backgroundDark)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        let isEmpty = viewModel.messageText.trimmingCharacters(in: .whitespaces).isEmpty

        return HStack(spacing: 0) {
            TextField("Message", text: $viewModel.messageText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(AppFont.nunito(16))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(1...5)
                .padding(.leading, 18)
                .padding(.trailing, isEmpty ? 4 : 8)
                .padding(.vertical, 10)
                .focused($isInputFocused)

            if !isEmpty {
                Button {
                    Task {
                        await viewModel.sendMessage()
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(AppTheme.primary)
                }
                .padding(.trailing, 8)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(AppTheme.backgroundInput)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(isEmpty ? AppTheme.border : AppTheme.primary,
                                lineWidth: isEmpty ? 1.5 : 2)
                        .animation(.easeInOut(duration: 0.2), value: isEmpty)
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .animation(.easeInOut(duration: 0.2), value: isEmpty)
    }
}
