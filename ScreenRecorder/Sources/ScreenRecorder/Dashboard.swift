import AVFoundation
import AVKit
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Library items

struct Screenshot: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let created: Date
    let bytes: Int
    var sizeText: String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }
}

enum LibrarySection: String, CaseIterable, Identifiable {
    case recordings, polished, screenshots
    var id: String { rawValue }
    var label: String {
        switch self {
        case .recordings: return "Recordings"
        case .polished: return "Polished"
        case .screenshots: return "Screenshots"
        }
    }
    var symbol: String {
        switch self {
        case .recordings: return "record.circle"
        case .polished: return "wand.and.stars"
        case .screenshots: return "camera"
        }
    }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case newest, oldest, longest, largest, name
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Facts about a recording derived from its telemetry sidecar.
struct TelemetryStats {
    let samples: Int
    let clicks: Int
    /// Total cursor travel in frame pixels.
    let distance: Double
    /// Fraction of 0.5 s windows in which the cursor moved.
    let activeFraction: Double

    static func load(_ url: URL) -> TelemetryStats? {
        guard let side = try? TelemetrySidecar.load(from: url), !side.samples.isEmpty else { return nil }
        var distance = 0.0
        var activeWindows = Set<Int>()
        var prev = side.samples[0]
        for s in side.samples.dropFirst() {
            let d = hypot(s.x - prev.x, s.y - prev.y)
            distance += d
            if d > 2 { activeWindows.insert(Int(s.t / 0.5)) }
            prev = s
        }
        let windows = max(1, Int(ceil((side.samples.last?.t ?? 0) / 0.5)))
        return TelemetryStats(
            samples: side.samples.count, clicks: side.samples.filter(\.click).count,
            distance: distance, activeFraction: Double(activeWindows.count) / Double(windows))
    }
}

// MARK: - Model

@MainActor
final class DashboardModel: ObservableObject {
    @Published var recordings: [Recording] = []
    @Published var screenshots: [Screenshot] = []
    @Published var thumbnails: [URL: NSImage] = [:]
    @Published var polishing: Set<URL> = []
    @Published var polishProgress: [URL: Double] = [:]
    @Published var message: String?

    // Navigation and selection
    @Published var section: LibrarySection = .recordings
    @Published var query = ""
    @Published var sort: SortOrder = .newest
    @Published var grid = false
    @Published var selection: Set<URL> = []
    @Published var stats: [URL: TelemetryStats] = [:]
    @Published var resolution: [URL: CGSize] = [:]

    // Player
    @Published var playing: Recording?
    @Published var playingPolished = false
    @Published var player: AVPlayer?

    // Trim
    @Published var trimming: Recording?
    @Published var trimStart: Double = 0
    @Published var trimEnd: Double = 0
    @Published var trimPlayer: AVPlayer?
    @Published var trimBusy = false
    @Published var trimRemove = false

    /// What the current section, search and sort produce.
    var visibleRecordings: [Recording] {
        var list = recordings
        if section == .polished { list = list.filter(\.isPolished) }
        if !query.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(query) } }
        switch sort {
        case .newest: list.sort { $0.created > $1.created }
        case .oldest: list.sort { $0.created < $1.created }
        case .longest: list.sort { ($0.duration ?? 0) > ($1.duration ?? 0) }
        case .largest: list.sort { $0.bytes > $1.bytes }
        case .name: list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return list
    }

