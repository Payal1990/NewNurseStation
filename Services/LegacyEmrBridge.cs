using System.Collections.Concurrent;
using System.Net;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Caching.Memory;
using NurseStationTablet.Infrastructure;

namespace NurseStationTablet.Services;

/// <summary>
/// Gets the signed EMR link (Daily Flow Sheet, Nurse Care Plan, Pre-Operative Checklist ...) from the legacy Nurse Station
/// page itself. The legacy page builds that link on its own server, with its own signing secret, when a nurse picks a
/// patient and chooses the module, so this app does the same with the user's own legacy session (the "ref"):
///   - open the legacy Nurse Station page once (kept ready for 10 minutes and started in the background when the app opens),
///   - post "this patient + this module" and read the address the page redirects to.
/// Nothing is stored and nothing is changed in the legacy system; the user is signed in to the EMR by the link.
/// </summary>
public sealed class LegacyEmrBridge
{
    private const string P = "ctl00$ContentPlaceHolder1$";
    private static readonly TimeSpan WarmFor = TimeSpan.FromMinutes(10);
    private static readonly TimeSpan LinkFor = TimeSpan.FromMinutes(20);     // the signed link itself is valid for 30 minutes

    private static readonly Regex InputTag = new(@"<input\b[^>]*>", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex SelectTag = new(@"<select\b[^>]*\bname=""([^""]*)""[^>]*>(.*?)</select>", RegexOptions.IgnoreCase | RegexOptions.Singleline | RegexOptions.Compiled);
    private static readonly Regex GridIp = new(@"id=""ContentPlaceHolder1_grdInPatientDtl_lblIpNo_(\d+)""[^>]*>\s*(\d+)\s*<", RegexOptions.Compiled);
    private static readonly Regex Redirect = new(@"RedirectNewTab\('([^']+)'\)", RegexOptions.Compiled);

    private readonly IConfiguration _config;
    private readonly IMemoryCache _cache;
    private readonly ILogger<LegacyEmrBridge> _log;
    private readonly ConcurrentDictionary<string, SemaphoreSlim> _locks = new();
    private readonly ConcurrentDictionary<string, Lazy<Task<string?>>> _inflight = new();

    public LegacyEmrBridge(IConfiguration config, IMemoryCache cache, ILogger<LegacyEmrBridge> log)
    {
        _config = config;
        _cache = cache;
        _log = log;
    }

    /// <summary>A legacy Nurse Station page kept ready for one user: its session cookie, form fields and IP -> grid row map.</summary>
    private sealed class Warm : IDisposable
    {
        public required HttpClient Http { get; init; }
        public required string Url { get; init; }
        public required List<KeyValuePair<string, string>> Fields { get; init; }
        public required Dictionary<long, int> RowByIp { get; init; }
        public void Dispose() => Http.Dispose();
    }

    /// <summary>Start the legacy page in the background so the first EMR tap is quick. Never throws.</summary>
    public async Task WarmUpAsync(NsSession s)
    {
        try { await GetWarmAsync(s, refresh: false); }
        catch (Exception ex) { _log.LogDebug(ex, "Legacy page warm-up failed."); }
    }

    /// <summary>
    /// The signed link for the module, or null when the legacy page cannot supply it (the caller falls back).
    /// A tap and a background prefetch for the same link share one request.
    /// </summary>
    public Task<string?> GetEmrUrlAsync(NsSession s, long ipNo, string action)
    {
        var linkKey = $"emr|{WarmKey(s)}|{ipNo}|{action}";
        if (_cache.TryGetValue(linkKey, out string? cached)) return Task.FromResult(cached);
        return _inflight.GetOrAdd(linkKey, _ => new Lazy<Task<string?>>(() => ResolveAsync(linkKey, s, ipNo, action))).Value;
    }

    private async Task<string?> ResolveAsync(string linkKey, NsSession s, long ipNo, string action)
    {
        try
        {
            var url = await FetchAsync(s, ipNo, action, refresh: false)
                      ?? await FetchAsync(s, ipNo, action, refresh: true);      // stale page or expired legacy session: start over once
            if (url is not null) _cache.Set(linkKey, url, LinkFor);             // the signed link is valid for 30 minutes
            return url;
        }
        catch (Exception ex)
        {
            _log.LogWarning(ex, "Could not get the {Action} link from the legacy Nurse Station page.", action);
            return null;
        }
        finally { _inflight.TryRemove(linkKey, out _); }
    }

    private static string WarmKey(NsSession s) => $"{s.UserId}|{s.RequestParameter}";

    private async Task<string?> FetchAsync(NsSession s, long ipNo, string action, bool refresh)
    {
        var warm = await GetWarmAsync(s, refresh);
        if (warm is null) return null;
        if (!warm.RowByIp.TryGetValue(ipNo, out var idx))
        {
            _log.LogInformation("IP {Ip} is not in the legacy Nurse Station list.", ipNo);
            return null;
        }

        var chk = new KeyValuePair<string, string>($"{P}grdInPatientDtl$ctl{idx + 2:00}$Chk", "on");
        var overrides = new[]
        {
            new KeyValuePair<string, string>("__EVENTTARGET", P + action),
            new KeyValuePair<string, string>("__EVENTARGUMENT", ""),
            new KeyValuePair<string, string>(P + "hdnLOSIdx", idx.ToString()),
            new KeyValuePair<string, string>(P + "hdnRptIpNo", ipNo.ToString()),
            new KeyValuePair<string, string>(P + "HFGrdRowindx", idx.ToString()),
            new KeyValuePair<string, string>(P + "hdninx", idx.ToString()),
            chk,
        };
        var names = new HashSet<string>(overrides.Select(o => o.Key));
        var body = warm.Fields.Where(f => !names.Contains(f.Key)).Concat(overrides);

        using var req = new HttpRequestMessage(HttpMethod.Post, warm.Url) { Content = new FormUrlEncodedContent(body) };
        req.Headers.Referrer = new Uri(warm.Url);
        using var resp = await warm.Http.SendAsync(req);
        var html = await resp.Content.ReadAsStringAsync();

        var m = Redirect.Match(html);
        if (!m.Success)
        {
            _log.LogInformation("The legacy page did not return a link for {Action} (IP {Ip}).", action, ipNo);
            return null;
        }
        return WebUtility.HtmlDecode(m.Groups[1].Value);
    }

    private async Task<Warm?> GetWarmAsync(NsSession s, bool refresh)
    {
        var key = "warm|" + WarmKey(s);
        if (!refresh && _cache.TryGetValue(key, out Warm? hit) && hit is not null) return hit;

        var gate = _locks.GetOrAdd(key, _ => new SemaphoreSlim(1, 1));
        await gate.WaitAsync();
        try
        {
            if (!refresh && _cache.TryGetValue(key, out hit) && hit is not null) return hit;      // another request just built it

            var created = await OpenLegacyPageAsync(s);
            if (created is null) return null;
            _cache.Set(key, created, new MemoryCacheEntryOptions { AbsoluteExpirationRelativeToNow = WarmFor }
                .RegisterPostEvictionCallback((_, value, _, _) => (value as IDisposable)?.Dispose()));
            return created;
        }
        finally { gate.Release(); }
    }

    private async Task<Warm?> OpenLegacyPageAsync(NsSession s)
    {
        var baseApp = _config["Legacy:BaseAppPath"];
        if (string.IsNullOrWhiteSpace(baseApp) || string.IsNullOrWhiteSpace(s.RequestParameter)) return null;

        // Open the legacy page exactly as its own menu would: as the Nursing Workbench module (406 / 424).
        var parts = s.RequestParameter.Split(';');
        if (parts.Length >= 12) { parts[8] = "NURSING WORKBENCH"; parts[10] = "406"; parts[11] = "424"; }
        var url = baseApp.TrimEnd('/') + "/NurseStation/Pages/Default.aspx" +
                  "?ref=" + Uri.EscapeDataString(string.Join(";", parts)) +
                  "&details=" + Uri.EscapeDataString("Ip;0;0;406;424;0") +
                  "&AppName=" + Uri.EscapeDataString("NURSING WORKBENCH;406;424");

        var handler = new HttpClientHandler { CookieContainer = new CookieContainer(), UseCookies = true, AllowAutoRedirect = true };
        var http = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(60) };
        try
        {
            var page = await http.GetStringAsync(url);
            var rows = new Dictionary<long, int>();
            foreach (Match m in GridIp.Matches(page)) rows[long.Parse(m.Groups[2].Value)] = int.Parse(m.Groups[1].Value);
            if (rows.Count == 0) { http.Dispose(); return null; }       // not the Nurse Station page (for example the login page)
            return new Warm { Http = http, Url = url, Fields = FormFields(page), RowByIp = rows };
        }
        catch { http.Dispose(); throw; }
    }

