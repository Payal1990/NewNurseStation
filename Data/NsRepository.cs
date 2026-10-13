using System.Globalization;
using NurseStationTablet.Infrastructure;
using NurseStationTablet.Services;

namespace NurseStationTablet.Data;

/// <summary>
/// Direct database access that replaces the NurseStation.svc and CmnSecurityFun.svc WCF calls.
/// Each method is a port of the WCF service method / DAL function named in its comment and calls the
/// matching NST_ procedure with the same parameters the DAL sent.
/// </summary>
public sealed class NsRepository
{
    // Numeric values of the legacy EnumCodeDecode (the DAL takes typ as Integer).
    public const int CodeWard = 2;
    public const int CodeDoctorSpeciality = 28;

    private readonly Db _db;
    private readonly SmsComposer _sms;

    public NsRepository(Db db, SmsComposer sms)
    {
        _db = db;
        _sms = sms;
    }

    // ===================================================================== patient list

    /// <summary>NurseStation.GetInPtnListByNameDocWard -> clsPatient.GetPtnHelpWithOpenFolio (SpSelInPtnMst014).</summary>
    public List<PatientRow> GetPatients(NsSession s, PatientSearch q, long backPtnNo, DateTime revDt) =>
        _db.List(Sp.SelPatientList, PatientRow.FromReader,
            ("pCoCd", s.CompanyCode), ("pDiv", s.Div), ("pLoc", s.Loc),
            ("pFrstNm", ""), ("pMidNm", ""), ("pLstNm", ""),              // SearchResult() always sends ""
            ("pDocCd", q.DocCd), ("pWardCd", q.WardCd),
            ("pAdmStsCd", 2),                                             // SearchResult(): AdmSts = 2
            ("pMRDStsCd", q.MrdStatus), ("PUserId", s.UserId), ("pPtnType", q.PtnTyp),
            ("pFathersName", ""), ("pPtnNo", backPtnNo), ("PArCd", ""), ("pRevDt", revDt),
            ("@IsPtnVulnerable", q.Vulnerable ? 1 : 0), ("@IsPtnIsolated", q.Isolated ? 1 : 0),
            ("DocSpltyCd", q.SpltyCd), ("floorNo", q.FlrNo), ("pIsArrivedOnBed", q.ArrivedOnBed), ("@IsHWC", q.Hwc ? 1 : 0),
            ("pPageNo", 1), ("pPageSize", int.MaxValue));

    /// <summary>
    /// Latest discharge-advice record per patient from the dschg_adv table — the real "who / when" behind the
    /// discharge-advice-given flag. doc_cd is the advising doctor; adv_dt_tm is when the advice was given.
    /// </summary>
    public List<DischargeAdvice> GetDischargeAdvice(IEnumerable<long> ipNos)
    {
        var ids = ipNos.Where(v => v > 0).Distinct().Take(1000).ToList();
        if (ids.Count == 0) return new();

        var names = ids.Select((_, i) => "@ip" + i).ToArray();
        var args = ids.Select((v, i) => ("@ip" + i, (object?)v)).ToArray();
        var inClause = string.Join(",", names);

        // Newest advice row per patient (highest adv_no).
        var sql =
            "SELECT a.ip_no, a.adv_no, a.adv_dt_tm, a.rmrk, a.exptd_dschg_dt, a.exptd_dschg_tm, a.dschg_adv_sts, a.doc_cd, a.crt_usr_id " +
            "FROM dschg_adv a " +
            "INNER JOIN (SELECT ip_no, MAX(adv_no) AS adv_no FROM dschg_adv WHERE ip_no IN (" + inClause + ") GROUP BY ip_no) m " +
            "ON a.ip_no = m.ip_no AND a.adv_no = m.adv_no";

        return _db.TextList(sql, r =>
        {
            var at = r.Date("adv_dt_tm");
            var exDt = r.Date("exptd_dschg_dt");
            var exTm = r.Date("exptd_dschg_tm");
            string F(DateTime d) => d == default ? "" : d.ToString("dd/MM/yyyy", CultureInfo.InvariantCulture);
            string T(DateTime d) => d == default ? "" : d.ToString("HH:mm", CultureInfo.InvariantCulture);
            var expected = exDt == default ? "" : (F(exDt) + (exTm == default ? "" : " " + T(exTm))).Trim();
            return new DischargeAdvice(
                r.Long("ip_no"),
                at == default ? "" : (F(at) + " " + T(at)).Trim(),
                r.Str("rmrk").Trim(),
                expected,
                r.Int("doc_cd"),
                r.Int("dschg_adv_sts"),
                r.Str("crt_usr_id").Trim());
        }, args);
    }

