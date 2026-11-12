import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var player: NowPlaying
    @ObservedObject var shelf: Shelf

    private var size: CGSize { model.contentSize }
    // The sides curve outward right at the top edge of the display, so the island pours out of
    // it like a drop; a little wider when open.
    private var earWidth: CGFloat { model.isExpanded ? 14 : 8 }
    private var earHeight: CGFloat { model.isExpanded ? 12 : 8 }
    private var flareTop: CGFloat { 0 }
    private var radius: CGFloat { model.isExpanded ? 34 : min(size.height * 0.42, 15) }

    /// Nothing to show: draw nothing, so only the real notch is visible. A black shape the size
    /// of the notch never lines up exactly with the hardware and leaves a thin outline around it.
    private var isHidden: Bool { !model.isExpanded && model.compact == .none }

    var body: some View {
        let shape = IslandShape(radius: radius, earWidth: earWidth, earHeight: earHeight, flareTop: flareTop)
        content
            .frame(width: size.width, height: size.height, alignment: .top)
            .padding(.horizontal, earWidth)
            .background(.black.opacity(isHidden ? 0 : 1))
            .clipShape(shape)
            .contentShape(shape)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // A little bounce when the island grows or shrinks, like the iPhone's.
            .animation(.spring(response: 0.46, dampingFraction: 0.74), value: size)
            .animation(.smooth(duration: 0.25), value: model.compact)
            .animation(.smooth(duration: 0.2), value: isHidden)
            .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        if model.isExpanded {
            ExpandedView(model: model, player: player, shelf: shelf)
                .transition(.blurFade)
        } else {
            switch model.compact {
            case .event(let event):
                EventView(event: event, notchWidth: model.notch.width)
                    .transition(.blurFade)
            case .timer:
                Wings(notchWidth: model.notch.width) {
                    Image(systemName: model.timer.isPaused ? "pause.fill" : "timer")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.orange)
                } trailing: {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(clock(model.timer.remaining(at: context.date)))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                    }
                }
                .transition(.blurFade)
            case .music:
                if let track = player.track {
                    Wings(notchWidth: model.notch.width) {
                        Artwork(image: player.artwork, fallback: track.player.icon, size: 22, radius: 6)
                    } trailing: {
                        EqualizerBars(tint: player.accent)
                    }
                    .transition(.blurFade)
                }
            case .eyes:
                let wing = IslandModel.eyesWingWidth
                let y = model.notch.screenFrame.maxY - size.height / 2
                Wings(notchWidth: model.notch.width) {
                    Eye(center: CGPoint(x: model.notch.rect.minX - wing / 2, y: y))
                } trailing: {
                    Eye(center: CGPoint(x: model.notch.rect.maxX + wing / 2, y: y))
                }
                .transition(.blurFade)
            case .none:
                EmptyView()
            }
        }
    }
}

/// The island outline: the top flares out into the screen edge ("ears"), the bottom is rounded.
struct IslandShape: Shape {
    var radius: CGFloat
    /// How far the flare runs along the top edge, and how far down the side it starts.
    var earWidth: CGFloat
    var earHeight: CGFloat
    /// Where the flares start: 0 for the screen edge, or the bottom of the menu bar. Above it the
    /// shape runs at full width, so it blends into a dark menu bar.
    var flareTop: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get { AnimatablePair(radius, AnimatablePair(earWidth, AnimatablePair(earHeight, flareTop))) }
        set {
            radius = newValue.first
            earWidth = newValue.second.first
            earHeight = newValue.second.second.first
            flareTop = newValue.second.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        // Corners are spread over 1.3× the radius with handles near the corner, which reads as a
        // smooth, continuous curve rather than a quarter circle glued to a straight edge.
        let spread: CGFloat = 1.3
        let left = rect.minX + earWidth
        let right = rect.maxX - earWidth
        let r = min(radius, (right - left) / (2 * spread), rect.height / (2 * spread))
        let flareY = rect.minY + flareTop
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: flareY))
        // Flare: a round fillet from the horizontal edge down into the side.
        path.addCurve(
            to: CGPoint(x: left, y: flareY + earHeight),
            control1: CGPoint(x: rect.minX + earWidth * 0.55, y: flareY),
            control2: CGPoint(x: left, y: flareY + earHeight * 0.45)
        )
        path.addLine(to: CGPoint(x: left, y: rect.maxY - r * spread))
        path.addCurve(
            to: CGPoint(x: left + r * spread, y: rect.maxY),
            control1: CGPoint(x: left, y: rect.maxY - r * 0.42),
            control2: CGPoint(x: left + r * 0.42, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: right - r * spread, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: right, y: rect.maxY - r * spread),
            control1: CGPoint(x: right - r * 0.42, y: rect.maxY),
            control2: CGPoint(x: right, y: rect.maxY - r * 0.42)
        )
        path.addLine(to: CGPoint(x: right, y: flareY + earHeight))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: flareY),
            control1: CGPoint(x: right, y: flareY + earHeight * 0.45),
            control2: CGPoint(x: rect.maxX - earWidth * 0.55, y: flareY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Content fades in from a soft blur, the way the island's own content appears on iPhone.
private struct BlurFade: ViewModifier {
    let amount: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: amount * 10)
            .opacity(1 - amount)
            .scaleEffect(1 - amount * 0.05, anchor: .top)
    }
}

extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(active: BlurFade(amount: 1), identity: BlurFade(amount: 0))
    }
}

/// Buttons sink a little while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
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
                let level = CGFloat(muted ? 0 : volume)
                HStack(spacing: 6) {
                    Capsule()
                        .fill(.white.opacity(0.2))
                        .overlay(alignment: .leading) {
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(.white)
                                    .frame(width: proxy.size.width * level)
                            }
                        }
                        .frame(width: 46, height: 5)
                    Text("\(Int((level * 100).rounded()))")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(level)))
                        .frame(width: 22, alignment: .trailing)
                }
                // Glide between volume steps instead of jumping.
                .animation(.spring(response: 0.28, dampingFraction: 0.9), value: level)
            case .charging(let level, _):
                Text("\(level)%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            case .inputSource(let code):
                Text(code)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            case .capsLock(let isOn):
                Text(isOn ? "Caps" : "caps")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(isOn ? .green : .white.opacity(0.6))
            case .output(let name, _):
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .padding(.trailing, 8)
            case .timerDone:
                Text("Готово")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
            case .colorCopied(let hex):
                Text(hex)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
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
        case .inputSource:
            return "keyboard"
        case .capsLock(let isOn):
            return isOn ? "capslock.fill" : "capslock"
        case .output(_, let isHeadphones):
            return isHeadphones ? "headphones" : "hifispeaker.fill"
        case .timerDone:
            return "bell.fill"
        case .colorCopied:
            return "circle.fill"
        }
    }

    private var tint: Color {
        switch event {
        case .charging(_, true), .capsLock(true): .green
        case .timerDone: .orange
        case .colorCopied(let hex): Color(hex: hex)
        default: .white
        }
    }
}

private struct ExpandedView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var player: NowPlaying
    @ObservedObject var shelf: Shelf
    @State private var isDropTargeted = false
    @Namespace private var tabHighlight

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Group {
                switch model.tab {
                case .home: HomeTab(player: player, model: model)
                case .tasks: TasksTab(tasks: model.tasks)
                case .tools: ToolsTab(timer: model.timer, mirror: model.mirror)
                case .actions: ActionsTab(actions: model.actions)
                case .shelf: ShelfTab(shelf: shelf, isDropTargeted: isDropTargeted)
                }
            }
            .id(model.tab)
            .transition(.blurFade)
            .animation(.smooth(duration: 0.28), value: model.tab)
            .padding(.horizontal, 12)
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
            HStack(spacing: 0) {
                ForEach(model.visibleTabs, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { model.tab = tab }
                    } label: {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(model.tab == tab ? .white : .white.opacity(0.45))
                            .frame(width: 21, height: 22)
                            .background {
                                if model.tab == tab {
                                    Capsule()
                                        .fill(.white.opacity(0.16))
                                        .matchedGeometryEffect(id: "tab", in: tabHighlight)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                    .help(tab.title)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 4)
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
                    Menu("Показывать у выреза") {
                        ForEach(Indicator.allCases, id: \.self) { indicator in
                            Toggle(indicator.title, isOn: Binding(
                                get: { model.shows(indicator) },
                                set: { model.setIndicator(indicator, visible: $0) }
                            ))
                        }
                        Divider()
                        Toggle("Глазки 👀", isOn: $model.showsEyes)
                    }
                    Picker("Высота у выреза", selection: $model.heightAdjust) {
                        ForEach(IslandModel.heightAdjustments, id: \.self) { value in
                            Text(value == 0 ? "Как вырез (по macOS)" : value < 0 ? "Короче на \(Int(-value)) пт" : "Длиннее на \(Int(value)) пт")
                                .tag(value)
                        }
                    }
                    Menu("Вкладки") {
                        ForEach(IslandTab.allCases.filter { $0 != .home }, id: \.self) { tab in
                            Toggle(tab.title, isOn: Binding(
                                get: { !model.hiddenTabs.contains(tab) },
                                set: { model.setTab(tab, visible: $0) }
                            ))
                        }
                    }
                    Divider()
                    Toggle("Запускать при входе", isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.launchAtLogin = $0 }
                    ))
                    Divider()
                    Button("Выйти из Islo") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity)
        }
        .frame(height: max(model.notch.height, 30))
    }
}

