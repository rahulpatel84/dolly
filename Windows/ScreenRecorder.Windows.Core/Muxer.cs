using Windows.Media.Editing;
using Windows.Media.Transcoding;
using Windows.Media.MediaProperties;
using Windows.Storage;

namespace ScreenRecorder.Windows.Core;

/// <summary>
/// Combines the clean video with the system and microphone WAVs into one MP4,
/// using MediaComposition so no third-party muxer is needed.
/// </summary>
public static class Muxer
{
    public static async Task<string> MuxAsync(string videoPath, string systemWav, string? micWav, string outputPath)
    {
        var video = await StorageFile.GetFileFromPathAsync(videoPath);
        var composition = new MediaComposition();
        composition.Clips.Add(await MediaClip.CreateFromFileAsync(video));

        composition.BackgroundAudioTracks.Add(
            await BackgroundAudioTrack.CreateFromFileAsync(await StorageFile.GetFileFromPathAsync(systemWav)));
        if (micWav is not null)
            composition.BackgroundAudioTracks.Add(
                await BackgroundAudioTrack.CreateFromFileAsync(await StorageFile.GetFileFromPathAsync(micWav)));

        var folder = await StorageFolder.GetFolderFromPathAsync(Path.GetDirectoryName(outputPath)!);
        var output = await folder.CreateFileAsync(Path.GetFileName(outputPath), CreationCollisionOption.ReplaceExisting);
        var profile = MediaEncodingProfile.CreateMp4(VideoEncodingQuality.HD1080p);
        var result = await composition.RenderToFileAsync(output, MediaTrimmingPreference.Precise, profile);
        if (result != TranscodeFailureReason.None)
            throw new InvalidOperationException($"Mux failed: {result}");
        return outputPath;
    }
}