    // ===================================================================== lookups

    /// <summary>clsPtnTypeMst.GetPtnTypListByUser (SpSelUserPtnTypMst001). Null when the user has no patient types.</summary>
    public List<PtnType>? GetPtnTypListByUser(NsSession s)
    {
        // NOTE: the WCF DAL passes the DIVISION code as pCocd (oParam.ParamValue = Div). Kept as-is so the
        // copied procedure behaves identically; correct it here and in NST_SelUserPtnTyp together if needed.
        var list = _db.List(Sp.SelUserPtnTyp,
            r => new PtnType(r.Int("PtnTypCd"), r.Str("PtnTypDesc"), r.Bool("Access"), r.Bool("DefPtntyp")),
            ("pCocd", s.Div), ("pDivCd", s.Div), ("pLocCd", s.Loc), ("pUserId", s.UserId));
        return list.Count == 0 ? null : list;
    }

    /// <summary>clsRuleMaster.GetRuleMstDtls (SPSELRULEMST). Null when the rule has no row.</summary>
    public RuleMaster? GetRule(NsSession s, int ruleId) =>
        _db.Last(Sp.SelRule,
            r => new RuleMaster(r.Int("RuleID"), r.Str("RuleName"), r.Str("Data1"), r.Str("Data2"),
                r.Has("Data3") ? r.Str("Data3") : "", r.Str("DetFlag"), r.Str("Desciption")),
            ("pCOCD", s.CompanyCode), ("pDIV", s.Div), ("pLOC", s.Loc), ("pRuleId", ruleId));

    /// <summary>clsCodeDecode.getCdDcdByContentSearch (SPCDDECDLIST011).</summary>
    public List<CodeDecode> SearchCodeDecode(NsSession s, int typ, string prefix) =>
        _db.List(Sp.SrchCodeDecode,
            r => new CodeDecode(r.Int("cd"), r.Str("dcd"), "", r.Int("typ"), false, ""),
            ("pCOCD", s.CompanyCode), ("pDIV", s.Div), ("pLOC", s.Loc), ("pTyp", typ), ("pPrefix", prefix));

    /// <summary>clsDoctor.getDocByContentSearch (SpSelDocMstByPrefix02).</summary>
    public List<Doctor> SearchDoctors(NsSession s, string prefix) =>
        _db.List(Sp.SrchDoctor,
            r => new Doctor(r.Int("DoctorCode"), r.Str("DoctorFullName"), r.Bool("Status"), r.Int("SpecialityCode"), r.Str("SpecialityCodeDesc")),
            ("pCOCD", s.CompanyCode), ("pDIV", s.Div), ("pLOC", s.Loc), ("pSortBy", "doc_cd"), ("pPrefix", prefix));

    /// <summary>clsMRDFileCollReq.GetMRDRecrds (spSelMRDFileReg001): first column of the first row.</summary>
    public int GetMrdRecords(NsSession s) =>
        _db.List(Sp.SelMrdRecCount, r => Convert.ToInt32(r.First() ?? 0, CultureInfo.InvariantCulture),
            ("CoCd", s.CompanyCode), ("DivCd", s.Div), ("LocCd", s.Loc), ("FileId", 0L)).FirstOrDefault();