/// The player across the whole island.
private struct HomeTab: View {
    @ObservedObject var player: NowPlaying
    @ObservedObject var model: IslandModel

    var body: some View {
        Group {
            if let track = player.track {
                nowPlaying(track)
                    .transition(.blurFade)
            } else {
                nothingPlaying
                    .transition(.blurFade)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.3), value: player.track == nil)
    }

    private func nowPlaying(_ track: Track) -> some View {
        HStack(spacing: 14) {
            Button { player.openPlayer() } label: {
                Artwork(image: player.artwork, fallback: track.player.icon, size: 80, radius: 20)
                    .shadow(color: player.accent.opacity(0.35), radius: 16, y: 4)
                    .id(track.title)
                    .transition(.blurFade)
            }
            .buttonStyle(.pressable)
            .help("Открыть \(track.player.displayName)")

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(track.title)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(track.player.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.08), in: Capsule())
                }
                HStack(spacing: 10) {
                    Text(track.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    // The player's own volume when it reports one, otherwise the Mac's.
                    VolumeSlider(value: player.appVolume.map(Float.init) ?? model.volume, tint: player.accent) { value in
                        if player.appVolume != nil {
                            player.setAppVolume(Double(value))
                        } else {
                            model.setVolume(value)
                        }
                    }
                    .frame(width: 86)
                }
                Progress(track: track, tint: player.accent) { player.seek(to: $0) }
                    .padding(.top, 8)
                HStack(spacing: 14) {
                    control("backward.fill", size: 17) { player.previous() }
                    control(track.isPlaying ? "pause.fill" : "play.fill", size: 26) { player.playPause() }
                    control("forward.fill", size: 17) { player.next() }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
            .animation(.smooth(duration: 0.3), value: track.title)
        }
    }

    private var nothingPlaying: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
            Text("Ничего не играет")
                .font(.system(size: 15, weight: .semibold))
            if player.chromeNeedsJavaScript {
                Text("Чтобы видеть музыку из Chrome, включите в нём: Вид → Разработчик → «Разрешить JavaScript из Apple Events»")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Включите музыку в Spotify, Музыке или на сайте в Chrome")
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
                .frame(width: 40, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
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
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
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
                .buttonStyle(.pressable)
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

/// System volume: speaker icon and a bar to click or drag, in the artwork's color.
private struct VolumeSlider: View {
    let value: Float
    var tint: Color = .white
    let onChange: (Float) -> Void

    @State private var dragValue: Float?
    @State private var isHovered = false

    var body: some View {
        let shown = dragValue ?? value
        let isActive = isHovered || dragValue != nil
        HStack(spacing: 7) {
            Image(systemName: shown == 0 ? "speaker.slash.fill" : shown < 0.34 ? "speaker.wave.1.fill" : shown < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 18)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(tint).frame(width: proxy.size.width * CGFloat(shown))
                }
                .frame(height: isActive ? 7 : 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let new = Float(min(max(drag.location.x / proxy.size.width, 0), 1))
                            dragValue = new
                            onChange(new)
                        }
                        .onEnded { _ in dragValue = nil }
                )
            }
            .frame(height: 14)
            .onHover { isHovered = $0 }
            .animation(.snappy(duration: 0.15), value: isActive)
        }
    }
}

/// Track progress you can click or drag to seek.
private struct Progress: View {
    let track: Track
    var tint: Color = .white
    var onSeek: ((Double) -> Void)?

