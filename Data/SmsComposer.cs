using System.Globalization;
using System.Text.RegularExpressions;
using NurseStationTablet.Infrastructure;

namespace NurseStationTablet.Data;

/// <summary>
/// Port of the WCF service's LOS SMS queueing:
///   NurseStation.GetLstSmsCategoryToSendDischarge (LOSConfirmSms / LOSExtendSms branches)
///   clsSmsDtl.ValidateSMSMain (template + mobile validation)
///   clsInsertUpdateSmsDtl.SpInsSmsDtl (queue row in SMS table)
/// Behaviour, including the legacy quirks noted inline, is kept so messages are queued exactly as before.
/// SMS is best effort: any failure is logged and never fails the LOS action (same as the service).
/// </summary>
public sealed class SmsComposer
{
    public const int LosConfirmSms = 5;   // EnumSmsInternal.LOSConfirmSms
    public const int LosExtendSms = 6;    // EnumSmsInternal.LOSExtendSms

    // SQL datetime-safe stand-in for the DAL's Date.MaxValue "no date" sentinel.
    private static readonly DateTime NoDate = new(9999, 12, 31, 23, 59, 59);

    private static readonly Regex ParamToken = new("[|]([A-Z])\\w+[|]", RegexOptions.IgnoreCase);

    private readonly Db _db;
    private readonly ILogger<SmsComposer> _log;
    private readonly CultureInfo _serverCulture;

    public SmsComposer(Db db, ILogger<SmsComposer> log, IConfiguration config)
    {
        _db = db;
        _log = log;
        // Dates/numbers were turned into text with the WCF server's culture (VB CStr). Default en-IN.
        _serverCulture = new CultureInfo(config["Sms:ServerCulture"] ?? "en-IN");
    }

    /// <summary>LOS SMS for one in-patient. SMS type = the module's sub-module code (submodcd), as in the service.</summary>
    public void SendLosSms(NsSession s, int category, LosUpdate u)
    {
        try
        {
            var serverNow = Convert.ToDateTime(_db.Scalar(Sp.SelServerDateTime), CultureInfo.InvariantCulture);
            var smsTyp = s.MainSubModCode;

            // GetLstSmsCategoryToSendDischarge: data used to fill the template placeholders.
            var replaceData = _db.List(Sp.SelSmsReplaceData, ReadReplaceRow,
                ("pCOCD", s.CompanyCode), ("pDIVcd", s.Div), ("pLOCcd", s.Loc), ("pModcd", 0), ("pSubModCd", smsTyp),
                ("pCategoryCd", category), ("pPtnNo", u.InPatientNo), ("pIpNo", u.InPatientNo), ("pDocCd", 0),
                ("pBedNo", category == LosConfirmSms ? (object?)NullIfEmpty(u.BedNo) : ""),
                ("pCompNo", 0), ("pCompDt", NoDate), ("pUsrNm", s.UserId), ("pFrmDeptCd", 0), ("pToDeptCd", 0),
                ("pItemCd", null), ("pCompDesc", null), ("pPriorityCd", 0), ("pEmpId", null), ("pFctCd", 0),
                ("pApptNo", 0), ("pApptDt", NoDate), ("pApptFrmTm", null), ("pApptToTm", null),
                ("pDischargeDate", u.DischargeDate == default ? NoDate : u.DischargeDate),
                ("pDischargeTime", u.DischargeTime == default ? NoDate : u.DischargeTime),
                ("pexptd_no_day", u.ExptdNoDays));

            var entries = Validate(s, smsTyp, serverNow, category, replaceData);
            if (entries is null) return;

            foreach (var e in entries)
            {
                _db.NonQuery(Sp.InsSmsDtl,
                    ("pSMSSrl", 0), ("pSMSSubSrl", e.SubSrl), ("pSMSType", e.Type), ("pSMSStsCd", (int)e.StsCd),
                    ("pSMSMobile", e.Mobile), ("pSMSMessage", e.Message.Replace("|", "")),
                    ("pSMSTimeToSend", serverNow), ("pSMSCrtby", s.UserId), ("pSMSCrtTm", serverNow), ("pSMSSentTm", serverNow),
                    ("pSMSParts", 101), ("pPTNNo", u.InPatientNo), ("pVchNo", "0"), ("PCATEGORYTYP", e.Category));
            }
        }
        catch (Exception ex)
        {
            _log.LogWarning(ex, "LOS SMS (category {Category}) not queued for IP {IpNo}", category, u.InPatientNo);
        }
    }

    private sealed record Entry(int SubSrl, int Type, string Mobile, string Message, byte StsCd, int Category);

