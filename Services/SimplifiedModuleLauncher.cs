using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Security.Claims;
using System.Text;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.IdentityModel.Tokens;
using NurseStationTablet.Infrastructure;
using NurseStationTablet.Data;
using NurseStationTablet.Models;
using NurseStationTablet.Helpers;

namespace NurseStationTablet.Services;

/// <summary>
/// Simplified module launcher using PatientQuery's approach:
/// - Direct URL navigation with query parameters (no iframe/window management)
/// - LaunchContext preserved through all navigation
/// - Simple exit mechanism (redirect to host dashboard)
/// - No complex SSO token generation
/// </summary>
public sealed class SimplifiedModuleLauncher
{
    public static readonly ModuleInfo[] Modules =
    {
        new("DFS", "Daily Flow Sheet"),
        new("DFSN", "Daily Flow Sheet - New"),
        new("MD", "Medicine Administration"),
        new("IPASS", "I-Pass Handover Form"),
        new("NCP", "Nurse Care Plan"),
        new("NCPN", "Nurse Care Plan - New"),
        new("POC", "Pre-Operative Checklist"),
        new("NAA", "Nursing Assessment - Adult"),
        new("INA", "Nursing Assessment - New"),
        new("DPN", "Daily Progress Notes"),
    };

    private static class ModCd
    {
        public const int DoctorsWorkbech = 401;
        public const int NursingAssForm = 406;
        public const int DoctorsWorkbenchForInPtn = 441;
    }

    private static class SubModCd
    {
        public const int NursingWorkbench = 1405;
        public const int NrsngAst = 930;
        public const int DailyProgressNotesMvc = 1246;
        public const int iPasshandoff = 1308;
    }

    private const int NursingWorkbenchSubMod = SubModCd.NursingWorkbench;
    private const int RightsDfs = 1380;     // module 406 sub-module whose rights sign the Daily Flow Sheet token
    private const int RightsNcp = 1381;     // ... and the Nurse Care Plan token

    private readonly NsRepository _db;
    private readonly IConfiguration _config;
    private readonly ILogger<SimplifiedModuleLauncher> _log;
    private readonly IMemoryCache _cache;
    private bool _warnedNoSecret;

    public SimplifiedModuleLauncher(NsRepository db, IConfiguration config, ILogger<SimplifiedModuleLauncher> log, IMemoryCache cache)
    {
        _db = db;
        _config = config;
        _log = log;
        _cache = cache;
    }

    /// <summary>The legacy Nurse Station action that issues the signed link for an EMR module (null for the other modules).</summary>
    public static string? EmrAction(string key) => key switch
    {
        "DFS" => "DFS", "DFSN" => "DFSNEW", "NCP" => "NCP", "NCPN" => "NCPNEW", "POC" => "POC",
        "INA" => "DFSNEW",   // Nursing Assessment - New reuses the Daily Flow Sheet - New signed link; Build swaps the route
        _ => null,
    };

    /// <summary>True when this app can sign the EMR token itself (Legacy:SsoSecret); otherwise the legacy page is asked for the link.</summary>
    public bool HasSsoSecret => !string.IsNullOrWhiteSpace(_config["Legacy:SsoSecret"]);

    /// <summary>Menu visibility (rights 406/1380 and 406/1381).</summary>
    public Dictionary<string, bool> MenuVisibility(NsSession s) => new()
    {
        ["DFS"] = HasAccess(SplitRights(_db.UserRights(s, 406, 1380))),
        ["DFSN"] = HasAccess(SplitRights(_db.UserRights(s, 406, 1380))),
        ["INA"] = HasAccess(SplitRights(_db.UserRights(s, 406, 1380))),
        ["MD"] = true,
        ["IPASS"] = true,
        ["NCP"] = HasAccess(SplitRights(_db.UserRights(s, 406, 1381))),
        ["NCPN"] = HasAccess(SplitRights(_db.UserRights(s, 406, 1381))),
        ["POC"] = true,
        ["NAA"] = true,
        ["DPN"] = true,
    };

