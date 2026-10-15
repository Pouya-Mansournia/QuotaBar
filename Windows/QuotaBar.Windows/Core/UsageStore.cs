namespace QuotaBar.Core;

/// Everything the UI needs to render one provider.
public sealed class ProviderSnapshot
{
    /// Latest successful reading. Kept across failed refreshes.
    public ProviderUsage? Usage { get; set; }
    public ProviderException? LastError { get; set; }
    public DateTimeOffset? LastSuccess { get; set; }

    /// True when a reading is on screen but the most recent refresh failed.
    public bool IsStale => Usage is not null && LastError is not null;
}

/// Runs the enabled providers concurrently and keeps the last good reading of each.
public sealed class UsageStore(IReadOnlyList<IUsageProvider> providers, Func<AIProvider, bool> isEnabled)
{
    private static readonly TimeSpan ProviderTimeout = TimeSpan.FromSeconds(30);

    public Dictionary<AIProvider, ProviderSnapshot> Snapshots { get; } =
        Enum.GetValues<AIProvider>().ToDictionary(p => p, _ => new ProviderSnapshot());

    public DateTimeOffset? LastRefresh { get; private set; }
    public bool IsRefreshing { get; private set; }

    public event Action? Changed;

    public async Task RefreshAsync()
    {
        if (IsRefreshing) return;
        IsRefreshing = true;
        Changed?.Invoke();
        try
        {
            var active = providers.Where(p => isEnabled(p.Provider)).ToList();
            var results = await Task.WhenAll(active.Select(FetchAsync));
            foreach (var (provider, usage, error) in results)
            {
                var snapshot = Snapshots[provider];
                if (usage is not null)
                {
                    snapshot.Usage = usage;
                    snapshot.LastError = null;
                    snapshot.LastSuccess = DateTimeOffset.Now;
                }
                else
                {
                    snapshot.LastError = error;
                }
            }
            LastRefresh = DateTimeOffset.Now;
        }
        finally
        {
            IsRefreshing = false;
            Changed?.Invoke();
        }
    }

    public void Clear(AIProvider provider)
    {
        Snapshots[provider] = new ProviderSnapshot();
        Changed?.Invoke();
    }

    private static async Task<(AIProvider, ProviderUsage?, ProviderException?)> FetchAsync(IUsageProvider provider)
    {
        using var timeout = new CancellationTokenSource(ProviderTimeout);
        try
        {
            return (provider.Provider, await provider.FetchUsageAsync(timeout.Token), null);
        }
        catch (ProviderException error)
        {
            return (provider.Provider, null, error);
        }
        catch (OperationCanceledException)
        {
            return (provider.Provider, null, new ProviderException(ProviderErrorKind.TimedOut));
        }
        catch (Exception error)
        {
            return (provider.Provider, null, new ProviderException(ProviderErrorKind.Unknown, error.Message));
        }
    }
}
