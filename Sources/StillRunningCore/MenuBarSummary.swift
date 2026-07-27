import Foundation

/// The menu bar icon stays monochrome, the way macOS menu bar icons do: it
/// takes the bar's own colour, inverts with the menu, and dims when the app is
/// not frontmost. Severity is carried by the glyph and the number beside it
/// rather than by tinting, which would make it the one loud thing up there.
public enum MenuBarSummary {
    /// Two full cores of wasted CPU is as far as the scale goes.
    public static let fullScaleCPU: Double = 200

    public static func level(forWastedCPU percent: Double) -> Double {
        guard percent > 0 else { return 0 }
        return min(1, percent / fullScaleCPU)
    }

    /// Quiet ring when nothing is burning, a dotted ring once something is
    /// merely sitting there, and a flame once it is eating a core.
    public static func symbolName(findingCount: Int, wastedCPU percent: Double) -> String {
        guard findingCount > 0 else { return "circle" }
        return percent >= fullScaleCPU / 2 ? "flame" : "circle.dotted.circle"
    }

    /// The count is the useful number until something is genuinely burning,
    /// at which point the size of the waste says more.
    public static func label(findingCount: Int, wastedCPU percent: Double) -> String? {
        guard findingCount > 0 else { return nil }
        return percent >= 20 ? "\(Int(percent))%" : "\(findingCount)"
    }
}
