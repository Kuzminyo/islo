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
    static let canvasSize = CGSize(width: 760, height: 280)

    private let model: IslandModel
    private var mouseMonitors: [Any] = []
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount

    init(model: IslandModel) {
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
        // Take keyboard focus only for text fields (adding a task), never just for hovering.
        becomesKeyOnlyIfNeeded = true

        contentView = ClickThroughHostingView(rootView: IslandView(model: model, player: model.player, shelf: model.shelf))
        reposition()
        model.onCollapse = { [weak self] in self?.giveBackKeyboard() }

        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        let track: (NSEvent) -> Void = { [weak self] event in self?.handle(event) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: track) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { event in
            track(event)
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    override var canBecomeKey: Bool { model.isExpanded }

    /// Re-ordering the window drops its key status, so typing goes back to the app underneath.
    private func giveBackKeyboard() {
        guard isKeyWindow else { return }
        orderOut(nil)
        orderFrontRegardless()
    }

    func reposition() {
        model.notch = NotchGeometry.current()
        setFrame(model.notch.frame(for: Self.canvasSize), display: true)
        orderFrontRegardless()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragChangeCount = NSPasteboard(name: .drag).changeCount
        case .leftMouseDragged where !model.isDraggingFiles:
            // A new drag puts its items on the drag pasteboard; we only care about files.
            let pasteboard = NSPasteboard(name: .drag)
            if pasteboard.changeCount != dragChangeCount, pasteboard.types?.contains(.fileURL) == true {
                model.isDraggingFiles = true
            }
        case .leftMouseUp:
            // Let the drop land before forgetting about the drag.
            DispatchQueue.main.async { self.model.isDraggingFiles = false }
        default:
            break
        }
        updateHover()
    }

    /// Expands while the pointer is over the island and lets clicks through everywhere else.
    private func updateHover() {
        let mouse = NSEvent.mouseLocation
        let island = model.notch.frame(for: model.contentSize)
        // A little slack so the island is easy to reach from the top edge of the screen,
        // and a lot more while dragging files, so they can be dropped without aiming.
        let slack: CGFloat = model.isDraggingFiles ? 40 : 10
        let hotZone = island.insetBy(dx: -slack, dy: model.isExpanded ? -6 : -slack / 2)
        let inside = hotZone.contains(mouse)
        if ignoresMouseEvents == inside { ignoresMouseEvents = !inside }
        if inside && model.isDraggingFiles && !model.isExpanded && !model.hiddenTabs.contains(.shelf) { model.tab = .shelf }
        model.setHovering(inside)
    }
}
