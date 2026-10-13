using System.Globalization;
using NurseStationTablet.Infrastructure;
using NurseStationTablet.Data;

namespace NurseStationTablet.Services;

/// <summary>State of the "Change LOS" popup, i.e. what btnRowSet_Click put on the page.</summary>
public sealed class LosGateResult
{
    /// <summary>Legacy lblAllowRightClick = "True": the context menu must NOT open for this row.</summary>
    public bool BlockMenu { get; set; }
    public bool ShowPopup { get; set; }
    public string Content1 { get; set; } = "";
    public string Content2 { get; set; } = "";
    public bool ConfirmEnabled { get; set; }
    public bool SkipEnabled { get; set; }
    public int SkipLeft { get; set; }
    public int SkipLimit { get; set; }
    public string CurrentExpectedDischarge { get; set; } = "";
}

public sealed record LosActionResult(bool Ok, string Message, LosGateResult? Gate = null, PatientRow? Row = null);

/// <summary>
/// Port of the Expected-LOS confirmation workflow from Default.aspx.vb:
/// btnRowSet_Click (gate on selection), btnConfirm_Click, btnSkip_Click, btnExtendLOS_Click, txtNewLOS_TextChanged.
/// </summary>
public sealed class LosService
{
    private readonly NsRepository _db;

    public LosService(NsRepository db) => _db = db;

    public LosGateResult Evaluate(NsSession s, PatientRow row)
    {
        var result = new LosGateResult { CurrentExpectedDischarge = $"{row.DschgDt}  {row.DschgTm}" };

        var cfg = _db.GetLosConfig(s);
        if (cfg is null || !cfg.EnableLOSConfirmation) return result;

        var los = _db.GetLosByIp(s, row.IpNo);
        if (los is null) return result;

        var now = _db.GetServerDateTime();
        var expDt = PatientRow.ParseLegacyDate(row.DschgDt);
        var expTm = ParseTime(row.DschgTm);
        var expDtTm = expDt.Date.Add(expTm);
        var expTm12 = DateTime.Today.Add(expTm).ToString("hh:mm tt", CultureInfo.InvariantCulture);

        // Patient still admitted after the expected discharge date/time -> must extend.
        if (now >= expDtTm)
        {
            result.ShowPopup = true;
            result.BlockMenu = false;
            result.Content1 = $"This Patient was admitted on  {row.AdmDt}   {row.AdmTm}     and length of stay is defined as   {row.Los}  Days.";
            result.Content2 = $"As per length of stay this patient was suppose to be discharged on  {row.DschgDt}   {expTm12}  Please extend the LOS";
            result.ConfirmEnabled = false;
            result.SkipEnabled = false;
            result.SkipLeft = 0;
            result.SkipLimit = cfg.LOSConfirmationSkipLimit;
            return result;
        }

        // Alert X days before the expected discharge date while LOS is unconfirmed.
        var alertFrom = expDt.Date.AddDays(cfg.LOSConfirmationBeforeXDays != 0 ? -cfg.LOSConfirmationBeforeXDays : 0);
        if (!los.IsLOSConfirmed && expDtTm > now.Date && now.Date >= alertFrom)
        {
            result.BlockMenu = true;
            result.ShowPopup = true;
            result.Content1 = $"This Patient was admitted on  {row.AdmDt}   {row.AdmTm}     and length of stay is defined as   {row.Los}  Days.";
            result.Content2 = $"As per length of stay this patient will be discharging on {row.DschgDt}   {expTm12}  Please confirm.";
            result.SkipLimit = cfg.LOSConfirmationSkipLimit;
            result.SkipLeft = los.LOSConfimSkipCount == 0
                ? cfg.LOSConfirmationSkipLimit
                : cfg.LOSConfirmationSkipLimit - los.LOSConfimSkipCount;
            result.ConfirmEnabled = true;
            result.SkipEnabled = cfg.AllowToSkipLOSConfirmation && los.LOSConfimSkipCount != cfg.LOSConfirmationSkipLimit;
        }
        return result;
    }

    public LosActionResult Confirm(NsSession s, long ipNo)
    {
        var los = _db.GetLosByIp(s, ipNo);
        if (los is { IsLOSConfirmed: true }) return new(false, "LOS of this IP is already Confirmed.");
        if (los is null) return new(false, "Record Not Confirmed");

        var now = _db.GetServerDateTime();
        var upd = new LosUpdate
        {
            InPatientNo = ipNo,
            LOSConfirmedByUsrID = s.UserId,
            DischargeDate = los.DischargeDate,
            DischargeTime = los.DischargeTime,
        };
        var log = ActionLog(s, ipNo, "LOS Confirmed", 21, now);

        return _db.ConfirmLos(s, upd, log)
            ? new(true, $"LOS of Ip- {ipNo}   is Confirmed.")
            : new(false, "Record Not Confirmed");
    }

