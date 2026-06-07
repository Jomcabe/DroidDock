import SwiftUI
import UniformTypeIdentifiers

/// The premium borderless main window: a translucent title overlay, the docked
/// mirror area, drag-and-drop transfer, and a collapsible log console.
struct ContentView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var prefs: Preferences

    @State private var showLogs = false
    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 0) {
                titleBar
                MirrorContainerView()
                    .overlay { if isDropTargeted { dropHighlight } }
                if showLogs {
                    LogConsoleView()
                        .frame(height: 168)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(
            WindowAccessor { window in
                app.attachHostWindow(window)
                configure(window)
            }
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            loadDroppedURLs(from: providers)
            return true
        }
        .frame(minWidth: 480, minHeight: 760)
    }

    // MARK: Title bar

    private var titleBar: some View {
        HStack(spacing: 12) {
            Label {
                Text("DroidDock").font(.headline)
            } icon: {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .foregroundStyle(.tint)
            }

            if app.devices.count > 1 {
                devicePicker
            }

            Spacer(minLength: 12)

            ConnectionStatusView()

            controlButtons
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var devicePicker: some View {
        Picker("Device", selection: Binding(
            get: { app.selectedSerial ?? "" },
            set: { app.selectedSerial = $0.isEmpty ? nil : $0 }
        )) {
            ForEach(app.devices) { device in
                Text(device.displayName).tag(device.serial)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 180)
    }

    private var controlButtons: some View {
        HStack(spacing: 8) {
            iconButton("rectangle.on.rectangle", help: "Toggle Control HUD",
                       active: app.hudVisible) { app.toggleHUD() }
            iconButton("text.alignleft", help: "Toggle Logs", active: showLogs) {
                withAnimation(.spring(response: 0.3)) { showLogs.toggle() }
            }
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button(action: { app.toggleMirror() }) {
                Label(app.isMirroring ? "Stop" : "Mirror",
                      systemImage: app.isMirroring ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(app.isMirroring ? .red : .accentColor)
            .disabled(!(app.selectedDevice?.state.isReady ?? false))
        }
        .font(.system(size: 14))
    }

    private func iconButton(_ symbol: String, help: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 26, height: 24)
                .background(active ? Color.accentColor.opacity(0.25) : .clear,
                            in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Background / overlays

    private var backgroundLayer: some View {
        LinearGradient(
            colors: [Color(red: 0.07, green: 0.08, blue: 0.10),
                     Color(red: 0.03, green: 0.04, blue: 0.05)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
            .foregroundStyle(.tint)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.app").font(.largeTitle)
                    Text("Drop an .apk to install · any file to push")
                        .font(.callout).bold()
                }
                .foregroundStyle(.tint)
            }
            .padding(16)
    }

    // MARK: Window chrome

    private func configure(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(calibratedWhite: 0.05, alpha: 1.0)
        window.minSize = NSSize(width: 480, height: 760)
    }

    // MARK: Drag & drop

    private func loadDroppedURLs(from providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        let lock = NSLock()
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL {
                    lock.lock(); urls.append(url); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { app.handleDroppedFiles(urls) }
        }
    }
}

/// Compact, auto-scrolling view of the in-app log ring buffer.
struct LogConsoleView: View {
    @EnvironmentObject private var log: AppLog

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Logs").font(.caption).bold().foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { log.clear() }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(log.entries) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: entry.level.symbol)
                                    .font(.system(size: 9))
                                    .foregroundStyle(color(for: entry.level))
                                Text(entry.message)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                Spacer(minLength: 0)
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                }
                .onChange(of: log.entries.count) { _, _ in
                    if let last = log.entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .background(.black.opacity(0.35))
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .debug:   return .secondary
        case .info:    return .blue
        case .warning: return .orange
        case .error:   return .red
        }
    }
}
