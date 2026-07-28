import SwiftUI
import Detectors

/// One meaning per colour: grey is something merely sitting there, amber is
/// something actively burning CPU. Nothing else is tinted, so amber always
/// means the same thing at a glance.
enum Theme {
    static let panelWidth: CGFloat = 390
    static let rowSpacing: CGFloat = 10
    static let cardRadius: CGFloat = 11

    /// Colour carries kind, so a glance at an icon or a rail says what sort of
    /// thing this is. Amber overrides everything: it only ever means "this one
    /// is burning CPU right now".
    static func tint(for kind: FindingKind) -> Color {
        switch kind {
        case .devServer: Color(red: 0.42, green: 0.44, blue: 0.96)       // indigo
        case .container: Color(red: 0.11, green: 0.67, blue: 0.71)       // teal
        case .simulator: Color(red: 0.85, green: 0.34, blue: 0.62)       // magenta
        case .isolatedBrowser: Color(red: 0.20, green: 0.56, blue: 0.95) // blue
        case .orphan: Color(red: 0.83, green: 0.56, blue: 0.18)          // ochre
        case .tunnel: Color(red: 0.86, green: 0.31, blue: 0.34)           // red: an open door
        case .keepingAwake: Color(red: 0.55, green: 0.42, blue: 0.90)     // violet: a lit screen at night
        }
    }

    static func accent(for finding: Finding) -> Color {
        finding.cpuPercent >= 20 ? .orange : tint(for: finding.kind)
    }

    static func isHot(_ finding: Finding) -> Bool { finding.cpuPercent >= 20 }

    static func icon(for kind: FindingKind) -> String {
        switch kind {
        case .isolatedBrowser: "globe"
        case .container: "shippingbox.fill"
        case .simulator: "iphone.gen3"
        case .devServer: "terminal.fill"
        case .orphan: "circle.dashed"
        case .tunnel: "point.3.connected.trianglepath.dotted"
        case .keepingAwake: "eye.fill"
        }
    }

    /// Sections group by how a thing is stopped, which is also how people think
    /// about them: a process is quit, a container is stopped, a device shuts down.
    static func section(for kind: FindingKind) -> String {
        switch kind {
        case .container: "Containers"
        case .simulator: "Simulators"
        default: "Processes"
        }
    }

    static let sectionOrder = ["Processes", "Containers", "Simulators"]
}

extension Font {
    /// Eyebrow labels above each group.
    static let eyebrow = Font.system(size: 10, weight: .semibold)
    /// Numbers are data: same width in every row so columns line up.
    static let figure = Font.system(size: 12, weight: .medium).monospacedDigit()
    static let figureLarge = Font.system(size: 13, weight: .semibold).monospacedDigit()
    static let rowTitle = Font.system(size: 13, weight: .medium)
    static let rowDetail = Font.system(size: 11)
}