    /// <summary>
    /// Build a module launch URL with LaunchContext preserved.
    /// Returns only the URL — no iframe/window management complexity.
    /// </summary>
    public LaunchUrlResult Build(
        NsSession s,
        LaunchContext context,
        string key,
        long ipNo,
        long ptnNo,
        Func<int, string> msg,
        string? bridgedUrl = null)
    {
        var module = Modules.FirstOrDefault(m => m.Key == key);
        if (module is null) return new(false, "Unknown module.");

        if (ipNo == 0) return new(false, msg(9));

        string? url = key switch
        {
            "DFS" => bridgedUrl ?? EmrUrl(s, ipNo, ptnNo, "DFS", _config["Tablet:DailyFlowSheetVariant"]),
            "NCP" => bridgedUrl ?? EmrUrl(s, ipNo, ptnNo, "NCP", _config["Tablet:NurseCarePlanVariant"]),
            "DFSN" => bridgedUrl ?? EmrV2Url(s, ipNo, ptnNo, "/daily-flow-sheet", RightsDfs),
            // Nursing Assessment - New: same as Daily Flow Sheet - New, only the EMR_AppV2 route differs.
            // Bridge mode reuses the DFS-New signed link and swaps the route; otherwise it signs its own token.
            "INA" => bridgedUrl is not null
                ? bridgedUrl.Replace("daily-flow-sheet", "initial-nursing-assessment")
                : EmrV2Url(s, ipNo, ptnNo, "/initial-nursing-assessment", RightsDfs),
            "NCPN" => bridgedUrl ?? EmrV2Url(s, ipNo, ptnNo, "/nursing-care-plan", RightsNcp),
            "POC" => bridgedUrl ?? EmrV2Url(s, ipNo, ptnNo, "/pre-operative-checklist", RightsDfs),
            "MD" => MedicineAdministration(s, context, ipNo, ptnNo),
            "IPASS" => NetIdModule(s, context, ModCd.NursingAssForm, SubModCd.iPasshandoff, "BaseMvcAppPath", ipNo, ptnNo),
            "NAA" => NetIdModule(s, context, ModCd.DoctorsWorkbech, SubModCd.NrsngAst, "BaseAppPath", ipNo, ptnNo),
            "DPN" => NetIdModule(s, context, ModCd.DoctorsWorkbenchForInPtn, SubModCd.DailyProgressNotesMvc, "BaseMvcAppPath", ipNo, ptnNo),
            _ => null,
        };

        return url is null
            ? new(false, "This module can't be opened right now. Please try again, or contact support if it keeps happening.")
            : new(true, Url: url, Key: key, Title: module.Title);
    }

    /// <summary>
    /// Build exit URL to return control to the host dashboard.
    /// Preserves LaunchContext for the dashboard to recognize the user.
    /// </summary>
    public string BuildExitUrl(LaunchContext context)
    {
        var exitUrl = _config["Legacy:SubMenuPath"] ?? "";
        if (string.IsNullOrEmpty(exitUrl)) return "";

        // Append timestamp to prevent caching
        var timestamp = DateTime.Now.ToString("dd-MM-yyyy HH:mm:ss");
        var qs = RouteHelper.BuildQueryString(context.RouteValues());
        var sep = string.IsNullOrEmpty(qs) ? "?" : (qs.StartsWith("?") ? "&" : "?");
        return $"{exitUrl}{qs}{sep}t={Uri.EscapeDataString(timestamp)}";
    }

    // ---- Module URL builders ----

    /// <summary>
    /// EMR_AppV2: the page address carries the signed token (same shape the legacy suite issues) and the EMR signs the user in. Without Legacy:SsoSecret the plain page URL is returned and EMR_AppV2 asks for its own login.
    /// </summary>
    private string? EmrV2Url(NsSession s, long ipNo, long ptnNo, string route, int rightsSubMod)
    {
        var baseUrl = _config["Legacy:EmrV2Path"]?.TrimEnd('/');
        if (string.IsNullOrWhiteSpace(baseUrl)) return null;

        var token = SsoToken(s, ipNo, rightsSubMod);
        return token is null
            ? $"{baseUrl}{route}?ipNo={ipNo}&ptnNo={ptnNo}"
            : $"{baseUrl}{route}?ssoToken={Uri.EscapeDataString(token)}";
    }

    private string MedicineAdministration(NsSession s, LaunchContext context, long ipNo, long ptnNo)
    {
        const int modCd = ModCd.DoctorsWorkbech;
        const int subModCd = 760;
        var path = _config["Legacy:BaseAppPath"] + "MedicineAdministration/Pages/Default.aspx";
        var details = $"Ip;{ptnNo};{ipNo};{modCd};{subModCd};1";
        var contextQuery = RouteHelper.BuildQueryString(context.RouteValues()).Replace("?", "&");
        return $"{path}?ref={s.RequestParameter}&details={details}&AppName=MEDICINE ADMINISTRATION;{modCd};{subModCd}{contextQuery}";
    }

