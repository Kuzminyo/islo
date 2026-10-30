import AppKit
import AVFoundation
import Carbon.HIToolbox

/// A countdown timer that lives in the island.
final class CountdownTimer: ObservableObject {
    static let presets = [1, 3, 5, 10, 15, 25, 45, 60]

    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    @Published private(set) var total: TimeInterval = 0

    var onFinish: (() -> Void)?
    private var ticker: Timer?

    var isActive: Bool { endDate != nil || pausedRemaining != nil }
    var isPaused: Bool { pausedRemaining != nil }

    func remaining(at date: Date = Date()) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return 0 }
        return max(0, endDate.timeIntervalSince(date))
    }

    func start(minutes: Int) {
        total = TimeInterval(minutes * 60)
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(total)
        schedule()
    }

    func addMinute() {
        total += 60
        if let pausedRemaining {
            self.pausedRemaining = pausedRemaining + 60
        } else if let endDate {
            self.endDate = endDate.addingTimeInterval(60)
            schedule()
        }
    }

    func togglePause() {
        if let pausedRemaining {
            endDate = Date().addingTimeInterval(pausedRemaining)
            self.pausedRemaining = nil
            schedule()
        } else if endDate != nil {
            pausedRemaining = remaining()
            endDate = nil
            ticker?.invalidate()
        }
    }

    func cancel() {
        ticker?.invalidate()
        endDate = nil
        pausedRemaining = nil
    }

    private func schedule() {
        ticker?.invalidate()
        guard let endDate else { return }
        let timer = Timer(fire: endDate, interval: 0, repeats: false) { [weak self] _ in
            self?.cancel()
            NSSound(named: "Glass")?.play()
            self?.onFinish?()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }
}

/// Front camera preview. Starts only when asked and stops when the island closes.
final class Mirror: ObservableObject {
    let session = AVCaptureSession()
    @Published private(set) var isOn = false
    @Published private(set) var isDenied = false

    private let queue = DispatchQueue(label: "com.kuzminyo.islo.camera")
    private var isConfigured = false

    func toggle() {
        isOn ? stop() : start()
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { granted ? self.run() : (self.isDenied = true) }
            }
        default:
            isDenied = true
        }
    }

    func stop() {
        guard isOn else { return }
        isOn = false
        queue.async { self.session.stopRunning() }
    }

    private func run() {
        isDenied = false
        isOn = true
        queue.async {
            if !self.isConfigured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .medium
                if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                    ?? AVCaptureDevice.default(for: .video),
                   let input = try? AVCaptureDeviceInput(device: camera),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
                self.session.commitConfiguration()
                self.isConfigured = true
            }
            self.session.startRunning()
        }
    }
}

/// Reports keyboard layout switches, e.g. "RU", "Русская".
final class InputSourceWatcher {
    private let onChange: (String, String) -> Void

    init(onChange: @escaping (String, String) -> Void) {
        self.onChange = onChange
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, let current = Self.current() else { return }
            self.onChange(current.code, current.name)
        }
    }

    static func current() -> (code: String, name: String)? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        func property(_ key: CFString) -> AnyObject? {
            guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
            return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
        }
        let name = property(kTISPropertyLocalizedName) as? String ?? ""
        let language = (property(kTISPropertyInputSourceLanguages) as? [String])?.first ?? name
        return (String(language.prefix(2)).uppercased(), name)
    }
}

/// Polls Caps Lock; reading the modifier state needs no special permission.
final class CapsLockWatcher {
    private var isOn = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
    private var timer: Timer?

    init(onChange: @escaping (Bool) -> Void) {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            let on = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
            if on != isOn {
                isOn = on
                onChange(on)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

extension NSImage {
    /// The image's average color, brightened so it reads well on black.
    var vividAverageColor: NSColor? {
        guard let image = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let color = NSColor(
            red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1
        )
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.usingColorSpace(.deviceRGB)?.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        // Grey covers stay white instead of turning a muddy color.
        guard saturation > 0.12 else { return .white }
        return NSColor(hue: hue, saturation: max(saturation, 0.55), brightness: max(brightness, 0.9), alpha: 1)
    }
}
