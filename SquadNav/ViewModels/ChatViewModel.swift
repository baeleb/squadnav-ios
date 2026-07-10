import Foundation
import Combine
import FirebaseAuth

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messageText: String = ""
    @Published var isSending: Bool = false

    let chatService: ChatService
    let groupId: String

    private var cancellables: Set<AnyCancellable> = []

    init(chatService: ChatService, groupId: String) {
        self.chatService = chatService
        self.groupId = groupId

        // Forward nested service changes so views observing this view model update.
        chatService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func sendMessage() async {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isSending = true
        messageText = ""

        do {
            try await chatService.sendMessage(groupId: groupId, text: text)
        } catch {
            messageText = text // Restore on failure
        }

        isSending = false
    }

    var currentUserId: String {
        Auth.auth().currentUser?.uid ?? ""
    }
}