    private static string? Attr(string tag, string name)
    {
        var m = Regex.Match(tag, @"\b" + name + @"=""([^""]*)""", RegexOptions.IgnoreCase);
        return m.Success ? WebUtility.HtmlDecode(m.Groups[1].Value) : null;
    }

    /// <summary>The form fields a browser would post for this page.</summary>
    private static List<KeyValuePair<string, string>> FormFields(string page)
    {
        var list = new List<KeyValuePair<string, string>>();
        foreach (Match m in InputTag.Matches(page))
        {
            var tag = m.Value;
            var name = Attr(tag, "name");
            if (name is null) continue;
            var type = (Attr(tag, "type") ?? "text").ToLowerInvariant();
            if (type is "submit" or "button" or "image" or "file" or "reset") continue;
            if (type is "checkbox" or "radio" && !Regex.IsMatch(tag, @"\bchecked\b", RegexOptions.IgnoreCase)) continue;
            list.Add(new(name, Attr(tag, "value") ?? ""));
        }
        foreach (Match m in SelectTag.Matches(page))
        {
            var options = m.Groups[2].Value;
            var sel = Regex.Match(options, @"<option[^>]*selected[^>]*value=""([^""]*)""|<option[^>]*value=""([^""]*)""[^>]*selected", RegexOptions.IgnoreCase);
            var first = Regex.Match(options, @"<option[^>]*value=""([^""]*)""", RegexOptions.IgnoreCase);
            var v = sel.Success ? (sel.Groups[1].Success ? sel.Groups[1].Value : sel.Groups[2].Value) : (first.Success ? first.Groups[1].Value : "");
            list.Add(new(WebUtility.HtmlDecode(m.Groups[1].Value), WebUtility.HtmlDecode(v)));
        }
        return list;
    }
}
