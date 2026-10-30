import AppKit
import Combine
import ServiceManagement
import SwiftUI

/// A short-lived event shown beside the notch.
enum IslandEvent: Equatable {
    case volume(Float, muted: Bool)
    case charging(level: Int, isCharging: Bool)
}

final class IslandModel: ObservableObject {
    static let expandedSize = CGSize(width: 420, height: 150)
    /// How far the island grows to each side of the notch when it shows something.
    static let wingWidth: CGFloat = 44
    static let eventWingWidth: CGFloat = 86

    @Published var notch = NotchGeometry.current()
    @Published private(set) var isExpanded = false
    @Published private(set) var event: IslandEvent?

    let player: NowPlaying
    private var collapseWork: DispatchWorkItem?
    private var eventWork: DispatchWorkItem?
    private var playerObserver: AnyCancellable?

    init(player: NowPlaying) {
        self.player = player
        // Re-publish so the island resizes when music starts or stops.
        playerObserver = player.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }

    /// Size of the black shape for the current state.
    var contentSize: CGSize {
        let notchWidth = notch.width
        if isExpanded {
            return CGSize(width: max(Self.expandedSize.width, notchWidth + 120), height: notch.height + Self.expandedSize.height)
        }
        if event != nil {
            return CGSize(width: notchWidth + Self.eventWingWidth * 2, height: notch.height)
        }
        if player.track?.isPlaying == true {
            return CGSize(width: notchWidth + Self.wingWidth * 2, height: notch.height)
        }
        // Idle: exactly the notch, so it blends in. Without a notch the island disappears.
        return CGSize(width: notchWidth, height: notch.height)
    }

    func setHovering(_ hovering: Bool) {
        if hovering {
            collapseWork?.cancel()
            collapseWork = nil
            guard !isExpanded else { return }
            isExpanded = true
            event = nil
        } else if isExpanded, collapseWork == nil {
            let work = DispatchWorkItem { [weak self] in
                self?.isExpanded = false
                self?.collapseWork = nil
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    func show(_ newEvent: IslandEvent) {
        guard !isExpanded else { return }
        event = newEvent
        eventWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.event = nil }
        eventWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }
}
