using System.Net;
using System.Net.Http.Headers;
using QuotaBar.Core;

namespace QuotaBar.Providers;

/// Reads Claude usage from the Anthropic account endpoint that Claude Code's
/// own "Account & Usage" panel uses.
///
/// This is the only code path that reads a credential or uses the network:
/// one GET to api.anthropic.com, authenticated with Claude Code's access token.
/// The endpoint is not publicly documented, so anything unrecognised is
/// reported as unsupported instead of guessed.
public sealed class ClaudeAccountUsageSource(
    IClaudeCredentialProvider credentials,
    HttpMessageHandler? handler = null,
    TimeSpan? minimumInterval = null,
    Func<DateTimeOffset>? now = null)
{
    public static readonly Uri Endpoint = new("https://api.anthropic.com/api/oauth/usage");

    private readonly HttpClient _client = new(handler ?? new HttpClientHandler { UseCookies = false }) { Timeout = TimeSpan.FromSeconds(15) };
    /// The endpoint is not meant for tight polling; never call it more often than this.
    private readonly TimeSpan _minimumInterval = minimumInterval ?? TimeSpan.FromMinutes(2);
    private readonly Func<DateTimeOffset> _now = now ?? (() => DateTimeOffset.Now);
    private readonly SemaphoreSlim _gate = new(1, 1);

    private ClaudeCredential? _credential;
    private ProviderUsage? _lastUsage;
    private DateTimeOffset? _lastFetch;

    public void Reset()
    {
        _credential = null;
        _lastUsage = null;
        _lastFetch = null;
    }

    public async Task<ProviderUsage> FetchAsync(CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var date = _now();
            if (_lastUsage is not null && _lastFetch is { } last && date - last < _minimumInterval)
                return _lastUsage;

            var token = AccessToken(date);
            using var request = new HttpRequestMessage(HttpMethod.Get, Endpoint);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            request.Headers.Add("anthropic-beta", "oauth-2025-04-20");
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            request.Headers.UserAgent.ParseAdd("QuotaBar");

            HttpResponseMessage response;
            try
            {
                response = await _client.SendAsync(request, cancellationToken);
            }
            catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                throw new ProviderException(ProviderErrorKind.TimedOut);
            }
            catch (HttpRequestException)
            {
                throw new ProviderException(ProviderErrorKind.NetworkUnavailable);
            }

            using (response)
            {
                switch (response.StatusCode)
                {
                    case HttpStatusCode.OK:
                        var body = await response.Content.ReadAsStringAsync(cancellationToken);
                        var usage = ClaudeUsageParser.ParseAccountUsage(body, date);
                        _lastUsage = usage;
                        _lastFetch = date;
                        return usage;
                    case HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden:
                        // Claude Code refreshes its own token; QuotaBar must not, because
                        // rotating the refresh token would sign Claude Code out.
                        _credential = null;
                        throw ProviderException.SessionExpired("Claude Code");
                    case HttpStatusCode.TooManyRequests:
                        throw ProviderException.NoUsageData("Anthropic is limiting usage checks; retrying later");
                    default:
                        throw ProviderException.Unsupported($"Usage endpoint returned HTTP {(int)response.StatusCode}");
                }
            }
        }
        finally
        {
            _gate.Release();
        }
    }

    private string AccessToken(DateTimeOffset date)
    {
        if (_credential is not null && !_credential.IsExpired(date))
            return _credential.AccessToken;
        // Re-read: Claude Code may have refreshed the token since last time.
        var fresh = credentials.Read();
        if (fresh.IsExpired(date))
        {
            _credential = null;
            throw ProviderException.SessionExpired("Claude Code");
        }
        _credential = fresh;
        return fresh.AccessToken;
    }
}
