import AppKit
import Carbon.HIToolbox
import Foundation
import ServiceManagement
import SwiftUI

/// User preferences, persisted in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    enum Quality: String, CaseIterable, Identifiable {
        case low, medium, high
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        /// Multiplier on the screen-content bitrate table.
        var bitrateFactor: Double {
            switch self {
            case .low: return 0.5
            case .medium: return 1.0
            case .high: return 1.8
            }
        }
    }

    @AppStorage("frameRate") var frameRate: Int = 60
    @AppStorage("quality") var qualityRaw: String = Quality.medium.rawValue
    @AppStorage("countdown") var countdownEnabled: Bool = true
    @AppStorage("cursorHighlight") var cursorHighlight: Bool = true
    @AppStorage("zoomStrength") var zoomStrength: Double = 2.0
    @AppStorage("zoomSmoothing") var zoomSmoothing: Double = 1.4
    @AppStorage("webcamEnabled") var webcamEnabled: Bool = false
    @AppStorage("webcamDeviceID") var webcamDeviceID: String = ""
    @AppStorage("includeMicrophone") var includeMicrophone: Bool = false
    @AppStorage("removeSilence") var removeSilence: Bool = false
    @AppStorage("silenceThresholdDB") var silenceThresholdDB: Double = -45
    @AppStorage("minSilenceSeconds") var minSilenceSeconds: Double = 1.2
    @AppStorage("background") var backgroundRaw: String = PolishExporter.Background.none.rawValue
    @AppStorage("exportHeight") var exportHeight: Int = 0
    @AppStorage("maxDurationMinutes") var maxDurationMinutes: Int = 0

    // Last recorded area, as "displayID,x,y,w,h" in display points.
    @AppStorage("lastArea") var lastArea: String = ""
    @AppStorage("hk.drawToggle") var hkDrawToggle: String = "\(kVK_ANSI_D):\(cmdKey | controlKey)"
    @AppStorage("hk.recordLastArea") var hkRecordLastArea: String = "\(kVK_ANSI_R):\(cmdKey | controlKey | optionKey)"

    // Screenshots
    @AppStorage("screenshotFolderPath") var screenshotFolderPath: String = ""
    @AppStorage("screenshotFormat") var screenshotFormat: String = "png"   // png | jpeg
    @AppStorage("downscaleRetina") var downscaleRetina: Bool = false
    @AppStorage("afterScreenshot") var afterScreenshot: String = "editor" // editor | preview | copy | none
    @AppStorage("previewSeconds") var previewSeconds: Int = 8
    @AppStorage("windowBackground") var windowBackground: String = "shadow" // shadow | transparent | solid | gradient | trim
    /// "system" | "light" | "dark" — applied to NSApp.appearance.
    @AppStorage("appearance") var appearance: String = "system" {
        didSet { AppSettings.applyAppearance(appearance) }
    }
    static func applyAppearance(_ value: String) {
        switch value {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    @AppStorage("launchAtLogin") var launchAtLoginStored: Bool = false

    var screenshotFolder: URL {
        if !screenshotFolderPath.isEmpty { return URL(fileURLWithPath: screenshotFolderPath) }
        return CaptureEngine.recordingsDirectory()
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                launchAtLoginStored = newValue
            } catch { NSLog("Launch at login: \(error.localizedDescription)") }
            objectWillChange.send()
        }
    }

    // Hot keys, stored as "keyCode:modifiers" (Carbon values).
    @AppStorage("hk.toggleRecording") var hkToggleRecording: String = "\(kVK_ANSI_R):\(cmdKey | controlKey)"
    @AppStorage("hk.pause") var hkPause: String = "\(kVK_ANSI_P):\(cmdKey | controlKey)"
    @AppStorage("hk.screenshot") var hkScreenshot: String = "\(kVK_ANSI_S):\(cmdKey | controlKey)"
    @AppStorage("hk.screenshotArea") var hkScreenshotArea: String = "\(kVK_ANSI_A):\(cmdKey | controlKey)"
    @AppStorage("hk.screenshotWindow") var hkScreenshotWindow: String = "\(kVK_ANSI_W):\(cmdKey | controlKey)"
    @AppStorage("hk.recordArea") var hkRecordArea: String = "\(kVK_ANSI_R):\(cmdKey | controlKey | shiftKey)"

    enum ZoomPreset: String, CaseIterable, Identifiable {
        case subtle, balanced, dramatic
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var values: (strength: Double, smoothing: Double) {
            switch self {
            case .subtle: return (1.5, 2.0)
            case .balanced: return (2.0, 1.4)
            case .dramatic: return (2.6, 1.0)
            }
        }
    }

    var polishOptions: PolishExporter.Options {
        var o = PolishExporter.Options()
        o.zoom = zoomSettings
        o.highlightCursor = cursorHighlight
        o.includeWebcam = webcamEnabled || true
        o.removeSilence = removeSilence
        o.silenceThresholdDB = silenceThresholdDB
        o.minSilenceSeconds = minSilenceSeconds
        o.background = PolishExporter.Background(rawValue: backgroundRaw) ?? .none
        o.exportHeight = exportHeight
        return o
    }

    var quality: Quality {
        get { Quality(rawValue: qualityRaw) ?? .medium }
        set { qualityRaw = newValue.rawValue }
    }

    var zoomSettings: ZoomPlanner.Settings {
        var s = ZoomPlanner.Settings.default
        s.maxScale = zoomStrength
        s.midScale = 1 + (zoomStrength - 1) * 0.4
        s.smoothingSeconds = zoomSmoothing
        return s
    }

    /// Which Settings tab is showing; not persisted.
    @Published var settingsTab = "general"

    private init() {}
}

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var cameras: [(id: String, name: String)] = []

    var body: some View {
        TabView(selection: $settings.settingsTab) {
            general.tabItem { Label("General", systemImage: "gearshape") }.tag("general")
            recording.tabItem { Label("Recording", systemImage: "record.circle") }.tag("recording")
            polish.tabItem { Label("Auto-Zoom", systemImage: "wand.and.stars") }.tag("polish")
            screenshots.tabItem { Label("Screenshots", systemImage: "camera") }.tag("screenshots")
            hotkeys.tabItem { Label("Hotkeys", systemImage: "keyboard") }.tag("hotkeys")
        }
        .frame(width: 560, height: 520)
        .onAppear { cameras = WebcamRecorder.availableCameras() }
    }

    private var general: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }))
                Picker("Appearance", selection: $settings.appearance) {
                    Text("Match system").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
                Toggle("3-second countdown before recording", isOn: $settings.countdownEnabled)
                Picker("Stop recording automatically after", selection: $settings.maxDurationMinutes) {
                    Text("Never").tag(0); Text("5 minutes").tag(5); Text("15 minutes").tag(15); Text("30 minutes").tag(30); Text("60 minutes").tag(60)
                }
            }
            Section("Files") {
                HStack {
                    Text("Recordings folder"); Spacer()
                    Text(CaptureEngine.recordingsDirectory().path).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Button("Show") { NSWorkspace.shared.open(CaptureEngine.recordingsDirectory()) }
                }
            }
            Section("About") {
                HStack { Text("\(Brand.name) \(Brand.version)"); Spacer(); Text("Developed by Rahul Patel").foregroundStyle(.secondary) }
            }
        }.formStyle(.grouped)
    }

    private var recording: some View {
        Form {
            Section("Video") {
                Picker("Frame rate", selection: $settings.frameRate) { Text("30 fps").tag(30); Text("60 fps").tag(60) }
                Picker("Quality", selection: $settings.qualityRaw) { ForEach(AppSettings.Quality.allCases) { q in Text(q.label).tag(q.rawValue) } }
            }
            Section("Audio") {
                Toggle("Include microphone", isOn: $settings.includeMicrophone)
                Text("System audio is always recorded on its own track.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("Webcam") {
                Toggle("Record webcam alongside the screen", isOn: $settings.webcamEnabled)
                if settings.webcamEnabled {
                    Picker("Camera", selection: $settings.webcamDeviceID) {
                        Text("Default").tag(""); ForEach(cameras, id: \.id) { cam in Text(cam.name).tag(cam.id) }
                    }
                    Text("Saved as a separate file and composited as picture-in-picture by Auto-Zoom, so it never obscures the original recording.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Section("Drawing on screen") {
                Text("Press ⌃⌘D while recording to draw on the screen. Drawings are recorded into the video. Esc stops, C clears, ⌘Z undoes.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private var polish: some View {
        Form {
            Section("Auto-Zoom") {
                HStack {
                    Text("Preset"); Spacer()
                    ForEach(AppSettings.ZoomPreset.allCases) { preset in
                        Button(preset.label) { settings.zoomStrength = preset.values.strength; settings.zoomSmoothing = preset.values.smoothing }.buttonStyle(.bordered)
                    }
                }
                HStack { Text("Zoom strength"); Slider(value: $settings.zoomStrength, in: 1.3...3.0, step: 0.1)
                         Text(String(format: "%.1f×", settings.zoomStrength)).monospacedDigit().frame(width: 44, alignment: .trailing) }
                HStack { Text("Smoothing"); Slider(value: $settings.zoomSmoothing, in: 0.5...3.0, step: 0.1)
                         Text(String(format: "%.1f s", settings.zoomSmoothing)).monospacedDigit().frame(width: 44, alignment: .trailing) }
                Toggle("Highlight cursor", isOn: $settings.cursorHighlight)
            }
            Section("Polish") {
                Toggle("Remove silences", isOn: $settings.removeSilence)
                if settings.removeSilence {
                    HStack { Text("Silence threshold"); Slider(value: $settings.silenceThresholdDB, in: -70 ... -25, step: 1)
                             Text("\(Int(settings.silenceThresholdDB)) dB").monospacedDigit().frame(width: 52, alignment: .trailing) }
                    HStack { Text("Minimum gap"); Slider(value: $settings.minSilenceSeconds, in: 0.5...4, step: 0.1)
                             Text(String(format: "%.1f s", settings.minSilenceSeconds)).monospacedDigit().frame(width: 52, alignment: .trailing) }
                }
                Picker("Background", selection: $settings.backgroundRaw) { ForEach(PolishExporter.Background.allCases) { Text($0.label).tag($0.rawValue) } }
                Picker("Export resolution", selection: $settings.exportHeight) {
                    Text("Original").tag(0); Text("720p").tag(720); Text("1080p").tag(1080); Text("1440p").tag(1440); Text("4K (2160p)").tag(2160)
                }
                Text("Applies the next time you run Auto-Zoom. Originals are never modified.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private var screenshots: some View {
        Form {
            Section("Saving") {
                HStack {
                    Text("Folder"); Spacer()
                    Text(settings.screenshotFolder.path).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Button("Choose…") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
                        if panel.runModal() == .OK, let url = panel.url { settings.screenshotFolderPath = url.path }
                    }
                    if !settings.screenshotFolderPath.isEmpty { Button("Reset") { settings.screenshotFolderPath = "" } }
                }
                Picker("Save format", selection: $settings.screenshotFormat) { Text("PNG").tag("png"); Text("JPEG").tag("jpeg") }.pickerStyle(.segmented)
                Toggle("Downscale Retina screenshots to 1×", isOn: $settings.downscaleRetina)
                Text("Always copied to the clipboard as well as saved.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("After capture") {
                Picker("Then", selection: $settings.afterScreenshot) {
                    Text("Open editor").tag("editor"); Text("Show preview thumbnail").tag("preview"); Text("Copy only").tag("copy"); Text("Nothing").tag("none")
                }
                if settings.afterScreenshot == "preview" {
                    Picker("Hide preview after", selection: $settings.previewSeconds) { Text("4 s").tag(4); Text("8 s").tag(8); Text("15 s").tag(15); Text("Manually").tag(0) }
                }
            }
            Section("Window screenshots") {
                Picker("Background", selection: $settings.windowBackground) {
                    Text("System shadow").tag("shadow"); Text("Transparent").tag("transparent"); Text("Solid colour").tag("solid"); Text("Gradient").tag("gradient"); Text("Trim shadow").tag("trim")
                }
            }
        }.formStyle(.grouped)
    }

    private var hotkeys: some View {
        Form {
            Section("Recording") {
                HotKeyField(title: "Record / stop", value: $settings.hkToggleRecording, action: .toggleRecording, defaultValue: "\(kVK_ANSI_R):\(cmdKey | controlKey)")
                HotKeyField(title: "Record area", value: $settings.hkRecordArea, action: .recordArea, defaultValue: "\(kVK_ANSI_R):\(cmdKey | controlKey | shiftKey)")
                HotKeyField(title: "Record last area again", value: $settings.hkRecordLastArea, action: .recordLastArea, defaultValue: "\(kVK_ANSI_R):\(cmdKey | controlKey | optionKey)")
                HotKeyField(title: "Pause / resume", value: $settings.hkPause, action: .pause, defaultValue: "\(kVK_ANSI_P):\(cmdKey | controlKey)")
                HotKeyField(title: "Draw on screen (while recording)", value: $settings.hkDrawToggle, action: .drawToggle, defaultValue: "\(kVK_ANSI_D):\(cmdKey | controlKey)")
            }
            Section("Screenshots") {
                HotKeyField(title: "Screenshot screen", value: $settings.hkScreenshot, action: .screenshot, defaultValue: "\(kVK_ANSI_S):\(cmdKey | controlKey)")
                HotKeyField(title: "Screenshot area", value: $settings.hkScreenshotArea, action: .screenshotArea, defaultValue: "\(kVK_ANSI_A):\(cmdKey | controlKey)")
                HotKeyField(title: "Screenshot window", value: $settings.hkScreenshotWindow, action: .screenshotWindow, defaultValue: "\(kVK_ANSI_W):\(cmdKey | controlKey)")
            }
            Text("Click a field, then press the new combination. Esc cancels. Changes apply immediately. Shortcuts macOS reserves (⇧⌘3, ⇧⌘4, ⇧⌘5, ⌘Space…) cannot be taken; pick another.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Button("Reset all shortcuts to defaults") {
                for key in ["hk.toggleRecording", "hk.recordArea", "hk.recordLastArea", "hk.pause", "hk.drawToggle", "hk.screenshot", "hk.screenshotArea", "hk.screenshotWindow"] {
                    UserDefaults.standard.removeObject(forKey: key)
                }
                HotKeys.active?.resume()
                NotificationCenter.default.post(name: .hotKeysChanged, object: nil)
            }
        }.formStyle(.grouped)
    }
}

@MainActor
final class SettingsWindowController {
    private(set) var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}


/// Click, then press a combination. Stores "keyCode:carbonModifiers".
struct HotKeyField: View {
    let title: String
    @Binding var value: String
    var action: HotKeys.Action? = nil
    var defaultValue: String? = nil
    @State private var recording = false
    @State private var monitor: Any?
    @State private var hint: String?

    private var conflict: Bool {
        guard let action, let hk = HotKeys.active else { return false }
        return hk.registered[action] == false
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let hint { Text(hint).font(.system(size: 10)).foregroundStyle(.secondary) }
                else if conflict { Text("Not available — another app or macOS owns this shortcut").font(.system(size: 10)).foregroundStyle(.orange) }
            }
            Spacer()
            if let defaultValue, defaultValue != value, !recording {
                Button { value = defaultValue; apply() } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.borderless).help("Reset to default (\(HotKeyField.describe(defaultValue)))")
            }
            Button(recording ? "Press keys…" : HotKeyField.describe(value)) { recording ? stop() : start() }
                .buttonStyle(.bordered).monospaced()
                .tint(recording ? .accentColor : (conflict ? .orange : nil))
        }
        .onDisappear { if recording { stop() } }
    }

    private func start() {
        recording = true
        hint = "Press a combination with ⌘, ⌃ or ⌥ · Esc cancels"
        // The live shortcuts would swallow the key press before it reaches us.
        HotKeys.active?.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if event.keyCode == 53 { stop(); return nil }  // Escape cancels
            guard !flags.isEmpty, flags != [.shift] else {
                hint = "Add ⌘, ⌃ or ⌥ — a plain key would block typing everywhere"
                return nil
            }
            var mods: UInt32 = 0
            if flags.contains(.command) { mods |= UInt32(cmdKey) }
            if flags.contains(.control) { mods |= UInt32(controlKey) }
            if flags.contains(.option) { mods |= UInt32(optionKey) }
            if flags.contains(.shift) { mods |= UInt32(shiftKey) }
            value = "\(event.keyCode):\(mods)"
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        hint = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        apply()
    }

    /// Re-register everything, then surface whether the system accepted it.
    private func apply() {
        HotKeys.active?.resume()
        NotificationCenter.default.post(name: .hotKeysChanged, object: nil)
        if conflict { hint = nil }
    }

    static func parse(_ s: String) -> (keyCode: UInt32, modifiers: UInt32)? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let k = UInt32(parts[0]), let m = UInt32(parts[1]) else { return nil }
        return (k, m)
    }

    static func describe(_ s: String) -> String {
        guard let (k, m) = parse(s) else { return "—" }
        var out = ""
        if m & UInt32(controlKey) != 0 { out += "⌃" }
        if m & UInt32(optionKey) != 0 { out += "⌥" }
        if m & UInt32(shiftKey) != 0 { out += "⇧" }
        if m & UInt32(cmdKey) != 0 { out += "⌘" }
        return out + keyName(Int(k))
    }

    private static func keyName(_ code: Int) -> String {
        let names: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
            kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
            kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
            kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9", kVK_ANSI_0: "0",
            kVK_Space: "Space", kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        return names[code] ?? "key\(code)"
    }
}

extension Notification.Name {
    static let hotKeysChanged = Notification.Name("ScreenRecorder.hotKeysChanged")
}