    var visibleScreenshots: [Screenshot] {
        var list = screenshots
        if !query.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(query) } }
        switch sort {
        case .oldest: list.sort { $0.created < $1.created }
        case .largest: list.sort { $0.bytes > $1.bytes }
        case .name: list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        default: list.sort { $0.created > $1.created }
        }
        return list
    }

    var selectedRecording: Recording? {
        guard selection.count == 1, let url = selection.first else { return nil }
        return recordings.first { $0.url == url }
    }

    var selectedScreenshot: Screenshot? {
        guard selection.count == 1, let url = selection.first else { return nil }
        return screenshots.first { $0.url == url }
    }

    var totalBytes: Int { recordings.reduce(0) { $0 + $1.bytes } + screenshots.reduce(0) { $0 + $1.bytes } }

    func reload() {
        recordings = RecordingsStore.scan()
        screenshots = RecordingsStore.scanScreenshots()
        let known = Set(recordings.map(\.url)).union(screenshots.map(\.url))
        selection = selection.intersection(known)
        for recording in recordings { loadDetails(for: recording) }
        for shot in screenshots where thumbnails[shot.url] == nil {
            let url = shot.url
            Task { [weak self] in
                guard let t = await RecordingsStore.imageThumbnail(url) else { return }
                self?.thumbnails[url] = t.image
                self?.resolution[url] = t.size
            }
        }
    }

    private func loadDetails(for recording: Recording) {
        let url = recording.url
        Task { [weak self] in
            let seconds = await RecordingsStore.duration(of: url)
            let playable = await RecordingsStore.isPlayable(url)
            let image = playable ? await RecordingsStore.thumbnail(for: url) : nil
            let size = playable ? await RecordingsStore.resolution(of: url) : nil
            let stats = recording.hasTelemetry
                ? TelemetryStats.load(PolishExporter.telemetryURL(for: url)) : nil
            guard let model = self else { return }
            if let index = model.recordings.firstIndex(where: { $0.url == url }) {
                model.recordings[index].duration = seconds
                model.recordings[index].isDamaged = !playable && ActiveRecording.shared.url != url
            }
            if let image { model.thumbnails[url] = image }
            if let size { model.resolution[url] = size }
            if let stats { model.stats[url] = stats }
        }
    }

    // MARK: Actions

    func play(_ recording: Recording, polished: Bool) {
        let url = polished ? (recording.polishedURL ?? recording.url) : recording.url
        playingPolished = polished
        playing = recording
        player = AVPlayer(url: url)
        player?.play()
    }

    func closePlayer() {
        player?.pause()
        player = nil
        playing = nil
    }

    func playSelected() {
        if let r = selectedRecording, !r.isDamaged { play(r, polished: r.isPolished) }
        else if let s = selectedScreenshot { NSWorkspace.shared.open(s.url) }
    }

    func polish(_ recording: Recording) {
        let url = recording.url
        guard !polishing.contains(url), recording.hasTelemetry, !recording.isDamaged else { return }
        polishing.insert(url)
        polishProgress[url] = 0
        message = nil
        Task { [weak self] in
            let target = self
            do {
                let options = await AppSettings.shared.polishOptions
                let output = try await PolishExporter.polish(videoURL: url, options: options) { fraction in
                    Task { @MainActor in target?.polishProgress[url] = fraction }
                }
                guard let model = self else { return }
                model.polishing.remove(url)
                model.polishProgress[url] = nil
                model.reload()
                model.message = "Polished → \(output.lastPathComponent)"
            } catch {
                guard let model = self else { return }
                model.polishing.remove(url)
                model.polishProgress[url] = nil
                model.message = error.localizedDescription
            }
        }
    }

    func polishSelected() {
        for r in recordings where selection.contains(r.url) { polish(r) }
    }

    func exportGIF(_ recording: Recording) { export(recording, format: .gif) }

    func export(_ recording: Recording, format: ExportService.Format) {
        let source = recording.polishedURL ?? recording.url
        let key = recording.url
        guard !polishing.contains(key) else { return }
        let name = recording.name + (recording.polishedURL != nil ? " (polished)" : "")
        Task { [weak self] in
            let target = self
            do {
                guard let out = try await ExportService.export(
                    source: source, suggestedName: name, format: format,
                    progress: { f in Task { @MainActor in target?.polishProgress[key] = f } })
                else { return }
                guard let model = self else { return }
                model.polishProgress[key] = nil
                model.message = "Exported → \(out.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([out])
            } catch {
                guard let model = self else { return }
                model.polishProgress[key] = nil
                model.message = error.localizedDescription
            }
        }
    }

    func rename(_ recording: Recording) {
        let alert = NSAlert()
        alert.messageText = "Rename Recording"
        alert.informativeText = "Sidecar files (telemetry, webcam, polished) are renamed with it."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = recording.name
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            _ = try ExportService.rename(recording, to: field.stringValue)
            reload()
        } catch {
            message = error.localizedDescription
        }
    }

    func delete(_ recording: Recording) {
        RecordingsStore.moveToTrash(recording)
        reload()
    }

    func deleteScreenshot(_ shot: Screenshot) {
        try? FileManager.default.trashItem(at: shot.url, resultingItemURL: nil)
        reload()
    }

    func deleteSelected() {
        let urls = selection
        guard !urls.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = urls.count == 1 ? "Move this item to the Trash?" : "Move \(urls.count) items to the Trash?"
        alert.informativeText = "Sidecar files go with their recordings."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        for r in recordings where urls.contains(r.url) { RecordingsStore.moveToTrash(r) }
        for s in screenshots where urls.contains(s.url) {
            try? FileManager.default.trashItem(at: s.url, resultingItemURL: nil)
        }
        selection.removeAll()
        reload()
    }

    func copyScreenshot(_ shot: Screenshot) {
        guard let image = NSImage(contentsOf: shot.url) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        message = "Copied \(shot.name) to the clipboard"
    }

    // Trim
    func beginTrim(_ recording: Recording) {
        trimming = recording
        trimStart = 0
        trimEnd = recording.duration ?? 0
        trimPlayer = AVPlayer(url: recording.url)
    }

    func seekTrim(to seconds: Double) {
        trimPlayer?.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func cancelTrim() {
        trimPlayer?.pause()
        trimPlayer = nil
        trimming = nil
    }

    func exportTrim() {
        guard let recording = trimming, !trimBusy else { return }
        trimBusy = true
        let (url, a, b, remove) = (recording.url, trimStart, trimEnd, trimRemove)
        Task { [weak self] in
            do {
                let output = try await TrimExporter.trim(videoURL: url, start: a, end: b, remove: remove)
                guard let model = self else { return }
                model.trimBusy = false
                model.cancelTrim()
                model.reload()
                model.message = "Trimmed → \(output.lastPathComponent)"
            } catch {
                guard let model = self else { return }
                model.trimBusy = false
                model.message = error.localizedDescription
            }
        }
    }
}

