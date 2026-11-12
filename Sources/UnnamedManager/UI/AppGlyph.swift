import AppKit

/// The app icon's glyph in one color: the menu bar icon (S-041) and the icon
/// of a menu in the Guide. If Icon/AppIcon.icon changes shape, change this.
enum AppGlyph {
    /// The glyph alone as a template image.
    static func image(side: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            draw(in: rect, alpha: 1)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The app icon's glyph (front.svg and back.svg, whose shapes span 193 to
    /// 765 of 1024): the back keycap, a gap, then the front keycap with its
    /// › cut out. In a flipped rect, so the SVG's coordinates work as is.
    static func draw(in rect: NSRect, alpha: CGFloat) {
        let scale = rect.width / 572
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: (x - 193) * scale, y: (y - 193) * scale) }
        func keycap(_ x: CGFloat, _ y: CGFloat, _ side: CGFloat) -> NSBezierPath {
            let origin = point(x, y)
            return NSBezierPath(roundedRect: NSRect(x: origin.x, y: origin.y, width: side * scale, height: side * scale),
                                xRadius: 106 * scale, yRadius: 106 * scale)
        }
        let gap = max(1, 24 * scale)
        NSColor.black.withAlphaComponent(alpha).set()
        keycap(193, 193, 462).fill()
        // The gap between the keycaps, so the front one reads as in front.
        let front = keycap(303, 303, 462)
        let halo = NSBezierPath(roundedRect: front.bounds.insetBy(dx: -gap, dy: -gap),
                                xRadius: 106 * scale + gap, yRadius: 106 * scale + gap)
        NSColor.clear.set()
        halo.fill(using: .copy)
        NSColor.black.withAlphaComponent(alpha).set()
        let chevron = NSBezierPath()
        chevron.move(to: point(462, 380))
        for (x, y) in [(565, 380), (680, 534), (565, 688), (462, 688), (577, 534)] as [(CGFloat, CGFloat)] {
            chevron.line(to: point(x, y))
        }
        chevron.close()
        front.append(chevron)
        front.windingRule = .evenOdd
        front.fill()
    }
}

extension NSBezierPath {
    func fill(using operation: NSCompositingOperation) {
        NSGraphicsContext.current?.compositingOperation = operation
        fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }
}