    /// <summary>clsUserDet.GetUserDetByCD (SPSELUSERDETBYCD).</summary>
    public UserDet? GetUserDet(NsSession s) =>
        _db.Last(Sp.SelUserDet,
            // The password column is read by the deployed (2025) version of GetUserDetByCD, which is not in the
            // service source provided; the usual column names are tried. Verify against SPSELUSERDETBYCD.
            r => new UserDet(r.Str("UserNickName"),
                r.Has("usr_pwd") ? r.Str("usr_pwd") : r.Has("UserPwd") ? r.Str("UserPwd") : r.Str("pwd"),
                r.Int("doc_cd")),
            ("pCOCD", s.CompanyCode), ("pDIV", s.Div), ("pLOC", s.Loc), ("pUSRID", s.UserId));

    /// <summary>clsNetId.GetNetIdDetByModCdSubModCd (SPSELNETID002). Null when no row.</summary>
    public NetId? GetNetId(NsSession s, int modCd, int subModCd) =>
        _db.Last(Sp.SelNetIdByModule,
            r => new NetId(r.Int("srno"), r.Str("WebPath"), r.Str("SubModName"), r.Str("path"), r.Str("DefPath")),
            ("pCOCD", s.CompanyCode), ("pDIV", s.Div), ("pLOC", s.Loc), ("pModCd", modCd), ("pSubModCd", subModCd));

    // ===================================================================== system

    /// <summary>clsCommonModule.ChkSysLock: SELECT dbo.FnCheckSysLock(); "0" means locked.</summary>
    public bool ChkSysLock(NsSession s) =>
        Convert.ToString(_db.Scalar(Sp.ChkSysLock), CultureInfo.InvariantCulture) == "0";

    /// <summary>commonFunctions.GetServerDateTime: SELECT GETDATE().</summary>
    public DateTime GetServerDateTime() =>
        Convert.ToDateTime(_db.Scalar(Sp.SelServerDateTime), CultureInfo.InvariantCulture);

    // ===================================================================== CommonSecurityFunc service

    /// <summary>CmnSecurityFun.UserRights — "Access;Save;Delete;Print;Auth" (e.g. "True;True;True;True;True").</summary>
    public string UserRights(NsSession s, int modCd, int subModCd) =>
        Convert.ToString(_db.Scalar(Sp.SelUserRights,
            ("pCoCd", s.CompanyCode), ("pDiv", s.Div), ("pLoc", s.Loc), ("pUserId", s.UserId), ("pModCd", modCd), ("pSubModCd", subModCd)),
            CultureInfo.InvariantCulture) ?? "";

    /// <summary>CmnSecurityFun.GetmsgmstList — module messages by serial number.</summary>
    public List<MsgMst> GetMessages(NsSession s) =>
        _db.List(Sp.SelMessages, r => new MsgMst(r.Int("MsgSrno"), r.Str("MsgDesc")),
            ("pCoCd", s.CompanyCode), ("pDiv", s.Div), ("pLoc", s.Loc), ("pModCd", s.MainModCode), ("pSubModCd", s.MainSubModCode));

    /// <summary>CmnSecurityFun.GetRevenueDate.</summary>
    public DateTime GetRevenueDate(NsSession s) =>
        Convert.ToDateTime(_db.Scalar(Sp.SelRevenueDate, ("pCoCd", s.CompanyCode), ("pDiv", s.Div), ("pLoc", s.Loc)), CultureInfo.InvariantCulture);

    /// <summary>NST_SelActiveLogin: LogSrNo of the user's current legacy login (0 when not logged in to the legacy suite).</summary>
    public long GetActiveLogSrNo(string userId) =>
        Convert.ToInt64(_db.Scalar(Sp.SelActiveLogin, ("pUserId", userId)) ?? 0L, System.Globalization.CultureInfo.InvariantCulture);

    // ===================================================================== patient tracking (location link)

    /// <summary>NST_SelIPWardEvnt: the patient's ward events, newest first. Pending rows (IsMarked = false) are awaiting acknowledgement.</summary>
    public List<TrackEvent> GetTracking(NsSession s, long ipNo) =>
        _db.List(Sp.SelIpWardEvnt, r =>
            {
                var marked = r.Bool("IsMarked");
                var d = r.Date("EventDt");
                DateTime? at = marked && d.Year > 1900 ? d.Date + r.Date("EventTime").TimeOfDay : null;
                return new TrackEvent(r.Long("RecID"), r.Int("EventId"), r.Str("EventDesc"), r.Str("LocName"), at, r.Str("Remark").Trim(), marked);
            },
            ("cocd", s.CompanyCode), ("divcd", s.Div), ("loccd", s.Loc), ("IPNO", ipNo));

