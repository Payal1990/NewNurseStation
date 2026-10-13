using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using NurseStationTablet.Data;
using NurseStationTablet.Infrastructure;

namespace NurseStationTablet.Pages;

public sealed class IndexModel : PageModel
{
    private readonly LegacySessionDecoder _decoder;
    private readonly IConfiguration _config;
    private readonly IWebHostEnvironment _env;
    private readonly NsRepository _gw;
    private readonly ILogger<IndexModel> _log;

    public IndexModel(LegacySessionDecoder decoder, IConfiguration config, IWebHostEnvironment env, NsRepository gw, ILogger<IndexModel> log)
    {
        _decoder = decoder;
        _config = config;
        _env = env;
        _gw = gw;
        _log = log;
    }

    // Header values rendered into the page by Razor at first paint. The /init endpoint returns the same
    // values for the client script, so the page is correct even before init completes.
    public string Company { get; private set; } = "";
    public string Division { get; private set; } = "";
    public string Location { get; private set; } = "";
    public string UserName { get; private set; } = "";
    public string AppName { get; private set; } = "NURSE STATION";
    public string? ClientImg { get; private set; }
    public string? SofImg { get; private set; }
    public string? BottomText { get; private set; }

    /// <summary>Two-letter avatar initials derived from the user's name.</summary>
    public string Initials
    {
        get
        {
            var parts = (string.IsNullOrWhiteSpace(UserName) ? "?" : UserName)
                .Trim().Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
            var s = string.Concat(parts.Select(p => p[0])).ToUpperInvariant();
            return s.Length > 2 ? s[..2] : s;
        }
    }

    // Entry point. Accepts the same "?ref=...&details=...&AppName=..." the suite dashboard passes to every
    // module, decodes it once into the session, then serves the tablet shell from a clean URL.
    public IActionResult OnGet()
    {
        var refToken = Request.Query["ref"].ToString();
        if (!string.IsNullOrEmpty(refToken))
        {
            var ns = _decoder.Decode(refToken, Request.Query["details"], Request.Query["AppName"]);
            if (ns is null) return Redirect(_config["Legacy:LoginPath"] ?? "/");
            HttpContext.Session.SetNs(ns);
            return Redirect(Request.PathBase + "/");
        }

        // clsGeneral.CheckSession: no user in session -> login page.
        if (HttpContext.Session.GetNs() is null)
        {
            // Development bypass: create a test session if no session exists
            if (_env.IsDevelopment())
            {
                var testSession = new NsSession
                {
                    UserId = "SSSL",
                    CompanyCode = "1",
                    Div = 1,
                    Loc = 1,
                    UserDocCd = 0,
                    MainModCode = 406,
                    MainSubModCode = 1405,
                    Shift = 1,
                    AppName = "NURSING WORKBENCH V2",
                    CompanyName = "TEST SERVER",
                    DivisionName = "JASLOK HOSPITAL",
                    LocationName = "JASLOK HOSPITAL",
                    FinancialYear = "2020",
                    IsDevSession = true,
                };
                testSession.UserNickName = testSession.UserId;
                try
                {
                    if (_gw.GetUserDet(testSession)?.UserNickName?.Trim() is { Length: > 0 } nick) testSession.UserNickName = nick;
                    // The legacy modules only accept a ref whose login is active, so build it from the user's real legacy login.
                    testSession.RequestParameter = LegacyRef.Build(testSession, testSession.UserNickName, _gw.GetActiveLogSrNo(testSession.UserId));
                }
                catch (Exception ex)
                {
                    // Database unreachable: the page still loads; /open rebuilds the ref when the database is back.
                    _log.LogWarning(ex, "Could not read the legacy login for the development session.");
                }
                HttpContext.Session.SetNs(testSession);
            }
            else
            {
                return Redirect(_config["Legacy:LoginPath"] ?? "/");
            }
        }

        var s = HttpContext.Session.GetNs()!;

        // If UserNickName is empty, try to fetch it from the database; fall back to the user id.
        if (string.IsNullOrWhiteSpace(s.UserNickName))
        {
            try
            {
                if (_gw.GetUserDet(s)?.UserNickName?.Trim() is { Length: > 0 } nick) s.UserNickName = nick;
            }
            catch (Exception ex) { _log.LogWarning(ex, "Could not read the user nickname."); }
            if (string.IsNullOrWhiteSpace(s.UserNickName)) s.UserNickName = s.UserId;
            HttpContext.Session.SetNs(s);
        }

        Response.Headers["Cache-Control"] = "no-store";

        Company = s.CompanyName;
        Division = s.DivisionName;
        Location = s.LocationName;
        UserName = s.UserNickName;
        AppName = string.IsNullOrEmpty(s.AppName) ? "NURSE STATION" : s.AppName;
        ClientImg = _config["Legacy:ClientImg"];
        SofImg = _config["Legacy:SofImg"];
        BottomText = _config["Legacy:BottomText"];
        return Page();
    }
}
