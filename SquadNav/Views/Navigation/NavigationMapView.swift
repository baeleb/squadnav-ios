import SwiftUI
import MapKit

struct NavigationMapView: View {
    @ObservedObject var navigationVM: NavigationViewModel
    @ObservedObject var groupViewModel: GroupViewModel
    @Environment(\.dismiss) var dismiss

    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var showEndConfirmation = false

    var body: some View {
        ZStack {
            // Full screen map
            mapView

            // Overlay UI
            VStack(spacing: 0) {
                // Top: Maneuver banner
                ManeuverBannerView(
                    navigationState: navigationVM.navigationService.navigationState
                )

                Spacer()

                // Bottom: Info bar
                bottomBar
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showEndConfirmation = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 60)
                }
                Spacer()
            }

            // Alerts overlay
            if let latestAlert = navigationVM.caravanMonitor.alerts.last {
                alertBanner(alert: latestAlert)
            }
        }
        .ignoresSafeArea()
        .alert("End Navigation?", isPresented: $showEndConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("End", role: .destructive) {
                Task {
                    await navigationVM.stopNavigation()
                    dismiss()
                }
            }
        } message: {
            Text("This will stop navigation for your car. Other drivers will be notified.")
        }
    }

    // MARK: - Map

    private var mapView: some View {
        Map(position: $mapCameraPosition) {
            // Route polyline
            if !navigationVM.navigationService.routePolylineCoordinates.isEmpty {
                MapPolyline(coordinates: navigationVM.navigationService.routePolylineCoordinates)
                    .stroke(
                        LinearGradient(
                            colors: [AppTheme.primary, AppTheme.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 6
                    )
            }

            // Current user location
            UserAnnotation()

            // Other caravan members
            ForEach(groupViewModel.groupService.members) { member in
                Annotation(member.displayName, coordinate: member.coordinate) {
                    VStack(spacing: 2) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: member.status.colorHex))
                                .frame(width: 36, height: 36)
                                .shadow(color: Color(hex: member.status.colorHex).opacity(0.6), radius: 6)

                            Image(systemName: member.isLeader ? "crown.fill" : "car.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        }

                        Text(member.displayName.components(separatedBy: " ").first ?? "")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.7)))
                    }
                }
            }

            // Destination pin
            if let activeGroup = groupViewModel.groupService.activeGroup,
               let lat = activeGroup.destinationLatitude,
               let lng = activeGroup.destinationLongitude {
                Annotation("Destination", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
                    Image(systemName: "flag.checkered.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(AppTheme.accent)
                        .shadow(color: AppTheme.accent.opacity(0.5), radius: 8)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
        .mapControls {
            MapCompass()
            MapUserLocationButton()
        }
        .colorScheme(.dark)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 24) {
            // ETA
            VStack(spacing: 2) {
                Text("ETA")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppTheme.textMuted)
                    .textCase(.uppercase)
                Text(navigationVM.navigationService.navigationState.formattedETA)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            Divider()
                .frame(height: 36)
                .overlay(Color.white.opacity(0.15))

            // Distance
            VStack(spacing: 2) {
                Text("Distance")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppTheme.textMuted)
                    .textCase(.uppercase)
                Text(navigationVM.navigationService.navigationState.formattedDistance)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            Divider()
                .frame(height: 36)
                .overlay(Color.white.opacity(0.15))

            // Caravan status
            VStack(spacing: 2) {
                Text("Caravan")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppTheme.textMuted)
                    .textCase(.uppercase)

                HStack(spacing: 4) {
                    let onRoute = groupViewModel.groupService.members.filter { $0.status == .onRoute }.count
                    let total = groupViewModel.groupService.members.count

                    Circle()
                        .fill(onRoute == total ? AppTheme.success : AppTheme.warning)
                        .frame(width: 8, height: 8)

                    Text("\(onRoute)/\(total)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(AppTheme.backgroundCard.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 20, y: -5)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    // MARK: - Alert Banner

    private func alertBanner(alert: CaravanAlert) -> some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: alert.status.iconSystemName)
                    .foregroundColor(Color(hex: alert.status.colorHex))

                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.memberName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text(alert.status.displayLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: alert.status.colorHex))
                }

                Spacer()

                Button {
                    navigationVM.caravanMonitor.clearAlerts()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppTheme.textMuted)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.backgroundCard.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(hex: alert.status.colorHex).opacity(0.4), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.top, 100)

            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.4), value: navigationVM.caravanMonitor.alerts.count)
    }
}