    /// <summary>The event the nurse acknowledges next: the oldest pending one.</summary>
    public static TrackEvent? CurrentEvent(IEnumerable<TrackEvent> events) =>
        events.Where(e => !e.IsMarked).OrderBy(e => e.RecId).FirstOrDefault();

    /// <summary>Actual date/time of the latest marked event before the given one (the new date/time may not be earlier).</summary>
    public static DateTime? PreviousActual(IEnumerable<TrackEvent> events, TrackEvent current) =>
        events.Where(e => e.IsMarked && e.At is not null && e.RecId < current.RecId)
              .OrderByDescending(e => e.RecId).Select(e => e.At).FirstOrDefault();

    /// <summary>NST_SaveIPWardEvnt (SAVE): marks the pending event and moves the patient's location. False when the row is no longer pending.</summary>
    public bool SaveTracking(NsSession s, long ipNo, TrackEvent ev, DateTime date, TimeSpan time, string remark) =>
        Convert.ToInt32(_db.Scalar(Sp.SaveIpWardEvnt,
            ("cocd", s.CompanyCode), ("divcd", s.Div), ("loccd", s.Loc), ("IPNO", ipNo), ("RecID", ev.RecId), ("EventID", ev.EventId),
            ("EventDt", date.Date), ("EventTime", time), ("Remark", remark), ("UserId", s.UserId)), System.Globalization.CultureInfo.InvariantCulture) == 1;

    // ===================================================================== LOS

    /// <summary>clsadtindt.GetEnableLOSConfirmation (SPSELADTINDT).</summary>
    public LosConfig? GetLosConfig(NsSession s) =>
        _db.Last(Sp.SelLosConfig,
            r => new LosConfig(r.Bool("EnableLOSConfirmation"), r.Int("LOSConfirmationBeforeXDays"),
                r.Bool("AllowToSkipLOSConfirmation"), r.Int("LOSConfirmationSkipLimit")),
            ("pCOCD", s.CompanyCode), ("pDIV", s.Div), ("pLOC", s.Loc));

    /// <summary>clsPatient.GetLOSDtlByIp (SPSELIPPTNVST036).</summary>
    public LosDetail? GetLosByIp(NsSession s, long ipNo) =>
        _db.Last(Sp.SelLosByIp,
            r => new LosDetail(r.Bool("IsLOSConfirmed"), r.Str("LOSConfirmedByUsrID"), r.Date("LOSConfirmedDtTm"),
                r.Int("LOSConfimSkipCount"), r.Date("dschg_dt"), r.Date("dschg_tm"), r.Date("adm_dt"), r.Date("adm_tm"), r.Int("LOS")),
            ("pCOCD", s.CompanyCode), ("pDIV", s.Div), ("pLOC", s.Loc), ("pIPNO", ipNo));

    /// <summary>NurseStation.ConfirmLOS: lock check, SPUPDIPPTNVST026, LOS action log, then the LOS-confirm SMS.</summary>
    public bool ConfirmLos(NsSession s, LosUpdate u, LosActionLog log)
    {
        if (ChkSysLock(s)) return false;

        var ok = InTransaction((cn, tx) =>
            Db.Proc(cn, tx, Sp.UpdLosConfirm,
                ("cocd", s.CompanyCode), ("divcd", s.Div), ("loccd", s.Loc), ("pIpNo", u.InPatientNo),
                ("pLOSConfirmedByUsrID", u.LOSConfirmedByUsrID), ("pLOSConfimSkipCount", u.LOSConfimSkipCount)).ExecuteNonQuery() != 0
            && InsertLog(cn, tx, s, log));
        if (!ok) return false;

        _sms.SendLosSms(s, SmsComposer.LosConfirmSms, u);   // best effort, as in the service
        return true;
    }

