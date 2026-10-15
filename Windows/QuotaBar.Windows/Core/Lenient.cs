using System.Globalization;
using System.Text.Json;

namespace QuotaBar.Core;

/// Numbers may arrive as strings, timestamps as epoch seconds, milliseconds or
/// ISO 8601. A malformed field is treated as absent instead of failing the document.
public static class Lenient
{
    public static JsonElement? Property(JsonElement element, string name) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) && value.ValueKind != JsonValueKind.Null
            ? value
            : null;

    public static JsonElement? Object(JsonElement element, string name) =>
        Property(element, name) is { ValueKind: JsonValueKind.Object } value ? value : null;

    public static string? String(JsonElement element, string name) =>
        Property(element, name) is { ValueKind: JsonValueKind.String } value ? value.GetString() : null;

    public static double? Number(JsonElement element, params string[] names)
    {
        foreach (var name in names)
        {
            if (Property(element, name) is not { } value) continue;
            if (value.ValueKind == JsonValueKind.Number && value.TryGetDouble(out var number)) return number;
            if (value.ValueKind == JsonValueKind.String &&
                double.TryParse(value.GetString()!.Trim().Trim('%').Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed))
                return parsed;
        }
        return null;
    }

    public static DateTimeOffset? Date(JsonElement element, params string[] names)
    {
        foreach (var name in names)
        {
            if (Property(element, name) is not { } value) continue;
            DateTimeOffset? date = value.ValueKind switch
            {
                JsonValueKind.Number when value.TryGetDouble(out var number) => FromEpoch(number),
                JsonValueKind.String => ParseDate(value.GetString()!),
                _ => null,
            };
            if (date is not null) return date;
        }
        return null;
    }

    public static DateTimeOffset? FromEpoch(double number)
    {
        if (!double.IsFinite(number) || number <= 0) return null;
        // Anything this large can only be milliseconds.
        var seconds = number > 100_000_000_000 ? number / 1000 : number;
        return DateTimeOffset.FromUnixTimeMilliseconds((long)(seconds * 1000));
    }

    public static DateTimeOffset? ParseDate(string text)
    {
        var trimmed = text.Trim();
        if (double.TryParse(trimmed, NumberStyles.Float, CultureInfo.InvariantCulture, out var number))
            return FromEpoch(number);
        return DateTimeOffset.TryParse(trimmed, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var date)
            ? date
            : null;
    }
}
