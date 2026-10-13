using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Security.Claims;
using System.Text;
using Microsoft.IdentityModel.Tokens;
using NurseStationTablet.Infrastructure;
using NurseStationTablet.Data;

namespace NurseStationTablet.Services;

public sealed record ModuleInfo(string Key, string Title);

public sealed record LaunchResult(bool Ok, string? Message = null, string? Url = null, string? Mode = null, string? Key = null, string? Title = null);

/// <summary>
/// Builds the launch URL for the six tablet menu modules. Each method is a port of the matching
/// click handler in the legacy Default.aspx.vb (DFS_Click, MD_Click, ipass_Click, NCP_Click,
/// lnkNrsngAstApp_Click, lnkdailyprgsnts_Click); the opened modules receive exactly the same
/// query string as before, so none of them needs to change.
/// </summary>
public sealed class ModuleLauncher
{
    public static readonly ModuleInfo[] Modules =
    {
        new("DFS", "Daily Flow Sheet"),
        new("MD", "Medicine Administration"),
        new("IPASS", "I-Pass Handover Form"),
        new("NCP", "Nurse Care Plan"),
        new("NAA", "Nursing Assessment - Adult"),
        new("DPN", "Daily Progress Notes"),
    };

    // Values of the suite's clsMainModuleAccessModCode / clsMainModuleAccessSubModCd enums.
    private static class ModCd
    {
        public const int DoctorsWorkbech = 401;
        public const int NursingAssForm = 406;
        public const int DoctorsWorkbenchForInPtn = 441;
    }

    private static class SubModCd
    {
        public const int NursingWorkbench = 424;     // sent in "details" by every module
        public const int NrsngAst = 930;
        public const int DailyProgressNotesMvc = 1246;
        public const int iPasshandoff = 1308;
    }

    private const int NursingWorkbenchSubMod = SubModCd.NursingWorkbench;

    private readonly NsRepository _db;
    private readonly IConfiguration _config;

    public ModuleLauncher(NsRepository db, IConfiguration config)
    {
        _db = db;
        _config = config;
    }

    /// <summary>Port of SetDailyFlowSheetRights / SetNurseCarePlanRights (rights 406/1380 and 406/1381).</summary>
    public Dictionary<string, bool> MenuVisibility(NsSession s) => new()
    {
        ["DFS"] = HasAccess(SplitRights(_db.UserRights(s, 406, 1380))),
        ["MD"] = true,
        ["IPASS"] = true,
        ["NCP"] = HasAccess(SplitRights(_db.UserRights(s, 406, 1381))),
        ["NAA"] = true,
        ["DPN"] = true,
    };

    public string HostMode(string key) =>
        string.Equals(_config[$"Tablet:HostModes:{key}"], "Window", StringComparison.OrdinalIgnoreCase) ? "Window" : "Frame";

    public LaunchResult Build(NsSession s, string key, long ipNo, long ptnNo, Func<int, string> msg)
    {
        var module = Modules.FirstOrDefault(m => m.Key == key);
        if (module is null) return new(false, "Unknown module.");

        // Legacy: If (ipno <> "") ... Else ShowErrorPopUp(ReturnErrorMsg(.., 9))
        if (ipNo == 0) return new(false, msg(9));

        var mode = HostMode(key);
        var rule9510 = _db.GetRule(s, 9510);
        var newTabRule = rule9510 is not null && rule9510.Data1 == "Y";

        // Last token of "details". In a frame we ask the module for its redirect-style exit
        // (it then navigates its parent, which the tablet host traps and turns into "return to Nurse Station").
        var forceRedirect = mode == "Frame" && _config.GetValue("Tablet:ForceRedirectExitFlagInFrame", true);
        var flag = forceRedirect ? "0" : (newTabRule ? "1" : "0");

        string? url = key switch
        {
            "DFS" => EmrUrl(s, ipNo, "DFS", _config["Tablet:DailyFlowSheetVariant"]),
            "NCP" => EmrUrl(s, ipNo, "NCP", _config["Tablet:NurseCarePlanVariant"]),
            "MD" => MedicineAdministration(s, ipNo, ptnNo, flag),
            "IPASS" => NetIdModule(s, ModCd.NursingAssForm, SubModCd.iPasshandoff, "BaseMvcAppPath", ipNo, ptnNo, flag),
            "NAA" => NetIdModule(s, ModCd.DoctorsWorkbech, SubModCd.NrsngAst, "BaseAppPath", ipNo, ptnNo, flag),
            "DPN" => NetIdModule(s, ModCd.DoctorsWorkbenchForInPtn, SubModCd.DailyProgressNotesMvc, "BaseMvcAppPath", ipNo, ptnNo, flag),
            _ => null,
        };

        return url is null
            ? new(false, msg(9))
            : new(true, Url: url, Mode: mode, Key: key, Title: module.Title);
    }

