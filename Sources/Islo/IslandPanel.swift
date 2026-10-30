import AppKit
import SwiftUI

/// Hosting view that reacts to the first click even though the panel never activates Islo.
private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A transparent window over the top of the screen that the island is drawn in.
///
/// The window is larger than the island; it ignores the mouse except while the pointer is
/// over the island, so clicks on the menu bar and apps around it go through.
final class IslandPanel: NSPanel {
    static let canvasSize = CGSize(width: 520, height: 260)

    private let model: IslandModel
    private var mouseMonitors: [Any] = []

    init(model: IslandModel, player: NowPlaying) {
        self.model = model
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.canvasSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Above the menu bar so the island can cover the notch area, even in full-screen apps.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true

        contentView = ClickThroughHostingView(rootView: IslandView(model: model, player: player))
        reposition()

        let track: (NSEvent) -> Void = { [weak self] _ in self?.updateHover() }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: track) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { event in
            track(event)
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    override var canBecomeKey: Bool { false }

    func reposition() {
        model.notch = NotchGeometry.current()
        setFrame(model.notch.frame(for: Self.canvasSize), display: true)
        orderFrontRegardless()
    }

    /// Expands while the pointer is over the island and lets clicks through everywhere else.
    private func updateHover() {
        let mouse = NSEvent.mouseLocation
        let island = model.notch.frame(for: model.contentSize)
        // A little slack so the island is easy to reach from the top edge of the screen.
        let hotZone = island.insetBy(dx: -10, dy: model.isExpanded ? -6 : -4)
        let inside = hotZone.contains(mouse)
        if ignoresMouseEvents == inside { ignoresMouseEvents = !inside }
        model.setHovering(inside)
    }
}
