import CarPlay
import MapKit

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?
    var mapTemplate: CPMapTemplate?
    var carPlayWindow: CPWindow?
    var mapViewController: CarPlayMapController?
    var navigationManager: CarPlayNavigationManager?

    // MARK: - Scene Lifecycle

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        self.interfaceController = interfaceController
        self.carPlayWindow = window

        let mapTemplate = CPMapTemplate()
        mapTemplate.mapDelegate = self
        self.mapTemplate = mapTemplate

        // Setup map view controller
        let mapVC = CarPlayMapController()
        window.rootViewController = mapVC
        window.makeKeyAndVisible()
        self.mapViewController = mapVC

        // Setup navigation manager
        let navManager = CarPlayNavigationManager(
            mapTemplate: mapTemplate,
            mapController: mapVC
        )
        self.navigationManager = navManager

        setupMapButtons(mapTemplate: mapTemplate)

        // CPMapTemplate may only be used as the root template — pushing it
        // onto another template raises an exception.
        interfaceController.setRootTemplate(mapTemplate, animated: true, completion: nil)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        self.interfaceController = nil
        self.carPlayWindow = nil
        self.mapTemplate = nil
        self.mapViewController = nil
        self.navigationManager = nil
    }

    // MARK: - Setup

    private func setupMapButtons(mapTemplate: CPMapTemplate) {
        // Zoom buttons
        let zoomIn = CPMapButton { [weak self] _ in
            self?.mapViewController?.zoomIn()
        }
        zoomIn.image = UIImage(systemName: "plus.magnifyingglass")

        let zoomOut = CPMapButton { [weak self] _ in
            self?.mapViewController?.zoomOut()
        }
        zoomOut.image = UIImage(systemName: "minus.magnifyingglass")

        // Recenter button
        let recenter = CPMapButton { [weak self] _ in
            self?.mapViewController?.recenterOnUser()
        }
        recenter.image = UIImage(systemName: "location.fill")

        mapTemplate.mapButtons = [zoomIn, zoomOut, recenter]

        // Navigation bar: show caravan status
        // CPMapTemplate manages its own navigation bar, setting these can cause internal crashes!
        // let caravanButton = CPBarButton(title: "Caravan") { _ in }
        // mapTemplate.leadingNavigationBarButtons = [caravanButton]
    }
}

// MARK: - CPMapTemplateDelegate

extension CarPlaySceneDelegate: CPMapTemplateDelegate {
    func mapTemplate(
        _ mapTemplate: CPMapTemplate,
        startedTrip trip: CPTrip,
        using routeChoice: CPRouteChoice
    ) {
        let session = mapTemplate.startNavigationSession(for: trip)
        navigationManager?.startNavigation(session: session)
    }

    func mapTemplate(_ mapTemplate: CPMapTemplate, didEndNavigationFor trip: CPTrip) {
        navigationManager?.stopNavigation()
    }

    func mapTemplate(
        _ mapTemplate: CPMapTemplate,
        shouldShowNotificationFor maneuver: CPManeuver
    ) -> Bool {
        return true
    }

    func mapTemplate(
        _ mapTemplate: CPMapTemplate,
        shouldUpdateNotificationFor maneuver: CPManeuver,
        with travelEstimates: CPTravelEstimates
    ) -> Bool {
        return true
    }
}
