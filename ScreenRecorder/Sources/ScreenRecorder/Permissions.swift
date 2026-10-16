import AVFoundation
import AppKit
import CoreGraphics

/// Permission handling, built second rather than last.
///
/// This is the most common place real screen recorders feel broken: the user
/// grants access, nothing happens, and no one explains why. Screen Recording
/// in particular cannot be granted silently and is re-confirmed periodically
/// by recent macOS versions.
enum Permissions {

    static var hasScreenRecording: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the system prompt. Returns the state immediately afterwards,
    /// which is usually still false -- macOS requires the app to be restarted
    /// after the grant before capture actually works.
    @discardableResult
    static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static var microphoneStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static var cameraStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// True when the camera may be used. Prompts on first use; explains the
    /// Settings route if it was denied before.
    @MainActor
    static func ensureCamera() async -> Bool {
        switch cameraStatus {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default:
            let alert = NSAlert()
            alert.messageText = "Camera access is off"
            alert.informativeText = "Allow \(Brand.name) under System Settings → Privacy & Security → Camera, then try again."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
            }
            return false
        }
    }

    static func openScreenRecordingSettings() {
        let url = URL(
            string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    static func openMicrophoneSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }

    /// Shown when capture is attempted without permission. Explains the
    /// restart requirement, which is the part users never guess.
    static func presentScreenRecordingDenied() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording permission is needed"
        alert.informativeText = """
            This app cannot record until you allow it in System Settings, under \
            Privacy & Security, Screen & System Audio Recording.

            After granting it, quit and reopen this app. macOS does not apply \
            the change to an app that is already running.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            openScreenRecordingSettings()
        }
    }
}
