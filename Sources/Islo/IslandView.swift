import SwiftUI

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var player: NowPlaying

    private var size: CGSize { model.contentSize }
    private var shape: UnevenRoundedRectangle {
        let radius = model.isExpanded ? 26 : min(size.height * 0.35, 12)
        return UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 0, bottomLeading: radius, bottomTrailing: radius, topTrailing: 0),
            style: .continuous
        )
    }

    var body: some View {
        content
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(.black)
            .clipShape(shape)
            .contentShape(shape)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.42, dampingFraction: 0.8), value: size)
            .animation(.easeOut(duration: 0.2), value: model.event)
            .environment(\.colorScheme, .dark)
            .contextMenu {
                Toggle("Запускать при входе", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.launchAtLogin = $0 }
                ))
                Divider()
                Button("Выйти из Islo") { NSApp.terminate(nil) }
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.isExpanded {
            ExpandedView(model: model, player: player)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
        } else if let event = model.event {
            EventView(event: event, notchWidth: model.notch.width)
                .transition(.opacity)
        } else if let track = player.track, track.isPlaying {
            Wings(notchWidth: model.notch.width) {
                Artwork(image: player.artwork, fallback: track.player.icon, size: 22, radius: 6)
            } trailing: {
                EqualizerBars()
            }
            .transition(.opacity)
        }
    }
}

/// Places views on the left and right of the notch.
private struct Wings<Leading: View, Trailing: View>: View {
    let notchWidth: CGFloat
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading.frame(maxWidth: .infinity)
            Color.clear.frame(width: notchWidth)
            trailing.frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)
    }
}

private struct EventView: View {
    let event: IslandEvent
    let notchWidth: CGFloat

    var body: some View {
        Wings(notchWidth: notchWidth) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
        } trailing: {
            switch event {
            case .volume(let volume, let muted):
                Capsule()
                    .fill(.white.opacity(0.2))
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(.white)
                                .frame(width: proxy.size.width * CGFloat(muted ? 0 : volume))
                        }
                    }
                    .frame(width: 56, height: 5)
            case .charging(let level, _):
                Text("\(level)%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }
        }
    }

    private var symbol: String {
        switch event {
        case .volume(let volume, let muted):
            if muted || volume == 0 { return "speaker.slash.fill" }
            return volume < 0.34 ? "speaker.wave.1.fill" : volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        case .charging(_, let isCharging):
            return isCharging ? "bolt.fill" : "battery.75percent"
        }
    }

    private var tint: Color {
        if case .charging(_, true) = event { return .green }
        return .white
    }
}

private struct ExpandedView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var player: NowPlaying

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.notch.height)
            Group {
                if let track = player.track {
                    nowPlaying(track)
                } else {
                    idle
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
            .frame(maxHeight: .infinity)
        }
        .foregroundStyle(.white)
    }

    private func nowPlaying(_ track: Track) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Button { player.openPlayer() } label: {
                    Artwork(image: player.artwork, fallback: track.player.icon, size: 62, radius: 14)
                }
                .buttonStyle(.plain)
                .help("Открыть \(track.player.scriptName)")

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                    Progress(track: track)
                        .padding(.top, 4)
                }
            }
            HStack(spacing: 34) {
                control("backward.fill", size: 17) { player.previous() }
                control(track.isPlaying ? "pause.fill" : "play.fill", size: 25) { player.playPause() }
                control("forward.fill", size: 17) { player.next() }
            }
        }
    }

    private var idle: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date(), format: .dateTime.hour().minute())
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let power = PowerWatcher.read() {
                    Label("\(power.level)%", systemImage: power.isCharging ? "bolt.fill" : "battery.75percent")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(power.isCharging ? .green : .white.opacity(0.8))
                }
                Text("Ничего не играет")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func control(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct Progress: View {
    let track: Track

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let position = track.position(at: context.date)
            let fraction = track.duration > 0 ? position / track.duration : 0
            HStack(spacing: 8) {
                Text(Self.time(position))
                Capsule()
                    .fill(.white.opacity(0.2))
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule().fill(.white).frame(width: proxy.size.width * fraction)
                        }
                    }
                    .frame(height: 4)
                Text(Self.time(track.duration))
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    private static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct Artwork: View {
    let image: NSImage?
    let fallback: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else if let fallback {
                Image(nsImage: fallback).resizable().scaledToFit().padding(size * 0.08)
            } else {
                Image(systemName: "music.note").foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: size, height: size)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Small animated bars that show music is playing.
private struct EqualizerBars: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4) { index in
                    let phase = time * (5 + Double(index) * 1.3) + Double(index)
                    Capsule()
                        .fill(.white)
                        .frame(width: 3, height: 4 + 10 * abs(sin(phase)))
                }
            }
            .frame(height: 14)
        }
    }
}
