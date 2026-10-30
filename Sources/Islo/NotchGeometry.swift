import AppKit

/// Where the camera notch is. On screens without one, a zero-width "notch" in the middle of the menu bar.
struct NotchGeometry: Equatable {
    let screenFrame: NSRect
    /// The notch in screen coordinates; its top edge is the top of the screen.
    let rect: NSRect
    let hasNotch: Bool

    var width: CGFloat { rect.width }
    var height: CGFloat { rect.height }

    static func current() -> NotchGeometry {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.frame
        let top = screen.safeAreaInsets.top

        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            // The notch is the gap between the two usable areas at the top of the screen.
            let minX = frame.minX + left.width
            let maxX = frame.maxX - right.width
            return NotchGeometry(
                screenFrame: frame,
                rect: NSRect(x: minX, y: frame.maxY - top, width: maxX - minX, height: top),
                hasNotch: true
            )
        }

        let height = NSStatusBar.system.thickness
        return NotchGeometry(
            screenFrame: frame,
            rect: NSRect(x: frame.midX, y: frame.maxY - height, width: 0, height: height),
            hasNotch: false
        )
    }

    /// A rectangle of `size` hanging from the top of the screen, centered on the notch.
    func frame(for size: CGSize) -> NSRect {
        NSRect(x: rect.midX - size.width / 2, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }
}