    private string? NetIdModule(
        NsSession s,
        LaunchContext context,
        int modCd,
        int subModCd,
        string baseKey,
        long ipNo,
        long ptnNo)
    {
        var cacheKey = $"netid|{s.CompanyCode}|{s.Div}|{s.Loc}|{modCd}|{subModCd}";
        var netId = _cache.GetOrCreate(cacheKey, entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(30);
            return _db.GetNetId(s, modCd, subModCd);
        });
        if (netId is null) return null;

        var path = _config[$"Legacy:{baseKey}"] + netId.WebPath;
        var details = $"Ip;{ptnNo};{ipNo};{modCd};{NursingWorkbenchSubMod};0";
        var contextQuery = RouteHelper.BuildQueryString(context.RouteValues()).Replace("?", "&");
        return $"{path}?ref={s.RequestParameter}&details={details}&AppName={netId.SubModName};{modCd};{subModCd}{contextQuery}";
    }

    // ---- Daily Flow Sheet / Nurse Care Plan (legacy Angular EMR): opened with a signed SSO token ----
    private string? EmrUrl(NsSession s, long ipNo, long ptnNo, string rightsType, string? variant)
    {
        var react = string.Equals(variant, "React", StringComparison.OrdinalIgnoreCase);
        var (baseKey, route) = (rightsType, react) switch
        {
            ("DFS", false) => ("AngularEMRPath", "/#/dashboard/daily-flow-sheet"),
            ("DFS", true) => ("ReactEMRPath", "/daily-flow-sheet"),
            ("NCP", false) => ("AngularEMRPath", "/#/dashboard/nursing-care-plan"),
            _ => ("ReactEMRPath", "/nursing-care-plan"),
        };
        var baseUrl = _config[$"Legacy:{baseKey}"]?.TrimEnd('/');
        if (string.IsNullOrWhiteSpace(baseUrl)) return null;

        var token = SsoToken(s, ipNo, rightsType == "DFS" ? RightsDfs : RightsNcp);
        return token is null
            ? $"{baseUrl}{route}?ipNo={ipNo}&ptnNo={ptnNo}"
            : $"{baseUrl}{route}?ssoToken={WebUtility.UrlEncode(token)}";
    }

    /// <summary>Port of GenerateSSOToken: same claims, issuer, audience and 30-minute expiry. Null when no secret is configured.</summary>
    private string? SsoToken(NsSession s, long ipNo, int rightsSubMod)
    {
        var secret = _config["Legacy:SsoSecret"];
        if (string.IsNullOrWhiteSpace(secret))
        {
            if (!_warnedNoSecret)
            {
                _warnedNoSecret = true;
                _log.LogWarning("No signed EMR link: the legacy Nurse Station page did not issue one and Legacy:SsoSecret is not configured, so the EMR shows its own login page.");
            }
            return null;
        }

        var rights = SplitRights(_db.UserRights(s, ModCd.NursingAssForm, rightsSubMod));
        var user = _db.GetUserDet(s);
        string R(int i) => rights is not null && rights.Length > i ? rights[i] : "False";

        var claims = new List<Claim>
        {
            new("userid", s.UserId), new("pass", user?.UserPwd ?? ""), new("ip", ipNo.ToString()),
            new("access", R(0)), new("save", R(1)), new("delete", R(2)), new("print", R(3)), new("auth", R(4)),
        };
        var creds = new SigningCredentials(new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secret)), SecurityAlgorithms.HmacSha256);
        var jwt = new JwtSecurityToken("LegacyApp", "AngularApp", claims, expires: DateTime.UtcNow.AddMinutes(30), signingCredentials: creds);
        return new JwtSecurityTokenHandler().WriteToken(jwt);
    }

    private static string[]? SplitRights(string rights) => string.IsNullOrEmpty(rights) ? null : rights.Split(';');

    private static bool HasAccess(string[]? rights) =>
        rights is { Length: > 0 } && string.Equals(rights[0], "TRUE", StringComparison.OrdinalIgnoreCase);
}

/// <summary>
/// Result of building a module launch URL.
/// Contains only the URL — no iframe/window mode complexity.
/// The client is responsible for opening the URL (in a new tab, window, or iframe as needed).
/// </summary>
public sealed record LaunchUrlResult(bool Ok, string? Message = null, string? Url = null, string? Key = null, string? Title = null);
