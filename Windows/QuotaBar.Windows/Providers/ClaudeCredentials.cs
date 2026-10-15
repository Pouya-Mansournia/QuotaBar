using System.Text.Json;
using QuotaBar.Core;

namespace QuotaBar.Providers;

/// The Claude Code sign-in, as far as QuotaBar needs it. Held in memory only.
public sealed record ClaudeCredential(string AccessToken, DateTimeOffset? ExpiresAt)
{
    public bool IsExpired(DateTimeOffset now) => ExpiresAt is { } expires && expires <= now;
}

public interface IClaudeCredentialProvider
{
    ClaudeCredential Read();
}

/// Reads Claude Code's own credentials file, read-only.
///
/// On Windows Claude Code stores its sign-in in `~/.claude/.credentials.json`,
/// readable only by the signed-in user. The token is never written, logged,
/// or refreshed by QuotaBar.
public sealed class ClaudeCredentialsFile(AppPaths paths) : IClaudeCredentialProvider
{
    public bool Exists() => File.Exists(paths.ClaudeCredentialsFile);

    public ClaudeCredential Read()
    {
        string text;
        try
        {
            text = File.ReadAllText(paths.ClaudeCredentialsFile);
        }
        catch (FileNotFoundException)
        {
            throw ProviderException.AuthenticationRequired("Claude Code");
        }
        catch (DirectoryNotFoundException)
        {
            throw ProviderException.AuthenticationRequired("Claude Code");
        }
        catch (UnauthorizedAccessException)
        {
            throw new ProviderException(ProviderErrorKind.PermissionDenied, paths.ClaudeCredentialsFile);
        }
        return Parse(text);
    }

    /// Claude Code stores `{"claudeAiOauth":{"accessToken":…,"expiresAt":<ms>,…}}`.
    public static ClaudeCredential Parse(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            if (Lenient.Object(document.RootElement, "claudeAiOauth") is { } oauth &&
                Lenient.String(oauth, "accessToken") is { Length: > 0 } token)
                return new ClaudeCredential(token, Lenient.Date(oauth, "expiresAt"));
        }
        catch (JsonException)
        {
        }
        // Never include the payload in the error: it contains the token.
        throw ProviderException.AuthenticationRequired("Claude Code");
    }
}