    /// Where the bar is being dragged to, 0…1; nil when not dragging.
    @State private var dragFraction: Double?
    @State private var isHovered = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let playing = track.duration > 0 ? track.position(at: context.date) / track.duration : 0
            let fraction = min(max(dragFraction ?? playing, 0), 1)
            let isActive = isHovered || dragFraction != nil
            HStack(spacing: 8) {
                Text(Self.time(fraction * track.duration))
                    .frame(minWidth: 28, alignment: .leading)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule().fill(tint).frame(width: proxy.size.width * fraction)
                    }
                    .frame(height: isActive ? 7 : 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                dragFraction = min(max(value.location.x / proxy.size.width, 0), 1)
                            }
                            .onEnded { value in
                                let target = min(max(value.location.x / proxy.size.width, 0), 1)
                                onSeek?(target * track.duration)
                                dragFraction = nil
                            }
                    )
                }
                .frame(height: 14)
                .onHover { isHovered = $0 }
                .animation(.snappy(duration: 0.15), value: isActive)
                Text(Self.time(track.duration))
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(dragFraction == nil ? 0.6 : 0.9))
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
        .background(.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Small animated bars that show music is playing.
/// Bars that rise and fall like a music visualizer, redrawn every display frame.
/// Each bar mixes a few slow waves with its own speeds, so the motion looks organic
/// instead of a bouncing sine.
private struct EqualizerBars: View {
    var tint: Color = .white

    private static let bars: [(speeds: (Double, Double, Double), offset: Double)] = [
        ((1.9, 3.1, 0.7), 0.0),
        ((2.6, 1.7, 1.1), 1.3),
        ((3.3, 2.2, 0.5), 2.1),
        ((2.1, 3.7, 0.9), 0.6),
        ((2.8, 1.4, 1.3), 1.8),
    ]

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(Self.bars.indices, id: \.self) { index in
                    let bar = Self.bars[index]
                    let wave = sin(time * bar.speeds.0 + bar.offset) * 0.5
                        + sin(time * bar.speeds.1 + bar.offset * 2) * 0.3
                        + sin(time * bar.speeds.2 + bar.offset * 3) * 0.2
                    // -1…1 → 0…1, eased so bars linger near the top and bottom like real levels.
                    let level = (1 - cos((wave + 1) / 2 * .pi)) / 2
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: 2.5, height: 3 + 12 * level)
                }
            }
            .frame(height: 15)
        }
    }
}

/// Formats seconds as m:ss or h:mm:ss.
private func clock(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded(.up))
    let hours = total / 3600, minutes = total % 3600 / 60, secs = total % 60
    return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
}

/// A googly eye that follows the pointer and blinks now and then.
private struct Eye: View {
    /// Eye position on screen, to aim the pupil at the pointer.
    let center: CGPoint

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let mouse = NSEvent.mouseLocation
            let dx = mouse.x - center.x, dy = mouse.y - center.y
            let distance = max(hypot(dx, dy), 1)
            let reach = 3.2 * min(distance / 60, 1)
            // Blink for a moment every few seconds; the two eyes share the clock, so they blink together.
            let isBlinking = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4.7) < 0.13
            ZStack {
                Circle().fill(.white)
                Circle()
                    .fill(.black)
                    .frame(width: 6.5, height: 6.5)
                    .offset(x: dx / distance * reach, y: -dy / distance * reach)
            }
            .frame(width: 15, height: 15)
            .scaleEffect(x: 1, y: isBlinking ? 0.1 : 1)
        }
    }
}

/// Timer on the left, camera mirror on the right.
private struct ToolsTab: View {
    @ObservedObject var timer: CountdownTimer
    let mirror: Mirror

    var body: some View {
        HStack(spacing: 18) {
            TimerPanel(timer: timer)
                .frame(maxWidth: .infinity)
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(width: 1)
                .padding(.vertical, 6)
            MirrorPanel(mirror: mirror)
                .frame(width: 130)
        }
    }
}

private struct TimerPanel: View {
    @ObservedObject var timer: CountdownTimer

