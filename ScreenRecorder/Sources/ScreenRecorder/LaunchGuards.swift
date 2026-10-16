import AppKit
import Foundation

/// Guards against the two ways a Mac app gets launched wrongly.
///
/// Both were hit in practice: a second copy running from a mounted disk image
/// alongside the installed one, producing two menu-bar icons and two apps
/// fighting over the same recordings folder and the same global hot keys.
@MainActor
enum LaunchGuards {

    /// True when this copy is running from a mounted disk image or any other
    /// read-only volume rather than from a real install location.
    static var isRunningFromDiskImage: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Volumes/")
    }

    /// Another copy of this app, already running.
    static var otherInstance: NSRunningApplication? {
        guard let id = Bundle.main.bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }

    /// Returns false when the app should stop launching.
    static func check() -> Bool {
        if let other = otherInstance {
            let alert = NSAlert()
            alert.messageText = "\(Brand.name) is already running"
            alert.informativeText =
                "Another copy is already in your menu bar. Two copies would each claim "
                + "the global shortcuts and write to the same folder, so this one will quit."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            other.activate()
            return false
        }

        if isRunningFromDiskImage {
            let alert = NSAlert()
            alert.messageText = "Move \(Brand.name) to Applications"
            alert.informativeText =
                "This copy is running from a disk image, which is read-only and will "
                + "disappear when the image is ejected.\n\n"
                + "Screen Recording permission is also tied to where the app lives, so a "
                + "copy on a disk image loses its permission every time you remount it."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Move to Applications")
            alert.addButton(withTitle: "Quit")

            if alert.runModal() == .alertFirstButtonReturn {
                moveToApplications()
            }
            return false
        }

        offerMoveToApplicationsIfNeeded()
        return true
    }

    /// Running from Downloads, the Desktop, or anywhere else that is not an
    /// Applications folder: offer to move, once. Screen Recording permission
    /// is bound to the app's location, so settling it early avoids losing the
    /// grant when the user tidies up later.
    private static func offerMoveToApplicationsIfNeeded() {
        let path = Bundle.main.bundlePath
        let inApplications = path.hasPrefix("/Applications/")
            || path.hasPrefix(NSHomeDirectory() + "/Applications/")
        let isDevBuild = path.contains("/build.noindex/") || path.contains("/.build/")
        guard !inApplications, !isDevBuild else { return }
        guard !UserDefaults.standard.bool(forKey: "declinedMoveToApplications") else { return }

        let alert = NSAlert()
        alert.messageText = "Move \(Brand.name) to the Applications folder?"
        alert.informativeText =
            "It is currently running from \(URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent). "
            + "Keeping it in Applications means its Screen Recording permission stays put and "
            + "it shows up in Spotlight like any other app."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        alert.addButton(withTitle: "Don't Ask Again")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            moveToApplications()
            NSApp.terminate(nil)
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(true, forKey: "declinedMoveToApplications")
        default:
            break
        }
    }

    private static func moveToApplications() {
        let source = URL(fileURLWithPath: Bundle.main.bundlePath)
        let destination = URL(fileURLWithPath: "/Applications")
            .appendingPathComponent(source.lastPathComponent)

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            if isRunningFromDiskImage {
                try FileManager.default.copyItem(at: source, to: destination)
            } else {
                try FileManager.default.moveItem(at: source, to: destination)
            }
            // Register the new location so Spotlight and the Apps view see it.
            NSWorkspace.shared.open(destination)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not move the app"
            alert.informativeText =
                error.localizedDescription
                + "\n\nDrag Screen Recorder to your Applications folder manually."
            alert.runModal()
        }
    }
}
