// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenRecorder",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ScreenRecorder",
            path: "Sources/ScreenRecorder",
            swiftSettings: [.swiftLanguageMode(.v5)],
            // AVKit must be linked explicitly: SwiftUI's VideoPlayer lives in the
            // _AVKit_SwiftUI overlay, whose classes subclass AVPlayerView. If the
            // code never names an AVKit class directly the linker drops the
            // framework, and the runtime aborts resolving the superclass.
            linkerSettings: [.linkedFramework("AVKit")]
        )
    ]
)
