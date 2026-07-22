import ActivityKit
import WidgetKit
import SwiftUI
import Foundation
import MapKit

struct SquadNavNavigationLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NavigationActivityAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        iconTile(36, systemName: context.state.maneuverIconName)
                        Text(formattedDistance(context.state.distanceToManeuverMeters))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formattedETA(context.state.etaSeconds))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        Text(formattedDistance(context.state.distanceRemainingMeters))
                            .font(.system(size: 11))
                            .foregroundColor(secondaryTextColor)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.instruction)
                            .lineLimit(1)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        if context.state.isRerouting {
                            Text("Rerouting\u{2026}")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(warningColor)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.maneuverIconName)
                    .foregroundColor(.white)
            } compactTrailing: {
                Text(shortDistance(context.state.distanceToManeuverMeters))
                    .foregroundColor(.white)
            } minimal: {
                Image(systemName: context.state.maneuverIconName)
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - Lock Screen

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<NavigationActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Icon tile
                iconTile(44, systemName: context.state.maneuverIconName)

                // Maneuver instruction
                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedDistance(context.state.distanceToManeuverMeters))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(context.state.instruction)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(secondaryTextColor)
                        .lineLimit(2)
                }

                Spacer()

                // ETA + remaining
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formattedETA(context.state.etaSeconds))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text(formattedDistance(context.state.distanceRemainingMeters))
                        .font(.system(size: 12))
                        .foregroundColor(secondaryTextColor)
                }
            }

            // Rerouting banner
            if context.state.isRerouting {
                HStack(spacing: 6) {
                    ProgressView()
                        .tint(warningColor)
                        .scaleEffect(0.8)
                    Text("Rerouting\u{2026}")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(warningColor)
                }
                .padding(.top, 8)
            }

            // Destination label
            Text("To \(context.attributes.destinationName)")
                .font(.system(size: 11))
                .foregroundColor(secondaryTextColor)
                .padding(.top, 8)
        }
        .padding(16)
        .background(backgroundColor)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func iconTile(_ size: CGFloat, systemName: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(primaryColor)
                .frame(width: size, height: size)
            Image(systemName: systemName)
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private func formattedETA(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(seconds, 0)) ?? "--"
    }

    private func formattedDistance(_ meters: Double) -> String {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter.string(fromDistance: meters)
    }

    private func shortDistance(_ meters: Double) -> String {
        if meters < 1609 {
            return "\(Int(meters * 3.281)) ft"
        } else {
            return String(format: "%.1f mi", meters / 1609.34)
        }
    }
}

// MARK: - Colors

private let backgroundColor = Color(red: 0.08, green: 0.08, blue: 0.17) // #14142B
private let primaryColor = Color(red: 0.43, green: 0.36, blue: 1.0) // #6E5BFF
private let secondaryTextColor = Color(red: 0.72, green: 0.72, blue: 0.82) // #B8B8D0
private let warningColor = Color(red: 1.0, green: 0.58, blue: 0.0) // #FF9500