// MARK: - Views

struct DashboardView: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject private var active = ActiveRecording.shared

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } content: {
            content
                .navigationSplitViewColumnWidth(min: 440, ideal: 620)
        } detail: {
            inspector
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        }
        .frame(minWidth: 900, minHeight: 520)
        .searchable(text: $model.query, placement: .toolbar, prompt: "Search")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Sort", selection: $model.sort) {
                    ForEach(SortOrder.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu).help("Sort")
                Picker("View", selection: $model.grid) {
                    Image(systemName: "list.bullet").tag(false)
                    Image(systemName: "square.grid.2x2").tag(true)
                }
                .pickerStyle(.segmented).help("List or grid")
                Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh")
                Button { NSWorkspace.shared.open(CaptureEngine.recordingsDirectory()) } label: {
                    Image(systemName: "folder")
                }.help("Open folder in Finder")
            }
        }
        .onAppear { model.reload() }
        .onChange(of: active.url) { _, _ in model.reload() }
        .onKeyPress(.space) { model.playSelected(); return .handled }
        .onDeleteCommand { model.deleteSelected() }
    }

    private var sidebar: some View {
        List(selection: $model.section) {
            Section("Library") {
                ForEach(LibrarySection.allCases) { section in
                    Label {
                        HStack {
                            Text(section.label)
                            Spacer()
                            Text("\(count(for: section))").foregroundStyle(.secondary).font(.system(size: 11))
                        }
                    } icon: { Image(systemName: section.symbol) }
                    .tag(section)
                }
            }
            Section("Storage") {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(model.totalBytes), countStyle: .file))
                        .font(.system(size: 13, weight: .medium))
                    Text("\(model.recordings.count) recordings · \(model.screenshots.count) screenshots")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.sidebar)
        .onChange(of: model.section) { _, _ in model.selection.removeAll() }
    }

    private func count(for section: LibrarySection) -> Int {
        switch section {
        case .recordings: return model.recordings.count
        case .polished: return model.recordings.filter(\.isPolished).count
        case .screenshots: return model.screenshots.count
        }
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            QuickTile(title: "Record Screen", symbol: "record.circle", key: "⌃⌘R", accent: true) { (NSApp.delegate as? AppDelegate)?.quickAction("screen") }
            QuickTile(title: "Record Area", symbol: "rectangle.dashed", key: "⌃⇧⌘R") { (NSApp.delegate as? AppDelegate)?.quickAction("area") }
            QuickTile(title: "Screenshot", symbol: "camera", key: "⌃⌘S") { (NSApp.delegate as? AppDelegate)?.quickAction("shot") }
            QuickTile(title: "Screenshot Area", symbol: "camera.viewfinder", key: "⌃⌘A") { (NSApp.delegate as? AppDelegate)?.quickAction("shotArea") }
            QuickTile(title: "Audio Only", symbol: "waveform", key: "") { (NSApp.delegate as? AppDelegate)?.quickAction("audio") }
            QuickTile(title: "Webcam Only", symbol: "video", key: "") { (NSApp.delegate as? AppDelegate)?.quickAction("webcam") }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            quickActions
            Divider()
            library
        }
    }

    @ViewBuilder private var library: some View {
        if model.section == .screenshots {
            if model.visibleScreenshots.isEmpty { empty("No screenshots", "⌃⌘S captures the screen; both to disk and the clipboard.") }
            else { screenshotGrid }
        } else {
            if model.visibleRecordings.isEmpty {
                empty(model.query.isEmpty ? "No recordings yet" : "Nothing matches",
                      model.query.isEmpty ? "Use Record Full Screen from the menu bar, or ⌃⌘R." : "Try a different search.")
            } else if model.grid { recordingGrid } else { recordingList }
        }
    }

    private func empty(_ title: String, _ hint: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "film.stack").font(.system(size: 34)).foregroundStyle(.tertiary)
            Text(title).font(.system(size: 14, weight: .medium))
            Text(hint).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recordingList: some View {
        List(model.visibleRecordings, selection: $model.selection) { recording in
            RecordingRow(recording: recording, model: model, isActive: recording.url == active.url)
                .tag(recording.url)
                .onDrag { NSItemProvider(object: recording.url as NSURL) }
                .contextMenu { RecordingMenu(recording: recording, model: model) }
        }
        .listStyle(.inset)
    }

    private var recordingGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 14)], spacing: 14) {
                ForEach(model.visibleRecordings) { recording in
                    RecordingCard(recording: recording, model: model, isActive: recording.url == active.url,
                                  selected: model.selection.contains(recording.url))
                        .onTapGesture { model.selection = [recording.url] }
                        .onTapGesture(count: 2) { if !recording.isDamaged { model.play(recording, polished: false) } }
                        .onDrag { NSItemProvider(object: recording.url as NSURL) }
                        .contextMenu { RecordingMenu(recording: recording, model: model) }
                }
            }
            .padding(16)
        }
    }

    private var screenshotGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 14)], spacing: 14) {
                ForEach(model.visibleScreenshots) { shot in
                    VStack(alignment: .leading, spacing: 6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12))
                            if let image = model.thumbnails[shot.url] {
                                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .frame(height: 120)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(model.selection.contains(shot.url) ? Color.accentColor : .clear, lineWidth: 2))
                        Text(shot.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Text(shot.sizeText).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .onTapGesture { model.selection = [shot.url] }
                    .onTapGesture(count: 2) { if let img = NSImage(contentsOf: shot.url) { ScreenshotEditorWindows.shared.open(image: img, sourceURL: shot.url) } }
                    .onDrag { NSItemProvider(object: shot.url as NSURL) }
                    .contextMenu {
                        Button("Edit…") { if let img = NSImage(contentsOf: shot.url) { ScreenshotEditorWindows.shared.open(image: img, sourceURL: shot.url) } }
                        Button("Pin on Screen") { if let img = NSImage(contentsOf: shot.url) { PinnedScreenshots.shared.pin(img) } }
                        Button("Open") { NSWorkspace.shared.open(shot.url) }
                        Button("Copy Image") { model.copyScreenshot(shot) }
                        ShareLink(item: shot.url) { Text("Share…") }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([shot.url]) }
                        Divider()
                        Button("Move to Trash", role: .destructive) { model.deleteScreenshot(shot) }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: Inspector

    @ViewBuilder private var inspector: some View {
        if let r = model.selectedRecording {
            RecordingInspector(recording: r, model: model)
        } else if let s = model.selectedScreenshot {
            ScreenshotInspector(shot: s, model: model)
        } else if model.selection.count > 1 {
            VStack(spacing: 12) {
                Text("\(model.selection.count) selected").font(.system(size: 14, weight: .medium))
                Button("Auto-Zoom All") { model.polishSelected() }.buttonStyle(.borderedProminent)
                Button("Move to Trash", role: .destructive) { model.deleteSelected() }
                Spacer()
            }
            .padding(16)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "sidebar.right").font(.system(size: 28)).foregroundStyle(.tertiary)
                Text("Select a recording").font(.system(size: 12)).foregroundStyle(.secondary)
                Text("Space plays · ⌫ trashes · drag out to copy").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct QuickTile: View {
    let title: String
    let symbol: String
    let key: String
    var accent = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 20, weight: .medium))
                    .foregroundStyle(accent ? Color.white : Color.accentColor)
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(accent ? .white : .primary)
                Text(key.isEmpty ? " " : key).font(.system(size: 9)).foregroundStyle(accent ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(accent ? Color.accentColor : Color.secondary.opacity(hover ? 0.18 : 0.1)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Rows, cards, menus

struct RecordingRow: View {
    let recording: Recording
    @ObservedObject var model: DashboardModel
    let isActive: Bool
    private var isPolishing: Bool { model.polishing.contains(recording.url) }

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(recording.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text("\(recording.createdText)  ·  \(recording.durationText)  ·  \(recording.sizeText)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if isActive { badge("Recording now", "record.circle") }
                    else if recording.isDamaged { badge("Damaged — not finalised", "exclamationmark.octagon") }
                    else {
                        if recording.hasTelemetry { badge("Telemetry", "scope") } else { badge("No telemetry", "exclamationmark.triangle") }
                        if recording.isPolished { badge("Polished", "wand.and.stars") }
                    }
                }
            }
            Spacer()
            actions
        }
        .padding(.vertical, 4)
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.12))
            if let image = model.thumbnails[recording.url] {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                Image(systemName: recording.isDamaged ? "exclamationmark.octagon" : "film").foregroundStyle(.tertiary)
            }
        }
        .frame(width: 92, height: 54)
    }

    private func badge(_ text: String, _ symbol: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 9))
            Text(text).font(.system(size: 10))
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.secondary.opacity(0.12)).clipShape(Capsule()).foregroundStyle(.secondary)
    }

    @ViewBuilder private var actions: some View {
        if isActive {
            Text("In progress — stop from the menu bar").font(.system(size: 11)).foregroundStyle(.secondary)
        } else if recording.isDamaged {
            Button("Move to Trash", role: .destructive) { model.delete(recording) }.controlSize(.small)
        } else if isPolishing {
            HStack(spacing: 6) {
                ProgressView(value: model.polishProgress[recording.url] ?? 0).frame(width: 80)
                Text("\(Int((model.polishProgress[recording.url] ?? 0) * 100))%")
                    .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
            }
        } else {
            HStack(spacing: 8) {
                Button("Play") { model.play(recording, polished: false) }
                if recording.hasTelemetry {
                    Button(recording.isPolished ? "Re-polish" : "Auto-Zoom") { model.polish(recording) }
                        .buttonStyle(.borderedProminent)
                }
                if recording.polishedURL != nil {
                    Button("Play Polished") { model.play(recording, polished: true) }
                }
            }
            .controlSize(.small)
        }
    }
}