    /// <summary>NurseStation.SkipLOS: lock check, SpUpdIpPtnVst027, LOS action log.</summary>
    public bool SkipLos(NsSession s, LosUpdate u, LosActionLog log)
    {
        if (ChkSysLock(s)) return false;
        return InTransaction((cn, tx) =>
            Db.Proc(cn, tx, Sp.UpdLosSkip,
                ("cocd", s.CompanyCode), ("divcd", s.Div), ("loccd", s.Loc), ("pIpNo", u.InPatientNo), ("pupdt_usr_id", u.UpdtBy)).ExecuteNonQuery() != 0
            && InsertLog(cn, tx, s, log));
    }

    /// <summary>NurseStation.UpdateIPLOS: lock check, SPUPDIPPTNVST025, LOS-extend SMS, LOS action log.</summary>
    public bool ExtendLos(NsSession s, LosUpdate u, LosActionLog log)
    {
        if (ChkSysLock(s)) return false;
        var ok = InTransaction((cn, tx) =>
            Db.Proc(cn, tx, Sp.UpdLosExtend,
                ("cocd", s.CompanyCode), ("divcd", s.Div), ("loccd", s.Loc), ("pIpNo", u.InPatientNo),
                ("pexptd_no_day", u.ExptdNoDays), ("pDsChgDt", u.DischargeDate), ("pDsChgTm", u.DischargeTime),
                ("pupdusrid", s.UserId)).ExecuteNonQuery() != 0
            && InsertLog(cn, tx, s, log));
        if (!ok) return false;

        _sms.SendLosSms(s, SmsComposer.LosExtendSms, u);
        return true;
    }

    /// <summary>clsInsUpdIPLOSActionLog.SpInsUpdIPLOSActionLog (date sent as MM/dd/yyyy text, as in the DAL).</summary>
    private static bool InsertLog(Microsoft.Data.SqlClient.SqlConnection cn, Microsoft.Data.SqlClient.SqlTransaction tx, NsSession s, LosActionLog log) =>
        Db.Proc(cn, tx, Sp.InsLosActionLog,
            ("pcocd", s.CompanyCode), ("pdivcd", s.Div), ("ploccd", s.Loc), ("pIPNo", log.IPNo), ("pActionID", log.ActionID),
            ("pActionDesc", log.ActionDesc), ("pActionDtTm", log.ActionDtTm.ToString("MM/dd/yyyy", CultureInfo.InvariantCulture)),
            ("pActionByUsrID", log.ActionByUsrID)).ExecuteNonQuery() != 0;

    /// <summary>
    /// The WCF service ran the update and the log as separate calls (a failed log left the update applied).
    /// Here both run in one transaction, so a LOS action is recorded completely or not at all.
    /// </summary>
    private bool InTransaction(Func<Microsoft.Data.SqlClient.SqlConnection, Microsoft.Data.SqlClient.SqlTransaction, bool> work)
    {
        using var cn = _db.Open();
        using var tx = cn.BeginTransaction();
        try
        {
            if (!work(cn, tx)) { tx.Rollback(); return false; }
            tx.Commit();
            return true;
        }
        catch
        {
            tx.Rollback();
            throw;
        }
    }
}

/// <summary>Latest discharge-advice detail for one patient (from the dschg_adv table).</summary>
public sealed record DischargeAdvice(long IpNo, string AdviceDateTime, string Remark, string ExpectedDischarge, int DocCd, int StatusCd, string CreatedByUserId);

/// <summary>Search criteria — the same inputs SearchResult() reads from the search header.</summary>
public sealed class PatientSearch
{
    public int WardCd { get; set; }
    public int DocCd { get; set; }
    public int SpltyCd { get; set; }
    public decimal FlrNo { get; set; }
    public int PtnTyp { get; set; }          // 0 = ALL
    public int MrdStatus { get; set; }       // drpmrdsts
    public bool Vulnerable { get; set; }
    public bool Isolated { get; set; }
    public bool Hwc { get; set; }
    public bool ArrivedOnBed { get; set; }
}
