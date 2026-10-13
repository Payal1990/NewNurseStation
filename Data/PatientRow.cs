using System.Globalization;
using NurseStationTablet.Data;

namespace NurseStationTablet.Services;

/// <summary>One grid row, already shaped for client-side binding (same values the legacy GridView bound).</summary>
public sealed class PatientRow
{
    public long IpNo { get; set; }
    public long PatientNo { get; set; }
    public string PatientFullName { get; set; } = "";
    public string Gender { get; set; } = "";
    public string Age { get; set; } = "";
    public string AgeType { get; set; } = "";
    public string BloodGroup { get; set; } = "";   // legacy "BLOOD GROUP" column is bound to OTClearance
    public string LocName { get; set; } = "";
    public decimal LastBmiIndex { get; set; }
    public string BedNo { get; set; } = "";
    public string BedTypDesc { get; set; } = "";
    public string Mobile { get; set; } = "";
    public int DoctorCd { get; set; }
    public string DoctorName { get; set; } = "";
    public int WardCd { get; set; }
    public string WardDCd { get; set; } = "";
    public string SpltyCd { get; set; } = "";
    public string SpltyDesc { get; set; } = "";
    public string DschgAdvSts { get; set; } = "";
    public string DschrgSts { get; set; } = "";
    public string ReqNo { get; set; } = "";
    public string AdmDt { get; set; } = "";        // dd/MM/yyyy
    public string AdmTm { get; set; } = "";        // HH:mm
    public string AdmDtTm { get; set; } = "";      // dd/MM/yyyy hh:mm (grid display)
    public string DschgDt { get; set; } = "";      // dd/MM/yyyy
    public string DschgTm { get; set; } = "";      // HH:mm
    public string PtnClass { get; set; } = "";
    public string CreditCompany { get; set; } = "";
    public string PtnSrc { get; set; } = "";
    public string RoomName { get; set; } = "";
    public int PtnTypCd { get; set; }
    public string PtnTypDesc { get; set; } = "";
    public string OTClearance { get; set; } = "";
    public int FolStsCd { get; set; }
    public int CseTypCd { get; set; }
    public int FlrNo { get; set; }
    public string FlrNm { get; set; } = "";
    public int Los { get; set; }
    public int ALos { get; set; }
    public bool Hwc { get; set; }
    public bool IsIsolated { get; set; }
    public bool IsPtnVulnerable { get; set; }
    public bool IsHighRisk { get; set; }
    public bool ReadyToDschrge { get; set; }
    public bool FinalBillSts { get; set; }
    public bool NoDues { get; set; }
    public bool IsDietAssigned { get; set; }
    public bool IsNewAdmission { get; set; }
    public bool OTBooked { get; set; }
    public bool DschgPlanning { get; set; }
    public bool IsArrivedOnBed { get; set; }
    public bool IsLOSConfirmed { get; set; }
    public bool AllowRightClick { get; set; }
    public bool FolioClosed => FinalBillSts && FolStsCd == 2;

    // Ward-level counters used by the card view.
    public int BloodReqCount { get; set; }
    public int LabReqCount { get; set; }
    public int RadReqCount { get; set; }
    public int ProcReqCount { get; set; }
    public int MedReqCount { get; set; }
    public int WardReqCount { get; set; }
    public int VIPPtnCount { get; set; }
    public int SampleRejPtnCount { get; set; }
    public int CrdCmpPtnCount { get; set; }

    internal static string D(DateTime d) => d == default ? "" : d.ToString("dd/MM/yyyy", CultureInfo.InvariantCulture);
    internal static string T24(DateTime d) => d == default ? "" : d.ToString("HH:mm", CultureInfo.InvariantCulture);
    internal static string T12(DateTime d) => d == default ? "" : d.ToString("hh:mm", CultureInfo.InvariantCulture);

    /// <summary>Parses a dd/MM/yyyy (or ISO) date written by this app.</summary>
    internal static DateTime ParseLegacyDate(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return default;
        string[] formats = { "dd/MM/yyyy", "dd/MM/yyyy HH:mm:ss", "d/M/yyyy", "yyyy-MM-dd", "yyyy-MM-ddTHH:mm:ss", "yyyy-MM-dd HH:mm:ss" };
        if (DateTime.TryParseExact(value.Trim(), formats, CultureInfo.InvariantCulture, DateTimeStyles.None, out var d)) return d;
        return DateTime.TryParse(value, new CultureInfo("en-GB"), DateTimeStyles.None, out d) ? d : default;
    }

