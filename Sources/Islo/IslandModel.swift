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

/// Things the collapsed island can show beside the notch; each can be turned off in settings.
enum Indicator: String, CaseIterable {
    case music, timer, volume, charging, layout, capsLock, output, color

    var title: String {
        switch self {
        case .music: "Музыка"
        case .timer: "Таймер"
        case .volume: "Громкость"
        case .charging: "Зарядка"
        case .layout: "Раскладка клавиатуры"
        case .capsLock: "Caps Lock"
        case .output: "Наушники и колонки"
        case .color: "Цвет из пипетки"
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

    var indicator: Indicator {
        switch self {
        case .volume: .volume
        case .charging: .charging
        case .inputSource: .layout
        case .capsLock: .capsLock
        case .output: .output
        case .timerDone: .timer
        case .colorCopied: .color
        }
    }

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
    static let expandedSize = CGSize(width: 420, height: 140)
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
    /// Indicators the user turned off in settings.
    @Published var hiddenIndicators = Set((UserDefaults.standard.stringArray(forKey: "hiddenIndicators") ?? []).compactMap(Indicator.init)) {
        didSet { UserDefaults.standard.set(hiddenIndicators.map(\.rawValue), forKey: "hiddenIndicators") }
    }
    /// macOS reports the menu bar height, not the camera notch itself, and the two differ with
    /// scaled resolutions. This lets the collapsed island be lined up with the real notch.
    static let heightAdjustments: [CGFloat] = [-4, -2, -1, 0, 1, 2, 3, 4, 6]
    @Published var heightAdjust = UserDefaults.standard.object(forKey: "heightAdjust") as? CGFloat ?? 0 {
        didSet { UserDefaults.standard.set(heightAdjust, forKey: "heightAdjust") }
    }
    /// System output volume, shown and changed from the player.
    @Published var volume: Float = 1
    var onSetVolume: ((Float) -> Void)?

    func setVolume(_ value: Float) {
        volume = value
        onSetVolume?(value)
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
        // Switching apps can bring the music's source to the front, or take it away.
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &observers)
        timer.onFinish = { [weak self] in self?.show(.timerDone) }
        actions.onColorPicked = { [weak self] hex in self?.show(.colorCopied(hex: hex)) }
    }

    /// What the collapsed island shows, in order of importance.
    enum Compact: Equatable {
        case event(IslandEvent), timer, music, eyes, none
    }

    func shows(_ indicator: Indicator) -> Bool { !hiddenIndicators.contains(indicator) }

    func setIndicator(_ indicator: Indicator, visible: Bool) {
        if visible { hiddenIndicators.remove(indicator) } else { hiddenIndicators.insert(indicator) }
    }

    var compact: Compact {
        if let event { return .event(event) }
        if timer.isActive && shows(.timer) { return .timer }
        // No need to show the music while its app or tab is the one you're looking at.
        if player.track?.isPlaying == true && shows(.music) && !player.isSourceInFront { return .music }
        if showsEyes { return .eyes }
        return .none
    }

    /// Size of the black shape for the current state.
    var contentSize: CGSize {
        let notchWidth = notch.width
        if isExpanded {
            // Room for the tabs on the left of the notch and the settings on the right.
            return CGSize(width: max(Self.expandedSize.width, notchWidth + 230), height: notch.height + Self.expandedSize.height)
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
        let height = notch.hasNotch ? notch.height + heightAdjust : notch.height
        return CGSize(width: notchWidth + wing * 2, height: height)
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
        guard !isExpanded, shows(newEvent.indicator) else { return }
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
