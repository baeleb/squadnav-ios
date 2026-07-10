import Foundation
import Combine
import FirebaseAuth

@MainActor
class GroupViewModel: ObservableObject {
    @Published var isCreating = false
    @Published var isJoining = false
    @Published var error: String?
    @Published var createdGroup: Group?
    @Published var showCreateSuccess = false

    let groupService: GroupService
    let chatService = ChatService()
    let fileService = FileStorageService()

    private var cancellables: Set<AnyCancellable> = []

    init(groupService: GroupService? = nil) {
        let service = groupService ?? GroupService()
        self.groupService = service
        service.listenToUserGroups()

        // Nested ObservableObjects don't propagate to views observing this
        // view model, so forward their change notifications.
        for serviceChange in [service.objectWillChange, chatService.objectWillChange, fileService.objectWillChange] {
            serviceChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    // MARK: - Group Management

    func createGroup(name: String) async {
        isCreating = true
        error = nil
        do {
            let group = try await groupService.createGroup(name: name)
            createdGroup = group
            showCreateSuccess = true
        } catch {
            self.error = error.localizedDescription
        }
        isCreating = false
    }

    func joinGroup(inviteCode: String) async {
        isJoining = true
        error = nil
        do {
            _ = try await groupService.joinGroup(inviteCode: inviteCode)
        } catch {
            self.error = error.localizedDescription
        }
        isJoining = false
    }

    func leaveGroup(_ group: Group) async {
        guard let groupId = group.id else { return }
        do {
            try await groupService.leaveGroup(groupId: groupId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Group Detail

    func selectGroup(_ group: Group) {
        guard let groupId = group.id else { return }
        groupService.listenToGroup(groupId: groupId)
        groupService.listenToMembers(groupId: groupId)
        chatService.listenToMessages(groupId: groupId)
        fileService.listenToFiles(groupId: groupId)
    }

    func deselectGroup() {
        groupService.stopListeningToGroup()
        chatService.stopListening()
        fileService.stopListening()
    }

    // MARK: - QR Code

    func generateQRCode(for group: Group) -> Data? {
        groupService.generateQRCode(for: group.inviteCode)
    }

    // MARK: - Helpers

    var isLeader: Bool {
        guard let userId = Auth.auth().currentUser?.uid else { return false }
        return groupService.activeGroup?.createdBy == userId
    }
}