    var body: some View {
        if timer.isActive {
            VStack(spacing: 10) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = timer.remaining(at: context.date)
                    VStack(spacing: 6) {
                        Text(clock(remaining))
                            .font(.system(size: 38, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                        Capsule()
                            .fill(.white.opacity(0.15))
                            .overlay(alignment: .leading) {
                                GeometryReader { proxy in
                                    Capsule()
                                        .fill(.orange)
                                        .frame(width: proxy.size.width * (timer.total > 0 ? remaining / timer.total : 0))
                                }
                            }
                            .frame(height: 4)
                    }
                }
                HStack(spacing: 8) {
                    pill(timer.isPaused ? "Дальше" : "Пауза", symbol: timer.isPaused ? "play.fill" : "pause.fill") { timer.togglePause() }
                    pill("+1 мин", symbol: "plus") { timer.addMinute() }
                    pill("Стоп", symbol: "xmark") { timer.cancel() }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Таймер", systemImage: "timer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(CountdownTimer.presets, id: \.self) { minutes in
                        Button { timer.start(minutes: minutes) } label: {
                            Text("\(minutes) мин")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 30)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
        }
    }

    private func pill(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(minHeight: 26)
                .background(.white.opacity(0.08), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }
}

private struct MirrorPanel: View {
    @ObservedObject var mirror: Mirror

    var body: some View {
        Button { mirror.toggle() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.05))
                if mirror.isOn {
                    CameraPreview(layer: mirror.previewLayer)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: mirror.isDenied ? "video.slash.fill" : "camera.fill")
                            .font(.system(size: 20))
                        Text(mirror.isDenied ? "Нет доступа к камере" : "Зеркало")
                            .font(.system(size: 12, weight: .semibold))
                        Text(mirror.isDenied ? "Разрешите в настройках" : "Нажмите, чтобы включить")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .foregroundStyle(.white.opacity(0.8))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .help(mirror.isOn ? "Выключить камеру" : "Включить камеру")
        .onDisappear { mirror.stop() }
    }
}

/// Shows the mirror's camera layer, which outlives this view.
private struct CameraPreview: NSViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        layer.removeFromSuperlayer()
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(layer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        layer.frame = nsView.bounds
    }
}

extension Color {
    /// "#RRGGBB" → Color.
    init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xFFFFFF
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// To-do list: type and press Return to add, click the circle to tick, × to remove.
private struct TasksTab: View {
    @ObservedObject var tasks: TaskList
    @State private var draft = ""
    @FocusState private var isTyping: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.5))
                    TextField("Новая задача", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($isTyping)
                        .onSubmit {
                            tasks.add(draft)
                            draft = ""
                            isTyping = true
                        }
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                if !tasks.items.isEmpty {
                    let done = tasks.doneCount
                    Text("Выполнено \(done) из \(tasks.items.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    if done > 0 {
                        Button("Убрать выполненные") { withAnimation { tasks.removeDone() } }
                            .buttonStyle(.pressable)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .frame(width: 170)

            if tasks.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .font(.system(size: 22))
                    Text("Задач нет")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Напишите задачу слева и нажмите ↩")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(tasks.items) { item in
                            TaskRow(item: item, tasks: tasks)
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct TaskRow: View {
    let item: TaskItem
    let tasks: TaskList
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Button { withAnimation(.snappy) { tasks.toggle(item) } } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(item.isDone ? Color.green : .white.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.pressable)

            Text(item.title)
                .font(.system(size: 13))
                .strikethrough(item.isDone, color: .white.opacity(0.5))
                .foregroundStyle(item.isDone ? .white.opacity(0.4) : .white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isHovered {
                Button { withAnimation(.snappy) { tasks.remove(item) } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 20, height: 20)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.pressable)
                .help("Удалить")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(.white.opacity(isHovered ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovered = $0 }
    }
}

/// Grid of one-click system actions.
private struct ActionsTab: View {
    @ObservedObject var actions: QuickActions

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            tile("Не спать", symbol: "cup.and.saucer.fill", isOn: actions.isKeepingAwake) { actions.toggleKeepAwake() }
            tile(actions.isDarkMode ? "Светлая тема" : "Тёмная тема",
                 symbol: actions.isDarkMode ? "sun.max.fill" : "moon.fill", isOn: false) { actions.toggleDarkMode() }
            tile("Пипетка", symbol: "eyedropper.halffull", isOn: false) { actions.pickColor() }
            tile("Скриншот", symbol: "camera.viewfinder", isOn: false) { actions.screenshot() }
            tile("Выкл. экран", symbol: "display", isOn: false) { actions.sleepDisplay() }
            tile("Скрыть окна", symbol: "macwindow.on.rectangle", isOn: false) { actions.hideAllApps() }
        }
    }

    private func tile(_ title: String, symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(isOn ? Color.orange : .white.opacity(0.08), in: Circle())
                // Two short lines rather than a cut-off label on the narrow island.
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 46)
            .background(.white.opacity(isOn ? 0.12 : 0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }
}
