import AppKit
import SwiftUI

/// The menu bar icon carries the size of the waste, not just its count.
///
/// Calm and monochrome while nothing is burning, then warming through amber
/// into red as the forgotten things eat cores. The gradient runs inside the
/// glyph so the change reads at a glance without needing to be looked at.
enum MenuBarIcon {
    /// Two full cores of wasted CPU is as red as it gets.
    static let fullScaleCPU: Double = 200

    static func level(forWastedCPU percent: Double) -> Double {
        guard percent > 0 else { return 0 }
        return min(1, percent / fullScaleCPU)
    }

    /// Nothing at all → the system's own colour. Anything else → amber to red.
    static func colors(for level: Double) -> (top: NSColor, bottom: NSColor)? {
        guard level > 0 else { return nil }
        let amber = NSColor.systemOrange
        let red = NSColor.systemRed
        let warm = NSColor.systemYellow

        let top = blend(warm, amber, by: min(1, level * 1.6))
        let bottom = blend(amber, red, by: level)
        return (top, bottom)
    }

    private static func blend(_ from: NSColor, _ to: NSColor, by amount: Double) -> NSColor {
        from.blended(withFraction: CGFloat(max(0, min(1, amount))), of: to) ?? to
    }

    static func image(wastedCPU percent: Double, findingCount: Int) -> NSImage {
        let name = findingCount == 0 ? "circle" : "circle.dotted.circle"
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: "Still Running")?
            .withSymbolConfiguration(configuration) else {
            return NSImage(size: NSSize(width: 14, height: 14))
        }

        guard let colors = colors(for: level(forWastedCPU: percent)) else {
            symbol.isTemplate = true          // follows the menu bar's own colour
            return symbol
        }

        let gradient = NSGradient(starting: colors.top, ending: colors.bottom)
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSGraphicsContext.current?.compositingOperation = .sourceAtop
            gradient?.draw(in: rect, angle: -90)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }
}