    public LosActionResult Skip(NsSession s, long ipNo, int skipLeft)
    {
        var los = _db.GetLosByIp(s, ipNo);
        if (los is { IsLOSConfirmed: true }) return new(false, "LOS of this IP is already Confirmed.");
        if (skipLeft == 0) return new(false, "You have reached maximum number of limit to change the LOS");

        var upd = new LosUpdate { InPatientNo = ipNo, UpdtBy = s.UserId };
        var log = ActionLog(s, ipNo, "LOS Confirmation Skipped", 11, _db.GetServerDateTime());

        if (!_db.SkipLos(s, upd, log)) return new(false, "Record Not Saved");

        var cfg = _db.GetLosConfig(s);
        los = _db.GetLosByIp(s, ipNo);
        var left = cfg is not null && los is not null ? cfg.LOSConfirmationSkipLimit - los.LOSConfimSkipCount : 0;
        // After a skip the legacy page sets lblAllowRightClick = "False": the menu is available again.
        return new(true, "", new LosGateResult { BlockMenu = false, SkipLeft = left });
    }

    /// <summary>txtNewLOS_TextChanged / GetExtendedDischargeDtTm: admission date + (current LOS + extra days), at admission time.</summary>
    public static DateTime? PreviewDischarge(PatientRow row, int currentLos, int extendDays)
    {
        if (extendDays <= 0) return null;
        var adm = PatientRow.ParseLegacyDate(row.AdmDt);
        return adm.Date.AddDays(currentLos + extendDays).Add(ParseTime(row.AdmTm));
    }

    public LosActionResult Extend(NsSession s, PatientRow row, int currentLos, string newLosText, Func<int, string> msg)
    {
        if (string.IsNullOrWhiteSpace(newLosText)) return new(false, "Enter New LOS");
        if (!int.TryParse(newLosText.Trim(), out var extendDays) || extendDays <= 0)
            return new(false, "Enter valid New LOS (greater than 0)");

        var totalLos = currentLos + extendDays;
        var newDischarge = PreviewDischarge(row, currentLos, extendDays)!.Value;
        var now = _db.GetServerDateTime();
        if (newDischarge <= now)
            return new(false, "Extended discharge date and time should be greater than current date and time.");

        // Legacy: Convert.ToDateTime(txtextendadmtm.Text) -> today's date at the admission time.
        var admTm = DateTime.Today.Add(ParseTime(row.AdmTm));
        var upd = new LosUpdate
        {
            InPatientNo = row.IpNo,
            ExptdNoDays = totalLos,
            DischargeDate = newDischarge.Date,
            DischargeTime = admTm,
            BedNo = "",
        };
        var log = ActionLog(s, row.IpNo, "LOS  Extended", 31, now);

        if (!_db.ExtendLos(s, upd, log)) return new(false, msg(13));

        // Refresh the row's LOS / expected discharge from the server, then re-evaluate the gate
        // exactly as btnExtendLOS_Click does.
        var los = _db.GetLosByIp(s, row.IpNo);
        if (los is not null)
        {
            row.Los = los.ExptdNoDays;
            row.DschgDt = PatientRow.D(los.DischargeDate);
            row.DschgTm = PatientRow.T24(los.DischargeTime);
        }

        var gate = new LosGateResult { CurrentExpectedDischarge = $"{row.DschgDt} {row.DschgTm}", ConfirmEnabled = true };
        var cfg = _db.GetLosConfig(s);
        if (cfg is { EnableLOSConfirmation: true } && los is not null)
        {
            var dschg = PatientRow.ParseLegacyDate(row.DschgDt);
            var alertFrom = dschg.Date.AddDays(cfg.LOSConfirmationBeforeXDays != 0 ? -cfg.LOSConfirmationBeforeXDays : 0);
            gate.BlockMenu = !los.IsLOSConfirmed && dschg > now.Date && now.Date >= alertFrom;
        }
        return new(true, "LOS Extended Successfully", gate, row);
    }

    private static LosActionLog ActionLog(NsSession s, long ipNo, string desc, int actionId, DateTime at) =>
        new(ipNo, actionId, desc, at, s.UserId);

    private static TimeSpan ParseTime(string? hhmm) =>
        TimeSpan.TryParseExact(hhmm ?? "", @"hh\:mm", CultureInfo.InvariantCulture, out var t) ? t : TimeSpan.Zero;
}
