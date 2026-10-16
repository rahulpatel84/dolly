import CoreMedia
import Foundation

/// One timeline shared by every writer in a recording.
///
/// Two jobs. First, pause/resume: while paused, samples are dropped, and on
/// resume the gap is subtracted from every later timestamp so the output has
/// no hole. Second, alignment: the screen and webcam files both start their
/// sessions at the same host-clock instant, so a timestamp in one file means
/// the same moment in the other without any later reconciliation.
final class RecordingClock {

    private let lock = NSLock()
    private(set) var sessionStart: CMTime
    private var pausedTotal: CMTime = .zero
    private var pauseBegan: CMTime?

    init() {
        sessionStart = CMClockGetTime(CMClockGetHostTimeClock())
    }

    var isPaused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pauseBegan != nil
    }

    func pause() {
        lock.lock()
        defer { lock.unlock() }
        guard pauseBegan == nil else { return }
        pauseBegan = CMClockGetTime(CMClockGetHostTimeClock())
    }

    func resume() {
        lock.lock()
        defer { lock.unlock() }
        guard let began = pauseBegan else { return }
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        pausedTotal = CMTimeAdd(pausedTotal, CMTimeSubtract(now, began))
        pauseBegan = nil
    }

    /// Total time spent paused so far, in seconds.
    var pausedSeconds: Double {
        lock.lock()
        defer { lock.unlock() }
        var total = pausedTotal
        if let began = pauseBegan {
            total = CMTimeAdd(
                total, CMTimeSubtract(CMClockGetTime(CMClockGetHostTimeClock()), began))
        }
        return CMTimeGetSeconds(total)
    }

    /// Output timestamp for a captured sample, or nil if it should be dropped
    /// (captured while paused, or before the session began).
    func outputTime(for captured: CMTime) -> CMTime? {
        lock.lock()
        defer { lock.unlock() }
        guard pauseBegan == nil else { return nil }
        guard CMTimeCompare(captured, sessionStart) >= 0 else { return nil }
        return CMTimeSubtract(captured, pausedTotal)
    }

    /// Re-stamps a sample buffer onto the output timeline.
    func retimed(_ sample: CMSampleBuffer) -> CMSampleBuffer? {
        let captured = CMSampleBufferGetPresentationTimeStamp(sample)
        guard let output = outputTime(for: captured) else { return nil }
        if CMTimeCompare(output, captured) == 0 { return sample }

        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sample),
            presentationTimeStamp: output,
            decodeTimeStamp: .invalid)
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault, sampleBuffer: sample,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &copy)
        return status == noErr ? copy : nil
    }
}