struct RecordingCard: View {
    let recording: Recording
    @ObservedObject var model: DashboardModel
    let isActive: Bool
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12))
                if let image = model.thumbnails[recording.url] {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Text(isActive ? "REC" : recording.durationText)
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(isActive ? Color.red : Color.black.opacity(0.6)).foregroundStyle(.white)
                    .clipShape(Capsule()).padding(6)
                if model.polishing.contains(recording.url) {
                    ProgressView(value: model.polishProgress[recording.url] ?? 0)
                        .frame(maxWidth: .infinity).padding(8)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(height: 130)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
            Text(recording.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
            HStack(spacing: 4) {
                Text(recording.sizeText).font(.system(size: 10)).foregroundStyle(.secondary)
                if recording.isPolished { Image(systemName: "wand.and.stars").font(.system(size: 9)).foregroundStyle(.secondary) }
                if recording.isDamaged { Image(systemName: "exclamationmark.octagon").font(.system(size: 9)).foregroundStyle(.red) }
            }
        }
    }
}

struct RecordingMenu: View {
    let recording: Recording
    @ObservedObject var model: DashboardModel

    var body: some View {
        if !recording.isDamaged {
            Button("Play") { model.play(recording, polished: false) }
            if recording.polishedURL != nil { Button("Play Polished") { model.play(recording, polished: true) } }
            Divider()
            Button(recording.isPolished ? "Re-polish (Auto-Zoom)" : "Auto-Zoom") { model.polish(recording) }
                .disabled(!recording.hasTelemetry)
            Button("Trim…") { model.beginTrim(recording) }.disabled(recording.duration == nil)
            Button("Rename…") { model.rename(recording) }
            Menu("Export") {
                ForEach(ExportService.Format.allCases) { format in
                    Button(format.rawValue) { model.export(recording, format: format) }
                }
            }
            ShareLink(item: recording.polishedURL ?? recording.url) { Text("Share…") }
            Divider()
        }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([recording.url]) }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(recording.url.path, forType: .string)
        }
        Divider()
        Button("Move to Trash", role: .destructive) { model.delete(recording) }
    }
}

