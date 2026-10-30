import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let player = NowPlaying()
    private let shelf = Shelf()
    private lazy var model = IslandModel(player: player, shelf: shelf)
    private var panel: IslandPanel!
    private var volumeWatcher: VolumeWatcher?
    private var powerWatcher: PowerWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = IslandPanel(model: model)

        volumeWatcher = VolumeWatcher { [weak self] volume, muted in
            self?.model.show(.volume(volume, muted: muted))
        }
        powerWatcher = PowerWatcher { [weak self] level, isCharging in
            self?.model.show(.charging(level: level, isCharging: isCharging))
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.panel.reposition()
        }
    }
}