    // ---- MD_Click: hard-coded path, ModCd DoctorsWorkbech (401), SubModCd 760 ----
    private string MedicineAdministration(NsSession s, long ipNo, long ptnNo, string flag)
    {
        const int modCd = ModCd.DoctorsWorkbech;
        const int subModCd = 760; // matches cd_net_id srno 40324 (as in legacy)
        var path = _config["Legacy:BaseAppPath"] + "MedicineAdministration/Pages/Default.aspx";
        var details = $"Ip;{ptnNo};{ipNo};{modCd};{subModCd};{flag}";
        return $"{path}?ref={s.RequestParameter}&details={details}&AppName=MEDICINE ADMINISTRATION;{modCd};{subModCd}";
    }

    // ---- ipass_Click / lnkNrsngAstApp_Click / lnkdailyprgsnts_Click: NetId lookup ----
    private string? NetIdModule(NsSession s, int modCd, int subModCd, string baseKey, long ipNo, long ptnNo, string flag)
    {
        var netId = _db.GetNetId(s, modCd, subModCd);
        if (netId is null) return null;

        var path = _config[$"Legacy:{baseKey}"] + netId.WebPath;
        var details = $"Ip;{ptnNo};{ipNo};{modCd};{NursingWorkbenchSubMod};{flag}";
        return $"{path}?ref={s.RequestParameter}&details={details}&AppName={netId.SubModName};{modCd};{subModCd}";
    }

    // ---- DFS_Click / NCP_Click (+ DFSNEW/NCPNEW): RedirectToEMR with SSO token ----
    private string? EmrUrl(NsSession s, long ipNo, string rightsType, string? variant)
    {
        var react = string.Equals(variant, "React", StringComparison.OrdinalIgnoreCase);
        var (baseKey, route) = (rightsType, react) switch
        {
            ("DFS", false) => ("AngularEMRPath", "/#/dashboard/daily-flow-sheet"),
            ("DFS", true) => ("ReactEMRPath", "/daily-flow-sheet"),
            ("NCP", false) => ("AngularEMRPath", "/#/dashboard/nursing-care-plan"),
            _ => ("ReactEMRPath", "/nursing-care-plan"),
        };
        var baseUrl = _config[$"Legacy:{baseKey}"];
        if (string.IsNullOrWhiteSpace(baseUrl)) return null;

        var rights = SplitRights(_db.UserRights(s, 406, rightsType == "DFS" ? 1380 : 1381));
        var user = _db.GetUserDet(s);
        var jwt = GenerateSsoToken(s.UserId, ipNo.ToString(), user?.UserPwd ?? "", rights);
        return $"{baseUrl}{route}?ssoToken={WebUtility.UrlEncode(jwt)}";
    }

    /// <summary>Port of GenerateSSOToken — same claims, issuer, audience and 30-minute expiry.</summary>
    private string GenerateSsoToken(string userId, string ip, string password, string[]? rightsArr)
    {
        var secret = _config["Legacy:SsoSecret"];
        if (string.IsNullOrEmpty(secret))
            throw new InvalidOperationException("Legacy:SsoSecret is not configured.");

        string R(int i) => rightsArr is not null && rightsArr.Length > i ? rightsArr[i] : "False";
        var claims = new List<Claim>
        {
            new("userid", userId), new("pass", password), new("ip", ip),
            new("access", R(0)), new("save", R(1)), new("delete", R(2)), new("print", R(3)), new("auth", R(4)),
        };
        var creds = new SigningCredentials(new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secret)), SecurityAlgorithms.HmacSha256);
        var token = new JwtSecurityToken("LegacyApp", "AngularApp", claims, expires: DateTime.UtcNow.AddMinutes(30), signingCredentials: creds);
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private static string[]? SplitRights(string rights) => string.IsNullOrEmpty(rights) ? null : rights.Split(';');

    private static bool HasAccess(string[]? rights) =>
        rights is { Length: > 0 } && string.Equals(rights[0], "TRUE", StringComparison.OrdinalIgnoreCase);
}
