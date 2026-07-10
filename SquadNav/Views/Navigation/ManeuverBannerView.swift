import SwiftUI

struct ManeuverBannerView: View {
    let navigationState: NavigationState

    var body: some View {
        SwiftUI.Group {
            switch navigationState.phase {
            case .navigating, .rerouting:
                activeBanner
            case .arrived:
                arrivedBanner
            case .calculatingRoute:
                loadingBanner
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Active Navigation Banner

    private var activeBanner: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                // Maneuver icon
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(AppTheme.primary)
                        .frame(width: 56, height: 56)

                    Image(systemName: maneuverIcon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    // Distance to next maneuver
                    Text(navigationState.formattedManeuverDistance)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    // Instruction
                    Text(navigationState.currentInstruction)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .padding(.top, 50) // Safe area padding

            // Rerouting indicator
            if navigationState.phase == .rerouting {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(AppTheme.warning)
                        .scaleEffect(0.8)

                    Text("Rerouting...")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.warning)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }

            // Next step preview
            if let nextInstruction = navigationState.nextInstruction, !nextInstruction.isEmpty {
                HStack(spacing: 8) {
                    Text("Then")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.textMuted)
                        .textCase(.uppercase)

                    Text(nextInstruction)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.2))
            }
        }
        .background(
            AppTheme.backgroundCard.opacity(0.95)
                .shadow(color: .black.opacity(0.3), radius: 15, y: 5)
        )
    }

    // MARK: - Arrived Banner

    private var arrivedBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "flag.checkered.circle.fill")
                .font(.system(size: 42))
                .foregroundColor(AppTheme.success)

            VStack(alignment: .leading, spacing: 4) {
                Text("You've arrived!")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Your destination is nearby")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .padding(.top, 50)
        .background(
            AppTheme.backgroundCard.opacity(0.95)
                .shadow(color: .black.opacity(0.3), radius: 15, y: 5)
        )
    }

    // MARK: - Loading Banner

    private var loadingBanner: some View {
        HStack(spacing: 14) {
            ProgressView()
                .tint(AppTheme.primary)

            Text("Calculating route...")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .padding(.top, 50)
        .background(
            AppTheme.backgroundCard.opacity(0.95)
                .shadow(color: .black.opacity(0.3), radius: 15, y: 5)
        )
    }

    // MARK: - Icon Helper

    private var maneuverIcon: String {
        let instruction = navigationState.currentInstruction.lowercased()

        if instruction.contains("right") && instruction.contains("slight") {
            return "arrow.turn.up.right"
        } else if instruction.contains("right") {
            return "arrow.turn.up.right"
        } else if instruction.contains("left") && instruction.contains("slight") {
            return "arrow.turn.up.left"
        } else if instruction.contains("left") {
            return "arrow.turn.up.left"
        } else if instruction.contains("u-turn") || instruction.contains("u turn") {
            return "arrow.uturn.down"
        } else if instruction.contains("merge") {
            return "arrow.merge"
        } else if instruction.contains("exit") || instruction.contains("ramp") {
            return "arrow.up.right"
        } else if instruction.contains("straight") || instruction.contains("continue") {
            return "arrow.up"
        } else if instruction.contains("arrive") || instruction.contains("destination") {
            return "flag.checkered"
        } else {
            return "arrow.up"
        }
    }
}