    /// <summary>clsSmsDtl.ValidateSMSMain for a single category (DefCatTyp = 0, one clsSMSMstDetails).</summary>
    private List<Entry>? Validate(NsSession s, int smsTyp, DateTime serverNow, int category, List<Dictionary<string, object?>> replaceData)
    {
        // clsSmsParam.GetSmsParamDataWithNoParamters
        var param = _db.List(Sp.SelSmsParam,
            r => (MobLen: r.Int("SMS_Mobile_Length"), ValidStart: r.Str("SMS_Valid_Mob_Start")),
            ("pcocd", s.CompanyCode), ("pdivcd", s.Div), ("ploccd", s.Loc)).LastOrDefault();

        int maxLenMob;
        string validMobStart;
        string[]? validStarts;
        if (param != default)
        {
            maxLenMob = param.MobLen;
            validMobStart = param.ValidStart;
            validStarts = validMobStart.Split('|');
        }
        else
        {
            maxLenMob = 12;
            validMobStart = "";
            validStarts = null;
        }
        var validTypes = validStarts is null ? 0 : validStarts.Length - 1;   // UBound

        var result = new List<Entry>();
        byte stsCd = 0;                                                       // not reset per row (legacy)

        var mst = _db.List(Sp.SelSmsMst,
            r => (Template: r.Str("SMS_Std_Mess"), Category: r.Int("CategoryTyp")),
            ("pCOCD", s.CompanyCode), ("pDIVcd", s.Div), ("pLOCcd", s.Loc), ("pSmsTyp", smsTyp), ("pCategoryTyp", category));
        if (mst.Count == 0) return result;

        var template = mst[0].Template;
        var tokens = ParamToken.Matches(template).Select(m => m.Value).ToList();
        var templateCategory = mst[0].Category;

        foreach (var src in replaceData)
        {
            if (VbVal(Text(src, "Category")) != templateCategory) continue;
            var row = BuildFetchRow(src);
            var message = template;

            var mobile = row["MOBILENO"] is long m ? m.ToString(CultureInfo.InvariantCulture) : "";

            if (mobile != ".")
            {
                if (VbValString(mobile).StartsWith('0'))
                {
                    if (Math.Max(0, mobile.Length - 1) != maxLenMob) stsCd = 2;
                }
                else if (mobile.Length != maxLenMob) stsCd = 2;
            }

            // Legacy "Exit Function": no mobile, or no valid-prefix setting -> nothing is queued at all.
            if (mobile == "") return null;
            if (validMobStart == "" || validStarts is null) return null;

            if (mobile.Length < maxLenMob) stsCd = 2;
            for (var n = 1; n <= validTypes; n++)                             // starts at 1, as in the DAL
            {
                var part = validStarts[n].Trim();
                if (part.Length > 0 && mobile.StartsWith(part, StringComparison.Ordinal))
                {
                    stsCd = 0;
                    break;
                }
            }

            foreach (var col in FetchColumns)
            {
                foreach (var token in tokens)
                {
                    if (col == token.Replace("|", ""))
                    {
                        message = Regex.Replace(message, Regex.Escape(token), _ => VbText(row[col]), RegexOptions.IgnoreCase);
                        break;
                    }
                }
            }

            result.Add(new Entry(1, smsTyp, mobile, message.Trim(), stsCd, category));
        }
        return result;
    }

    // Column order of the DAL's dtFetchData table (replacement order matters).
    private static readonly string[] FetchColumns =
    {
        "SMS_Typ", "Category", "PTN_NAME", "MaxAge_Gender", "IP_NO", "WARD_NAME", "BED_NO", "MOBILENO", "Doc_Name",
        "DocMobile_No", "Discharge_Status", "COMPNO", "COMPDT", "USERNAME", "FROMDEPT", "ITEMDESC", "COMPDESC", "PRIORITY",
        "OT_NAME", "APPT_NO", "APPT_DT", "APPT_FRMTM", "APPT_TOTM", "exptd_no_day", "DischargeDate", "ExtendBy", "DischargeTime",
        "class", "PtnTyp",
    };