// MARK: - Inspectors

struct RecordingInspector: View {
    let recording: Recording
    @ObservedObject var model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12))
                    if let image = model.thumbnails[recording.url] {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .frame(height: 140)

                Text(recording.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)

                if !recording.isDamaged {
                    HStack(spacing: 8) {
                        Button("Play") { model.play(recording, polished: false) }
                        if recording.hasTelemetry {
                            Button(recording.isPolished ? "Re-polish" : "Auto-Zoom") { model.polish(recording) }
                                .buttonStyle(.borderedProminent)
                        }
                        ShareLink(item: recording.polishedURL ?? recording.url) { Image(systemName: "square.and.arrow.up") }
                    }
                    .controlSize(.small)
                }

                group("File") {
                    row("Recorded", recording.createdText)
                    row("Duration", recording.durationText)
                    row("Size", recording.sizeText)
                    if let size = model.resolution[recording.url] {
                        row("Resolution", "\(Int(size.width)) × \(Int(size.height))")
                    }
                    row("Status", recording.isDamaged ? "Damaged — not finalised" : recording.isPolished ? "Polished" : "Original")
                }

                if let stats = model.stats[recording.url] {
                    group("Telemetry") {
                        row("Samples", "\(stats.samples)")
                        row("Clicks", "\(stats.clicks)")
                        row("Cursor travel", String(format: "%.0f px", stats.distance))
                        row("Active time", String(format: "%.0f%%", stats.activeFraction * 100))
                    }
                    Text("Active time is the share of half-second windows in which the cursor moved — a rough measure of how much Auto-Zoom will have to do.")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                } else if !recording.isDamaged {
                    Text("No telemetry sidecar, so Auto-Zoom is unavailable for this recording.")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }

                group("Sidecars") {
                    row("Telemetry", recording.hasTelemetry ? "Yes" : "—")
                    row("Webcam", FileManager.default.fileExists(atPath: WebcamRecorder.sidecarURL(for: recording.url).path) ? "Yes" : "—")
                    row("Polished", recording.isPolished ? "Yes" : "—")
                }
                Spacer()
            }
            .padding(14)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
            Text(value).font(.system(size: 11)).monospacedDigit().textSelection(.enabled)
        }
    }
}

