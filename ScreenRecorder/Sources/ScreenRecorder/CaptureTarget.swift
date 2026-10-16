import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// What the user chose to record.
enum CaptureTarget {
    case display(SCDisplay)
    /// A rectangle within a display, in that display's own point coordinates,
    /// top-left origin.
    case region(SCDisplay, CGRect)
    case window(SCWindow)

    var label: String {
        switch self {
        case .display(let d): return "Display \(d.displayID)"
        case .region(_, let r):
            return "Area \(Int(r.width))×\(Int(r.height))"
        case .window(let w):
            return w.title ?? w.owningApplication?.applicationName ?? "Window"
        }
    }
}

/// Snapshot of what can currently be recorded.
struct ShareableTargets {
    let displays: [SCDisplay]
    let windows: [SCWindow]

    static func current() async throws -> ShareableTargets {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)

        let ownBundleID = Bundle.main.bundleIdentifier
        // Windows worth offering: titled, reasonably sized, not our own.
        let windows =
            content.windows
            .filter { window in
                guard let title = window.title, !title.isEmpty else { return false }
                guard window.owningApplication?.bundleIdentifier != ownBundleID else {
                    return false
                }
                return window.frame.width > 120 && window.frame.height > 120
            }
            .sorted {
                let a = $0.owningApplication?.applicationName ?? ""
                let b = $1.owningApplication?.applicationName ?? ""
                return a == b ? ($0.title ?? "") < ($1.title ?? "") : a < b
            }

        return ShareableTargets(displays: content.displays, windows: windows)
    }
}

extension SCDisplay {
    /// Native pixel dimensions, which can differ from the point dimensions
    /// SCDisplay reports on a Retina or scaled display.
    var pixelSize: (width: Int, height: Int) {
        let mode = CGDisplayCopyDisplayMode(displayID)
        return (mode?.pixelWidth ?? width, mode?.pixelHeight ?? height)
    }

    var localizedName: String {
        let bounds = CGDisplayBounds(displayID)
        let isMain = CGDisplayIsMain(displayID) != 0
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
                == displayID
        }
        let name = screen?.localizedName ?? "Display \(displayID)"
        return "\(name) — \(Int(bounds.width))×\(Int(bounds.height))\(isMain ? " (main)" : "")"
    }
}