    /// <summary>Builds the typed dtFetchData row exactly like ValidateSMSMain (each assignment is try/ignored).</summary>
    private static Dictionary<string, object?> BuildFetchRow(Dictionary<string, object?> src)
    {
        var row = FetchColumns.ToDictionary(c => c, _ => (object?)null);
        void Try(string col, Func<object?> value) { try { row[col] = value(); } catch { /* legacy: Catch / End Try */ } }

        Try("SMS_Typ", () => VbVal(Text(src, "SMS_Typ")).ToString(CultureInfo.InvariantCulture));
        Try("Category", () => (int)VbVal(Text(src, "Category")));
        Try("PTN_NAME", () => Text(src, "PTN_NAME"));
        Try("MaxAge_Gender", () => Text(src, "MaxAge_Gender"));
        Try("IP_NO", () => (long)VbVal(Text(src, "IP_NO")));
        Try("WARD_NAME", () => Text(src, "WARD_NAME"));
        // Legacy quirk: BED_NO goes through Val(), so "B-112" becomes "0". Kept for identical messages.
        Try("BED_NO", () => VbVal(Text(src, "BED_NO")).ToString(CultureInfo.InvariantCulture));
        Try("MOBILENO", () => src.ContainsKey("MOBILE_NO") ? (long)VbVal(Text(src, "MOBILE_NO")) : null);
        Try("Doc_Name", () => Text(src, "Doc_Name"));
        Try("DocMobile_No", () => (long)VbVal(Text(src, "DocMobile_No")));
        Try("Discharge_Status", () => (long)VbVal(Text(src, "Discharge_Status")));
        Try("COMPNO", () => (long)VbVal(Text(src, "COMPNO")));
        Try("COMPDT", () => src.GetValueOrDefault("COMPDT") is { } d ? Convert.ToDateTime(d, CultureInfo.InvariantCulture) : null);
        Try("USERNAME", () => Text(src, "USERNAME"));
        Try("FROMDEPT", () => Text(src, "FROMDEPT"));
        Try("ITEMDESC", () => Text(src, "ITEMDESC"));
        Try("COMPDESC", () => Text(src, "COMPDESC"));
        Try("PRIORITY", () => Text(src, "PRIORITY"));
        Try("OT_NAME", () => Text(src, "OT_NAME"));
        Try("APPT_DT", () => src.GetValueOrDefault("APPT_DT") is { } d ? Convert.ToDateTime(d, CultureInfo.InvariantCulture) : null);
        Try("APPT_FRMTM", () => src.GetValueOrDefault("APPT_FRMTM"));
        Try("exptd_no_day", () => src.GetValueOrDefault("exptd_no_day") is { } v ? Convert.ToInt32(v, CultureInfo.InvariantCulture) : null);
        Try("DischargeDate", () => src.GetValueOrDefault("DischargeDate") is { } d ? Convert.ToDateTime(d, CultureInfo.InvariantCulture) : null);
        Try("ExtendBy", () => src.GetValueOrDefault("ExtendBy"));
        Try("APPT_NO", () => (int)VbVal(Text(src, "APPT_NO")));
        Try("DischargeTime", () => src.GetValueOrDefault("DischargeTime"));
        Try("class", () => Text(src, "class"));
        Try("PtnTyp", () => Text(src, "PtnTyp"));
        return row;
    }

    private static Dictionary<string, object?> ReadReplaceRow(Db.Row r)
    {
        var d = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
        foreach (var name in new[]
                 {
                     "SMS_Typ", "Category", "PTN_NAME", "MaxAge_Gender", "IP_NO", "WARD_NAME", "BED_NO", "MOBILE_NO", "Doc_Name",
                     "DocMobile_No", "Discharge_Status", "COMPNO", "COMPDT", "USERNAME", "FROMDEPT", "ITEMDESC", "COMPDESC",
                     "PRIORITY", "OT_NAME", "APPT_NO", "APPT_DT", "APPT_FRMTM", "exptd_no_day", "DischargeDate", "ExtendBy",
                     "DischargeTime", "class", "PtnTyp",
                 })
        {
            if (r.Has(name)) d[name] = r.Raw(name);
        }
        return d;
    }

    private static string Text(Dictionary<string, object?> src, string key) =>
        src.TryGetValue(key, out var v) && v is not null ? Convert.ToString(v, CultureInfo.InvariantCulture)!.Trim() : "";

    private static object? NullIfEmpty(string v) => string.IsNullOrEmpty(v) ? null : v;

    /// <summary>VB CStr of a typed DataRow value: dates without a time print as the short date.</summary>
    private string VbText(object? value) => value switch
    {
        null => "",
        DateTime d when d.TimeOfDay == TimeSpan.Zero => d.ToString("d", _serverCulture),
        DateTime d => d.ToString("G", _serverCulture),
        IFormattable f => f.ToString(null, CultureInfo.InvariantCulture),
        _ => value.ToString() ?? "",
    };

    /// <summary>VB Val(): leading number, ignoring blanks; 0 when none.</summary>
    internal static double VbVal(string s)
    {
        var compact = new string(s.Where(c => c != ' ' && c != '\t' && c != '\r' && c != '\n').ToArray());
        var m = Regex.Match(compact, @"^[+-]?(\d+\.?\d*|\.\d+)([eEdD][+-]?\d+)?");
        return m.Success && double.TryParse(m.Value.Replace('d', 'e').Replace('D', 'e'), NumberStyles.Float, CultureInfo.InvariantCulture, out var v) ? v : 0;
    }

    private static string VbValString(string s) => VbVal(s).ToString(CultureInfo.InvariantCulture);
}
