import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let player = NowPlaying()
    private let shelf = Shelf()
    private lazy var model = IslandModel(player: player, shelf: shelf)
    private var panel: IslandPanel!
    private var volumeWatcher: VolumeWatcher?
    private var powerWatcher: PowerWatcher?
    private var inputSourceWatcher: InputSourceWatcher?
    private var capsLockWatcher: CapsLockWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = IslandPanel(model: model)

        volumeWatcher = VolumeWatcher { [weak self] volume, muted in
            self?.model.show(.volume(volume, muted: muted))
        }
        volumeWatcher?.onDeviceChange = { [weak self] name, isHeadphones in
            self?.model.show(.output(name: name, isHeadphones: isHeadphones))
        }
        inputSourceWatcher = InputSourceWatcher { [weak self] code, _ in
            // Outside full screen the menu bar already shows the layout.
            guard let self, isFrontAppFullScreen(on: model.notch.screenFrame) else { return }
            model.show(.inputSource(code: code))
        }
        capsLockWatcher = CapsLockWatcher { [weak self] isOn in
            self?.model.show(.capsLock(isOn))
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
