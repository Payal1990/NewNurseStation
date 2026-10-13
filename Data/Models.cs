namespace NurseStationTablet.Data;

// Plain models replacing the WCF data contracts (same member names as the legacy classes).

public sealed record CodeDecode(int Code, string Decode, string AddInfo1, int Type, bool HasRights, string DefWard);

public sealed record Doctor(int DoctorCode, string DoctorFullName, bool Status, int SpecialityCode, string SpecialityCodeDesc);

public sealed record PtnType(int PtnTypCd, string PtnTypDesc, bool HasAccess, bool DefAccess);

public sealed record RuleMaster(int RuleId, string RuleName, string Data1, string Data2, string Data3, string DetFlag, string Description);

public sealed record UserDet(string UserNickName, string UserPwd, int DocCd);

/// <summary>One ward event of an IP patient (IPWardEvnt). At is the actual date/time once the event is marked.</summary>
public sealed record TrackEvent(long RecId, int EventId, string EventName, string LocName, DateTime? At, string Remark, bool IsMarked);

public sealed record LosConfig(bool EnableLOSConfirmation, int LOSConfirmationBeforeXDays, bool AllowToSkipLOSConfirmation, int LOSConfirmationSkipLimit);

public sealed record LosDetail(bool IsLOSConfirmed, string LOSConfirmedByUsrID, DateTime LOSConfirmedDtTm, int LOSConfimSkipCount,
    DateTime DischargeDate, DateTime DischargeTime, DateTime AdmissionDate, DateTime AdmissionTime, int ExptdNoDays);

public sealed record NetId(int SrNo, string WebPath, string SubModName, string Path, string DefPath);

public sealed record MsgMst(int MsgSrno, string MsgDesc);

/// <summary>Values written by the LOS actions (subset of the legacy clsInPatient).</summary>
public sealed class LosUpdate
{
    public long InPatientNo { get; set; }
    public int ExptdNoDays { get; set; }
    public DateTime DischargeDate { get; set; }
    public DateTime DischargeTime { get; set; }
    public string LOSConfirmedByUsrID { get; set; } = "";
    public int LOSConfimSkipCount { get; set; }
    public string UpdtBy { get; set; } = "";
    public string BedNo { get; set; } = "";
}

/// <summary>Legacy clsIPLOSActionLog.</summary>
public sealed record LosActionLog(long IPNo, int ActionID, string ActionDesc, DateTime ActionDtTm, string ActionByUsrID);
