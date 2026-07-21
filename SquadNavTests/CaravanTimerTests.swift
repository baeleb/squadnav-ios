import XCTest

/// F12: NavigationViewModel.startCaravanMonitoring overwrites monitorTimer
/// without invalidating the previous timer — calling it twice leaves TWO live
/// repeating timers (duplicate member evaluation + duplicate chat alerts).
/// startCaravanMonitoring/monitorTimer are internal test seams.
@MainActor
final class CaravanTimerTests: XCTestCase {

    override class func setUp() {
        FirebaseTestSupport.configureIfNeeded()
    }

    /// F12: UNTESTABLE in this standalone harness (2026-07-20).
    /// Constructing NavigationViewModel constructs LocationService, whose init
    /// sets `allowsBackgroundLocationUpdates = true` (LocationService.swift:28).
    /// In an unhosted test bundle (no UIBackgroundModes location entitlement)
    /// CoreLocation raises a fatal NSInternalInconsistencyException
    /// ("!stayUp || CLClientIsBackgroundable") before the test body runs.
    /// Making the VM constructible would require a behavior change to app
    /// code (lazy LocationService / injection), which is out of scope for a
    /// verification-only task. The timer bug itself is confirmed by code read:
    /// startCaravanMonitoring assigns monitorTimer without invalidating the
    /// previous timer (NavigationViewModel.swift, startCaravanMonitoring).
    func testDoubleStartCaravanMonitoringLeavesOrphanedTimer() throws {
        throw XCTSkip("F12 untestable: NavigationViewModel init fatals via LocationService.allowsBackgroundLocationUpdates in unhosted bundle. See header comment.")
        let viewModel = NavigationViewModel(groupService: GroupService(), chatService: ChatService())

        viewModel.startCaravanMonitoring()
        let firstTimer = viewModel.monitorTimer

        viewModel.startCaravanMonitoring()
        let secondTimer = viewModel.monitorTimer

        XCTAssertNotNil(firstTimer)
        XCTAssertNotNil(secondTimer)
        XCTAssertFalse(
            firstTimer === secondTimer,
            "Sanity: second start should create a new timer object"
        )
        XCTAssertFalse(
            firstTimer?.isValid ?? false,
            "F12: first timer is still live after the second start — two monitors now run concurrently"
        )

        // Cleanup so no timers leak into other tests.
        firstTimer?.invalidate()
        secondTimer?.invalidate()
    }
}
