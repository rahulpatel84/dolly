import AVFoundation
import AppKit
import ScreenCaptureKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private(set) var statusItem: NSStatusItem!
    private let engine = CaptureEngine()
    private var elapsedTimer: Timer?
    private var recordingStart: Date?

    let dashboard = DashboardWindowController()
    var engineIsRecording: Bool { engine.isRecording }
    private let regionSelector = RegionSelector()
    private let shotRegionSelector = RegionSelector()
    private let countdown = CountdownOverlay()
    private let hotKeys = HotKeys()
    private let overlay = DrawingOverlay()
    private let audioRecorder = AudioRecorder()
    private var webcamOnly: WebcamRecorder?
    private var webcamOnlyURL: URL?
    let settingsWindow = SettingsWindowController()
    private var settings: AppSettings { AppSettings.shared }
    private var limitTimer: Timer?
    private var scheduleTimer: Timer?
    private var scheduledFor: Date?
    private var useCountdown: Bool { settings.countdownEnabled }
    private var targets = ShareableTargets(displays: [], windows: [])

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Refuse to run as a duplicate, or from a read-only disk image.
        // Showcase runs unattended from the build folder: no guards or prompts.
        if Showcase.outputDir == nil, FeatureAudit.dir == nil {
            guard LaunchGuards.check() else { return NSApp.terminate(nil) }
        }

        AppSettings.applyAppearance(AppSettings.shared.appearance)
        buildMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIdleIcon()
        buildMenu()

        engine.onUnexpectedStop = { [weak self] error, result in
            Task { @MainActor in self?.handleUnexpectedStop(error, result) }
        }

        if !Permissions.hasScreenRecording, Showcase.outputDir == nil, FeatureAudit.dir == nil {
            Permissions.requestScreenRecording()
        }
        refreshTargets()

        dashboard.show()
        NSApp.activate(ignoringOtherApps: true)
        Showcase.runIfRequested(delegate: self)
        FeatureAudit.runIfRequested(delegate: self)

        hotKeys.register { [weak self] action in
            guard let self else { return }
            switch action {
            case .toggleRecording:
                if self.engine.isRecording { self.stopTapped() } else { self.startTapped() }
            case .screenshot:
                self.screenshotScreenTapped()
            case .pause:
                if self.engine.isRecording { self.pauseTapped() }
            case .screenshotArea:
                self.screenshotAreaTapped()
            case .screenshotWindow:
                self.screenshotWindowTapped()
            case .recordArea:
                if !self.engine.isRecording { self.recordAreaTapped() }
            case .drawToggle:
                if self.engine.isRecording { self.overlay.toggle() }
            case .recordLastArea:
                if !self.engine.isRecording { self.recordLastAreaTapped() }
            }
        }
    }

    /// Closing the window keeps the app alive in the Dock and menu bar, like
    /// Music or Messages. Quit is explicit.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Clicking the Dock icon with no windows open brings the dashboard back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { dashboard.show() }
        return true
    }

    /// Quit while recording: finish the file before the process goes away.
    /// Synchronous on purpose -- see CaptureEngine.stopSynchronously.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard engine.isRecording else { return .terminateNow }
        _ = engine.stopSynchronously()
        ActiveRecording.shared.url = nil
        return .terminateNow
    }

    /// Used by --selftest-quit: start a full-screen recording without the UI.
    func selfTestStartRecording() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        Task { @MainActor in
            guard let display = (try? await ShareableTargets.current())?.displays.first else { return }
            beginNow(.display(display))
        }
    }

    func selfTestSimulateUnexpectedStop() { engine.simulateUnexpectedStop() }

    /// Quick actions for the dashboard header.
    func quickAction(_ name: String) {
        switch name {
        case "screen": startTapped()
        case "area": recordAreaTapped()
        case "window": buildMenu(); statusItem.button?.performClick(nil)
        case "shot": screenshotScreenTapped()
        case "shotArea": screenshotAreaTapped()
        case "audio": recordAudioTapped()
        case "webcam": recordWebcamOnlyTapped()
        default: break
        }
    }

    // MARK: - Main menu bar

    private func item(_ title: String, _ action: Selector?, _ key: String = "",
                      _ mods: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.keyEquivalentModifierMask = mods
        it.target = action.map { _ in self }
        return it
    }

    /// The standard macOS menu bar. Edit-menu items use responder-chain
    /// selectors with no target so text fields handle them natively.
    private func buildMainMenu() {
        let main = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(item("About \(Brand.name)", #selector(showAbout)))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings…", #selector(showSettings), ","))
        appMenu.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu()
        services.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(services)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide \(Brand.name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit \(Brand.name)", #selector(quitTapped), "q"))
        let appItem = NSMenuItem(); appItem.submenu = appMenu
        main.addItem(appItem)

        // File
        let file = NSMenu(title: "File")
        file.addItem(item("Record Full Screen", #selector(startTapped), "r", [.command, .control]))
        file.addItem(item("Record Area…", #selector(recordAreaTapped), "r", [.command, .control, .shift]))
        file.addItem(item("Screenshot Screen", #selector(screenshotScreenTapped), "s", [.command, .control]))
        file.addItem(item("Screenshot Area…", #selector(screenshotAreaTapped), "s", [.command, .control, .shift]))
        file.addItem(item("Screenshot Window…", #selector(screenshotWindowTapped)))
        file.addItem(.separator())
        file.addItem(item("Open Recordings Folder", #selector(openFolder)))
        file.addItem(.separator())
        file.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: ""); fileItem.submenu = file
        main.addItem(fileItem)

        // Edit (responder chain)
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); editItem.submenu = edit
        main.addItem(editItem)

        // Recording
        let rec = NSMenu(title: "Recording")
        rec.addItem(item("Pause / Resume", #selector(pauseTapped), "p", [.command, .control]))
        rec.addItem(item("Stop Recording", #selector(stopTapped), ".", [.command]))
        rec.addItem(.separator())
        rec.addItem(item("Include Microphone", #selector(toggleMic)))
        rec.addItem(item("Record Webcam", #selector(toggleWebcam)))
        let recItem = NSMenuItem(title: "Recording", action: nil, keyEquivalent: ""); recItem.submenu = rec
        recItem.submenu?.delegate = self
        main.addItem(recItem)

        // View
        let view = NSMenu(title: "View")
        view.addItem(item("Recordings", #selector(showDashboard), "r"))
        let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: ""); viewItem.submenu = view
        main.addItem(viewItem)

        // Window
        let window = NSMenu(title: "Window")
        window.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        window.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: ""))
        window.addItem(.separator())
        window.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: ""); windowItem.submenu = window
        main.addItem(windowItem)
        NSApp.windowsMenu = window

        // Help
        let help = NSMenu(title: "Help")
        help.addItem(item("Dolly User Guide", #selector(openUserGuide)))
        help.addItem(item("Install Guide", #selector(openInstallGuide)))
        help.addItem(item("Dolly Website", #selector(openWebsite)))
        help.addItem(item("Grant Screen Recording Permission…", #selector(fixPermission)))
        let helpItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: ""); helpItem.submenu = help
        main.addItem(helpItem)
        NSApp.helpMenu = help

        NSApp.mainMenu = main
    }

    @objc private func openUserGuide() {
        if let url = Bundle.main.url(forResource: "User Guide", withExtension: "md") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(string: "https://github.com/rahulpatel84/dolly/blob/master/ScreenRecorder/GUIDE.md")!)
        }
    }

    @objc private func openWebsite() { NSWorkspace.shared.open(URL(string: "https://screen-recorder-site.vercel.app")!) }

    @objc private func openInstallGuide() {
        if let url = Bundle.main.url(forResource: "Install Guide", withExtension: "md") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(string: "https://github.com/rahulpatel84/dolly#install")!)
        }
    }

    /// Keeps the Recording menu's toggles in sync with Settings.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == "Recording" else { return }
        for it in menu.items {
            switch it.title {
            case "Include Microphone": it.state = settings.includeMicrophone ? .on : .off
            case "Record Webcam": it.state = settings.webcamEnabled ? .on : .off
            case "Pause / Resume", "Stop Recording": it.isEnabled = engine.isRecording
            default: break
            }
        }
    }

    // MARK: - Status-bar menu

    /// Our own glyph, as a template image so macOS tints it for the menu bar.
    private static let menuBarIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
            let image = NSImage(contentsOf: url)
        else { return nil }
        if let url2x = Bundle.main.url(forResource: "MenuBarIcon@2x", withExtension: "png"),
            let rep = NSImageRep(contentsOf: url2x)
        {
            rep.size = NSSize(width: 18, height: 18)
            image.addRepresentation(rep)
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    private func setIdleIcon() {
        statusItem.button?.image =
            Self.menuBarIcon
            ?? NSImage(systemSymbolName: "record.circle", accessibilityDescription: Brand.name)
        statusItem.button?.title = ""
    }

    private func setRecordingIcon() {
        statusItem.button?.image = NSImage(
            systemSymbolName: "stop.circle.fill", accessibilityDescription: "Recording")
    }

    private func buildMenu() {
        let menu = NSMenu()

        if audioRecorder.isRecording {
            let stop = NSMenuItem(title: "Stop Audio Recording", action: #selector(stopAudioTapped), keyEquivalent: "")
            stop.target = self; menu.addItem(stop)
        } else if webcamOnly != nil {
            let stop = NSMenuItem(title: "Stop Webcam Recording", action: #selector(stopWebcamOnlyTapped), keyEquivalent: "")
            stop.target = self; menu.addItem(stop)
        } else if engine.isRecording {
            let elapsed = recordingStart.map { Date().timeIntervalSince($0) } ?? 0
            let stop = NSMenuItem(
                title: "Stop Recording  (\(Self.format(elapsed)))", action: #selector(stopTapped),
                keyEquivalent: "")
            stop.target = self
            stop.toolTip = "⌃⌘R"
            menu.addItem(stop)

            let pause = NSMenuItem(
                title: engine.isPaused ? "Resume Recording" : "Pause Recording",
                action: #selector(pauseTapped), keyEquivalent: "")
            pause.target = self
            pause.toolTip = "⌃⌘P"
            menu.addItem(pause)

            let draw = NSMenuItem(title: overlay.isDrawing ? "Stop Drawing" : "Draw on Screen", action: #selector(drawTapped), keyEquivalent: "")
            draw.target = self; draw.toolTip = "⌃⌘D"
            menu.addItem(draw)
        } else {
            let start = NSMenuItem(
                title: "Record Full Screen", action: #selector(startTapped), keyEquivalent: "")
            start.target = self
            start.toolTip = "⌃⌘R"
            menu.addItem(start)

            let area = NSMenuItem(
                title: "Record Area…", action: #selector(recordAreaTapped), keyEquivalent: "")
            area.target = self
            menu.addItem(area)

            if !settings.lastArea.isEmpty {
                let last = NSMenuItem(title: "Record Last Area Again", action: #selector(recordLastAreaTapped), keyEquivalent: "")
                last.target = self; last.toolTip = "⌃⌥⌘R"
                menu.addItem(last)
            }
            let audioItem = NSMenuItem(title: "Record Audio Only", action: #selector(recordAudioTapped), keyEquivalent: "")
            audioItem.target = self
            menu.addItem(audioItem)
            let camItem = NSMenuItem(title: "Record Webcam Only", action: #selector(recordWebcamOnlyTapped), keyEquivalent: "")
            camItem.target = self
            menu.addItem(camItem)

            if let when = scheduledFor {
                let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
                let cancel = NSMenuItem(
                    title: "Cancel Scheduled Recording (\(f.string(from: when)))",
                    action: #selector(cancelScheduled), keyEquivalent: "")
                cancel.target = self
                menu.addItem(cancel)
            } else {
                let sched = NSMenuItem(
                    title: "Schedule Recording…", action: #selector(scheduleTapped), keyEquivalent: "")
                sched.target = self
                menu.addItem(sched)
            }

            // Window submenu, grouped by application.
            let windowItem = NSMenuItem(title: "Record Window", action: nil, keyEquivalent: "")
            let windowMenu = NSMenu()
            if targets.windows.isEmpty {
                let none = NSMenuItem(title: "No windows found", action: nil, keyEquivalent: "")
                none.isEnabled = false
                windowMenu.addItem(none)
            } else {
                for (index, window) in targets.windows.prefix(40).enumerated() {
                    let app = window.owningApplication?.applicationName ?? "?"
                    let title = window.title ?? "Untitled"
                    let short = title.count > 45 ? String(title.prefix(45)) + "…" : title
                    let item = NSMenuItem(
                        title: "\(app) — \(short)", action: #selector(recordWindowTapped(_:)),
                        keyEquivalent: "")
                    item.target = self
                    item.tag = index
                    windowMenu.addItem(item)
                }
            }
            windowItem.submenu = windowMenu
            menu.addItem(windowItem)

            // Display submenu only when there is a choice to make.
            if targets.displays.count > 1 {
                let displayItem = NSMenuItem(
                    title: "Record Display", action: nil, keyEquivalent: "")
                let displayMenu = NSMenu()
                for (index, display) in targets.displays.enumerated() {
                    let item = NSMenuItem(
                        title: display.localizedName,
                        action: #selector(recordDisplayTapped(_:)), keyEquivalent: "")
                    item.target = self
                    item.tag = index
                    displayMenu.addItem(item)
                }
                displayItem.submenu = displayMenu
                menu.addItem(displayItem)
            }

            menu.addItem(.separator())

            let shotScreen = NSMenuItem(
                title: "Screenshot Screen", action: #selector(screenshotScreenTapped),
                keyEquivalent: "")
            shotScreen.target = self
            shotScreen.toolTip = "⌃⌘S"
            menu.addItem(shotScreen)

            let shotArea = NSMenuItem(
                title: "Screenshot Area…", action: #selector(screenshotAreaTapped),
                keyEquivalent: "")
            shotArea.target = self
            menu.addItem(shotArea)

            let shotWindow = NSMenuItem(
                title: "Screenshot Window…", action: #selector(screenshotWindowTapped),
                keyEquivalent: "")
            shotWindow.target = self
            menu.addItem(shotWindow)

            menu.addItem(.separator())

            let mic = NSMenuItem(
                title: "Include Microphone", action: #selector(toggleMic), keyEquivalent: "")
            mic.target = self
            mic.state = settings.includeMicrophone ? .on : .off
            menu.addItem(mic)

            let cam = NSMenuItem(
                title: "Record Webcam", action: #selector(toggleWebcam), keyEquivalent: "")
            cam.target = self
            cam.state = settings.webcamEnabled ? .on : .off
            menu.addItem(cam)

            let prefs = NSMenuItem(
                title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
            prefs.target = self
            menu.addItem(prefs)
        }

        menu.addItem(.separator())

        let dash = NSMenuItem(
            title: "Recordings…", action: #selector(showDashboard), keyEquivalent: "r")
        dash.target = self
        menu.addItem(dash)

        let reveal = NSMenuItem(
            title: "Open Recordings Folder", action: #selector(openFolder), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)

        if !Permissions.hasScreenRecording {
            let warn = NSMenuItem(
                title: "Grant Screen Recording Permission…", action: #selector(fixPermission),
                keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
        }

        menu.addItem(.separator())
        let about = NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit", action: #selector(quitTapped), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        menu.delegate = self
        statusItem.menu = menu
    }

    /// Enumerating windows is an async call, so the list is refreshed in the
    /// background and the menu rebuilt when it arrives.
    private func refreshTargets() {
        Task { @MainActor in
            guard let fresh = try? await ShareableTargets.current() else { return }
            self.targets = fresh
            if !self.engine.isRecording { self.buildMenu() }
        }
    }

    // MARK: - Actions

    @objc private func drawTapped() { overlay.toggle(); buildMenu() }

    @objc private func recordLastAreaTapped() {
        let parts = settings.lastArea.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 5 else { return }
        Task { @MainActor in
            guard let fresh = try? await ShareableTargets.current(),
                  let display = fresh.displays.first(where: { $0.displayID == CGDirectDisplayID(parts[0]) }) ?? fresh.displays.first
            else { return }
            begin(.region(display, CGRect(x: parts[1], y: parts[2], width: parts[3], height: parts[4])))
        }
    }

    @objc private func recordAudioTapped() {
        Task { @MainActor in
            do {
                _ = try await audioRecorder.start(includeMicrophone: settings.includeMicrophone)
                recordingStart = Date()
                statusItem.button?.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Recording audio")
                startElapsedTimer(); buildMenu()
            } catch { presentError("Could not start audio recording", error.localizedDescription) }
        }
    }

    @objc private func stopAudioTapped() {
        Task { @MainActor in
            let url = await audioRecorder.stop()
            stopElapsedTimer(); setIdleIcon(); recordingStart = nil; buildMenu()
            if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }

    @objc private func recordWebcamOnlyTapped() {
        Task { @MainActor in
            guard await Permissions.ensureCamera() else { return }
            startWebcamOnly()
        }
    }

    private func startWebcamOnly() {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = CaptureEngine.recordingsDirectory().appendingPathComponent("Webcam \(f.string(from: Date())).mov")
        let cam = WebcamRecorder()
        do {
            try cam.start(besideVideoAt: url.deletingPathExtension().appendingPathExtension("mov"), deviceID: settings.webcamDeviceID, clock: RecordingClock())
            webcamOnly = cam; webcamOnlyURL = url
            recordingStart = Date()
            statusItem.button?.image = NSImage(systemSymbolName: "video.circle.fill", accessibilityDescription: "Recording webcam")
            startElapsedTimer(); buildMenu()
        } catch { presentError("Could not start webcam", error.localizedDescription) }
    }

    @objc private func stopWebcamOnlyTapped() {
        guard let cam = webcamOnly else { return }
        Task { @MainActor in
            let out = await cam.stop()
            webcamOnly = nil
            stopElapsedTimer(); setIdleIcon(); recordingStart = nil; buildMenu()
            if let out { NSWorkspace.shared.activateFileViewerSelecting([out]) }
        }
    }

    @objc private func scheduleTapped() {
        let alert = NSAlert()
        alert.messageText = "Schedule a full-screen recording"
        alert.informativeText = "Recording starts at the chosen time and stops after the chosen length."
        let picker = NSDatePicker(frame: NSRect(x: 0, y: 30, width: 220, height: 24))
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay, .hourMinute]
        picker.dateValue = Date().addingTimeInterval(300)
        let length = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        length.addItems(withTitles: ["5 minutes", "15 minutes", "30 minutes", "60 minutes"])
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 56))
        box.addSubview(picker); box.addSubview(length)
        alert.accessoryView = box
        alert.addButton(withTitle: "Schedule")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let minutes = [5, 15, 30, 60][max(0, length.indexOfSelectedItem)]
        let when = picker.dateValue
        scheduledFor = when
        scheduleTimer = Timer(fire: when, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.scheduledFor = nil
                let previous = self.settings.maxDurationMinutes
                self.settings.maxDurationMinutes = minutes
                self.startTapped()
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.settings.maxDurationMinutes = previous }
            }
        }
        RunLoop.main.add(scheduleTimer!, forMode: .common)
        buildMenu()
    }

    @objc private func cancelScheduled() {
        scheduleTimer?.invalidate(); scheduleTimer = nil; scheduledFor = nil
        buildMenu()
    }

    @objc private func showSettings() {
        settingsWindow.show()
    }

    @objc private func toggleWebcam() {
        settings.webcamEnabled.toggle()
        if settings.webcamEnabled {
            Task { @MainActor in
                if !(await Permissions.ensureCamera()) { settings.webcamEnabled = false }
                buildMenu()
            }
        }
        buildMenu()
    }

    @objc private func pauseTapped() {
        if engine.isPaused {
            engine.resume()
            setRecordingIcon()
        } else {
            engine.pause()
            statusItem.button?.image = NSImage(
                systemSymbolName: "pause.circle.fill", accessibilityDescription: "Paused")
        }
        buildMenu()
    }

    @objc private func screenshotScreenTapped() {
        Task { @MainActor in
            var display = targets.displays.first
            if display == nil {
                display = (try? await ShareableTargets.current())?.displays.first
            }
            guard let display else { return }
            await takeScreenshot(.display(display))
        }
    }

    @objc private func screenshotAreaTapped() {
        guard Permissions.hasScreenRecording else {
            Permissions.presentScreenRecordingDenied()
            return
        }
        shotRegionSelector.present { [weak self] result in
            guard let self, let result else { return }
            Task { @MainActor in
                guard let target = await self.resolve(result) else { return }
                await self.takeScreenshot(target)
            }
        }
    }

    /// Window screenshot: a one-shot picker overlay. Click a window.
    @objc private func screenshotWindowTapped() {
        guard Permissions.hasScreenRecording else { Permissions.presentScreenRecordingDenied(); return }
        Task { @MainActor in
            guard let fresh = try? await ShareableTargets.current(), !fresh.windows.isEmpty else {
                return presentError("No windows", "No capturable windows were found.")
            }
            // The window under the mouse is the usual intent; fall back to a menu.
            let mouse = NSEvent.mouseLocation
            let primaryH = NSScreen.screens.first?.frame.maxY ?? 0
            let cgPoint = CGPoint(x: mouse.x, y: primaryH - mouse.y)
            if let hit = fresh.windows.first(where: { $0.frame.contains(cgPoint) }) {
                await takeScreenshot(.window(hit))
            } else {
                let menu = NSMenu()
                for (i, w) in fresh.windows.prefix(30).enumerated() {
                    let item = NSMenuItem(title: "\(w.owningApplication?.applicationName ?? "?") — \(w.title ?? "")", action: #selector(windowMenuPicked(_:)), keyEquivalent: "")
                    item.target = self; item.tag = i
                    menu.addItem(item)
                }
                self.targets = fresh
                menu.popUp(positioning: nil, at: mouse, in: nil)
            }
        }
    }

    @objc private func windowMenuPicked(_ sender: NSMenuItem) {
        guard targets.windows.indices.contains(sender.tag) else { return }
        let w = targets.windows[sender.tag]
        Task { @MainActor in await takeScreenshot(.window(w)) }
    }

    private func takeScreenshot(_ target: CaptureTarget) async {
        guard Permissions.hasScreenRecording else {
            Permissions.presentScreenRecordingDenied()
            return
        }
        do {
            let shot = try await Screenshotter.captureImage(target: target)
            flashStatusIcon()
            switch settings.afterScreenshot {
            case "editor": ScreenshotEditorWindows.shared.open(image: shot.image, sourceURL: shot.url, saved: shot.saved)
            case "preview": ScreenshotPreview.shared.show(image: shot.image, url: shot.url)
            default: break  // copy / none: saved and copied in the background
            }
        } catch {
            presentError("Screenshot failed", error.localizedDescription)
        }
    }

    private func flashStatusIcon() {
        statusItem.button?.image = NSImage(
            systemSymbolName: "camera.fill", accessibilityDescription: "Captured")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated { self?.setIdleIcon() }
        }
    }

    @objc private func toggleMic() {
        settings.includeMicrophone.toggle()
        if settings.includeMicrophone, Permissions.microphoneStatus == .notDetermined {
            Task { _ = await Permissions.requestMicrophone() }
        }
        buildMenu()
    }

    @objc private func startTapped() {
        Task { @MainActor in
            // `??` takes a non-async autoclosure, so the fallback cannot be
            // awaited inline.
            var display = targets.displays.first
            if display == nil {
                display = (try? await ShareableTargets.current())?.displays.first
            }
            guard let display else {
                return presentError("No display", "No display is available to record.")
            }
            begin(.display(display))
        }
    }

    @objc private func recordDisplayTapped(_ sender: NSMenuItem) {
        guard targets.displays.indices.contains(sender.tag) else { return }
        begin(.display(targets.displays[sender.tag]))
    }

    @objc private func recordWindowTapped(_ sender: NSMenuItem) {
        guard targets.windows.indices.contains(sender.tag) else { return }
        begin(.window(targets.windows[sender.tag]))
    }

    @objc private func recordAreaTapped() {
        guard Permissions.hasScreenRecording else {
            Permissions.presentScreenRecordingDenied()
            return
        }
        regionSelector.present { [weak self] result in
            guard let self, let result else { return }
            Task { @MainActor in
                guard let target = await self.resolve(result) else { return }
                if case .region(let d, let rect) = target {
                    self.settings.lastArea = "\(d.displayID),\(rect.minX),\(rect.minY),\(rect.width),\(rect.height)"
                }
                self.begin(target)
            }
        }
    }

    /// A dragged region becomes a region target; a click becomes the window
    /// under that point (or the whole display if nothing is there).
    private func resolve(_ choice: RegionChoice) async -> CaptureTarget? {
        guard let fresh = try? await ShareableTargets.current() else { return nil }
        func display(for screen: NSScreen) -> SCDisplay? {
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return fresh.displays.first { $0.displayID == id }
        }
        switch choice {
        case .region(let screen, let rect):
            guard let d = display(for: screen) else { return nil }
            return .region(d, rect)
        case .click(let screen, let local):
            guard let d = display(for: screen) else { return nil }
            let bounds = CGDisplayBounds(d.displayID)
            let global = CGPoint(x: bounds.minX + local.x, y: bounds.minY + local.y)
            // Topmost window under the point. SCK lists windows front-to-back.
            if let hit = fresh.windows.first(where: { $0.frame.contains(global) }) { return .window(hit) }
            return .display(d)
        }
    }

    private func begin(_ target: CaptureTarget) {
        guard Permissions.hasScreenRecording else {
            Permissions.presentScreenRecordingDenied()
            return
        }
        guard useCountdown else { return beginNow(target) }
        countdown.run { [weak self] in self?.beginNow(target) }
    }

    private func beginNow(_ target: CaptureTarget) {
        Task { @MainActor in
            do {
                // The drawing overlay must exist before the stream starts so
                // ScreenCaptureKit can be told to keep it.
                let screen: NSScreen? = {
                    switch target {
                    case .display(let d), .region(let d, _):
                        return NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == d.displayID }
                    case .window(let w):
                        return NSScreen.screens.first { $0.frame.intersects(w.frame) }
                    }
                }()
                if let screen { overlay.prepare(on: screen) }
                var options = CaptureEngine.Options()
                options.overlayWindowNumber = overlay.windowNumber
                if settings.webcamEnabled, !(await Permissions.ensureCamera()) {
                    settings.webcamEnabled = false
                }
                options.captureMicrophone = settings.includeMicrophone
                options.frameRate = settings.frameRate
                options.qualityFactor = settings.quality.bitrateFactor
                options.webcam = settings.webcamEnabled
                options.webcamDeviceID = settings.webcamDeviceID
                let url = try await engine.start(target: target, options: options)
                ActiveRecording.shared.url = url
                recordingStart = Date()
                if settings.maxDurationMinutes > 0 {
                    limitTimer = Timer.scheduledTimer(
                        withTimeInterval: Double(settings.maxDurationMinutes) * 60, repeats: false
                    ) { [weak self] _ in MainActor.assumeIsolated { self?.stopTapped() } }
                }
                setRecordingIcon()
                startElapsedTimer()
                buildMenu()
            } catch {
                presentError("Could not start recording", error.localizedDescription)
            }
        }
    }

    @objc private func stopTapped() {
        limitTimer?.invalidate(); limitTimer = nil
        Task { @MainActor in
            let result = await engine.stop()
            overlay.tearDown()
            ActiveRecording.shared.url = nil
            stopElapsedTimer()
            setIdleIcon()
            recordingStart = nil
            buildMenu()
            if let result { presentFinished(result) }
        }
    }

    @objc private func showDashboard() {
        dashboard.show()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(
            options: [
                .applicationName: Brand.name,
                .applicationVersion: Brand.version,
                .credits: {
                    let text = NSMutableAttributedString()
                    let bold: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 11)]
                    let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11)]
                    text.append(NSAttributedString(string: "Developer\n", attributes: bold))
                    text.append(NSAttributedString(string: "Rahul Patel\n\n", attributes: body))
                    text.append(NSAttributedString(string: "How it works\n", attributes: bold))
                    text.append(NSAttributedString(
                        string: "Records a clean stream plus a cursor-telemetry sidecar, then applies "
                            + "zoom, cursor framing and click emphasis afterwards. Effects are never "
                            + "burned into the pixels, so any recording can be re-polished.\n\n",
                        attributes: body))
                    text.append(NSAttributedString(string: "Shortcuts\n", attributes: bold))
                    text.append(NSAttributedString(
                        string: "⌃⌘R record · ⌃⌘P pause · ⌃⌘S screenshot · ⌘R recordings · ⌘, settings",
                        attributes: body))
                    return text
                }(),
            ])
    }

    @objc private func openFolder() {
        NSWorkspace.shared.open(CaptureEngine.recordingsDirectory())
    }

    @objc private func fixPermission() {
        Permissions.openScreenRecordingSettings()
    }

    @objc private func quitTapped() {
        NSApp.terminate(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        if !engine.isRecording { refreshTargets() }
    }

    // MARK: - Elapsed time in the menu bar

    private func startElapsedTimer() {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let start = self.recordingStart, !self.engine.isPaused
                else { return }
                self.statusItem.button?.title = " " + Self.format(Date().timeIntervalSince(start))
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        statusItem.button?.title = ""
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - Reporting

    private func handleUnexpectedStop(_ error: Error, _ result: CaptureEngine.Result?) {
        overlay.tearDown()
        stopElapsedTimer()
        setIdleIcon()
        recordingStart = nil
        ActiveRecording.shared.url = nil
        buildMenu()
        if CommandLine.arguments.contains(where: { $0.hasPrefix("--selftest") }) { return }
        if let result {
            // The file was finalised and is playable; say so, and why it ended.
            let alert = NSAlert()
            alert.messageText = "Recording ended by macOS"
            alert.informativeText =
                "macOS stopped the screen capture (\(error.localizedDescription)).\n\n"
                + "What was captured has been saved and is playable:\n"
                + "\(result.videoURL.lastPathComponent) — \(Self.format(result.duration)), "
                + "\(result.framesWritten) frames."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Recordings…")
            alert.addButton(withTitle: "OK")
            if alert.runModal() == .alertFirstButtonReturn { dashboard.show() }
        } else {
            presentError("Recording stopped", error.localizedDescription)
        }
    }

    /// Dropped frames are reported rather than hidden. A recorder that
    /// stutters under load is the failure mode that matters, and a number the
    /// user can see is the only way it gets noticed.
    private func presentFinished(_ result: CaptureEngine.Result) {
        let total = result.framesWritten + result.framesDropped
        let dropRate = total > 0 ? Double(result.framesDropped) / Double(total) * 100 : 0

        let alert = NSAlert()
        alert.messageText = "Recording saved"
        var lines = [
            result.videoURL.lastPathComponent,
            "",
            String(format: "Duration: %@", Self.format(result.duration)),
            "Frames written: \(result.framesWritten)",
            String(format: "Frames dropped: %d (%.1f%%)", result.framesDropped, dropRate),
            "Clicks recorded: \(result.clickCount)",
        ]
        if result.telemetryURL != nil {
            lines.append("Telemetry sidecar written")
        }
        if result.webcamURL != nil {
            lines.append("Webcam recorded alongside")
        }
        alert.informativeText = lines.joined(separator: "\n")
        alert.alertStyle = dropRate > 5 ? .warning : .informational
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "Done")
        alert.addButton(withTitle: "Recordings…")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.activateFileViewerSelecting([result.videoURL])
        case .alertThirdButtonReturn:
            dashboard.show()
        default:
            break
        }
    }

    private func presentError(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
