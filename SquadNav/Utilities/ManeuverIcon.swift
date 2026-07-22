import Foundation

enum ManeuverIcon {
    static func symbolName(for instruction: String) -> String {
        let lower = instruction.lowercased()
        if lower.contains("right") { return "arrow.turn.up.right" }
        if lower.contains("left") { return "arrow.turn.up.left" }
        if lower.contains("u-turn") || lower.contains("u turn") { return "arrow.uturn.down" }
        if lower.contains("merge") { return "arrow.merge" }
        if lower.contains("exit") || lower.contains("ramp") { return "arrow.up.right" }
        if lower.contains("straight") || lower.contains("continue") { return "arrow.up" }
        if lower.contains("arrive") || lower.contains("destination") { return "flag.checkered" }
        return "arrow.up"
    }
}
