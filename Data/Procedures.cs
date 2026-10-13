namespace NurseStationTablet.Data;

/// <summary>
/// Stored procedures the app calls. Each NST_ procedure is a NEW procedure created for the tablet
/// (Database/01_NST_CreateFromExisting.sql copies the body of the procedure the WCF service used,
/// so behaviour is identical on day one and the NST_ copy can then be changed independently).
/// Parameter names are the legacy ones, so the copies are drop-in.
/// </summary>
public static class Sp
{
    // ---- copied from procedures used by NurseStation.svc (WCF DAL) ----
    public const string SelPatientList = "NST_SelPatientList";        // SpSelInPtnMst014        clsPatient.GetPtnHelpWithOpenFolio
    public const string SelUserPtnTyp = "NST_SelUserPtnTyp";          // SpSelUserPtnTypMst001   clsPtnTypeMst.GetPtnTypListByUser
    public const string SelRule = "NST_SelRule";                      // SPSELRULEMST            clsRuleMaster.GetRuleMstDtls
    public const string SrchCodeDecode = "NST_SrchCodeDecode";        // SPCDDECDLIST011         clsCodeDecode.getCdDcdByContentSearch
    public const string SrchDoctor = "NST_SrchDoctor";                // SpSelDocMstByPrefix02   clsDoctor.getDocByContentSearch
    public const string SelMrdRecCount = "NST_SelMRDRecCount";        // spSelMRDFileReg001      clsMRDFileCollReq.GetMRDRecrds
    public const string SelUserDet = "NST_SelUserDet";                // SPSELUSERDETBYCD        clsUserDet.GetUserDetByCD
    public const string SelLosConfig = "NST_SelLOSConfig";            // SPSELADTINDT            clsadtindt.GetEnableLOSConfirmation
    public const string SelLosByIp = "NST_SelLOSByIp";                // SPSELIPPTNVST036        clsPatient.GetLOSDtlByIp
    public const string UpdLosConfirm = "NST_UpdLOSConfirm";          // SPUPDIPPTNVST026        NurseStation.ConfirmLOS
    public const string UpdLosSkip = "NST_UpdLOSSkip";                // SpUpdIpPtnVst027        NurseStation.SkipLOS
    public const string UpdLosExtend = "NST_UpdLOSExtend";            // SPUPDIPPTNVST025        NurseStation.UpdateIPLOS
    public const string InsLosActionLog = "NST_InsLOSActionLog";      // SpInsUpdIPLOSActionLog  clsInsUpdIPLOSActionLog
    public const string SelNetIdByModule = "NST_SelNetIdByModule";    // SPSELNETID002           clsNetId.GetNetIdDetByModCdSubModCd
    public const string SelSmsParam = "NST_SelSmsParam";              // SpSelSmsParam           clsSmsParam.GetSmsParamDataWithNoParamters
    public const string SelSmsMst = "NST_SelSmsMst";                  // SpSelSmsMst             clsSmsMst.SpSelSmsMst
    public const string SelSmsReplaceData = "NST_SelSmsReplaceData";  // SpSelGetSmsDtlForReplaceStr
    public const string InsSmsDtl = "NST_InsSmsDtl";                  // SpInsSmsDtl             clsInsertUpdateSmsDtl.SpInsSmsDtl

    // ---- new procedures for logic the WCF DAL ran as inline SQL ----
    public const string ChkSysLock = "NST_ChkSysLock";                // SELECT dbo.FnCheckSysLock()   clsCommonModule.ChkSysLock
    public const string SelServerDateTime = "NST_SelServerDateTime";  // SELECT GETDATE()               commonFunctions.GetServerDateTime

    // ---- LOCATION column: legacy PATIENT TRACKING page (Database/03_NST_MarkPatient.sql) ----
    public const string SelIpWardEvnt = "NST_SelIPWardEvnt";          // SPSelIPWardEvnt         patient's ward events (newest first)
    public const string SaveIpWardEvnt = "NST_SaveIPWardEvnt";        // SPUpdIPWardEvnt + spInsUpdIPCurrentLocn   SAVE on the tracking page

    // ---- stand-alone (Development) session ----
    public const string SelActiveLogin = "NST_SelActiveLogin";      // LogInOutDetail: latest login of the user that has not logged out

    // ---- CommonSecurityFunc service (source not yet provided) ----
    public const string SelUserRights = "NST_SelUserRights";          // CmnSecurityFun.UserRights
    public const string SelMessages = "NST_SelMessages";              // CmnSecurityFun.GetmsgmstList
    public const string SelRevenueDate = "NST_SelRevenueDate";        // CmnSecurityFun.GetRevenueDate
}
