import ActivityKit
import Combine
import Foundation

/// Bridges `NavigationService`'s turn-by-turn state to a Live Activity so
/// the current maneuver stays visible on the Lock Screen / Dynamic Island.
/// Best-effort throughout: a Live Activity failure must never break
/// navigation, so every ActivityKit call is swallowed with `try?`.
@MainActor
final class LiveActivityService: ObservableObject {
    private var activity: Activity<NavigationActivityAttributes>?
    private var cancellables = Set<AnyCancellable>()
    private let navigationService: NavigationService
    private var lastSent: NavigationActivityAttributes.ContentState?
    private var lastSentAt: Date?

    init(navigationService: NavigationService) {
        self.navigationService = navigationService

        // Clear any activities orphaned by a previous run/crash so a fresh
        // one can start clean.
        for stale in Activity<NavigationActivityAttributes>.activities {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }

        navigationService.objectWillChange
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.pushUpdateIfChanged()
                }
            }
            .store(in: &cancellables)
    }

    func startActivity(destinationName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // A leader switch can re-run start/joinNavigation on a device that
        // already has this navigation's activity running; don't double-start.
        guard activity == nil else { return }

        let attributes = NavigationActivityAttributes(destinationName: destinationName)
        let initial = contentState(from: navigationService.navigationState)

        activity = try? Activity<NavigationActivityAttributes>.request(
            attributes: attributes,
            content: .init(state: initial, staleDate: nil),
            pushType: nil
        )
        lastSent = initial
        lastSentAt = Date()
    }

    func endActivity(finalState: NavigationActivityAttributes.ContentState? = nil) async {
        let current = activity
        activity = nil
        lastSent = nil
        lastSentAt = nil
        await current?.end(
            finalState.map { .init(state: $0, staleDate: nil) },
            dismissalPolicy: finalState == nil ? .immediate : .default
        )
    }

    private func contentState(from state: NavigationState) -> NavigationActivityAttributes.ContentState {
        let nextInstruction = state.nextInstruction.flatMap { $0.isEmpty ? nil : $0 }
        return NavigationActivityAttributes.ContentState(
            instruction: state.currentInstruction,
            nextInstruction: nextInstruction,
            maneuverIconName: ManeuverIcon.symbolName(for: state.currentInstruction),
            distanceToManeuverMeters: state.distanceToNextManeuver,
            distanceRemainingMeters: state.totalDistanceRemaining,
            etaSeconds: state.estimatedTimeRemaining,
            isRerouting: state.phase == .rerouting
        )
    }

    private func pushUpdateIfChanged() {
        guard let activity else { return }

        let next = contentState(from: navigationService.navigationState)

        let shouldSend: Bool
        if let last = lastSent, let lastAt = lastSentAt {
            let lastBucket = Int(last.distanceToManeuverMeters / 100)
            let nextBucket = Int(next.distanceToManeuverMeters / 100)
            shouldSend = next.instruction != last.instruction
                || next.maneuverIconName != last.maneuverIconName
                || next.nextInstruction != last.nextInstruction
                || next.isRerouting != last.isRerouting
                || nextBucket != lastBucket
                || Date().timeIntervalSince(lastAt) >= 15
        } else {
            shouldSend = true
        }

        guard shouldSend else { return }

        lastSent = next
        lastSentAt = Date()

        Task {
            await activity.update(.init(state: next, staleDate: nil))
        }
    }
}