struct ScreenshotInspector: View {
    let shot: Screenshot
    @ObservedObject var model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let image = model.thumbnails[shot.url] {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                let size = model.resolution[shot.url] ?? image.size
                Text("\(Int(size.width)) × \(Int(size.height)) · \(shot.sizeText)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(shot.name).font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                Button("Edit") { if let img = NSImage(contentsOf: shot.url) { ScreenshotEditorWindows.shared.open(image: img, sourceURL: shot.url) } }
                    .buttonStyle(.borderedProminent)
                Button("Copy") { model.copyScreenshot(shot) }
                ShareLink(item: shot.url) { Image(systemName: "square.and.arrow.up") }
            }
            .controlSize(.small)
            Spacer()
        }
        .padding(14)
    }
}

// MARK: - Player and trim content (hosted in their own windows)

struct PlayerSheet: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.playing?.name ?? "").font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(model.playingPolished ? "Polished" : "Original").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if let recording = model.playing, recording.polishedURL != nil {
                    Picker("", selection: Binding(
                        get: { model.playingPolished },
                        set: { model.play(recording, polished: $0) }
                    )) {
                        Text("Original").tag(false)
                        Text("Polished").tag(true)
                    }
                    .pickerStyle(.segmented).frame(width: 180)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if let player = model.player {
                PlayerView(player: player).frame(minWidth: 480, minHeight: 270)
            }
        }
    }
}

