import AppKit

/// One-click system actions shown in the island.
final class QuickActions: ObservableObject {
    @Published private(set) var isKeepingAwake = false
    @Published private(set) var isDarkMode = QuickActions.readDarkMode()

    /// Called with the HEX code after the color picker copies a color.
    var onColorPicked: ((String) -> Void)?

    private var caffeinate: Process?
    private let scriptQueue = DispatchQueue(label: "com.kuzminyo.islo.actions")

    init() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.isDarkMode = Self.readDarkMode()
        }
    }

    /// Keeps the Mac and display awake with the system `caffeinate` tool. It exits on its own
    /// if Islo quits, so the Mac never stays awake by accident.
    func toggleKeepAwake() {
        if let caffeinate {
            caffeinate.terminate()
            self.caffeinate = nil
            isKeepingAwake = false
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-di", "-w", "\(ProcessInfo.processInfo.processIdentifier)"]
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.caffeinate = nil
                self?.isKeepingAwake = false
            }
        }
        guard (try? process.run()) != nil else { return }
        caffeinate = process
        isKeepingAwake = true
    }

    /// Asks System Events to flip the appearance; macOS asks once for permission.
    func toggleDarkMode() {
        isDarkMode.toggle()
        scriptQueue.async {
            var error: NSDictionary?
            NSAppleScript(source: """
            tell application "System Events" to tell appearance preferences to set dark mode to not dark mode
            """)?.executeAndReturnError(&error)
            if let error { NSLog("Islo: dark mode %@", error) }
            DispatchQueue.main.async { self.isDarkMode = Self.readDarkMode() }
        }
    }

    func pickColor() {
        NSColorSampler().show { [weak self] color in
            guard let color = color?.usingColorSpace(.sRGB) else { return }
            let hex = String(
                format: "#%02X%02X%02X",
                Int((color.redComponent * 255).rounded()),
                Int((color.greenComponent * 255).rounded()),
                Int((color.blueComponent * 255).rounded())
            )
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hex, forType: .string)
            self?.onColorPicked?(hex)
        }
    }

    func screenshot() {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    func sleepDisplay() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        try? process.run()
    }

    func hideAllApps() {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            app.hide()
        }
    }

    private static func readDarkMode() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }
}
