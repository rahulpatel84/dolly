import AVFoundation
import AVKit
import SwiftUI

/// Native macOS video player, wrapping AVPlayerView directly.
///
/// Used instead of SwiftUI's VideoPlayer for two reasons: it gives the real
/// macOS controls (scrubber, volume, full-screen toggle), and it references
/// AVKit by name, which guarantees the framework is linked. The SwiftUI
/// VideoPlayer alone left AVKit unlinked and crashed on first use.
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        // Inline: the transport bar is always visible, not hover-only.
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.showsFrameSteppingButtons = true
        view.allowsPictureInPicturePlayback = true
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