    /// <summary>
    /// Column mapping of NST_SelPatientList (copy of SpSelInPtnMst014), exactly as
    /// clsPatient.GetPtnHelpWithOpenFolio in the WCF DAL read it.
    /// </summary>
    public static PatientRow FromReader(Db.Row r)
    {
        // DschrgSts: NULL or "" -> "Not Discharge"
        var dschrgSts = r.Str("DschrgSts");
        if (string.IsNullOrEmpty(dschrgSts)) dschrgSts = "Not Discharge";

        // DschgDt: the DAL kept the value whatever the status (second assignment wins); NULL -> "".
        var dschgRaw = r.Raw("DschgDt");
        var dschgDt = dschgRaw switch
        {
            null => default,
            DateTime dt => dt,
            _ => ParseLegacyDate(Convert.ToString(dschgRaw, CultureInfo.InvariantCulture)),
        };

        var admDt = r.Date("AdmDt");
        var admTm = r.Date("Admtm");
        return new PatientRow
        {
            IpNo = r.Long("InPatientNo"),
            PatientNo = r.Long("PatientNo"),
            PatientFullName = r.Str("PatientFullName"),
            Gender = r.Str("Gender"),
            Age = r.Str("Age"),
            AgeType = r.Str("AgeType"),
            BloodGroup = r.Str("OTClearance"),
            LocName = r.Str("LocName"),
            LastBmiIndex = r.Dec("LastBmi"),
            BedNo = r.Str("BedNo"),
            BedTypDesc = r.Str("BedTypDesc"),
            Mobile = r.Str("mobile"),
            DoctorCd = r.Int("DocCd"),
            DoctorName = r.Str("DocNm"),
            WardCd = r.Int("WardCd"),
            WardDCd = r.Str("WardDCd"),
            SpltyCd = r.Str("spltyCd"),
            SpltyDesc = r.Str("SpecialityCodeDesc"),
            DschgAdvSts = r.Str("dschg_adv_sts"),
            DschrgSts = dschrgSts,
            ReqNo = r.Str("ReqNo"),
            AdmDt = D(admDt),
            AdmTm = T24(admTm),
            AdmDtTm = $"{D(admDt)}    {T12(admTm)}",
            DschgDt = D(dschgDt),
            DschgTm = T24(r.Date("dschg_tm")),
            PtnClass = r.Str("PatientClassCodeDesc"),
            CreditCompany = r.Str("ArDesc"),
            PtnSrc = r.Str("PtnSrc"),
            RoomName = r.Str("RoomName"),
            PtnTypCd = r.Int("PtnTypCd"),
            PtnTypDesc = r.Str("PtnTypDesc"),
            OTClearance = r.Str("OTClearance"),
            FolStsCd = r.Int("fol_sts_cd"),
            CseTypCd = r.Int("CseTypCd"),
            FlrNo = r.Int("flr_no"),
            FlrNm = r.Str("flr_nm"),
            Los = r.Int("LOS"),
            ALos = r.Int("ALOS"),
            Hwc = r.Bool("IsPtnBlackListed"),          // legacy: HWC = IsPtnBlackListed
            IsIsolated = r.Bool("IsIsolated"),
            IsPtnVulnerable = r.Bool("IsPtnVulnerable"),
            IsHighRisk = r.Bool("IsHighRisk"),
            ReadyToDschrge = r.Bool("ReadyToDschrge"),
            FinalBillSts = r.Bool("FinalBillSts"),
            NoDues = r.Bool("NoDues"),
            IsDietAssigned = r.Bool("IsDietAssigned"),
            IsNewAdmission = r.Bool("IsNewAdmission"),
            OTBooked = r.Bool("OTBooked"),
            DschgPlanning = r.Long("DschgPlanDocNo") != 0,
            IsArrivedOnBed = r.Bool("IsArrivedOnBed"),
            IsLOSConfirmed = r.Bool("IsLOSConfirmed"),
            AllowRightClick = r.Bool("AllowRightClick"),
            BloodReqCount = r.Int("BloodReqCount"),
            LabReqCount = r.Int("LabReqCount"),
            RadReqCount = r.Int("RadReqCount"),
            ProcReqCount = r.Int("ProcReqCount"),
            MedReqCount = r.Int("MedReqCount"),
            WardReqCount = r.Int("WardReqCount"),
            VIPPtnCount = r.Int("VIPPtnCount"),
            SampleRejPtnCount = r.Int("SampleRejPtnCount"),
            CrdCmpPtnCount = r.Int("CrdCmpPtnCount"),
        };
    }
}
