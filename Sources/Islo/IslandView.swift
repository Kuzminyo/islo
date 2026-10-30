import SwiftUI
import UniformTypeIdentifiers

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var player: NowPlaying
    @ObservedObject var shelf: Shelf

    private var size: CGSize { model.contentSize }
    private var ear: CGFloat { model.isExpanded ? 12 : 6 }
    private var radius: CGFloat { model.isExpanded ? 30 : min(size.height * 0.35, 12) }

    var body: some View {
        let shape = IslandShape(radius: radius, ear: ear)
        content
            .frame(width: size.width, height: size.height, alignment: .top)
            .padding(.horizontal, ear)
            .background(.black)
            .clipShape(shape)
            .contentShape(shape)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: size)
            .animation(.easeOut(duration: 0.2), value: model.event)
            .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        if model.isExpanded {
            ExpandedView(model: model, player: player, shelf: shelf)
                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
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

/// The island outline: square top that flares into the screen edge ("ears"), rounded bottom.
struct IslandShape: Shape {
    var radius: CGFloat
    var ear: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(radius, ear) }
        set { radius = newValue.first; ear = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(radius, (rect.width - ear * 2) / 2, rect.height / 2)
        let left = rect.minX + ear
        let right = rect.maxX - ear
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.minY + ear), control: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: left + r, y: rect.maxY), control: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: right - r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: right, y: rect.maxY - r), control: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: right, y: rect.minY + ear))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: right, y: rect.minY))
        path.closeSubpath()
        return path
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
    @ObservedObject var shelf: Shelf
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Group {
                switch model.tab {
                case .home: HomeTab(player: player)
                case .shelf: ShelfTab(shelf: shelf, isDropTargeted: isDropTargeted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .frame(maxHeight: .infinity)
        }
        .foregroundStyle(.white)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            model.tab = .shelf
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { shelf.add([url]) }
                }
            }
            return true
        }
        .onChange(of: isDropTargeted) { _, targeted in
            if targeted { model.tab = .shelf }
        }
    }

    /// Tabs on the left of the notch, settings on the right.
    private var topBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(IslandTab.allCases, id: \.self) { tab in
                    Button { model.tab = tab } label: {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(model.tab == tab ? .white : .white.opacity(0.45))
                            .frame(width: 30, height: 22)
                            .background(model.tab == tab ? .white.opacity(0.16) : .clear, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(tab.title)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 16)
            .frame(maxWidth: .infinity)

            Color.clear.frame(width: model.notch.width)

            HStack {
                Spacer(minLength: 0)
                if model.tab == .shelf, !shelf.files.isEmpty {
                    Text("\(shelf.files.count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Menu {
                    Toggle("Запускать при входе", isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.launchAtLogin = $0 }
                    ))
                    Divider()
                    Button("Выйти из Islo") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity)
        }
        .frame(height: max(model.notch.height, 30))
    }
}

/// Player on the left, the week and battery on the right.
private struct HomeTab: View {
    @ObservedObject var player: NowPlaying

    var body: some View {
        HStack(spacing: 18) {
            Group {
                if let track = player.track {
                    nowPlaying(track)
                } else {
                    nothingPlaying
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(width: 1)
                .padding(.vertical, 6)

            WeekView()
                .frame(width: 210)
        }
    }

    private func nowPlaying(_ track: Track) -> some View {
        HStack(spacing: 14) {
            Button { player.openPlayer() } label: {
                Artwork(image: player.artwork, fallback: track.player.icon, size: 78, radius: 16)
            }
            .buttonStyle(.plain)
            .help("Открыть \(track.player.scriptName)")

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                Progress(track: track)
                    .padding(.top, 3)
                HStack(spacing: 22) {
                    control("backward.fill", size: 15) { player.previous() }
                    control(track.isPlaying ? "pause.fill" : "play.fill", size: 21) { player.playPause() }
                    control("forward.fill", size: 15) { player.next() }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            }
        }
    }

    private var nothingPlaying: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(width: 78, height: 78)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.35))
                }
            VStack(alignment: .leading, spacing: 4) {
                Text("Ничего не играет")
                    .font(.system(size: 14, weight: .semibold))
                Text("Включите музыку в Spotify или Музыке")
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
                .frame(width: 32, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Today's date, the current week with today highlighted, and the battery.
private struct WeekView: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            let today = context.date
            let calendar = Calendar.current
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
            let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(today, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(today, format: .dateTime.hour().minute())
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { day in
                        let isToday = calendar.isDate(day, inSameDayAs: today)
                        VStack(spacing: 4) {
                            Text(day, format: .dateTime.weekday(.narrow))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                            Text(day, format: .dateTime.day())
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .frame(width: 26, height: 26)
                                .background(isToday ? Color.accentColor : .clear, in: Circle())
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                if let power = PowerWatcher.read() {
                    Label("\(power.level)%\(power.isCharging ? " · заряжается" : "")",
                          systemImage: power.isCharging ? "bolt.fill" : "battery.75percent")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(power.isCharging ? .green : .white.opacity(0.6))
                }
            }
        }
    }
}

/// Files dropped on the island, ready to be dragged out again or sent over AirDrop.
private struct ShelfTab: View {
    @ObservedObject var shelf: Shelf
    let isDropTargeted: Bool

    var body: some View {
        if shelf.files.isEmpty {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(.white.opacity(isDropTargeted ? 0.7 : 0.25))
                .background(isDropTargeted ? Color.accentColor.opacity(0.15) : .clear,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 22))
                        Text("Перетащите файлы сюда")
                            .font(.system(size: 13, weight: .medium))
                        Text("Они подождут здесь, пока не понадобятся")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .foregroundStyle(.white.opacity(0.8))
                }
        } else {
            HStack(spacing: 12) {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(shelf.files, id: \.self) { url in
                            ShelfItem(url: url, shelf: shelf)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.never)
                .overlay {
                    if isDropTargeted {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }

                VStack(spacing: 8) {
                    shelfButton("AirDrop", symbol: "airplayaudio") { shelf.airDrop() }
                    shelfButton("Очистить", symbol: "xmark") { shelf.clear() }
                }
                .frame(width: 92)
            }
        }
    }

    private func shelfButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ShelfItem: View {
    let url: URL
    let shelf: Shelf
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 46, height: 46)
            Text(url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 72)
        }
        .padding(6)
        .background(.white.opacity(isHovered ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button { shelf.remove(url) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .onHover { isHovered = $0 }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .contextMenu {
            Button("Открыть") { NSWorkspace.shared.open(url) }
            Button("Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button("Убрать с полки") { shelf.remove(url) }
        }
        .help(url.path)
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