struct TrimSheet: View {
    @ObservedObject var model: DashboardModel
    private var total: Double { model.trimming?.duration ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Trim").font(.system(size: 13, weight: .medium))
                    Text(model.trimming?.name ?? "").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Cancel") { model.cancelTrim() }.keyboardShortcut(.cancelAction)
                Button(model.trimBusy ? "Exporting…" : "Export Trim") { model.exportTrim() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.trimBusy || model.trimEnd - model.trimStart < 0.1)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            if let player = model.trimPlayer {
                PlayerView(player: player).frame(minWidth: 480, minHeight: 270)
            }
            Divider()
            VStack(spacing: 10) {
                HStack {
                    Text("Start").frame(width: 40, alignment: .leading)
                    Slider(value: $model.trimStart, in: 0...max(0.01, total)) { editing in
                        if !editing { model.seekTrim(to: model.trimStart) }
                    }
                    .onChange(of: model.trimStart) { _, v in
                        if v > model.trimEnd { model.trimEnd = v }
                        model.seekTrim(to: v)
                    }
                    Text(Self.stamp(model.trimStart)).monospacedDigit().frame(width: 60)
                }
                HStack {
                    Text("End").frame(width: 40, alignment: .leading)
                    Slider(value: $model.trimEnd, in: 0...max(0.01, total)) { editing in
                        if !editing { model.seekTrim(to: model.trimEnd) }
                    }
                    .onChange(of: model.trimEnd) { _, v in
                        if v < model.trimStart { model.trimStart = v }
                        model.seekTrim(to: v)
                    }
                    Text(Self.stamp(model.trimEnd)).monospacedDigit().frame(width: 60)
                }
                HStack {
                    Picker("", selection: $model.trimRemove) {
                        Text("Keep selection").tag(false)
                        Text("Remove selection").tag(true)
                    }.pickerStyle(.segmented).frame(width: 240)
                    Text(model.trimRemove
                         ? "Cuts \(Self.stamp(model.trimEnd - model.trimStart)) out of \(Self.stamp(total)) and joins the rest"
                         : "Keeps \(Self.stamp(model.trimEnd - model.trimStart)) of \(Self.stamp(total))")
                    Spacer()
                    Text("Lossless. Telemetry and webcam follow.").foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
            }
            .padding(14)
        }
    }

