import AppKit
import Combine
import ServiceManagement
import SwiftUI

enum IslandTab: String, CaseIterable {
    case home, tasks, tools, actions, shelf

    var title: String {
        switch self {
        case .home: "Главная"
        case .tasks: "Задачи"
        case .tools: "Таймер и зеркало"
        case .actions: "Быстрые действия"
        case .shelf: "Полка"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .tasks: "checklist"
        case .tools: "timer"
        case .actions: "bolt.fill"
        case .shelf: "tray.full.fill"
        }
    }
}

/// A short-lived event shown beside the notch.
enum IslandEvent: Equatable {
    case volume(Float, muted: Bool)
    case charging(level: Int, isCharging: Bool)
    case inputSource(code: String)
    case capsLock(Bool)
    case output(name: String, isHeadphones: Bool)
    case timerDone
    case colorCopied(hex: String)

    /// How far the island grows to each side of the notch for this event.
    var wingWidth: CGFloat {
        switch self {
        case .output: 150
        case .colorCopied: 92
        case .inputSource, .capsLock: 64
        default: 86
        }
    }
}

final class IslandModel: ObservableObject {
    static let expandedSize = CGSize(width: 620, height: 180)
    /// How far the island grows to each side of the notch when it shows something.
    static let musicWingWidth: CGFloat = 44
    static let timerWingWidth: CGFloat = 64
    static let eyesWingWidth: CGFloat = 30

    @Published var notch = NotchGeometry.current()
    @Published private(set) var isExpanded = false
    @Published private(set) var event: IslandEvent?
    @Published var tab: IslandTab = .home
    /// Files are being dragged somewhere on screen; the island opens its shelf when they come near.
    @Published var isDraggingFiles = false
    @Published var showsEyes = UserDefaults.standard.object(forKey: "showsEyes") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showsEyes, forKey: "showsEyes") }
    }
    /// Tabs the user turned off in settings. Home can't be hidden.
    @Published var hiddenTabs = Set((UserDefaults.standard.stringArray(forKey: "hiddenTabs") ?? []).compactMap(IslandTab.init)) {
        didSet {
            UserDefaults.standard.set(hiddenTabs.map(\.rawValue), forKey: "hiddenTabs")
            if hiddenTabs.contains(tab) { tab = .home }
        }
    }
    /// Called when the island closes, so the panel can hand keyboard focus back.
    var onCollapse: (() -> Void)?

    let player: NowPlaying
    let shelf: Shelf
    let timer = CountdownTimer()
    let mirror = Mirror()
    let tasks = TaskList()
    let actions = QuickActions()
    private var collapseWork: DispatchWorkItem?
    private var eventWork: DispatchWorkItem?
    private var observers: Set<AnyCancellable> = []

    init(player: NowPlaying, shelf: Shelf) {
        self.player = player
        self.shelf = shelf
        // Re-publish so the island resizes when music or the timer starts or stops.
        player.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &observers)
        timer.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &observers)
        timer.onFinish = { [weak self] in self?.show(.timerDone) }
        actions.onColorPicked = { [weak self] hex in self?.show(.colorCopied(hex: hex)) }
    }

    /// What the collapsed island shows, in order of importance.
    enum Compact: Equatable {
        case event(IslandEvent), timer, music, eyes, none
    }

    var compact: Compact {
        if let event { return .event(event) }
        if timer.isActive { return .timer }
        if player.track?.isPlaying == true { return .music }
        if showsEyes { return .eyes }
        return .none
    }

    /// Size of the black shape for the current state.
    var contentSize: CGSize {
        let notchWidth = notch.width
        if isExpanded {
            return CGSize(width: max(Self.expandedSize.width, notchWidth + 120), height: notch.height + Self.expandedSize.height)
        }
        let wing: CGFloat
        switch compact {
        case .event(let event): wing = event.wingWidth
        case .timer: wing = Self.timerWingWidth
        case .music: wing = Self.musicWingWidth
        case .eyes: wing = Self.eyesWingWidth
        case .none: wing = 0
        }
        // Idle: exactly the notch, so it blends in. Without a notch the island disappears.
        return CGSize(width: notchWidth + wing * 2, height: notch.height)
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
                guard let self else { return }
                self.collapseWork = nil
                // Keep the island open while a file is dragged out of the shelf, or while typing a task.
                let isTyping = NSApp.keyWindow is IslandPanel && NSApp.keyWindow?.firstResponder is NSText
                if NSEvent.pressedMouseButtons != 0 || isTyping {
                    self.setHovering(false)
                    return
                }
                self.isExpanded = false
                self.mirror.stop()
                self.onCollapse?()
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    var visibleTabs: [IslandTab] {
        IslandTab.allCases.filter { !hiddenTabs.contains($0) }
    }

    func setTab(_ tab: IslandTab, visible: Bool) {
        guard tab != .home else { return }
        if visible { hiddenTabs.remove(tab) } else { hiddenTabs.insert(tab) }
    }

    /// Shows an event beside the notch for a moment.
    func show(_ newEvent: IslandEvent) {
        guard !isExpanded else { return }
        event = newEvent
        eventWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.event = nil }
        eventWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (newEvent == .timerDone ? 4 : 1.8), execute: work)
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }
}
