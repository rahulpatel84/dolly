import Foundation

/// Which file is being written right now, if any.
///
/// A `.mov` has no `moov` atom until the writer finalises it, so an
/// in-progress recording is a valid file on disk that no player can open.
/// The dashboard needs to know this to avoid offering a Play button that
/// can only fail.
@MainActor
final class ActiveRecording: ObservableObject {
    static let shared = ActiveRecording()
    @Published var url: URL?
    private init() {}
}
