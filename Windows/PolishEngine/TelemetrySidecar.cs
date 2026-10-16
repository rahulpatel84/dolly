using System.Text.Json;
using System.Text.Json.Serialization;

namespace PolishEngine;

/// <summary>
/// The telemetry sidecar written by the recorder. Identical schema on every
/// platform: this file is the contract between a recorder and the polish engine.
/// Coordinates are top-left-origin pixels of the recorded frame.
/// </summary>
public sealed record TelemetrySample(
    [property: JsonPropertyName("t")] double T,
    [property: JsonPropertyName("x")] double X,
    [property: JsonPropertyName("y")] double Y,
    [property: JsonPropertyName("click")] bool Click);

public sealed record TelemetrySidecar(
    [property: JsonPropertyName("version")] int Version,
    [property: JsonPropertyName("sampleRateHz")] int SampleRateHz,
    [property: JsonPropertyName("displayPixelWidth")] int DisplayPixelWidth,
    [property: JsonPropertyName("displayPixelHeight")] int DisplayPixelHeight,
    [property: JsonPropertyName("samples")] IReadOnlyList<TelemetrySample> Samples)
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    public static TelemetrySidecar Load(string path) =>
        JsonSerializer.Deserialize<TelemetrySidecar>(File.ReadAllText(path), Options)
        ?? throw new InvalidDataException($"Could not parse telemetry: {path}");

    public static TelemetrySidecar Parse(string json) =>
        JsonSerializer.Deserialize<TelemetrySidecar>(json, Options)
        ?? throw new InvalidDataException("Could not parse telemetry JSON.");
}
