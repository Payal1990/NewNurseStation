using System.Reflection;
using System.Text.Json;

namespace NurseStationTablet.Infrastructure;

/// <summary>
/// The values the legacy MasterPage put into Session from the "ref" query string
/// (USERID, COMPANYCODE, DIVCODE, LOCCODE, MAINMODCODE, MAINSUBMODCODE, RequestParameter ...).
/// </summary>
public sealed class NsSession
{
    public string UserId { get; set; } = "";
    public string CompanyCode { get; set; } = "";
    public int Div { get; set; }
    public int Loc { get; set; }
    public int UserDocCd { get; set; }
    public int MainModCode { get; set; }
    public int MainSubModCode { get; set; }
    public int Shift { get; set; }
    public string UserNickName { get; set; } = "";
    public string AppName { get; set; } = "";
    public string CompanyName { get; set; } = "";
    public string DivisionName { get; set; } = "";
    public string LocationName { get; set; } = "";

    /// <summary>Raw "ref" token. Forwarded unchanged to every opened module, exactly like Session("RequestParameter").</summary>
    public string RequestParameter { get; set; } = "";

    /// <summary>Session("InpatientNo") — details[1] of the incoming query string; the row to pre-select.</summary>
    public string? InpatientNo { get; set; }

    /// <summary>True for the Development stand-alone session (no legacy hand-off); its ref is built from the user's active legacy login.</summary>
    public bool IsDevSession { get; set; }
    public string FinancialYear { get; set; } = "";
}

/// <summary>
/// Builds a "ref" string in the layout the legacy suite passes to its modules (CommonSessionVariables.RetrieveSessionData):
/// user;company;div;loc;financialYear;division;location;company;application;doctor;modCd;subModCd;shift;nickName;logSrNo;0
/// Item 15 is LogInOutDetail.LogSrNo; the legacy pages only accept a ref whose login is still active.
/// </summary>
public static class LegacyRef
{
    public static string Build(NsSession s, string nickName, long logSrNo) => string.Join(";", new[]
    {
        s.UserId, (s.CompanyCode ?? "").PadRight(3), s.Div.ToString(), s.Loc.ToString(), s.FinancialYear,
        s.DivisionName, s.LocationName, s.CompanyName, s.AppName,
        s.UserDocCd.ToString(), s.MainModCode.ToString(), s.MainSubModCode.ToString(), s.Shift.ToString(),
        nickName, logSrNo.ToString(), "0",
    });
}

public static class NsSessionExtensions
{
    private const string Key = "NS.Session";

    public static NsSession? GetNs(this ISession session)
    {
        var json = session.GetString(Key);
        return json is null ? null : JsonSerializer.Deserialize<NsSession>(json);
    }

    public static void SetNs(this ISession session, NsSession value) =>
        session.SetString(Key, JsonSerializer.Serialize(value));
}

/// <summary>
/// Decodes the legacy "ref" token by calling CommonSessionVariables.SessionVariables.RetrieveSessionData
/// from the shared suite assembly. Loaded by reflection because the assembly targets .NET Framework
/// (it references WinForms types that are never touched by RetrieveSessionData).
/// </summary>
public sealed class LegacySessionDecoder
{
    private readonly Lazy<MethodInfo?> _retrieve;
    private readonly ILogger<LegacySessionDecoder> _log;

    public LegacySessionDecoder(IConfiguration config, IWebHostEnvironment env, ILogger<LegacySessionDecoder> log)
    {
        _log = log;
        _retrieve = new Lazy<MethodInfo?>(() =>
        {
            var path = config["Legacy:SessionDllPath"] ?? "";
            if (!Path.IsPathRooted(path)) path = Path.Combine(env.ContentRootPath, path);
            if (!File.Exists(path))
            {
                _log.LogError("CommonSessionVariables.dll not found at {Path}", path);
                return null;
            }
            var asm = Assembly.LoadFrom(path);
            return asm.GetType("CommonSessionVariables.SessionVariables")
                      ?.GetMethod("RetrieveSessionData", BindingFlags.Public | BindingFlags.Static);
        });
    }

    public NsSession? Decode(string refToken, string? details, string? appName)
    {
        var method = _retrieve.Value;
        if (method is null) return null;

        object? s;
        try { s = method.Invoke(null, new object[] { refToken }); }
        catch (Exception ex)
        {
            _log.LogWarning(ex, "Could not decode ref token");
            return null;
        }
        if (s is null) return null;

        T Get<T>(string name)
        {
            // Most members are properties; UserNickName is exposed as a public field.
            var t = s.GetType();
            var v = t.GetProperty(name)?.GetValue(s) ?? t.GetField(name)?.GetValue(s);
            return v is null ? default! : (T)Convert.ChangeType(v, typeof(T));
        }

        var ns = new NsSession
        {
            UserId = Get<string>("userid") ?? "",
            CompanyCode = Get<string>("companycode") ?? "",
            Div = Get<int>("div"),
            Loc = Get<int>("loc"),
            UserDocCd = Get<int>("UserDocCd"),
            MainModCode = Get<int>("ModCd"),
            MainSubModCode = Get<int>("SubModCd"),
            Shift = Get<int>("Shift"),
            UserNickName = Get<string>("UserNickName") ?? "",
            AppName = Get<string>("ApplicationName") ?? "",
            CompanyName = Get<string>("CompanyName") ?? "",
            DivisionName = Get<string>("DivisionName") ?? "",
            LocationName = Get<string>("LocationName") ?? "",
            RequestParameter = refToken,
        };

        // Same parsing as MasterPage.master.vb: details = dctcode;InpatientNo;WardCode
        if (!string.IsNullOrEmpty(details))
        {
            var parts = details.Split(';');
            if (parts.Length > 1 && !string.IsNullOrWhiteSpace(parts[1])) ns.InpatientNo = parts[1];
        }
        if (!string.IsNullOrEmpty(appName)) ns.AppName = appName;
        return ns;
    }
}
