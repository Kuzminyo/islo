import AppKit
import SwiftUI

enum Player: String, CaseIterable {
    case spotify = "com.spotify.client"
    case music = "com.apple.Music"

    var scriptName: String { self == .spotify ? "Spotify" : "Music" }

    /// Posted by the player whenever the track or play state changes.
    var notification: Notification.Name {
        Notification.Name(self == .spotify ? "com.spotify.client.PlaybackStateChanged" : "com.apple.Music.playerInfo")
    }

    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).isEmpty }

    var icon: NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

struct Track: Equatable {
    var player: Player
    var title: String
    var artist: String
    var duration: Double
    var position: Double
    var positionDate: Date
    var isPlaying: Bool
    var artworkURL: URL?

    /// Current position, counting time since the player last reported it.
    func position(at date: Date) -> Double {
        let elapsed = isPlaying ? date.timeIntervalSince(positionDate) : 0
        return min(position + elapsed, duration > 0 ? duration : .infinity)
    }
}

/// What Spotify or Music is playing. Listens to the players' own notifications and asks them
/// for details over AppleScript (macOS asks once for permission to control each player).
final class NowPlaying: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    /// Color taken from the artwork, used to tint the equalizer and progress bar.
    @Published private(set) var accent: Color = .white

    private let scriptQueue = DispatchQueue(label: "com.kuzminyo.islo.applescript")
    private var artworkURL: URL?

    init() {
        for player in Player.allCases {
            DistributedNotificationCenter.default().addObserver(
                forName: player.notification, object: nil, queue: .main
            ) { [weak self] note in
                self?.handle(note, from: player)
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == self?.track?.player.rawValue { self?.setTrack(nil) }
        }
        for player in Player.allCases where player.isRunning {
            refresh(player)
        }
    }

    // MARK: - Controls

    func playPause() { send("playpause") }
    func next() { send("next track") }
    func previous() { send("previous track") }

    func openPlayer() {
        guard let player = track?.player,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.rawValue) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func send(_ command: String) {
        guard let player = track?.player ?? Player.allCases.first(where: \.isRunning) else { return }
        if command == "playpause", var current = track {
            // Update right away; the player's notification confirms it a moment later.
            current.position = current.position(at: Date())
            current.positionDate = Date()
            current.isPlaying.toggle()
            setTrack(current)
        }
        scriptQueue.async {
            Self.run("tell application \"\(player.scriptName)\" to \(command)")
        }
    }

    // MARK: - Updates

    private func handle(_ note: Notification, from player: Player) {
        let info = note.userInfo ?? [:]
        let state = info["Player State"] as? String
        if state == "Stopped" {
            if track?.player == player { setTrack(nil) }
            return
        }
        // Fill in from the notification first, so the island reacts even without AppleScript access.
        if let title = info["Name"] as? String {
            let duration = (info["Duration"] as? Double ?? info["Total Time"] as? Double ?? 0) / 1000
            var track = Track(
                player: player,
                title: title,
                artist: info["Artist"] as? String ?? "",
                duration: duration,
                position: info["Playback Position"] as? Double ?? 0,
                positionDate: Date(),
                isPlaying: state == "Playing",
                artworkURL: self.track?.title == title ? self.track?.artworkURL : nil
            )
            if let current = self.track, current.title == title, info["Playback Position"] == nil {
                track.position = current.position(at: Date())
            }
            setTrack(track)
        }
        refresh(player)
    }

    /// Asks the player for the full state, including position and artwork.
    private func refresh(_ player: Player) {
        guard player.isRunning else { return }
        let script = player == .spotify ? Self.spotifyScript : Self.musicScript
        scriptQueue.async { [weak self] in
            guard let output = Self.run(script) else { return }
            let track = Self.parse(output, player: player)
            DispatchQueue.main.async {
                guard let self else { return }
                if let track {
                    // Don't let a paused player replace the one that is playing.
                    if let current = self.track, current.player != player, current.isPlaying, !track.isPlaying { return }
                    self.setTrack(track)
                } else if self.track?.player == player {
                    self.setTrack(nil)
                }
            }
        }
    }

    private func setTrack(_ newTrack: Track?) {
        if track != newTrack { track = newTrack }
        let url = newTrack?.artworkURL
        guard url != artworkURL else { return }
        artworkURL = url
        artwork = nil
        accent = .white
        guard let url else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                guard let self, self.artworkURL == url else { return }
                self.artwork = image
                self.accent = Color(nsColor: image.vividAverageColor ?? .white)
            }
        }.resume()
    }

    // MARK: - AppleScript

    private static let spotifyScript = """
    tell application "Spotify"
        if player state is stopped then return "stopped"
        set t to current track
        return (player state as text) & linefeed & (name of t) & linefeed & (artist of t) & linefeed & ((duration of t) / 1000 as text) & linefeed & (player position as text) & linefeed & (artwork url of t)
    end tell
    """

    private static let musicScript = """
    tell application "Music"
        if player state is stopped then return "stopped"
        set t to current track
        return (player state as text) & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (duration of t as text) & linefeed & (player position as text) & linefeed & ""
    end tell
    """

    @discardableResult
    private static func run(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("Islo: AppleScript error %@", error) }
        return result?.stringValue
    }

    private static func parse(_ output: String, player: Player) -> Track? {
        let lines = output.components(separatedBy: "\n")
        guard lines.count >= 5, lines[0] != "stopped" else { return nil }
        // AppleScript formats numbers with the system decimal separator.
        func number(_ text: String) -> Double { Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        return Track(
            player: player,
            title: lines[1],
            artist: lines[2],
            duration: number(lines[3]),
            position: number(lines[4]),
            positionDate: Date(),
            isPlaying: lines[0] == "playing",
            artworkURL: lines.count > 5 ? URL(string: lines[5]) : nil
        )
    }
}
