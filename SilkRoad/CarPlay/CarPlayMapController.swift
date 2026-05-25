import UIKit
import MapKit

/// UIViewController hosting an MKMapView for the CarPlay screen.
/// Shows the route polyline and caravan member annotations.
class CarPlayMapController: UIViewController {
    private var mapView: MKMapView!
    private var routeOverlay: MKPolyline?

    override func viewDidLoad() {
        super.viewDidLoad()

        mapView = MKMapView(frame: view.bounds)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.delegate = self
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .followWithHeading
        mapView.overrideUserInterfaceStyle = .dark

        // Dark map appearance
        if #available(iOS 17.0, *) {
            mapView.preferredConfiguration = MKStandardMapConfiguration(
                elevationStyle: .realistic,
                emphasisStyle: .muted
            )
        }

        view.addSubview(mapView)
    }

    // MARK: - Map Controls

    func zoomIn() {
        var region = mapView.region
        region.span.latitudeDelta /= 2
        region.span.longitudeDelta /= 2
        mapView.setRegion(region, animated: true)
    }

    func zoomOut() {
        var region = mapView.region
        region.span.latitudeDelta = min(region.span.latitudeDelta * 2, 180)
        region.span.longitudeDelta = min(region.span.longitudeDelta * 2, 360)
        mapView.setRegion(region, animated: true)
    }

    func recenterOnUser() {
        mapView.setUserTrackingMode(.followWithHeading, animated: true)
    }

    // MARK: - Route Display

    func showRoute(coordinates: [CLLocationCoordinate2D]) {
        // Remove existing overlay
        if let existing = routeOverlay {
            mapView.removeOverlay(existing)
        }

        guard !coordinates.isEmpty else { return }

        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        routeOverlay = polyline
        mapView.addOverlay(polyline, level: .aboveRoads)

        // Fit map to show entire route
        mapView.setVisibleMapRect(
            polyline.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 80, left: 40, bottom: 80, right: 40),
            animated: true
        )
    }

    // MARK: - Member Annotations

    func updateMemberAnnotations(members: [MemberLocation]) {
        // Remove existing non-user annotations
        let existing = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(existing)

        // Add member annotations
        for member in members {
            let annotation = CaravanMemberAnnotation(member: member)
            mapView.addAnnotation(annotation)
        }
    }
}

// MARK: - MKMapViewDelegate

extension CarPlayMapController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor(red: 108/255, green: 99/255, blue: 255/255, alpha: 1.0) // AppTheme.primary
            renderer.lineWidth = 6
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let caravanAnnotation = annotation as? CaravanMemberAnnotation else {
            return nil
        }

        let identifier = "CaravanMember"
        var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView

        if view == nil {
            view = MKMarkerAnnotationView(annotation: caravanAnnotation, reuseIdentifier: identifier)
            view?.canShowCallout = true
        } else {
            view?.annotation = caravanAnnotation
        }

        let member = caravanAnnotation.member
        view?.glyphImage = UIImage(systemName: member.isLeader ? "crown.fill" : "car.fill")
        view?.markerTintColor = UIColor(
            red: CGFloat(Int(member.status.colorHex.prefix(2), radix: 16)!) / 255,
            green: CGFloat(Int(member.status.colorHex.dropFirst(2).prefix(2), radix: 16)!) / 255,
            blue: CGFloat(Int(member.status.colorHex.suffix(2), radix: 16)!) / 255,
            alpha: 1.0
        )

        return view
    }
}

// MARK: - Custom Annotation

class CaravanMemberAnnotation: NSObject, MKAnnotation {
    let member: MemberLocation

    var coordinate: CLLocationCoordinate2D {
        member.coordinate
    }

    var title: String? {
        member.displayName
    }

    var subtitle: String? {
        member.status.displayLabel
    }

    init(member: MemberLocation) {
        self.member = member
        super.init()
    }
}