    private static func stamp(_ s: Double) -> String {
        let total = max(0, s)
        return String(format: "%d:%05.2f", Int(total) / 60, total.truncatingRemainder(dividingBy: 60))
    }
}

// MARK: - Window controller

/// Owns the dashboard window, plus the player and trim windows it spawns.
@MainActor
final class DashboardWindowController {
    private(set) var window: NSWindow?
    private(set) var playerWindow: NSWindow?
    private(set) var trimWindow: NSWindow?
    let model = DashboardModel()
    private var observers: [Any] = []
    private var subscriptions: [AnyCancellable] = []

    init() {
        subscriptions.append(model.$playing.receive(on: RunLoop.main).sink { [weak self] playing in
            guard let self else { return }
            if playing != nil { self.showPlayer() } else { self.playerWindow?.orderOut(nil) }
        })
        subscriptions.append(model.$trimming.receive(on: RunLoop.main).sink { [weak self] trimming in
            guard let self else { return }
            if trimming != nil { self.showTrim() } else { self.trimWindow?.orderOut(nil) }
        })
    }

    private func sizeForVideo(_ url: URL?, chrome: CGFloat) async -> NSSize {
        var aspect: CGFloat = 16.0 / 9.0
        if let url, let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
            let natural = try? await track.load(.naturalSize), natural.height > 0 {
            aspect = natural.width / natural.height
        }
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var width = min(visible.width * 0.72, 1280)
        var height = width / aspect + chrome
        if height > visible.height * 0.85 { height = visible.height * 0.85; width = (height - chrome) * aspect }
        return NSSize(width: width.rounded(), height: height.rounded())
    }

    private func makeWindow<V: View>(_ view: V, title: String, onClose: @escaping () -> Void) -> NSWindow {
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = title
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 560, height: 360)
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: w, queue: .main
        ) { _ in MainActor.assumeIsolated { onClose() } })
        return w
    }

    private func showPlayer() {
        if playerWindow == nil {
            playerWindow = makeWindow(PlayerSheet(model: model), title: "Player") { [weak self] in self?.model.closePlayer() }
        }
        guard let playerWindow else { return }
        playerWindow.title = model.playing?.name ?? "Player"
        let url = model.playingPolished ? model.playing?.polishedURL : model.playing?.url
        Task { @MainActor in
            playerWindow.setContentSize(await self.sizeForVideo(url, chrome: 52))
            playerWindow.center()
            playerWindow.makeKeyAndOrderFront(nil)
        }
    }

    private func showTrim() {
        if trimWindow == nil {
            trimWindow = makeWindow(TrimSheet(model: model), title: "Trim") { [weak self] in self?.model.cancelTrim() }
        }
        guard let trimWindow else { return }
        trimWindow.title = "Trim — \(model.trimming?.name ?? "")"
        Task { @MainActor in
            trimWindow.setContentSize(await self.sizeForVideo(model.trimming?.url, chrome: 150))
            trimWindow.center()
            trimWindow.makeKeyAndOrderFront(nil)
        }
    }

    func show() {
        if let window {
            model.reload()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: DashboardView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = Brand.name
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 1080, height: 620))
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window
        model.reload()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
