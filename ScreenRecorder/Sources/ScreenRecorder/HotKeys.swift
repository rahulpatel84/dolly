import AppKit
import Carbon.HIToolbox
import Foundation

/// Global keyboard shortcuts.
///
/// Uses Carbon's RegisterEventHotKey rather than an NSEvent global monitor or
/// a CGEventTap. That matters: the event-tap routes would each require the
/// Accessibility or Input Monitoring permission and another approval prompt,
/// whereas registered hot keys need none at all. The API is old but it is the
/// only permission-free way to claim a system-wide shortcut.
@MainActor
final class HotKeys {

    enum Action: UInt32, CaseIterable {
        case toggleRecording = 1
        case screenshot = 2
        case pause = 3
        case screenshotArea = 4
        case screenshotWindow = 5
        case recordArea = 6
        case drawToggle = 7
        case recordLastArea = 8
    }

    /// The app's live instance, so Settings can pause it while a field is
    /// waiting for a key press (a registered combo never reaches NSEvent).
    static weak var active: HotKeys?
    private var refs: [EventHotKeyRef?] = []
    private(set) var registered: [Action: Bool] = [:]
    private var suspended = false

    /// Unregister everything so the next key press reaches the app normally.
    func suspend() {
        suspended = true
        for ref in refs { if let ref { UnregisterEventHotKey(ref) } }
        refs.removeAll()
    }

    func resume() { suspended = false; registerAll() }
    private var handler: EventHandlerRef?
    private var callback: ((Action) -> Void)?

    /// ⌃⌘R toggles recording, ⌃⌘S takes a screenshot, ⌃⌘P pauses/resumes.
    func register(_ callback: @escaping (Action) -> Void) {
        self.callback = callback
        HotKeys.active = self

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return noErr }
                var id = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                let owner = Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue()
                if let action = Action(rawValue: id.id) {
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { owner.callback?(action) }
                    }
                }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)

        registerAll()
        NotificationCenter.default.addObserver(
            forName: .hotKeysChanged, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.registerAll() } }
    }

    /// (Re)registers every shortcut from Settings.
    func registerAll() {
        guard !suspended else { return }
        for ref in refs { if let ref { UnregisterEventHotKey(ref) } }
        refs.removeAll()
        let s = AppSettings.shared
        let table: [(Action, String)] = [
            (.toggleRecording, s.hkToggleRecording), (.screenshot, s.hkScreenshot), (.pause, s.hkPause),
            (.screenshotArea, s.hkScreenshotArea), (.screenshotWindow, s.hkScreenshotWindow),
            (.recordArea, s.hkRecordArea), (.drawToggle, s.hkDrawToggle), (.recordLastArea, s.hkRecordLastArea),
        ]
        for (action, stored) in table {
            guard let (code, mods) = HotKeyField.parse(stored) else { continue }
            add(keyCode: code, modifiers: mods, action: action)
        }
    }

    private func add(keyCode: UInt32, modifiers: UInt32, action: Action) {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x5343_5243), id: action.rawValue)  // 'SCRC'
        let status = RegisterEventHotKey(
            keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            refs.append(ref)
            registered[action] = true
        } else {
            registered[action] = false
            NSLog("Hot key registration failed (\(status)) for \(action); another app may own it.")
        }
    }

    deinit {
        for ref in refs { if let ref { UnregisterEventHotKey(ref) } }
        if let handler { RemoveEventHandler(handler) }
    }
}
