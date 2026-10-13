/* =====================================================================================
   NURSE STATION (new Nursing Workbench) - INSTALL ALL STORED PROCEDURES

   Run this ONE script on the CareWorks database (SOFCWHMIS) of each environment.
   It creates every dbo.NST_* procedure the application calls - 26 procedures - and nothing else.

     * Safe to re-run: each procedure is dropped and created again.
     * Touches only dbo.NST_* procedures. No table, data or existing (legacy) procedure is changed.
     * Lists (as a warning, without stopping) any existing object the procedures read that this database does not have.
     * To remove everything again, run Uninstall_NST_Procedures.sql.

   Run with a login that can create procedures (SSMS, or: sqlcmd -S <server> -d <database> -b -i Install_NST_Procedures.sql).
   Dropping and re-creating a procedure removes its permissions: set @GrantTo in the last section to re-grant EXECUTE.

   Procedures
     NST_SelPatientList       patient list (same logic as SpSelInPtnMst014, all rows, paging parameters kept)
     NST_SelUserPtnTyp        patient types the user may see
     NST_SelRule              rule master lookup
     NST_SrchCodeDecode       ward / speciality search box
     NST_SrchDoctor           doctor search box
     NST_SelMRDRecCount       MRD file register check (MRD status filter)
     NST_SelUserDet           user details (nick name, stored password, doctor code)
     NST_SelLOSConfig         length-of-stay confirmation settings
     NST_SelLOSByIp           length-of-stay details of one patient
     NST_UpdLOSConfirm        confirm length of stay
     NST_UpdLOSSkip           skip length-of-stay confirmation
     NST_UpdLOSExtend         extend length of stay
     NST_InsLOSActionLog      length-of-stay action log
     NST_SelNetIdByModule     web path of a module (netid)
     NST_SelSmsParam          discharge SMS: parameters
     NST_SelSmsMst            discharge SMS: templates
     NST_SelSmsReplaceData    discharge SMS: replacement data
     NST_InsSmsDtl            discharge SMS: queue the message
     NST_ChkSysLock           system lock check
     NST_SelServerDateTime    server date / time
     NST_SelIPWardEvnt        PATIENT TRACKING (location column): ward events of a patient
     NST_SaveIPWardEvnt       PATIENT TRACKING (location column): SAVE the current event
     NST_SelActiveLogin       active legacy login of a user (used only by the stand-alone development session)
     NST_SelUserRights        module rights of a user
     NST_SelMessages          module messages (msgmst)
     NST_SelRevenueDate       revenue date (hsp_in_dt)
===================================================================================== */

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ---------------------------------------------------------------- 1. pre-flight check ---- */
/* The procedures read these existing objects. A missing one is only reported; the procedure that uses it fails when it is called. */
DECLARE @missing NVARCHAR(MAX) = N'';
SELECT @missing = @missing + CHAR(13) + CHAR(10) + N'   ' + v.nm
FROM (VALUES
       (N'dbo.adt_in_dt'),
       (N'dbo.ar_mst'),
       (N'dbo.bed_mst'),
       (N'dbo.bed_typ_mst'),
       (N'dbo.bloodrqheader'),
       (N'dbo.calage'),
       (N'dbo.calmax_dob'),
       (N'dbo.calyear_yy'),
       (N'dbo.cd_dcd'),
       (N'dbo.chrg_mst'),
       (N'dbo.divisionmst'),
       (N'dbo.doc_mst'),
       (N'dbo.dschg_adv'),
       (N'dbo.fct_mst'),
       (N'dbo.fn_doc_name'),
       (N'dbo.fn_doc_speciality'),
       (N'dbo.fn_getcddcd'),
       (N'dbo.fn_getgender'),
       (N'dbo.fn_getlosstatusforrightclick'),
       (N'dbo.fn_ipopname'),
       (N'dbo.fnchecksyslock'),
       (N'dbo.fninsurancecodedesc'),
       (N'dbo.hsp_in_dt'),
       (N'dbo.instal'),
       (N'dbo.ip_bil_instrn'),
       (N'dbo.ip_bill'),
       (N'dbo.ip_fol'),
       (N'dbo.ip_ins_reg'),
       (N'dbo.ip_ptn_vst'),
       (N'dbo.ip_trn_doc_shr'),
       (N'dbo.ipcurrentlocn'),
       (N'dbo.ipdschgplan'),
       (N'dbo.iplosactionlog'),
       (N'dbo.ipnodueshdr'),
       (N'dbo.ipreservation'),
       (N'dbo.ipwardevnt'),
       (N'dbo.ipwardevntmst'),
       (N'dbo.locationmst'),
       (N'dbo.loginoutdetail'),
       (N'dbo.module'),
       (N'dbo.moduleweb'),
       (N'dbo.mrdfilecollreq'),
       (N'dbo.mrdfilereg'),
       (N'dbo.msgmst'),
       (N'dbo.mtritemmst'),
       (N'dbo.netid'),
       (N'dbo.personaldetails'),
       (N'dbo.ptn_cls_mst'),
       (N'dbo.ptn_mst1'),
       (N'dbo.ptn_mst2'),
       (N'dbo.ptnbodymassindx'),
       (N'dbo.ptntypemst'),
       (N'dbo.room_mst'),
       (N'dbo.rq_main'),
       (N'dbo.rulemst'),
       (N'dbo.s_userdet'),
       (N'dbo.serorddtl'),
       (N'dbo.serordhdr'),
       (N'dbo.sms_dtl'),
       (N'dbo.sms_grp_dtl'),
       (N'dbo.sms_mst'),
       (N'dbo.sms_mst_forward'),
       (N'dbo.sms_param'),
       (N'dbo.spinsupdipcurrentlocn'),
       (N'dbo.spupdipwardevnt'),
       (N'dbo.str_mst'),
       (N'dbo.traineedocmst'),
       (N'dbo.user_wards'),
       (N'dbo.userptntypmst'),
       (N'dbo.usertypemst'),
       (N'dbo.usr_det'),
       (N'dbo.wardcontactmst'),
       (N'ems.eqp_dept'),
       (N'ems.eqpdeptemp')
     ) AS v(nm)
WHERE OBJECT_ID(v.nm) IS NULL;

IF @missing <> N'' PRINT N'WARNING - these objects were not found in this database:' + @missing;
ELSE PRINT N'Pre-flight check passed.';
GO

/* ---------------------------------------------------------------- 2. retired procedures ---- */
/* Used by earlier versions of the application; no longer needed. Removed when present. */
IF OBJECT_ID(N'dbo.NST_SelWardListByUser', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelWardListByUser;
IF OBJECT_ID(N'dbo.NST_SelDoctor', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelDoctor;
IF OBJECT_ID(N'dbo.NST_SelCodeDecode', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelCodeDecode;
IF OBJECT_ID(N'dbo.NST_SelCodeDecodeList', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelCodeDecodeList;
IF OBJECT_ID(N'dbo.NST_UpdDefaultWard', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_UpdDefaultWard;
IF OBJECT_ID(N'dbo.NST_MarkArrivedOnBed', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_MarkArrivedOnBed;
IF OBJECT_ID(N'dbo.NST_SelIPCurrentLocn', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelIPCurrentLocn;
GO

/* ---------------------------------------------------------------- 3. procedures ---- */

/* 01 / 26  NST_SelPatientList - patient list (same logic as SpSelInPtnMst014, all rows, paging parameters kept) */
IF OBJECT_ID(N'dbo.NST_SelPatientList', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelPatientList;
GO
/* =============================================================================
   dbo.SpSelInPtnMst014  -  static (non-dynamic) rewrite
   -----------------------------------------------------------------------------
   Logic identical to the dynamic-SQL version except:
     * ORDER BY rule 9365 handled via CASE (BedNo / AdmDt / WardDCd / Roomno / DocNm)
     * RevDt- and UserId-dependent columns are always returned (NULL when N/A)
   Performance:
     * Ward-level counts computed once per ward, patient-level counts once per
       patient (was: 10 correlated sub-selects re-evaluated per patient row)
     * OPTION (RECOMPILE) on the main list query so plans fit the supplied filters
   ============================================================================= */
CREATE   PROCEDURE [dbo].[NST_SelPatientList]
    @pCoCd           CHAR(3)      = NULL,
    @pDiv            SMALLINT     = 0,
    @pLoc            SMALLINT     = 0,
    @pFrstNm         VARCHAR(40)  = NULL,
    @pMidNm          VARCHAR(40)  = NULL,
    @pLstNm          VARCHAR(40)  = NULL,
    @pDocCd          INT          = 0,
    @pWardCd         INT          = NULL,
    @pAdmStsCd       INT          = NULL,
    @pMRDStsCd       INT          = 0,
    @PArCd           INT          = NULL,
    @PUserId         VARCHAR(16)  = '',
    @pPtnType        INT          = 0,
    @pFathersName    VARCHAR(100) = '',
    @pPtnNo          BIGINT       = 0,
    @pRevDt          DATETIME     = NULL,
    @IsPtnVulnerable BIT          = 0,
    @IsPtnIsolated   BIT          = 0,
    @DocSpltyCd      INT          = 0,
    @floorNo         FLOAT        = 0,
    @pIsArrivedOnBed BIT          = 0,
    @IsHWC           BIT          = 0,
    @pPageNo         INT          = 1,
    @pPageSize       INT          = 20
AS
BEGIN
    SET NOCOUNT ON;

    /* ------------------------------------------------------------ pagination */
    IF ISNULL(@pPageNo,   0) <= 0 SET @pPageNo   = 1;
    IF ISNULL(@pPageSize, 0) <= 0 SET @pPageSize = 20;
    DECLARE @Offset INT = (@pPageNo - 1) * @pPageSize;

    /* ------------------------------------------------------------ rules */
    DECLARE @Rule9365 NVARCHAR(510) =
        (SELECT ISNULL(Data2, '') FROM rulemst
          WHERE RuleID = 9365 AND Data1 = 'Y' AND Data2 <> '');

    DECLARE @isnewadmn INT =
        ISNULL((SELECT CONVERT(INT, Data2) FROM RuleMst
                 WHERE RuleID = 9277 AND Data1 = 'Y'), 0);

    /* ---------------------------- normalised filters (same rules as old IFs) */
    DECLARE @FrstNmPat   VARCHAR(41)  = CASE WHEN @pFrstNm      <> '' THEN @pFrstNm + '%'            END;
    DECLARE @MidNmPat    VARCHAR(41)  = CASE WHEN @pMidNm       <> '' THEN @pMidNm  + '%'            END;
    DECLARE @LstNmPat    VARCHAR(41)  = CASE WHEN @pLstNm       <> '' THEN @pLstNm  + '%'            END;
    DECLARE @FatherPat   VARCHAR(102) = CASE WHEN @pFathersName <> '' THEN '%' + @pFathersName + '%' END;
    DECLARE @HasRevDt    BIT          = CASE WHEN @pRevDt <> '' THEN 1 ELSE 0 END;
    DECLARE @RevDt       DATE         = CASE WHEN @pRevDt <> '' THEN CAST(@pRevDt AS DATE) END;
    DECLARE @HasUser     BIT          = CASE WHEN ISNULL(@PUserId, '') <> '' THEN 1 ELSE 0 END;
    DECLARE @DefPtnTypCd INT          = CASE WHEN @HasUser = 1
                                             THEN (SELECT ISNULL(DefPtntypeCd, 0) FROM usr_det WHERE usr_id = @PUserId)
                                        END;

    /* ------------------------------------------- bill / folio status (#temp) */
    CREATE TABLE #temp
    (
        ipno             BIGINT,
        final            INT,
        fol_sts_cd       INT,
        ReadyToDischarge BIT
    );

    INSERT INTO #temp (ipno, final, fol_sts_cd, ReadyToDischarge)
    SELECT ip_no,
           CASE WHEN SUM(final) > 0 THEN 1 ELSE 0 END                                   AS final,
           fol_sts_cd,
           CASE WHEN SUM(amt) - SUM(concamt) = SUM(stlmtamt)
                 AND SUM(final) > 0
                 AND fol_sts_cd = 2
                THEN 1 ELSE 0 END                                                        AS ReadyToDischarge
    FROM
    (
        SELECT v.ip_no,
               ISNULL(b.bil_no, 0)      AS bil_no,
               ISNULL(f.fol_sts_cd, 0)  AS fol_sts_cd,
               ISNULL(v.adm_sts_cd, 0)  AS adm_sts_cd,
               CAST(b.final AS INT)     AS final,
               ISNULL(b.amt, 0)         AS amt,
               ISNULL(b.conc_amt, 0)    AS concamt,
               ISNULL(b.stlmt_amt, 0)   AS stlmtamt
        FROM ip_ptn_vst v
             JOIN ip_bill b ON v.ip_no = b.ip_no
             JOIN ip_fol  f ON f.ip_no = v.ip_no
        WHERE b.bil_no <> 0
          AND v.adm_sts_cd = 2
          AND (@pDocCd  = 0 OR @pDocCd  IS NULL OR v.doc_cd = @pDocCd)
          AND (@pWardCd = 0 OR @pWardCd IS NULL OR v.wrd_cd = @pWardCd)
    ) tabb
    GROUP BY ip_no, fol_sts_cd;

    CREATE UNIQUE CLUSTERED INDEX IX_temp ON #temp (ipno, fol_sts_cd);

    /* --------------------------------------------------- user access tables */
    CREATE TABLE #TempTblPtnTypes (PtnTypCd INT PRIMARY KEY);
    CREATE TABLE #UserWards       (WrdCd    INT PRIMARY KEY);

    IF @HasUser = 1
    BEGIN
        INSERT INTO #TempTblPtnTypes (PtnTypCd)
        SELECT DISTINCT PtnTypCd
        FROM UserPtnTypMst
        WHERE usr_id = @PUserId AND HasAccess = 1;

        INSERT INTO #UserWards (WrdCd)
        SELECT DISTINCT WrdCd
        FROM User_Wards
        WHERE UserID = @PUserId AND HasRights = 1;
    END;

    /* ---------------------------------------------------- main patient list */
    SELECT *
    INTO #TempPtnTab
    FROM
    (
        SELECT
            ISNULL(a.ptn_no, 0)                                    AS [PatientNo],
            ISNULL(a.ip_no, 0)                                     AS [InPatientNo],
            ISNULL(b.ttl_cd, 0)                                    AS [PatientTitleCode],
            ISNULL(c.dcd, '')                                      AS [PatientTitleCodeDesc],
            ISNULL(ptn_frst_nm, '')                                AS [PatientFirstName],
            ISNULL(ptn_mid_nm, '')                                 AS [PatientMiddleName],
            ISNULL(ptn_lst_nm, '')                                 AS [PatientLastName],
            ISNULL(c.dcd, '') + ' ' + ISNULL(ptn_lst_nm, '') + ' '
                + ISNULL(ptn_frst_nm, '') + ' ' + ISNULL(ptn_mid_nm, '')
                                                                   AS [PatientFullName],
            CAST(ISNULL(adm_dt, '') AS DATE)                       AS [AdmDt],
            FORMAT(ISNULL(dschg_dt, '1900-01-01'), 'dd/MM/yyyy')   AS [DschgDt],
            FORMAT(ISNULL(dschg_tm, ''), 'hh:mm tt')               AS [dschg_tm],
            ISNULL(dbo.fn_GetGender(sex), '')                      AS [Gender],
            ISNULL(dbo.fn_GetLOSStatusForRightClick(ISNULL(a.ip_no, 0)), '')
                                                                   AS [AllowRightClick],
            ISNULL(mobile, '')                                     AS [mobile],
            ISNULL(b.brth_dt, '')                                  AS [BirthDt],
            ISNULL(dbo.CalAge(b.brth_dt, GETDATE()), '')           AS [Age],
            ISNULL(a.bed_no, '')                                   AS [BedNo],
            ISNULL(bed_typ_dcd, '')                                AS [BedTypDesc],
            ISNULL(adm_sts_cd, '')                                 AS [Status],
            ISNULL(a.wrd_cd, 0)                                    AS [WardCd],
            ISNULL(f.dcd, '')                                      AS [WardDCd],
            ISNULL(a.doc_cd, 0)                                    AS [DocCd],
            ISNULL(mrd.ReqNo, '')                                  AS [ReqNo],
            ISNULL(dbo.fn_Doc_Name(a.doc_cd), '')                  AS [DocNm],
            ISNULL(d.splty_cd, 0)                                  AS spltyCd,
            CASE WHEN ISNULL(h.dschg_adv_sts, 0) = 1 THEN 'Given' ELSE 'Not given' END
                                                                   AS dschg_adv_sts,
            ISNULL(i.dcd, '')                                      AS DschrgSts,
            ISNULL(bmi.PtnBodyMassIndx, 0)                         AS LastBmi,
            ISNULL(ew.locname, '')                                 AS locname,
            ISNULL(j.rm_no, '0')                                   AS [Roomno],
            ISNULL(RmMst.rm_name, '')                              AS [RoomName],
            ISNULL(a.ptn_cls_cd, 0)                                AS [PatientClassCode],
            ISNULL(ptnclsmst.ptn_cls_dcd, '')                      AS [PatientClassCodeDesc],
            ISNULL(Ar_Mst.ar_lng_nm, '')                           AS [ArDesc],
            ISNULL(Ar_Mst.ar_cd, '')                               AS [ArCd],
            ISNULL(a.ptn_src_cd, '')                               AS [ptnSrcCd],
            ISNULL(a.cse_typ_cd, '')                               AS [csetypcd],
            ISNULL(CdDcdptnsrc.dcd, '')                            AS [PtnSrc],
            ISNULL(t.ReadyToDischarge, 0)                          AS [ReadyToDschrge],
            ISNULL(AgeTypeCdDcd.dcd, '')                           AS [AgeType],
            ISNULL(a.PtnTypCd, '0')                                AS [PtnTypCd],
            ISNULL(PtnTypeMst.PtnTypDesc, '')                      AS PtnTypDesc,
            ISNULL(t.final, 0)                                     AS [FinalBillSts],
            ISNULL(g.fol_sts_cd, 0)                                AS fol_sts_cd,
            ISNULL(IpNoDuesHdr.NoDues, 0)                          AS [NoDues],
            ISNULL(a.IsLOSConfirmed, 0)                            AS [IsLOSConfirmed],
            @DefPtnTypCd                                           AS DefPtnTypCd,      -- NULL when no user
            ISNULL(b.PtnFathersNm, '')                             AS [FatherName],

            /* ---- review-date dependent columns (NULL when @pRevDt not given) ---- */
            CASE WHEN @HasRevDt = 1 THEN ISNULL(diet.IsDietAssigned, 0) END
                                                                   AS IsDietAssigned,
            CASE WHEN @HasRevDt = 1 THEN
                 CASE WHEN @isnewadmn > 0
                       AND DATEDIFF(HOUR,
                                    CAST(adm_dt AS DATETIME) + CAST(CONVERT(TIME, adm_tm) AS DATETIME),
                                    @RevDt) <= @isnewadmn
                      THEN 1
                      ELSE CASE WHEN CAST(ISNULL(adm_dt, '') AS DATE) = @RevDt THEN 1 ELSE 0 END
                 END
            END                                                    AS IsNewAdmission,
            CASE WHEN @HasRevDt = 1 THEN
                 CASE WHEN CAST(ISNULL(adm_dt, '') AS DATE) = @RevDt
                      THEN DATEDIFF(HOUR,
                                    CAST(adm_dt AS DATETIME) + CAST(CONVERT(TIME, adm_tm) AS DATETIME),
                                    @RevDt)
                      ELSE '' END
            END                                                    AS AdmittedBeforeHrs,
            CASE WHEN @HasRevDt = 1 THEN
                 CASE WHEN CAST(ISNULL(adm_dt, '') AS DATE) = @RevDt
                      THEN DATEDIFF(MINUTE,
                                    CAST(adm_dt AS DATETIME) + CAST(CONVERT(TIME, adm_tm) AS DATETIME),
                                    GETDATE())
                      ELSE '' END
            END                                                    AS AdmittedBeforeMins,

            ISNULL(j.flr_no, 0)                                    AS [flr_no],
            ISNULL(cddcdflr.dcd, '')                               AS [flr_nm],
            FORMAT(ISNULL(adm_tm, ''), 'hh:mm tt')                 AS [Admtm],
            ISNULL(CAST(dbo.FN_GetCDDCD(1, 1, 1, 12,  TRY_CAST(aA.bld_grp_cd AS INT)) AS NVARCHAR(MAX)), 'NA')
                + ' ' +
            ISNULL(CAST(dbo.FN_GetCDDCD(1, 1, 1, 303, TRY_CAST(aA.rh_fctr    AS INT)) AS NVARCHAR(MAX)), '')
                                                                   AS [OTClearance],
            ISNULL('0', 0)                                         AS [OTBooked],
            ISNULL(cddcdSpclty.dcd, '')                            AS [SpecialityCodeDesc],
            ISNULL(a.DschgPlanDocNo, 0)                            AS [DschgPlanDocNo],
            ISNULL(a.IsIsolated, 0)                                AS IsIsolated,
            ISNULL(b.IsPtnBlackListed, 0)                          AS IsPtnBlackListed,
            ISNULL(a.IsPtnVulnerable, 0)                           AS IsPtnVulnerable,
            0                                                      AS IsHighRisk,
            ISNULL(a.IsArrivedOnBed, 0)                            AS IsArrivedOnBed,
            ISNULL(a.exptd_no_day, 0)                              AS [LOS],
            DATEDIFF(d, a.adm_dt, GETDATE()) + 1                   AS [ALOS]
        FROM ip_ptn_vst a (NOLOCK)
             LEFT JOIN ptn_mst1   b  (NOLOCK) ON a.ptn_no = b.ptn_no AND adm_Sts_cd <> 5
             LEFT JOIN ptn_mst2   aA (NOLOCK) ON aA.ptn_no = b.ptn_no
             JOIN      cd_dcd     c  (NOLOCK) ON b.ttl_cd = c.cd AND c.typ = 3 AND Ptn_sts = 'N'
             LEFT JOIN cd_dcd AgeTypeCdDcd (NOLOCK) ON b.AgetypFlg = AgeTypeCdDcd.cd AND AgeTypeCdDcd.typ = 8052
             LEFT JOIN PtnTypeMst PtnTypeMst (NOLOCK) ON PtnTypeMst.PtnTypCd = a.PtnTypCd
             JOIN      doc_mst    d  (NOLOCK) ON a.doc_cd = d.doc_cd
             JOIN      bed_typ_mst e (NOLOCK) ON a.bed_typ_cd = e.bed_typ_cd
             JOIN      cd_dcd     f  (NOLOCK) ON a.wrd_cd = f.cd AND f.typ = 2
             JOIN      ip_fol     g  (NOLOCK) ON a.ip_no = g.ip_no
             JOIN      ptn_cls_mst ptnclsmst (NOLOCK) ON ptnclsmst.ptn_cls_cd = a.ptn_cls_cd
             LEFT JOIN bed_mst    j  (NOLOCK) ON j.bed_no = a.bed_no
             LEFT JOIN Room_mst   RmMst (NOLOCK) ON j.rm_no = RmMst.rm_no
             LEFT JOIN ip_bil_instrn Ip_Bill_instr (NOLOCK) ON Ip_Bill_instr.ip_no = a.ip_no
             LEFT JOIN ar_mst     Ar_Mst (NOLOCK) ON Ar_Mst.ar_cd = Ip_Bill_instr.ar_cd
             LEFT JOIN cd_dcd     CdDcdptnsrc (NOLOCK) ON CdDcdptnsrc.cd = a.ptn_src_cd AND CdDcdptnsrc.typ = 13
             LEFT JOIN DSCHG_ADV  h  ON a.ip_no = h.ip_no AND h.dschg_adv_sts <> 3
             LEFT JOIN cd_dcd     i  ON h.dschg_sts_cd = i.cd AND i.typ = 19
             LEFT JOIN #temp      t  ON t.ipno = a.ip_no
             LEFT JOIN IpNoDuesHdr IpNoDuesHdr ON IpNoDuesHdr.ipno = a.ip_no
             LEFT JOIN ipcurrentlocn ew ON ew.IPNo = a.ip_no
             LEFT JOIN cd_dcd     cddcdflr ON j.flr_no = cddcdflr.cd AND cddcdflr.typ = 501
             LEFT JOIN cd_dcd     cddcdSpclty (NOLOCK) ON d.doc_cd = cddcdSpclty.cd AND cddcdSpclty.typ = 28
             LEFT JOIN IPDschgPlan IPDschgPlan ON IPDschgPlan.DschgPlanDocNo = a.DschgPlanDocNo
                                               AND IPDschgPlan.IpNo = a.ip_no
             /* latest MRD file-collection request */
             OUTER APPLY
             (
                 SELECT TOP (1) CONVERT(VARCHAR, q.ReqNo) + '_' + CONVERT(VARCHAR, q.ReqStatusCd) AS ReqNo
                 FROM MRDFileCollReq q
                 WHERE q.PtnNo = a.ptn_no AND q.IPNo = a.ip_no
                 ORDER BY ISNULL(CAST(CONCAT(CAST(q.ReqDate AS DATE), ' ', CAST(q.ReqTime AS TIME)) AS DATETIME2(0)), '') DESC
             ) mrd
             /* last BMI */
             OUTER APPLY
             (
                 SELECT TOP (1) ISNULL(x.PtnBodyMassIndx, 0) AS PtnBodyMassIndx
                 FROM PtnBodyMassIndx x
                 WHERE x.cocd  = @pCoCd
                   AND x.divcd = CONVERT(VARCHAR(5), @pDiv)
                   AND x.loccd = CONVERT(VARCHAR(5), @pLoc)
                   AND x.PtnNo = a.ptn_no
                   AND x.IPNo  = a.ip_no
                 ORDER BY x.Srno DESC
             ) bmi
             /* diet order on review date */
             OUTER APPLY
             (
                 SELECT TOP (1) CASE WHEN ISNULL(o.ord_no, 0) = '0' THEN '0' ELSE '1' END AS IsDietAssigned
                 FROM nst_diet_ord_det o
                 WHERE @HasRevDt = 1
                   AND o.ord_date   = @RevDt
                   AND o.ord_status = 1
                   AND o.ip_no      = a.ip_no
             ) diet
        WHERE 1 = 1
          /* kept verbatim: NULL flr_no / splty_cd rows are excluded, as before */
          AND d.splty_cd = CASE WHEN @DocSpltyCd = 0 THEN d.splty_cd ELSE @DocSpltyCd END
          AND j.flr_no   = CASE WHEN @floorNo   = 0 THEN j.flr_no   ELSE @floorNo   END
          AND (@FrstNmPat  IS NULL OR ptn_frst_nm    LIKE @FrstNmPat)
          AND (@MidNmPat   IS NULL OR ptn_mid_nm     LIKE @MidNmPat)
          AND (@LstNmPat   IS NULL OR ptn_lst_nm     LIKE @LstNmPat)
          AND (@FatherPat  IS NULL OR b.PtnFathersNm LIKE @FatherPat)
          AND (ISNULL(@pDocCd,    0) = 0 OR a.doc_cd            = @pDocCd)
          AND (ISNULL(@pWardCd,   0) = 0 OR a.wrd_cd            = @pWardCd)
          AND (ISNULL(@pAdmStsCd, 0) = 0 OR a.adm_sts_cd        = @pAdmStsCd)
          AND (ISNULL(@PArCd,     0) = 0 OR Ip_Bill_instr.ar_cd = @PArCd)
          AND (ISNULL(@pPtnNo,    0) = 0 OR b.ptn_no            = @pPtnNo)
          AND (ISNULL(@IsPtnVulnerable, 0) = 0 OR a.IsPtnVulnerable  = 1)
          AND (ISNULL(@IsPtnIsolated,   0) = 0 OR a.IsIsolated       = 1)
          AND (ISNULL(@IsHWC,           0) = 0 OR b.IsPtnBlackListed = 1)
          AND (ISNULL(@pIsArrivedOnBed, 0) = 0 OR a.IsArrivedOnBed   = 1)
          AND (   @HasUser = 0
               OR (ISNULL(@pPtnType, 0) <> 0 AND a.PtnTypCd = @pPtnType)
               OR (ISNULL(@pPtnType, 0) =  0
                   AND a.PtnTypCd IN (SELECT PtnTypCd FROM #TempTblPtnTypes)
                   AND a.wrd_cd   IN (SELECT WrdCd    FROM #UserWards))
              )
    ) tab
    WHERE @pMRDStsCd = CASE WHEN @pMRDStsCd = 0 THEN @pMRDStsCd
                            ELSE SUBSTRING(ReqNo, LEN(ReqNo), 1) END
    OPTION (RECOMPILE);

    CREATE INDEX IX_TempPtnTab_Ward ON #TempPtnTab (WardCd) INCLUDE (InPatientNo, PatientNo, ArCd);

    /* ----------------------------------------- ward-wise counts (set based) */

    /* distinct patients in the result */
    SELECT DISTINCT InPatientNo, PatientNo
    INTO #Ptn
    FROM #TempPtnTab;
    CREATE UNIQUE CLUSTERED INDEX IX_Ptn ON #Ptn (InPatientNo, PatientNo);

    /* per-patient counts: each source table touched once */
    SELECT p.InPatientNo,
           p.PatientNo,
           ISNULL(bl.Cnt,  0) AS BldReqCnt,
           ISNULL(lab.Cnt, 0) AS LabReqCnt,
           ISNULL(rad.Cnt, 0) AS RadReqCnt,
           ISNULL(prc.Cnt, 0) AS ProcReqCnt,
           ISNULL(med.Cnt, 0) AS MedReqCnt,
           ISNULL(vip.Cnt, 0) AS VipPtnCnt,
           ISNULL(rej.Cnt, 0) AS SampleRejPtnCount
    INTO #PtnCnt
    FROM #Ptn p
         LEFT JOIN (SELECT p.InPatientNo, COUNT(*) AS Cnt
                    FROM #Ptn p JOIN BloodrqHeader a ON a.BldRqIPNo = p.InPatientNo AND a.BldRqStatus = 1
                    GROUP BY p.InPatientNo) bl  ON bl.InPatientNo = p.InPatientNo
         LEFT JOIN (SELECT p.InPatientNo, COUNT(a.ip_no) AS Cnt
                    FROM #Ptn p JOIN nst_tst_ord_det a ON a.ip_no = p.InPatientNo AND a.ord_status = 1
                                JOIN chrg_mst c ON a.chrg_cd = c.chrg_cd AND c.lab_chrg_flg = 'Y'
                    GROUP BY p.InPatientNo) lab ON lab.InPatientNo = p.InPatientNo
         LEFT JOIN (SELECT p.InPatientNo, COUNT(a.ip_no) AS Cnt
                    FROM #Ptn p JOIN nst_tst_ord_det a ON a.ip_no = p.InPatientNo AND a.ord_status = 1
                                JOIN chrg_mst c ON a.chrg_cd = c.chrg_cd AND c.IsRadiologyChrg = 1
                    GROUP BY p.InPatientNo) rad ON rad.InPatientNo = p.InPatientNo
         LEFT JOIN (SELECT p.InPatientNo, COUNT(a.ip_no) AS Cnt
                    FROM #Ptn p JOIN nst_tst_ord_det a ON a.ip_no = p.InPatientNo AND a.ord_status = 1
                                JOIN chrg_mst c ON a.chrg_cd = c.chrg_cd AND c.IsProcedureChrg = 1
                    GROUP BY p.InPatientNo) prc ON prc.InPatientNo = p.InPatientNo
         LEFT JOIN (SELECT p.InPatientNo, COUNT(a.ip_no) AS Cnt
                    FROM #Ptn p JOIN nst_med_ord_det a ON a.ip_no = p.InPatientNo AND a.ord_status = 1
                    GROUP BY p.InPatientNo) med ON med.InPatientNo = p.InPatientNo
         LEFT JOIN (SELECT p.PatientNo, COUNT(*) AS Cnt
                    FROM (SELECT DISTINCT PatientNo FROM #Ptn) p
                         JOIN ptn_mst2 a5 ON a5.ptn_no = p.PatientNo AND a5.vip_flag IN (1, 2)
                    GROUP BY p.PatientNo) vip ON vip.PatientNo = p.PatientNo
         LEFT JOIN (SELECT p.InPatientNo, COUNT(b1.ORDSRNO) AS Cnt
                    FROM #Ptn p
                         JOIN SERORDHDR a  ON a.HOSPNO = p.InPatientNo AND a.PATTYPE = 'I'
                         JOIN SERORDDTL b1 ON b1.FACCODE = a.FACCODE AND b1.ORDNO = a.ORDNO AND b1.STATUSCODE = 7
                    GROUP BY p.InPatientNo) rej ON rej.InPatientNo = p.InPatientNo;

    /* per-ward counts: rq_main scanned once per ward instead of once per patient */
    SELECT w.WardCd, ISNULL(r.Cnt, 0) AS WardReqCnt
    INTO #WardReq
    FROM (SELECT DISTINCT WardCd FROM #TempPtnTab) w
         LEFT JOIN (SELECT a4.rqmn_cst_cntr_cd AS WardCd, COUNT(*) AS Cnt
                    FROM rq_main a4
                    WHERE a4.rqmn_cst_cntr_typ_cd = 37
                      AND a4.rqmn_sts_flg = 0
                      AND a4.rqmn_cst_cntr_cd IN (SELECT DISTINCT WardCd FROM #TempPtnTab)
                    GROUP BY a4.rqmn_cst_cntr_cd) r ON r.WardCd = w.WardCd;

    SELECT WardCd, SUM(CASE ArCd WHEN 0 THEN 0 ELSE 1 END) AS CrdCmpCnt
    INTO #CrdCmp
    FROM #TempPtnTab
    GROUP BY WardCd;

    CREATE TABLE #TempWrdWiseCount
    (
        WardCd            INT,
        BloodReqCount     INT,
        LabReqCount       INT,
        RadReqCount       INT,
        ProcReqCount      INT,
        MedReqCount       INT,
        WardReqCount      INT,
        VIPPtnCount       INT,
        CrdCmpPtnCount    INT,
        SampleRejPtnCount INT
    );

    /* same DISTINCT + GROUP BY shape as the original, so results are identical */
    INSERT INTO #TempWrdWiseCount
    SELECT WardCd,
           SUM(BldReqCnt),
           SUM(LabReqCnt),
           SUM(RadReqCnt),
           SUM(ProcReqCnt),
           SUM(MedReqCnt),
           WardReqCnt,
           SUM(VipPtnCnt),
           CrdCmpCnt,
           SUM(SampleRejPtnCount)
    FROM
    (
        SELECT DISTINCT
               b.WardCd,
               c.BldReqCnt,
               c.LabReqCnt,
               c.RadReqCnt,
               c.ProcReqCnt,
               c.MedReqCnt,
               w.WardReqCnt,
               c.VipPtnCnt,
               cc.CrdCmpCnt,
               c.SampleRejPtnCount
        FROM #TempPtnTab b
             JOIN #PtnCnt  c  ON c.InPatientNo = b.InPatientNo AND c.PatientNo = b.PatientNo
             JOIN #WardReq w  ON w.WardCd  = b.WardCd
             JOIN #CrdCmp  cc ON cc.WardCd = b.WardCd
    ) tab
    GROUP BY WardCd, WardReqCnt, CrdCmpCnt;

    /* ------------------------------------------------------- final page */
    SELECT a.*,
           COUNT(*) OVER () AS TotalCount,
           b.BloodReqCount, b.LabReqCount, b.RadReqCount, b.ProcReqCount, b.MedReqCount,
           b.WardReqCount, b.VIPPtnCount, b.CrdCmpPtnCount, b.SampleRejPtnCount
    FROM #TempPtnTab a
         JOIN #TempWrdWiseCount b ON a.WardCd = b.WardCd
    ORDER BY
        /* rule 9365: add branches here if other column names are configured */
        CASE WHEN @Rule9365 = 'BedNo'   THEN a.BedNo   END,
        CASE WHEN @Rule9365 = 'AdmDt'   THEN a.AdmDt   END,
        CASE WHEN @Rule9365 = 'WardDCd' THEN a.WardDCd END,
        CASE WHEN @Rule9365 = 'Roomno'  THEN a.Roomno  END,
        CASE WHEN @Rule9365 = 'DocNm'   THEN a.DocNm   END,
        a.PatientFullName,
        a.InPatientNo                                   -- deterministic paging
    OFFSET @Offset ROWS FETCH NEXT @pPageSize ROWS ONLY;

    DROP TABLE #CrdCmp;
    DROP TABLE #WardReq;
    DROP TABLE #PtnCnt;
    DROP TABLE #Ptn;
    DROP TABLE #TempWrdWiseCount;
    DROP TABLE #TempPtnTab;
    DROP TABLE #UserWards;
    DROP TABLE #TempTblPtnTypes;
    DROP TABLE #temp;
END;
GO

/* 02 / 26  NST_SelUserPtnTyp - patient types the user may see */
IF OBJECT_ID(N'dbo.NST_SelUserPtnTyp', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelUserPtnTyp;
GO
-- =============================================                                
-- Author:shital                           
-- Create date:2020-007-25   
--     
-- =============================================                                
CREATE   PROCEDURE [dbo].[NST_SelUserPtnTyp]       
@pCocd     CHAR(3)  = '',           
@pDivcd    SMALLINT = 0,           
@pLoccd    SMALLINT = 0  ,    
  @pUserID VARCHAR(16)    
    
AS          
    BEGIN          
        SELECT ISNULL(mst.PtnTypCd, 0) [PtnTypCd],           
               ISNULL(mst.PtnTypDesc, '') [PtnTypDesc]        
                 
                    
                 
      ,    
      isnull(UserPtnTypMst.HasAccess,0)[Access],    
      UserPtnTypMst.usr_id    
    , CASE WHEN usr_det.DefPtntypeCd<>'' OR usr_det.DefPtnTypeCd IS not NULL OR usr_det.DefPtnTypeCd<>0  then 1 else 0 end as  [DefPtntyp]    
        FROM PtnTypeMst mst       
    
  left join UserPtnTypMst UserPtnTypMst on UserPtnTypMst.PtnTypCd=mst.PtnTypCd and UserPtnTypMst.cocd=mst.cocd and UserPtnTypMst.divcd=mst.divcd and UserPtnTypMst.usr_id=@pUserID    
  and UserPtnTypMst.loccd=mst.loccd      
    
  left join usr_det on usr_det.DefPtntypeCd= UserPtnTypMst.PtnTypCd AND usr_det.usr_id=UserPtnTypMst.usr_id    
        WHERE mst.IsActive=1    
  and mst.cocd=@pCocd and mst.divcd=@pDivcd and mst.loccd=@pLoccd    
  and  UserPtnTypMst.HasAccess=1   
    END;
GO

/* 03 / 26  NST_SelRule - rule master lookup */
IF OBJECT_ID(N'dbo.NST_SelRule', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelRule;
GO
  
  
-- =============================================        
-- Author:  Mayur Gujrathi        
-- Create date: 18 Dec 2013                
-- Description: Selects data1 from RuleMst table                 
-- =============================================        
CREATE PROCEDURE dbo.[NST_SelRule] @pCOCD   CHAR(3)  = '',     
                                     @pDIV    SMALLINT = 0,     
                                     @pLOC    SMALLINT = 0,     
                                     @pRuleID INT      = 0    
AS    
    BEGIN    
        SET NOCOUNT ON;    
        SELECT       
        --isnull(Data1,'')       
        RuleID,     
        ISNULL(RuleName, '') RuleName,     
        ISNULL(Data1, '') Data1,     
        ISNULL(Data2, '') Data2,     
        ISNULL(DetFlag, '') DetFlag,     
        ISNULL(Desciption, '') Desciption, --Neha S.C. 20140217      
  ISNULL(Data3,'') [Data3]  -- #.SACHIN.M 20220629  
        FROM RuleMst    
        WHERE RuleID = @pRuleID;    
    END;
GO

/* 04 / 26  NST_SrchCodeDecode - ward / speciality search box */
IF OBJECT_ID(N'dbo.NST_SrchCodeDecode', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SrchCodeDecode;
GO
-- =============================================        
-- Author:  <Author,Shital>        
-- Create date: <2020-07-30>        
-- Description: <Get spclty list by content search>        
-- =============================================        
CREATE PROCEDURE [dbo].[NST_SrchCodeDecode]      --         
 -- Add the parameters for the stored procedure here        
@pCOCD    char(3),                        
@pDIV   smallint,                        
@pLOC  smallint ,      
@pTyp int,  
@pPrefix varchar(70)        
AS        
BEGIN        
 -- SET NOCOUNT ON added to prevent extra result sets from        
 -- interfering with SELECT statements.        
 SET NOCOUNT ON;        
        
    -- Insert statements for procedure here        
 select  ISNULL(typ,0) [typ] , ISNULL(CD,0) [cd], isnull(dcd,'')dcd    from cd_dcd (nolock)  where typ=@pTyp and dcd like '%'+@pPrefix+'%'         
order by dcd      ;  
END
GO

/* 05 / 26  NST_SrchDoctor - doctor search box */
IF OBJECT_ID(N'dbo.NST_SrchDoctor', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SrchDoctor;
GO
                
-- =============================================                                      
-- Author:  shital                                     
-- Create date: 2020-07-23                                    
-- Description: Selects all record from Doctor Master table      
--SPSELDOCMST 1,1,1      
-- =============================================                                      
CREATE PROCEDURE [dbo].[NST_SrchDoctor] -- 001,1,1                                      
 -- Add the parameters for the stored procedure here                                      
 @pCOCD    char(3),                                      
 @pDIV    smallint,                                      
 @pLOC    smallint,                    
 @pSpltyCd int=0    ,            
  @pSortBy varchar(20)=null     --shital 20190828             
 , @pPrefix  VARCHAR(10) = NULL        
                                      
AS                                      
BEGIN                                      
                
--declare @OrderBycolName varchar(150) = ''                
                
            
--SELECT @OrderBycolName= OrderByCol1 from F2HelpParamMst a                 
--where                 
-- a.cocd = @pCOCD and                
-- a.loccd =@pLOC and                
-- a.divcd =@pDIV and                
-- a.SubModCd = @pSubModCd and a.helpID =@phelpID;                
--SET @OrderBycolName = ISNULL(@OrderBycolName ,'');                
                
                
     --shital 20190828                   
 --if (isnull(@pSortBy,'')='')            
 --begin            
 --set @pSortBy='doc_nm'            
 --end            
            
    set @pSortBy='doc_nm'            
-- print @pSortBy;                
                                       
 -- SET NOCOUNT ON added to prevent extra result sets from                                      
 -- interfering with SELECT statements.                                      
 SET NOCOUNT ON;                     
               
               
      declare @sql1 varchar(5000)                               
-- SELECT                              
-- a.doc_cd [DoctorCode],                                      
-- a.ttl_cd [DoctorTitleCode],                                       
-- ISNULL(b.dcd,'') [DoctorTitleCodeDesc],                                      
-- ISNULL(a.doc_frst_nm,'') [DoctorFirstName] ,                                       
-- ISNULL(a.doc_mid_nm,'') [DoctorMiddleName],                                      
-- ISNULL(a.doc_lst_nm,'') [DoctorLastName],     -- ISNULL(b.dcd,'') + ' ' +                                   
----ISNULL(a.doc_frst_nm,'') + ' ' + ISNULL(a.doc_mid_nm,'') + ' ' + ISNULL(a.doc_lst_nm,'') [DoctorFullName],                                
-- ISNULL(b.dcd,'')+ ' ' + ISNULL(a.doc_lst_nm,'') + ' ' + ISNULL(a.doc_frst_nm,'') + ' ' + ISNULL(a.doc_mid_nm,'') [DoctorFullName],                                            
-- a.doc_sts_cd [Status],                                      
-- a.splty_cd [SpecialityCode],                                      
-- ISNULL(c.dcd,'') [SpecialityCodeDesc]                                      
-- FROM doc_mst a left join  cd_dcd b                                       
-- on a.ttl_cd  = b.cd and b.typ = 3  left join cd_dcd c                                       
-- on a.splty_cd = c.cd   and c.typ = 28                       
-- where                      
--  isnull(a.doc_sts_cd,0)=1 --anamika 2017017                     
--  and a.DOCTYPCD2<>3     -- maitri 20190319                   
--  and a.splty_cd =case isnull(@pSpltyCd,0) when 0 then a.splty_cd else @pSpltyCd end                    
--  AND a.Cocd=@pCOCD AND a.DivCd=@pDIV AND a.LocCd=@pLOC --DEVEN 2018-11-19                  
                
-- ORDER BY                 
                  
--  case WHEN @OrderBycolName ='doc_cd' then  convert(varchar(20),a.doc_cd)                
--  WHEN @OrderBycolName ='doc_nm' then  ISNULL(a.doc_lst_nm,'') + ' ' + ISNULL(a.doc_frst_nm,'') + ' ' + ISNULL(a.doc_mid_nm,'')        
--  else                
--   convert(varchar(20),a.doc_cd)                 
                   
-- end                
              
set @sql1='select  a.doc_cd [DoctorCode],            
            
 a.ttl_cd [DoctorTitleCode],                                       
 ISNULL(b.dcd,'''') [DoctorTitleCodeDesc] ,            
  ISNULL(a.doc_frst_nm,'''') [DoctorFirstName] ,                                
 ISNULL(a.doc_mid_nm,'''') [DoctorMiddleName],                                      
 ISNULL(a.doc_lst_nm,'''') [DoctorLastName],              
                 ISNULL(a.doc_lst_nm,'''') +'' ''+ ISNULL(a.doc_frst_nm,'''') + '' ''+ ISNULL(a.doc_mid_nm,'''')   [DoctorFullName],                
                                  
 a.doc_sts_cd [Status],                                      
 a.splty_cd [SpecialityCode],                                      
 ISNULL(c.dcd,'''') [SpecialityCodeDesc]               
 ,isnull(a.DocCategory,0) ''DocCategoryCd''      
  ,isnull(DocCat.dcd,'''') ''DocCategory''      
 from doc_mst a left join  cd_dcd b                                       
on a.ttl_cd  = b.cd and b.typ = ''3''            
 left join cd_dcd c                                       
 on a.splty_cd = c.cd   and c.typ = ''28 ''      
 left join cd_dcd DocCat on a.DocCategory=DocCat.cd       
         and DocCat.typ=''8039''      
 where                      
  isnull(a.doc_sts_cd,0)=1            
 and a.DOCTYPCD2<>''3 ''             
  and a.splty_cd =case isnull('''+cast(@pSpltyCd as varchar(10))+''',0) when 0 then a.splty_cd else '''+cast (@pSpltyCd as varchar(10))+''' end              
  AND a.Cocd='''+@pCOCD+''' AND a.DivCd='''+cast(@pDIV as varchar(5))+''' AND a.LocCd='''+cast(@pLOC as varchar(5))+'''            
        and (a.doc_frst_nm like ''%'+ @pPrefix+'%'' OR a.doc_mid_nm like  ''%'+ @pPrefix+'%''    
  OR a.doc_lst_nm like  ''%'+ @pPrefix+'%'' )    
   ORDER BY   '            
                
    if @pSortBy='doc_cd'             
    begin            
   set  @sql1=@sql1 + 'doc_cd'            
    end             
              
            
  if @pSortBy='doc_nm'            
  begin            
     set  @sql1=@sql1 + '     ISNULL(a.doc_lst_nm,'''') +'' ''+ ISNULL(a.doc_frst_nm,'''') + '' ''+ ISNULL(a.doc_mid_nm,'''')            
                 
     '            
 end            
 print (@sql1)             
 exec (@sql1)              
                             
END
GO

/* 06 / 26  NST_SelMRDRecCount - MRD file register check (MRD status filter) */
IF OBJECT_ID(N'dbo.NST_SelMRDRecCount', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelMRDRecCount;
GO
--maitri
--20191007
--only for nursing workbench,doctor's workbench
--exec spSelMRDFileReg001 1,1,1,0
create proc NST_SelMRDRecCount
@CoCd varchar(3),
@DivCd smallint,
@LocCd smallint,
@FileId bigint=0
as
begin
if exists(select * from sys.objects where name='MRDFileLog' and type='U')
begin
if ((select COUNT(*) from MRDFileReg)>0)
begin
select 1 as cnt
end
else
begin
select 0 as cnt
end
end
else
begin
select 0 as cnt
end

end
GO

/* 07 / 26  NST_SelUserDet - user details (nick name, stored password, doctor code) */
IF OBJECT_ID(N'dbo.NST_SelUserDet', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelUserDet;
GO
-- =============================================                              
-- Author: Neha S.C.                            
-- Create date: 28/02/2014                            
-- Description: Select Data From usr_det against a usrid                          
-- =============================================                              
--exec SPSELUSERDETBYCD 1,1,1,'Aarti'          
CREATE PROCEDURE dbo.[NST_SelUserDet] -- 1,1,1,'sssl'                        
-- Add the parameters for the stored procedure here                              
@pCOCD  CHAR(3),   
@pDIV   SMALLINT,   
@pLOC   SMALLINT,   
@pUSRID VARCHAR(16)  
AS  
    BEGIN                              
        -- SET NOCOUNT ON added to prevent extra result sets from                              
        -- interfering with SELECT statements.                              
        SET NOCOUNT ON;  
        SELECT   
         usr_id,  
         usr_lst_nm,   
               usr_frst_nm,   
               usr_mid_nm,   
               grp_id,   
               dept_cd,   
               x.str_cd,   
               y.str_dcd,   
               shft,   
               doc_cd,   
               VIP_Acc,   
               ISNULL(UserNickName, '') UserNickName, --anamika 20160129                        
  
               ISNULL(usr_pswd, '') UserPwd, --RasikV 20161201                        
               pswd_exp, --RasikV 20161201                        
               ISNULL(tm_in, '') TmIn, --RasikV 20161201                        
               ISNULL(tm_out, '') TmOut, --RasikV 20161201                        
               ISNULL(IsPoUnlimited, 0) IsPoUnlimited, --RasikV 20161201                        
               ISNULL(PoLimitDaily, 0) PoLimitDaily, --RasikV 20161201                        
               ISNULL(PoLimitMonthly, 0) PoLimitMonthly, --RasikV 20161201                        
               ISNULL(PoLimitYearly, 0) PoLimitYearly, --RasikV 20161201                        
               ISNULL(lv_flg, 0) LvFlg, --RasikV 20161201                        
               ISNULL(UserLevel, '') UserLevel, --RasikV 20161201                        
               ISNULL(IsHeadCashier, 0) IsHeadCashier, ---Pramila 23aug2017                      
  
               ISNULL(AllowExpiredItem, 0) AllowExpiredItem, --ANAND:23NOV2018                      
               ----ISNULL(x.CoCd,'') CoCd,    --ANAND:24NOV2018                      
               ISNULL(x.DivCd, 0) DivCd, --ANAND:24NOV2018                      
               ISNULL(x.LocCd, 0) LocCd, --ANAND:24NOV2018                      
               ISNULL(d.DivName, '') DivName, -- maitri 20190412                    
               ISNULL(l.LocName, '') LocName, -- maitri 20190412                    
               ISNULL(x.mobileno, '') AS mobileno, -- maitri 20190415                    
               ISNULL(x.EmailID, '') AS EmailID, -- maitri 20190415                    
               digitalsign, --Rusikesh 20200415                
               ISNULL(u.UserTypeDesc, '') UserTypeDesc, --Nikita 20200513               
               ISNULL(x.UsrTypeCd, 0) UsrTypeCd, --Nikita 20200513               
               ISNULL(x.DefPtnTypeCd, 0) DefPtnTypeCd,   
               ISNULL(x.DefIssStrCd, 0) DefIssStrCd, --Rushikesh 20210428          
               ISNULL(strmst.str_dcd, '') DefIssStrDCd, --Rushikesh 20210428         
               ISNULL(x.DefMiscPayRcpt, 'R') DefMiscPayRcpt, --Amol 30-07-2021        
               ISNULL(x.MaxPoAuthLimit, 0) MaxPoAuthLimit, --Rushikesh 20210802      
               ISNULL(x.DontShowPtnMobile, 0) DontShowPtnMobile, --shivkumar 20210825    
               IsUserAcActive, --Afrin 25.11.2021  
               UserAcInactiveSinceDtTm, ----Afrin 25.11.2021      
               ISNULL(x.HideDocShareFromUsr, 0) HideDocShareFromUsr  
        FROM usr_det x(NOLOCK)  
             JOIN str_mst y(NOLOCK) ON x.usr_id = @pUSRID  
                                       AND x.str_cd = y.str_cd  
             JOIN DivisionMst d ON(d.CoCd = x.CoCd  
                                   AND d.DivCd = x.DivCd)   -- maitri 20190412                    
             JOIN LocationMst l ON(l.CoCd = x.CoCd  
                                   AND l.DivCd = x.DivCd  
                                   AND l.LocCd = x.LocCd)  -- maitri 20190412              
             LEFT JOIN UserTypeMst u ON(u.UserTypeCd = x.UsrTypeCd  
                                        AND u.IsActive = 1) --Nikita 20200513          
             LEFT JOIN str_mst strmst ON strmst.str_cd = x.DefIssStrCd;--Rushikesh 20210428          
    END;
GO

/* 08 / 26  NST_SelLOSConfig - length-of-stay confirmation settings */
IF OBJECT_ID(N'dbo.NST_SelLOSConfig', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelLOSConfig;
GO
-- =============================================    
-- Author:  Anamika Suresh Shedge    
-- Create date: 27 may 2013    
-- Description: Select Data from ADT_in_dt table    
-- =============================================    
CREATE PROCEDURE [dbo].[NST_SelLOSConfig]     
 -- Add the parameters for the stored procedure here    
@pCOCD    varchar(6),             
@pDIV    int,                
@pLOC    int    
AS    
BEGIN    
 -- SET NOCOUNT ON added to prevent extra result sets from    
 -- interfering with SELECT statements.    
 SET NOCOUNT ON;    
    
select EMG_SRV_END_TM,EMG_SRV_TM,EMG_SRV_PRCNT   
  
--shital 20211118   
  
  
, isnull(EnableLOSConfirmation,0)EnableLOSConfirmation,  
isnull(LOSConfirmationBeforeXDays,0)LOSConfirmationBeforeXDays,  
isnull(AllowToSkipLOSConfirmation,0)AllowToSkipLOSConfirmation  
,isnull(LOSConfirmationSkipLimit,0)LOSConfirmationSkipLimit   
  
--shital 201211118 end  
from ADT_in_dt    
END
GO

/* 09 / 26  NST_SelLOSByIp - length-of-stay details of one patient */
IF OBJECT_ID(N'dbo.NST_SelLOSByIp', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelLOSByIp;
GO

-- =============================================                                                      
-- Author: Shital                                        
-- alter date:2021-11-18                                                 
-- Description: select LOS confirmation from ip_ptn_vst                
                                                      
-- =============================================                                                      
CREATE PROCEDURE [dbo].[NST_SelLOSByIp] @pCOCD CHAR(3)  = '1',                         
                                          @pDIV  SMALLINT = 1,                         
                                          @pLOC  SMALLINT = 1,                                                    
                                          --@pIPNO  int                                          
                                          @pIPNO BIGINT   = 0 --anamika 20160906                                                 
AS                        
    BEGIN                        
        SET NOCOUNT ON;                        
           

    
    SELECT     
    
        I.ptn_cls_cd PtnClsCd,I.adm_dt AdmDt,concat(CAST(I.adm_dt AS date),' ', CAST(I.adm_tm AS time)) AS AdmTm,isnull(I.PtnTypCd, 0) BillTyp,I.wrd_cd,wrd.dcd WardDesc,I.bed_no BedNo,    
        B.ar_cd ArCd, dbo.CalYear_YY(P.brth_dt,getdate())   AGE ,P.sex AGEGENDER,      
        C.free_flag FreeFlag, isnull(C.zero_rt_flg,' ') ZeroRtFlag,    
        dbo.fn_IpOPName('I',I.ip_no) PtnName,    
        I.PTN_NO PTN_NO,    
        M.AR_TYP_CD ARTYPCD , isnull(ARTYP.DCD, ' ') ARTYPDESC,    
        isnull(P.ISMLC,0)ISMLC,P.NRI,isnull(P.IsInternationalPtn,0) IsInternationalPtn,isnull(P.IsPtnBlackListed,0)IsPtnBlackListed,    
        P.bill_type PtnBillType,Biltyp.dcd PtnBillTypeDesc ,I.IP_NO Ipno ,    
        isnull(d.doc_cd,0) DocCd ,    
        isnull(dbo.fn_Doc_Name(d.doc_cd) ,0 ) DocNm    ,
		
 isnull(IsLOSConfirmed ,0)IsLOSConfirmed,        
isnull( LOSConfirmedByUsrID ,'')LOSConfirmedByUsrID,        
 isnull(LOSConfirmedDtTm,'')LOSConfirmedDtTm,        
isnull( LOSConfimSkipCount,0)LOSConfimSkipCount  ,      
isnull(dschg_dt,'')dschg_dt,      
isnull(dschg_tm,'')dschg_tm,      
isnull(exptd_no_day,0)LOS  ,    
ISNULL(adm_tm,'')adm_tm,    
ISNULL(adm_dt,'')adm_dt  
           
    FROM     
    ip_ptn_vst I     
    JOIN PTN_MST1 P ON I.PTN_NO = P.PTN_NO     
    LEFT JOIN ip_bil_instrn B ON I.IP_NO = B.IP_NO    
    LEFT JOIN cd_dcd wrd On Typ = 2 and I.wrd_cd = wrd.cd      
    AND wrd.COCD =@pCOCD AND wrd.DIVCD = @pDIV AND wrd.LOCCD = @pLOC    
    JOIN ptn_cls_mst C ON I.PTN_CLS_CD = C.PTN_CLS_CD    
    AND C.COCD =@pCOCD AND C.DIVCD = @pDIV AND C.LOCCD = @pLOC    
    LEFT JOIN AR_MST M ON B.AR_CD = M.AR_CD    
    AND M.COCD =@pCOCD AND M.DIVCD = @pDIV AND M.LOCCD = @pLOC    
    LEFT OUTER JOIN CD_DCD ARTYP ON M.AR_TYP_CD = ARTYP.CD AND ARTYP.TYP = 60    
    AND ARTYP.COCD = M.COCD AND ARTYP.DIVCD = M.DIVCD AND ARTYP.LOCCD = M.LOCCD    
    Left Outer Join cd_dcd Biltyp ON Biltyp.Typ = 154 and P.bill_type = Biltyp.cd      
    Left  join doc_mst d on I.doc_cd = d.doc_cd    
      WHERE  (I.ip_no = @pIPNO or @pIPNO=0 );    

        
--         SELECT                 


-- isnull(IsLOSConfirmed ,0)IsLOSConfirmed,        
--isnull( LOSConfirmedByUsrID ,'')LOSConfirmedByUsrID,        
-- isnull(LOSConfirmedDtTm,'')LOSConfirmedDtTm,        
--isnull( LOSConfimSkipCount,0)LOSConfimSkipCount  ,      
--isnull(dschg_dt,'')dschg_dt,      
--isnull(dschg_tm,'')dschg_tm,      
--isnull(exptd_no_day,0)LOS  ,    
--ISNULL(adm_tm,'')adm_tm,    
--ISNULL(adm_dt,'')adm_dt    
--from ip_ptn_vst         
                            
--        WHERE ip_no = @pIPNO        
    END;
GO

/* 10 / 26  NST_UpdLOSConfirm - confirm length of stay */
IF OBJECT_ID(N'dbo.NST_UpdLOSConfirm', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_UpdLOSConfirm;
GO
--created by :shital    
--created on :2021-11-18    
-- =============================================                
CREATE PROCEDURE [dbo].[NST_UpdLOSConfirm]                 
 -- Add the parameters for the stored procedure here                
@cocd    char(3),                             
@divcd    smallint,                                
@loccd    smallint ,                   
--@pIpNo   int,                
@pIpNo   bigint, --anamika 20160906                
       
    
 @pLOSConfirmedByUsrID varchar(16),    
 @pLOSConfimSkipCount  int=0    
      
            
    
AS                
BEGIN                
--SET NOCOUNT ON; anamika 20140722                
                
--select * from NWBBYMST  where NWBBYIPNO =4000025                
                
update IP_PTN_VST set                
IsLOSConfirmed = 1 ,             
  LOSConfirmedByUsrID=@pLOSConfirmedByUsrID,    
  LOSConfirmedDtTm =getdate(),    
 -- LOSConfimSkipCount =@pLOSConfimSkipCount ,    
    
    
updt_dt = convert(date,GETDATE()),                 
updt_tm = convert(time,GETDATE()),                 
updt_usr_id =@pLOSConfirmedByUsrID                
                
WHERE IP_NO =@pIpNo              
                
END
GO

/* 11 / 26  NST_UpdLOSSkip - skip length-of-stay confirmation */
IF OBJECT_ID(N'dbo.NST_UpdLOSSkip', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_UpdLOSSkip;
GO
--created by :shital  
--created on :2021-11-18  
-- =============================================              
CREATE PROCEDURE [dbo].[NST_UpdLOSSkip]               
 -- Add the parameters for the stored procedure here              
@cocd    char(3),                           
@divcd    smallint,                              
@loccd    smallint ,                 
--@pIpNo   int,              
@pIpNo   bigint, --anamika 20160906              
     
  
 @pupdt_usr_id varchar(16)  
  
          
  
AS              
BEGIN              
--SET NOCOUNT ON; anamika 20140722              
              
--select * from NWBBYMST  where NWBBYIPNO =4000025              
              
update IP_PTN_VST set              
  
  LOSConfimSkipCount =isnull(LOSConfimSkipCount,0)+1 ,  
  
  
updt_dt = convert(date,GETDATE()),               
updt_tm = convert(time,GETDATE()),               
updt_usr_id =@pupdt_usr_id              
              
WHERE IP_NO =@pIpNo            
              
END
GO

/* 12 / 26  NST_UpdLOSExtend - extend length of stay */
IF OBJECT_ID(N'dbo.NST_UpdLOSExtend', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_UpdLOSExtend;
GO
                
-- =============================================                
CREATE PROCEDURE [dbo].[NST_UpdLOSExtend]                 
 -- Add the parameters for the stored procedure here                
@cocd    char(3),                             
@divcd    smallint,                                
@loccd    smallint ,                   
--@pIpNo   int,                
@pIpNo   bigint, --anamika 20160906                
@pexptd_no_day  int=0,         
 @pDsChgDt            DATE          = NULL,         
 @pDsChgTm            DATETIME      = NULL,         
      
            
@pupdusrid varchar(16)       
AS                
BEGIN                
--SET NOCOUNT ON; anamika 20140722                
                
--select * from NWBBYMST  where NWBBYIPNO =4000025                
                
update IP_PTN_VST set                
exptd_no_day = @pexptd_no_day ,             
      
dschg_dt=@pDsChgDt,      
dschg_tm=@pDsChgTm,      
updt_dt = convert(date,GETDATE()),                 
updt_tm = convert(time,GETDATE()),                 
updt_usr_id =@pupdusrid                
                
     ,IsLOSConfirmed=0,  
     LOSConfimSkipCount=0,  
     LOSConfirmedByUsrID='',  
     LOSConfirmedDtTm=null  
WHERE IP_NO =@pIpNo              
                
END
GO

/* 13 / 26  NST_InsLOSActionLog - length-of-stay action log */
IF OBJECT_ID(N'dbo.NST_InsLOSActionLog', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_InsLOSActionLog;
GO
/****** Script for SelectTopNRows command from SSMS  ******/

create Proc [dbo].[NST_InsLOSActionLog]
(


    @pcocd  CHAR(3)  = '',            
    @pdivcd SMALLINT = 0,      
    @ploccd SMALLINT = 0,      
    @pIPNo bigint=0,
    @pActionID int=0,
    @pActionDesc varchar(20)='',
    @pActionDtTm date=null,
    @pActionByUsrID varchar(16)=''
)
as
begin

insert into IPLOSActionLog(

      [cocd]
      ,[divcd]
      ,[loccd]
      ,[IPNo]
      ,[ActionID]
      ,[ActionDesc]
      ,[ActionDtTm]
      ,[ActionByUsrID])

	  values (
	 
    @pcocd  ,
    @pdivcd ,
    @ploccd ,
    @pIPNo ,
    @pActionID ,
    @pActionDesc ,
    @pActionDtTm ,
    @pActionByUsrID )
  end
GO

/* 14 / 26  NST_SelNetIdByModule - web path of a module (netid) */
IF OBJECT_ID(N'dbo.NST_SelNetIdByModule', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelNetIdByModule;
GO
-- =============================================        
-- Author:  Anamika Suresh Shedge        
-- Create date: 12 Dec 2013        
-- Description: Query returns you module name for particular serial number        
-- =============================================        
CREATE PROCEDURE [dbo].[NST_SelNetIdByModule]        
-- Add the parameters for the stored procedure here        
@pCOCD     VARCHAR(3),   
@pDIV      TINYINT,   
@pLOC      TINYINT,   
@pModCd    INT,   
@pSubModCd INT  
AS  
    BEGIN        
        -- SET NOCOUNT ON added to prevent extra result sets from        
        -- interfering with SELECT statements.        
        SET NOCOUNT ON;  
        DECLARE @pEnableScrollRequestMode BIT;  
        SET @pEnableScrollRequestMode =  
        (  
            SELECT EnableScrollRequestMode  
            FROM ModuleWeb x  
            WHERE x.ModCd = @pModCd  
                  AND x.SubModCd = @pSubModCd  
                  AND x.cocd = @pCOCD  
                  AND x.divcd = @pDIV  
                  AND x.loccd = @pLOC  
        );  
        SET @pEnableScrollRequestMode = ISNULL(@pEnableScrollRequestMode, 0);  
        DECLARE @netid INT;  
        SELECT @netid = netid  
        FROM Module  
        WHERE SubModCd = @pSubModCd  
              AND ModCd > 400;  --ModCd=@pModCd and 'anamika 20140116    
        SELECT ISNULL(srno, 0) srno,   
               ISNULL(mdbname, '') mdbname,   
               ISNULL(tablename, '') tablename,   
               ISNULL([path], '') [path],   
               ISNULL([desc], '') [desc],   
               ISNULL(DefPath, '') DefPath,   
               ISNULL(WebPath, '') WebPath,   
               ISNULL(UPPER(b.SubModName), '') SubModName,   
               @pEnableScrollRequestMode EnableScrollRequestMode  
        FROM Netid a  
             LEFT OUTER JOIN Module b ON a.srno = b.NetId  
        WHERE a.srno = @netid;  
    END;
GO

/* 15 / 26  NST_SelSmsParam - discharge SMS: parameters */
IF OBJECT_ID(N'dbo.NST_SelSmsParam', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelSmsParam;
GO
-- =============================================  
-- Author:  PRAGYA  
-- Create date: 28-JUL-2016  
-- Description: SELECT DATA FROM SMS_PARAM  
-- =============================================  
CREATE PROCEDURE NST_SelSmsParam  
@pcocd char(3),  
@pdivcd smallint,  
@ploccd smallint  
AS  
BEGIN  
 -- SET NOCOUNT ON added to prevent extra result sets from  
 -- interfering with SELECT statements.  
 SET NOCOUNT ON;  
  
    SELECT TOP 1 SMS_Port,SMS_Last_No,SMS_Valid_Mob_Start,SMS_Max_Length,SMS_Mobile_Length   
 FROM SMS_Param   (nolock);
END
GO

/* 16 / 26  NST_SelSmsMst - discharge SMS: templates */
IF OBJECT_ID(N'dbo.NST_SelSmsMst', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelSmsMst;
GO

-- =============================================
-- Author:		PARAGYA
-- Create date: 28-JUL-2016
-- Description:	GET THE ACTIVE SMS_MST DETAILS BY PASSING SMS_TYP(SUBMODCD) AND CATEGORY_TYP(CD_DCD.TYP=5010)
-- =============================================
CREATE PROCEDURE [dbo].[NST_SelSmsMst] 
-- Add the parameters for the stored procedure here
@pcocd char(3),
@pdivcd smallint,
@pLoccd smallint,
@pSmsTyp int,
@pCategoryTyp int
AS
BEGIN
-- SET NOCOUNT ON added to prevent extra result sets from
-- interfering with SELECT statements.
SET NOCOUNT ON;
SELECT ISNULL(SMS_Type,0)SMS_Type, ISNULL(SMS_Type_Desc,'') SMS_Type_Desc , ISNULL(SMS_Std_Mess,'') SMS_Std_Mess,
CategoryTyp,
 isnull(b.dcd,'') [CategoryTypDesc] ,
Active_Flag,
Delay_Mins,
No_Send_Chk,
No_Send_1_From,
No_Send_1_To,
No_Send_2_From,
No_Send_2_To,
No_Send_3_From,
No_Send_3_To,
No_Send_4_From,
No_Send_4_To,
No_Send_5_From,
No_Send_5_To,
Send_MultiParts
  FROM [dbo].[SMS_Mst]   a
  left Join cd_dcd b on b.typ =5010 and a.CategoryTyp =b.cd 
  where  Active_Flag = 'Y'and SMS_Type = @pSmsTyp AND CategoryTyp = @pCategoryTyp
END
GO

/* 17 / 26  NST_SelSmsReplaceData - discharge SMS: replacement data */
IF OBJECT_ID(N'dbo.NST_SelSmsReplaceData', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelSmsReplaceData;
GO


CREATE PROCEDURE [dbo].[NST_SelSmsReplaceData]
-- Add the parameters for the stored procedure here
@pcocd          CHAR(3),
@pdivcd         SMALLINT,
@ploccd         SMALLINT,
@pModcd         INT,
@pSubModCd      INT,
@pCategoryCd    INT,
@pPtnNo         BIGINT         = NULL, --Amol Margaj 27-05-2017 int to bigint
@pBedNo         VARCHAR(50)    = NULL, --Amol 2018-04-20
@pRoomNo        VARCHAR(50)    = NULL, --Amol 2018-04-20
@pIPNo          BIGINT         = NULL, --Amol 2018-04-20
@pDocCd         BIGINT         = NULL, --Amol 2018-04-20
@pDiscSts       INT            = NULL, --pragya : 22-apr-2018
@pInsRegNo      INT            = NULL, --pragya : 31-oct-2017
@pCompNo        INT            = NULL, --RasikV 20180605
@pCompDt        DATETIME       = NULL, --RasikV 20180605
@pUsrNm         VARCHAR(16)    = NULL, --RasikV 20180605
@pFrmDeptCd     INT            = NULL, --RasikV 20180605
@pToDeptCd      INT            = NULL, --RasikV 20180605
@pItemCd        VARCHAR(10)    = NULL, --RasikV 20180605
@pCompDesc      VARCHAR(150)   = NULL, --RasikV 20180605
@pPriorityCd    SMALLINT       = NULL, --RasikV 20180605
@pEmpId         VARCHAR(10)    = NULL, --RasikV 20180918
@pFctCd         INT            = NULL, --RasikV 20180918
@pApptNo        INT            = NULL, --RasikV 20180918
@pApptDt        DATETIME       = NULL, --RasikV 20180918
@pApptFrmTm     VARCHAR(10)    = NULL, --RasikV 20180918
@pApptToTm      VARCHAR(10)    = NULL, --RasikV 20180918
@pRsvNo         BIGINT         = NULL, --RasikV 20180918
@pKinMobile     VARCHAR(20)    = NULL, --Sana  16-AUG-2019
@pWardNo        VARCHAR(50)    = NULL, --Sana  24-OCT-2019
@pOldApptNo     INT            = NULL, -- Aarti 17 Jan 2020
@pFRM_BED_NO    VARCHAR(50)    = NULL,
@pDischargeDate DATETIME       = NULL,
@pexptd_no_day  INT            = 0,
@pDischargeTime DATETIME       = NULL,
@peqp_cd        INT            = NULL,
@pEqpSts        INT            = NULL,
@pPtnClassCd    INT            = NULL,
@pPtnTypeCd     INT            = NULL,
@pAdmDt         DATETIME       = NULL,
@pAdmTm         DATETIME       = NULL,
@pVoucherNo     INT            = NULL, --shivkumar 07/06/2022
@pAmount        DECIMAL(18, 2)  = NULL  -- shivkumar 07/06/2022
AS
BEGIN
    -- SET NOCOUNT ON added to prevent extra result sets from
    -- interfering with SELECT statements.
    SET NOCOUNT ON;
    DECLARE @Rule9171 AS CHAR(1);
    SET @Rule9171 =
    (
    SELECT ISNULL(data1, '')
    FROM RuleMst
    WHERE RuleID = 9171
    );
    DECLARE @pWardContactNo VARCHAR(MAX), @Hsp_Nm VARCHAR(50),@DocSpeciality Varchar(70);
	DECLARE @docCd INT, @DocName VARCHAR(MAX), @ClassName VARCHAR(20), @ptnTypDesc VARCHAR(70), @AdmDt DATETIME, @AdmTm DATETIME;
    
    ----- ********************* ADMISSION SMS QUERY BELOW******************************************************************
    --===================================Afrin 18.05.2022=======================
    IF @pSubModCd = 405
    AND @pCategoryCd = 2
    BEGIN
        DECLARE @strPtnName10 VARCHAR(MAX), @strAgeGender10 VARCHAR(60);
        IF @pPtnNo IS NOT NULL
        AND @pPtnNo != 0
        BEGIN
            SELECT @strPtnName10 = (ISNULL(C.DCD, '') + ' ' + ISNULL(B.ptn_lst_nm, '') + ' ' + ISNULL(B.ptn_frst_nm, '') + ' ' + ISNULL(B.ptn_mid_nm, '')),
            @strAgeGender10 = ISNULL(CASE
            WHEN B.brth_dt IS NULL
            THEN
            (
            SELECT([DBO].[CalMax_DOB](
            (
            SELECT DATEADD(Year, -1 * b.age_yy, b.crt_dt)
            ), GETDATE()
            ))
            )
            ELSE
            (
            SELECT [DBO].[CalMax_DOB](B.brth_dt, GETDATE())
            )
        END, '') + ' / ' + B.SEX
        FROM PTN_MST1 B
        LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
        AND C.TYP = 3
        WHERE b.ptn_NO = @pPtnNo;
    END;
    SELECT @pSubModCd AS SMS_Typ,
    @pCategoryCd AS Category,
    @strPtnName10 PTN_NAME,
    @strAgeGender10 'MaxAge_Gender',
    @pIPNo IP_NO,
    @pBedNo BED_NO,
    @pFRM_BED_NO FRM_BED_NO,
    ISNULL(ContactMobile, '') MOBILE_NO,
    @pAdmTm DOA
    FROM WardContactMst
    WHERE WardCd = @pWardNo
    AND cocd = @pcocd
    AND divcd = @pdivcd
    AND loccd = @ploccd
    AND IsActive = 1
    AND SendBedTnsfrAlertToContactPerson = 1;
END;
--===================================Afrin 18.05.2022=======================
--===================================Afrin 23.05.2022=======================
IF @pSubModCd = 449
AND @pCategoryCd = 15
BEGIN
    DECLARE @strPtnName11 VARCHAR(MAX);
    IF @pPtnNo IS NOT NULL
    AND @pPtnNo != 0
    BEGIN
        SELECT @strPtnName11 = (ISNULL(C.DCD, '') + ' ' + ISNULL(B.ptn_lst_nm, '') + ' ' + ISNULL(B.ptn_frst_nm, '') + ' ' + ISNULL(B.ptn_mid_nm, ''))
        FROM PTN_MST1 B
        LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
        AND C.TYP = 3
        WHERE b.ptn_NO = @pPtnNo;
    END;
    SELECT @pSubModCd AS SMS_Typ,
    @pCategoryCd AS Category,
    @strPtnName11 PTN_NAME,
    @pIPNo IP_NO,
    @pBedNo BED_NO,
    (shr_srv_cd / 100) AS Doc_cd,
    ROUND(SUM(shr_amt), 2) AS shr_amt,
    ROUND(SUM(ISNULL(DocConcAmt, 0)), 2) AS DocConcAmt,
    SUM(ISNULL(ROUND(shr_amt, 2), 0) - ISNULL(ROUND(DocConcAmt, 2), 0)) AS Amount,
    D.MobileNo MOBILE_NO
    FROM ip_trn_doc_shr I
    LEFT OUTER JOIN Doc_Mst D ON(I.shr_srv_cd / 100) = D.doc_cd
    WHERE(ipno = @pIPNo)
    AND (shr_srv_cd <> 0)
    AND (cmpnt_cd IN(2, 3))
    AND (ISNULL(shr_amt, 0) - ISNULL(DocConcAmt, 0) <> 0)
    GROUP BY(shr_srv_cd / 100),
    D.MobileNo;
END;
--===================================Afrin 23.05.2022=======================

IF @pSubModCd = 407
AND @pCategoryCd = 1   -- for @pSubModCd = 407 (ADMISSION) and @pCategoryCd = 1(IP Patient : CD_DCD.TYP=5010)
BEGIN
    SELECT @pSubModCd SMS_Typ,
    @pCategoryCd Category,
    ISNULL(C.DCD, '') + ' ' + B.ptn_lst_nm + ' ' + B.ptn_frst_nm + ' ' + B.ptn_mid_nm PTN_NAME,
    ISNULL(CASE
    WHEN B.brth_dt IS NULL
    THEN
    (
    SELECT([DBO].[CalMax_DOB](
    (
    SELECT DATEADD(Year, -1 * b.age_yy, b.crt_dt)
    ), GETDATE()
    ))
    )
    ELSE
    (
    SELECT [DBO].[CalMax_DOB](B.brth_dt, GETDATE())
    )
END, '') + ' / ' + B.SEX 'MaxAge_Gender', --'MaxAge/Gender' ,  --RasikV 20180919
'' IP_NO,
'' WARD_NAME,
'' BED_NO,
ISNULL(B.mobile, '') MOBILE_NO,                          ISNULL(C.DCD, '') + ' ' + E.doc_lst_nm + ' ' + E.doc_frst_nm + ' ' + E.doc_mid_nm Doc_Name
FROM PTN_MST1 B
LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
AND C.TYP = 3
LEFT JOIN DOC_MST E ON B.doc_cd = E.doc_cd
WHERE b.ptn_NO = @pPtnNo;
END;
ELSE
IF @pSubModCd = 407
AND @pCategoryCd = 2
BEGIN
    --SELECT ISNULL(C.DCD,'') + ' ' + B.ptn_lst_nm + ' ' + B.ptn_frst_nm + ' ' + B.ptn_mid_nm PTNNAME,
    --isnull(CASE WHEN B.brth_dt IS NULL THEN
    -- (SELECT ([DBO].[CalMax_DOB]((SELECT DATEADD(Year,-1*b.age_yy,b.crt_dt)),GETDATE())))
    --ELSE
    -- (SELECT [DBO].[CalMax_DOB] (B.brth_dt,getdate())) END,'')  + ' / ' + B.SEX  'MaxAge_Gender' , --'MaxAge/Gender' ,  --RasikV 20180919

    --A.IP_NO IPNO, ISNULL(D.dcd ,'') WARDNAME , A.bed_no BEDNO , ISNULL(E.MobileNo ,'')MOBILENO,
    --   ISNULL(C.DCD,'') + ' ' + E.doc_lst_nm + ' ' + E.doc_frst_nm + ' ' + E.doc_mid_nm DocName
    --      FROM IP_PTN_VST A JOIN PTN_MST1 B ON A.PTN_NO = B.PTN_NO
    --LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD AND C.TYP = 3
    --LEFT JOIN CD_DCD D ON A.wrd_cd = D.CD AND D.TYP = 2
    --LEFT JOIN DOC_MST E ON A.doc_cd = E.doc_cd
    --WHERE A.IP_NO = @pIPNo

    DECLARE @strDocName VARCHAR(60);
    IF @pDocCd IS NOT NULL
    AND @pDocCd != 0
    BEGIN
        SELECT @strDocName = ISNULL(C.DCD, '') + ' ' + ISNULL(doc.doc_lst_nm, '') + ' ' + ISNULL(doc.doc_frst_nm, '') + ' ' + ISNULL(doc.doc_mid_nm, '')
        FROM doc_mst Doc
        LEFT JOIN CD_DCD C ON doc.ttl_cd = C.CD
        AND C.TYP = 3
        WHERE doc_cd = @pDocCd;
    END;
    SELECT @pSubModCd SMS_Typ,
    @pCategoryCd Category,
    ISNULL(C.DCD, '') + ' ' + B.ptn_lst_nm + ' ' + B.ptn_frst_nm + ' ' + B.ptn_mid_nm PTN_NAME,
    ISNULL(CASE
    WHEN B.brth_dt IS NULL
    THEN
    (
    SELECT([DBO].[CalMax_DOB](
    (
    SELECT DATEADD(Year, -1 * b.age_yy, b.crt_dt)
    ), GETDATE()
    ))
    )
    ELSE
    (
    SELECT [DBO].[CalMax_DOB](B.brth_dt, GETDATE())
    )
END, '') + ' / ' + B.SEX 'MaxAge_Gender', --'MaxAge/Gender' ,  --RasikV 20180919
@pIPNo IP_NO,
'' WARD_NAME,
--case when @pBedNo is not null and @pBedNo != 0 then @pBedNo else '' end BED_NO ,  --commented by aparna 26 dec 2018
CASE
WHEN @pBedNo IS NOT NULL
AND @pBedNo != '0'
THEN @pBedNo
ELSE ''
END BED_NO,
ISNULL(B.mobile, '') MOBILE_NO,
@strDocName Doc_Name,
' ' DocMobile_No
FROM PTN_MST1 B
LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
AND C.TYP = 3
WHERE b.ptn_NO = @pPtnNo;
END;
ELSE
IF @pSubModCd = 407
AND @pCategoryCd = 3
BEGIN
    --SELECT ISNULL(C.DCD,'') + ' ' + B.ptn_lst_nm + ' ' + B.ptn_frst_nm + ' ' + B.ptn_mid_nm PTNNAME,
    --isnull(CASE WHEN B.brth_dt IS NULL THEN
    -- (SELECT ([DBO].[CalMax_DOB]((SELECT DATEADD(Year,-1*b.age_yy,b.crt_dt)),GETDATE())))
    --ELSE
    -- (SELECT [DBO].[CalMax_DOB] (B.brth_dt,getdate())) END,'')  + ' / ' + B.SEX  'MaxAge_Gender' , --'MaxAge/Gender' ,  --RasikV 20180919
    --A.IP_NO IPNO, ISNULL(D.dcd ,'') WARDNAME , A.bed_no BEDNO , ISNULL(E.MobileNo ,'')MOBILENO,
    --   ISNULL(C.DCD,'') + ' ' + E.doc_lst_nm + ' ' + E.doc_frst_nm + ' ' + E.doc_mid_nm DocName
    --FROM IP_PTN_VST A JOIN PTN_MST1 B ON A.PTN_NO = B.PTN_NO
    --LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD AND C.TYP = 3
    --LEFT JOIN CD_DCD D ON A.wrd_cd = D.CD AND D.TYP = 2
    --LEFT JOIN DOC_MST E ON A.doc_cd = E.doc_cd
    --WHERE A.IP_NO = @pIPNo

    DECLARE @strPtnName VARCHAR(60);
    DECLARE @strAgeGender VARCHAR(60);
    IF @pPtnNo IS NOT NULL
    AND @pPtnNo != 0
    BEGIN
        SELECT @strPtnName = (ISNULL(C.DCD, '') + ' ' + ISNULL(B.ptn_lst_nm, '') + ' ' + ISNULL(B.ptn_frst_nm, '') + ' ' + ISNULL(B.ptn_mid_nm, '')),
        @strAgeGender = ISNULL(CASE
        WHEN B.brth_dt IS NULL
        THEN
        (
        SELECT([DBO].[CalMax_DOB](
        (
        SELECT DATEADD(Year, -1 * b.age_yy, b.crt_dt)
        ), GETDATE()
        ))
        )
        ELSE
        (
        SELECT [DBO].[CalMax_DOB](B.brth_dt, GETDATE())
        )
    END, '') + ' / ' + B.SEX,
    --0 IPNO, ''  WARDNAME ,
    --@pBedNo =case when @pBedNo is not null and @pBedNo != 0 then @pBedNo else '0' end   commented by aparna 26 dec 2018
    @pBedNo = CASE
    WHEN @pBedNo IS NOT NULL
    AND @pBedNo != '0'
    THEN @pBedNo
    ELSE '0'
END
FROM PTN_MST1 B
LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
AND C.TYP = 3
--WHERE b.ptn_NO = 1003835
WHERE b.ptn_NO = @pPtnNo; --SACHIN 20180428: Bug fix patient no was hardcoded.

END;
SELECT @pSubModCd SMS_Typ,
@pCategoryCd Category,
@strPtnName PTN_NAME,
@strAgeGender 'MaxAge_Gender', --'MaxAge/Gender' ,  --RasikV 20180919
@pIPNo IP_NO,
'' WARD_NAME,
@pBedNo BED_NO,
ISNULL(C.DCD, '') + ' ' + ISNULL(doc.doc_lst_nm, '') + ' ' + ISNULL(doc.doc_frst_nm, '') + ' ' + ISNULL(doc.doc_mid_nm, '') Doc_Name,
ISNULL(doc.MobileNo, '') MOBILE_NO
FROM doc_mst doc
LEFT JOIN CD_DCD C ON doc.ttl_cd = C.CD
AND C.TYP = 3
WHERE doc.doc_cd = @pDocCd

--shital 20200211 Added for epic requirement when Client wants  to send admission sms to some people who may not be doctors or are not part of admission details.
--start
UNION ALL
SELECT SMSType AS SMSTyp,
@pCategoryCd AS Category,
PersonName PTN_NAME,
@strAgeGender 'MaxAge_Gender',
'' IP_NO,
'' WARD_NAME,
'' BED_NO,
'' Doc_Name,
ISNULL(MobileNo, '') MOBILE_NO
FROM SMS_Mst_Forward
WHERE CoCd = @pcocd
AND LocCd = @ploccd
AND DivCd = @pdivcd
AND Active_Flag = 'Y'
AND ISNULL(AdmDocCdIs, 0) = @pDocCd
AND SMSType = @pSubModCd
AND CategoryType = @pCategoryCd; --shital 20200314
END;  --end
ELSE
IF @pSubModCd = 407
AND @pCategoryCd = 99   -- Only for addmission Condition discussion with pragya
BEGIN
    SELECT @pSubModCd SMS_Typ,
    @pCategoryCd Category,
    ISNULL(C.DCD, '') + ' ' + B.ptn_lst_nm + ' ' + B.ptn_frst_nm + ' ' + B.ptn_mid_nm PTN_NAME,
    ISNULL(CASE
    WHEN B.brth_dt IS NULL
    THEN
    (
    SELECT([DBO].[CalMax_DOB](
    (
    SELECT DATEADD(Year, -1 * b.age_yy, b.crt_dt)
    ), GETDATE()
    ))
    )
    ELSE
    (
    SELECT [DBO].[CalMax_DOB](B.brth_dt, GETDATE())
    )
END, '') + ' / ' + B.SEX 'MaxAge_Gender', --'MaxAge/Gender' ,  --RasikV 20180919
0 IP_NO,
'' WARD_NAME,
'' BED_NO,
ISNULL(B.mobile, '') MOBILE_NO,
'' Doc_Name,
' ' DocMobile_No
FROM PTN_MST1 B
LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
AND C.TYP = 3
WHERE b.ptn_NO = @pPtnNo
UNION ALL
SELECT @pSubModCd SMS_Typ,
@pCategoryCd Category,
'' PTN_NAME,
'' 'MaxAge_Gender', --'MaxAge/Gender' ,  --RasikV 20180919
0 IP_NO,
'' WARD_NAME,
'' BED_NO,
'' MOBILE_NO,
ISNULL(C.DCD, '') + ' ' + doc.doc_lst_nm + ' ' + doc.doc_frst_nm + ' ' + doc.doc_mid_nm Doc_Name,
ISNULL(doc.MobileNo, '') DocMobile_No
FROM doc_mst doc
LEFT JOIN CD_DCD C ON doc.ttl_cd = C.CD
AND C.TYP = 3
WHERE doc.doc_cd = @pDocCd;
END;

--shital 20210427 start

IF @pSubModCd = 407
AND @pCategoryCd = 7
BEGIN
    SET @pWardContactNo = STUFF(
    (
    SELECT ',' + ContactMobile
    FROM WardContactMst
    WHERE WardCd = @pWardNo
    AND cocd = @pcocd
    AND divcd = @pdivcd
    AND loccd = @ploccd
    AND IsActive = 1 FOR XML PATH('')
    ), 1, 1, '');
    IF @pWardContactNo != ''
    OR @pWardContactNo IS NOT NULL
    BEGIN
        SELECT @Hsp_Nm = ISNULL(hsp_lng_nm, '')
        FROM instal;
        SELECT @pSubModCd SMS_Typ,
        @pCategoryCd Category,
        ISNULL(C.DCD, '') Initial,
        B.ptn_lst_nm + ' ' + B.ptn_frst_nm + ' ' + B.ptn_mid_nm PTN_NAME,
        @pIPNo IP_NO,
        '' WARD_NAME,
        CASE
        WHEN @pBedNo IS NOT NULL
        AND @pBedNo != '0'
        THEN @pBedNo
        ELSE ''
    END BED_NO,
    ISNULL(B.mobile, '') MOBILE_NO,
    @strDocName Doc_Name,
    @pWardContactNo WardContactNo,
    @Hsp_Nm Hsp_Name
    FROM PTN_MST1 B
    LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
    AND C.TYP = 3
    WHERE b.ptn_NO = @pPtnNo;
END;
END;
ELSE
IF @pSubModCd = 407
AND @pCategoryCd = 6
BEGIN
    IF @pPtnNo IS NOT NULL
    AND @pPtnNo != 0
    BEGIN
        SET @pWardContactNo = STUFF(
        (
        SELECT ',' + ContactMobile
        FROM WardContactMst
        WHERE WardCd = @pWardNo
        AND cocd = @pcocd
        AND divcd = @pdivcd
        AND loccd = @ploccd
        AND IsActive = 1 FOR XML PATH('')
        ), 1, 1, '');
        IF @pWardContactNo != ''
        OR @pWardContactNo IS NOT NULL
        BEGIN
            IF @pKinMobile != '0'
            OR @pKinMobile IS NOT NULL
            OR @pKinMobile != ''
            BEGIN
                SELECT @Hsp_Nm = ISNULL(hsp_lng_nm, '')
                FROM instal;
                SELECT @pSubModCd SMS_Typ,
                @pCategoryCd Category,
                ISNULL(C.DCD, '') Initial,
                B.ptn_lst_nm + ' ' + B.ptn_frst_nm + ' ' + B.ptn_mid_nm PTN_NAME,
                @pIPNo IP_NO,
                '' WARD_NAME,
                CASE
                WHEN @pBedNo IS NOT NULL
                AND @pBedNo != '0'
                THEN @pBedNo
                ELSE ''
            END BED_NO,
            (CASE
            WHEN @pKinMobile IS NOT NULL
            AND @pKinMobile != ''
            THEN @pKinMobile
            ELSE ''
        END) MOBILE_NO,
        @strDocName Doc_Name,
        @pWardContactNo WardContactNo,
        @Hsp_Nm Hsp_Name
        FROM PTN_MST1 B
        LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
        AND C.TYP = 3
        WHERE b.ptn_NO = @pPtnNo;
    END;
END;
END;
END;
--shital 20210427 end
----- ********************* DISCHARGE SMS QUERY BELOW******************************************************************

--   *********************

ELSE
--========================================================== Afrin 20220517
IF(@pSubModCd = 407
AND @pCategoryCd = 11
AND @pWardNo <> '')
BEGIN
   -- DECLARE @docCd INT, @DocName VARCHAR(MAX), @ClassName VARCHAR(20), @ptnTypDesc VARCHAR(70), @AdmDt DATETIME, @AdmTm DATETIME;
    IF @pPtnNo IS NOT NULL
    AND @pPtnNo != 0
    BEGIN
        SELECT @strPtnName = (ISNULL(C.DCD, '') + ' ' + ISNULL(B.ptn_lst_nm, '') + ' ' + ISNULL(B.ptn_frst_nm, '') + ' ' + ISNULL(B.ptn_mid_nm, '')),
        @strAgeGender = ISNULL(CASE
        WHEN B.brth_dt IS NULL
        THEN
        (
        SELECT([DBO].[CalMax_DOB](
        (
        SELECT DATEADD(Year, -1 * b.age_yy, b.crt_dt)
        ), GETDATE()
        ))
        )
        ELSE
        (
        SELECT [DBO].[CalMax_DOB](B.brth_dt, GETDATE())
        )
    END, '') + ' / ' + B.SEX
    FROM PTN_MST1 B
    LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
    AND C.TYP = 3
    WHERE b.ptn_NO = @pPtnNo;
END;
SELECT @DocName = ISNULL(C.DCD, '') + ' ' + ISNULL(doc.doc_lst_nm, '') + ' ' + ISNULL(doc.doc_frst_nm, '') + ' ' + ISNULL(doc.doc_mid_nm, ''),
@docCd = doc.doc_cd
FROM doc_mst doc
LEFT JOIN CD_DCD C ON doc.ttl_cd = C.CD
AND C.TYP = 3
WHERE doc.doc_cd = @pDocCd;
SELECT @ClassName =
(
SELECT ptn_cls_dcd
FROM ptn_cls_mst(NOLOCK)
WHERE ptn_cls_cd = @pPtnClassCd
);
SELECT @ptnTypDesc =
(
SELECT PtnTypDesc
FROM PtnTypeMst(NOLOCK)
WHERE PtnTypCd = @pPtnTypeCd
);
SELECT @pSubModCd AS SMS_Typ,
@pCategoryCd AS Category,
@strPtnName PTN_NAME,
@strAgeGender 'MaxAge_Gender',
@pIPNo IP_NO,
'' WARD_NAME,
@pBedNo BED_NO,
ISNULL(ContactMobile, '') MOBILE_NO,
@DocName Doc_Name,
@ClassName class,
@ptnTypDesc ptnTyp,
@pAdmTm DOA
FROM WardContactMst
WHERE WardCd = @pWardNo
AND cocd = @pcocd
AND divcd = @pdivcd
AND loccd = @ploccd
AND IsActive = 1
AND SendAdmAlertToContactPerson = 1;
END;  --end
--===========================================================  Afrin 20220517 end code

ELSE
BEGIN
    IF @pSubModCd = 407
    AND ( @pCategoryCd = 9 Or @pCategoryCd = 8 OR @pCategoryCd = 10)
    BEGIN
        PRINT 'here';
        --DECLARE @docCd INT, @DocName VARCHAR(MAX), @ClassName VARCHAR(20), @ptnTypDesc VARCHAR(70), @AdmDt DATETIME, @AdmTm DATETIME;
        --DECLARE @strPtnName VARCHAR(60);
        --DECLARE @strAgeGender VARCHAR(60);
        IF @pPtnNo IS NOT NULL
        AND @pPtnNo != 0
        BEGIN
            SELECT @strPtnName = (ISNULL(C.DCD, '') + ' ' + ISNULL(B.ptn_lst_nm, '') + ' ' + ISNULL(B.ptn_frst_nm, '') + ' ' + ISNULL(B.ptn_mid_nm, '')),
            @strAgeGender = ISNULL(CASE
            WHEN B.brth_dt IS NULL
            THEN
            (
            SELECT([DBO].[CalMax_DOB](
            (
            SELECT DATEADD(Year, -1 * b.age_yy, b.crt_dt)
            ), GETDATE()
            ))
            )
            ELSE
            (
            SELECT [DBO].[CalMax_DOB](B.brth_dt, GETDATE())
            )
        END, '') + ' / ' + B.SEX
        FROM PTN_MST1 B
        LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
        AND C.TYP = 3
        --WHERE b.ptn_NO = 1003835
        WHERE b.ptn_NO = @pPtnNo; --SACHIN 20180428: Bug fix patient no was hardcoded.

    END;
    SELECT @DocName = ISNULL(C.DCD, '') + ' ' + ISNULL(doc.doc_lst_nm, '') + ' ' + ISNULL(doc.doc_frst_nm, '') + ' ' + ISNULL(doc.doc_mid_nm, ''),
    @docCd = doc.doc_cd
    FROM doc_mst doc
    LEFT JOIN CD_DCD C ON doc.ttl_cd = C.CD
    AND C.TYP = 3
    WHERE doc.doc_cd = @pDocCd;
    SELECT @ClassName =
    (
    SELECT ptn_cls_dcd
    FROM ptn_cls_mst(NOLOCK)
    WHERE ptn_cls_cd = @pPtnClassCd
    );
    SELECT @ptnTypDesc =
    (
    SELECT PtnTypDesc
    FROM PtnTypeMst(NOLOCK)
    WHERE PtnTypCd = @pPtnTypeCd
    );

    --select @AdmDt= (select convert(datetime,convert(varchar,@pAdmDt
    --,102 ) +' '+convert(varchar,@AdmTm,108 ) )
    --from ip_ptn_vst I where ip_no=@pIPNo)
    SELECT SMS_TYPE AS SMS_Typ,
    @pCategoryCd AS Category,
    @strPtnName PTN_NAME,
    @strAgeGender 'MaxAge_Gender',
    @pIPNo IP_NO,
    '' WARD_NAME,
    @pBedNo BED_NO,
    RegNo,
    ISNULL(MobileNo, '') MOBILE_NO,
    @DocName Doc_Name,
    @ClassName class,
    @ptnTypDesc ptnTyp,
    @pAdmTm DOA
    FROM SMS_GRP_DTL
    WHERE IsActive = 1
    AND SMS_TYPE = @pSubModCd
    AND CategoryTyp = @pCategoryCd --shital 20200314
    -- Send SMS for Category Type 8 From SMS_MSt_Forward  #Payal 20260514 Start

END;  --end

ELSE
IF @pSubModCd = 625
AND (@pCategoryCd = 9
OR @pCategoryCd = 10)
BEGIN

    -- declare @docCd int,@DocName varchar(max)
    --DECLARE @strPtnName VARCHAR(60);
    --DECLARE @strAgeGender VARCHAR(60);
    IF @pPtnNo IS NOT NULL
    AND @pPtnNo != 0
    BEGIN
        SELECT @strPtnName = (ISNULL(C.DCD, '') + ' ' + ISNULL(B.ptn_lst_nm, '') + ' ' + ISNULL(B.ptn_frst_nm, '') + ' ' + ISNULL(B.ptn_mid_nm, '')),
        @strAgeGender = ISNULL(CASE
        WHEN B.brth_dt IS NULL
        THEN
        (
        SELECT([DBO].[CalMax_DOB](
        (
        SELECT DATEADD(Year, -1 * b.age_yy, b.crt_dt)
        ), GETDATE()
        ))
        )
        ELSE
        (
        SELECT [DBO].[CalMax_DOB](B.brth_dt, GETDATE())
        )
    END, '') + ' / ' + B.SEX
    FROM PTN_MST1 B
    LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
    AND C.TYP = 3
    --WHERE b.ptn_NO = 1003835
    WHERE b.ptn_NO = @pPtnNo; --SACHIN 20180428: Bug fix patient no was hardcoded.

END;
SELECT @DocName = ISNULL(C.DCD, '') + ' ' + ISNULL(doc.doc_lst_nm, '') + ' ' + ISNULL(doc.doc_frst_nm, '') + ' ' + ISNULL(doc.doc_mid_nm, ''),
@docCd = doc.doc_cd
FROM doc_mst doc
LEFT JOIN CD_DCD C ON doc.ttl_cd = C.CD
AND C.TYP = 3
WHERE doc.doc_cd = @pDocCd;
SELECT @ClassName =
(
SELECT TOP 1 ptn_cls_dcd
FROM ptn_cls_mst
WHERE ptn_cls_cd = @pPtnClassCd
);
SELECT @ptnTypDesc =
(
SELECT TOP 1 PtnTypDesc
FROM PtnTypeMst
WHERE PtnTypCd = @pPtnTypeCd
);
SELECT SMS_TYPE AS SMSTyp,
@pCategoryCd AS Category,
@strPtnName PTN_NAME,
@strAgeGender 'MaxAge_Gender',
@pIPNo IP_NO,
'' WARD_NAME,
@pBedNo BED_NO,
RegNo,
ISNULL(MobileNo, '') MOBILE_NO,
@DocName Doc_Name,
@ClassName class,
@ptnTypDesc ptnTyp,
@pAdmTm DOA
FROM SMS_GRP_DTL
WHERE IsActive = 1
AND SMS_TYPE = @pSubModCd
AND CategoryTyp = @pCategoryCd; --shital 20200314
END;  --end

ELSE
IF @pSubModCd = 424
AND @pCategoryCd = 6
BEGIN
    PRINT '***';
    SELECT @pCategoryCd Category,
    @pSubModCd SMS_Typ,
    @pDischargeDate DischargeDate,
    @pexptd_no_day exptd_no_day,
    CONVERT(VARCHAR(8), CONVERT(TIME, @pDischargeTime)) DischargeTime,
    @pUsrNm ExtendBy,
    @pIPNo IP_NO,
    MOBILENO MOBILE_NO
    FROM SMS_GRP_DTL
    WHERE IsActive = 1
    AND CategoryTyp = @pCategoryCd
    AND SMS_TYPE = 501;
END;
ELSE
IF @pSubModCd = 424
AND @pCategoryCd = 5
BEGIN
    PRINT '***';
    SELECT @strPtnName = ISNULL(C.DCD, '') + ' ' + mst.ptn_lst_nm + ' ' + mst.ptn_frst_nm + ' ' + mst.ptn_mid_nm
    FROM ip_ptn_vst(NOLOCK) vst
    INNER JOIN ptn_mst1(NOLOCK) mst ON vst.ptn_no = mst.ptn_no
    LEFT JOIN CD_DCD(NOLOCK) C ON mst.ttl_cd = C.CD
    AND C.TYP = 3
    WHERE vst.ip_no = @pIPNo;
    SELECT @pBedNo = --''
    ISNULL(vst.bed_no, '')
    FROM ip_ptn_vst(NOLOCK) vst
    WHERE vst.ip_no = @pIPNo;
    SET @ClassName = --''
    (
    SELECT ptn_cls_dcd
    FROM ptn_cls_mst(NOLOCK)
    WHERE ptn_cls_cd =
    (
    SELECT ptn_cls_cd
    FROM ip_ptn_vst(NOLOCK)
    WHERE ip_no = @pIPNo
    )
    );
    SELECT @ptnTypDesc = --''
    (
    SELECT PtnTypDesc
    FROM PtnTypeMst(NOLOCK)
    WHERE PtnTypCd =
    (
    SELECT PtnTypCd
    FROM ip_ptn_vst(NOLOCK)
    WHERE ip_no = @pIPNo
    )
    );
    SELECT @pCategoryCd Category,
    @pSubModCd SMS_Typ,
    @pDischargeDate DischargeDate,
    @pexptd_no_day exptd_no_day,
    CONVERT(VARCHAR(8), CONVERT(TIME, @pDischargeTime)) DischargeTime,
    @pUsrNm ExtendBy,
    @pIPNo IP_NO,
    MOBILENO MOBILE_NO,
    @ClassName class,
    @ptnTypDesc ptnTyp,
    @strPtnName PTN_NAME,
    @pBedNo BED_NO
    FROM SMS_GRP_DTL
    WHERE IsActive = 1
    AND CategoryTyp = @pCategoryCd
    AND SMS_TYPE = 424;
END;

--   ****************
---

--****
ELSE
IF @pSubModCd = 424
AND @pCategoryCd = 7
BEGIN
    DECLARE @mobile1 varchar(20)
    PRINT '***';

    SELECT @strPtnName = ISNULL(C.DCD, '') + ' ' + mst.ptn_lst_nm + ' ' + mst.ptn_frst_nm + ' ' + mst.ptn_mid_nm ,
    @mobile1=mst.mobile

    FROM ip_ptn_vst(NOLOCK) vst
    INNER JOIN ptn_mst1(NOLOCK) mst ON vst.ptn_no = mst.ptn_no
    LEFT JOIN CD_DCD(NOLOCK) C ON mst.ttl_cd = C.CD
    AND C.TYP = 3
    WHERE vst.ip_no = @pIPNo;
    SELECT @pBedNo = --''
    ISNULL(vst.bed_no, '')
    FROM ip_ptn_vst(NOLOCK) vst
    WHERE vst.ip_no = @pIPNo;
    SET @ClassName = --''
    (
    SELECT ptn_cls_dcd
    FROM ptn_cls_mst(NOLOCK)
    WHERE ptn_cls_cd =
    (
    SELECT ptn_cls_cd
    FROM ip_ptn_vst(NOLOCK)
    WHERE ip_no = @pIPNo
    )
    );
    SELECT @ptnTypDesc = --''
    (
    SELECT PtnTypDesc
    FROM PtnTypeMst(NOLOCK)
    WHERE PtnTypCd =
    (
    SELECT PtnTypCd
    FROM ip_ptn_vst(NOLOCK)
    WHERE ip_no = @pIPNo
    )
    );
    SELECT @pCategoryCd Category,
    @pSubModCd SMS_Typ,
    @pDischargeDate DischargeDate,
    @pexptd_no_day exptd_no_day,
    CONVERT(VARCHAR(8), CONVERT(TIME, @pDischargeTime)) DischargeTime,
    @pUsrNm ExtendBy,
    @pIPNo IP_NO,
    @mobile1 MOBILE_NO,
    @ClassName class,
    @ptnTypDesc ptnTyp,
    @strPtnName PTN_NAME,
    @pBedNo BED_NO
    FROM SMS_GRP_DTL
    WHERE IsActive = 1
    AND CategoryTyp = @pCategoryCd
    AND SMS_TYPE = 424;
END;
---***



ELSE
IF @pSubModCd = 449
AND @pCategoryCd = 1
BEGIN
    PRINT '***';
    SELECT @strPtnName = ISNULL(C.DCD, '') + ' ' + mst.ptn_lst_nm + ' ' + mst.ptn_frst_nm + ' ' + mst.ptn_mid_nm
    FROM ip_ptn_vst(NOLOCK) vst
    INNER JOIN ptn_mst1(NOLOCK) mst ON vst.ptn_no = mst.ptn_no
    LEFT JOIN CD_DCD(NOLOCK) C ON mst.ttl_cd = C.CD
    AND C.TYP = 3
    WHERE vst.ip_no = @pIPNo;
    SELECT @pBedNo = --''
    ISNULL(vst.bed_no, '')
    FROM ip_ptn_vst(NOLOCK) vst
    WHERE vst.ip_no = @pIPNo;
    SET @ClassName = --''
    (
    SELECT ptn_cls_dcd
    FROM ptn_cls_mst(NOLOCK)
    WHERE ptn_cls_cd =
    (
    SELECT ptn_cls_cd
    FROM ip_ptn_vst(NOLOCK)
    WHERE ip_no = @pIPNo
    )
    );
    SELECT @ptnTypDesc = --''
    (
    SELECT PtnTypDesc
    FROM PtnTypeMst(NOLOCK)
    WHERE PtnTypCd =
    (
    SELECT PtnTypCd
    FROM ip_ptn_vst(NOLOCK)
    WHERE ip_no = @pIPNo
    )
    );

    Select @mobile1 = SUBSTRING (mobile,3, len(mobile))   from ptn_mst1 a where a.ptn_no in (
    Select ptn_no  from ip_ptn_vst a where a.ip_no =@pIPNo)
    SELECT @pCategoryCd Category,
    @pSubModCd SMS_Typ,
    @pIPNo IP_NO,
    @mobile1 MOBILE_NO,
    @ClassName class,
    @ptnTypDesc ptnTyp,
    @strPtnName PTN_NAME,
    @pBedNo BED_NO

    /* SELECT @pCategoryCd Category,
    @pSubModCd SMS_Typ,
    @pIPNo IP_NO,
    MOBILENO MOBILE_NO,
    @ClassName class,
    @ptnTypDesc ptnTyp,
    @strPtnName PTN_NAME,
    @pBedNo BED_NO
    FROM SMS_GRP_DTL
    WHERE IsActive = 1
    AND CategoryTyp = @pCategoryCd
    AND SMS_TYPE = @pSubModCd;
    */
END

---  ;    ;          ;
ELSE
IF @pSubModCd = 447
AND @pCategoryCd = 1            --(DICHARGE SMS IP PTN)
BEGIN
    DECLARE @strDisChrgDesc VARCHAR(90);
    --SELECT @strDisChrgDesc = isnull(cd, 0)  --commented by aparna 31 dec 2018

    SELECT @strDisChrgDesc = ISNULL(dcd, '')
    FROM cd_dcd
    WHERE typ = 19
    AND cd = @pDiscSts;
    SELECT @pSubModCd SMS_Typ,
    @pCategoryCd Category,
    ISNULL(C.DCD, '') + ' ' + mst.ptn_lst_nm + ' ' + mst.ptn_frst_nm + ' ' + mst.ptn_mid_nm PTN_NAME,
    ISNULL(CASE
    WHEN mst.brth_dt IS NULL
    THEN
    (
    SELECT([DBO].[CalMax_DOB](
    (
    SELECT DATEADD(Year, -1 * mst.age_yy, mst.crt_dt)
    ), GETDATE()
    ))
    )
    ELSE
    (
    SELECT [DBO].[CalMax_DOB](mst.brth_dt, GETDATE())
    )
END, '') + ' / ' + mst.SEX 'MaxAge_Gender', --'MaxAge/Gender' ,  --RasikV 20180919
@pIPNo IP_NO,
ISNULL(vst.bed_no, '') BED_NO,
ISNULL(vst.lcl_tel, '') MOBILE_NO,
@strDisChrgDesc Discharge_Status
FROM ip_ptn_vst vst
INNER JOIN ptn_mst1 mst ON vst.ptn_no = mst.ptn_no
LEFT JOIN CD_DCD C ON mst.ttl_cd = C.CD
AND C.TYP = 3
WHERE vst.ip_no = @pIPNo;

--select * from ip_ptn_vst where ip_no=  4000000249

END;
ELSE
IF @pSubModCd = 447
AND @pCategoryCd = 3   --(DICHARGE SMS DOC)
BEGIN
    DECLARE @strDisChrgDescDoc VARCHAR(90);
    --SELECT @strDisChrgDescDoc = isnull(cd, 0)     --commented by aparna 31 dec 2018
    SELECT @strDisChrgDescDoc = ISNULL(dcd, '')
    FROM cd_dcd
    WHERE typ = 19
    AND cd = @pDiscSts;
    SELECT @pSubModCd SMS_Typ,
    @pCategoryCd Category,
    ISNULL(C.DCD, '') + ' ' + mst.ptn_lst_nm + ' ' + mst.ptn_frst_nm + ' ' + mst.ptn_mid_nm PTN_NAME,
    ISNULL(CASE
    WHEN mst.brth_dt IS NULL
    THEN
    (
    SELECT([DBO].[CalMax_DOB](
    (
    SELECT DATEADD(Year, -1 * mst.age_yy, mst.crt_dt)
    ), GETDATE()
    ))
    )
    ELSE
    (
    SELECT [DBO].[CalMax_DOB](mst.brth_dt, GETDATE())
    )
END, '') + ' / ' + mst.SEX 'MaxAge_Gender', --'MaxAge/Gender' ,  --RasikV 20180919
@pIPNo IP_NO,
ISNULL(vst.bed_no, '') BED_NO,
@strDisChrgDescDoc Discharge_Status,
ISNULL(doc.MobileNo, '') MOBILE_NO
FROM ip_ptn_vst vst
INNER JOIN ptn_mst1 mst ON vst.ptn_no = mst.ptn_no
LEFT JOIN CD_DCD C ON mst.ttl_cd = C.CD
AND C.TYP = 3
LEFT JOIN doc_mst doc ON vst.doc_cd = doc.doc_cd
WHERE vst.ip_no = @pIPNo
AND doc.doc_cd = @pDocCd;
END;

-- **********************

ELSE
IF @pSubModCd = 447
AND @pCategoryCd = 8   --(DICHARGE SMS DOC)
BEGIN

    --SELECT @strDisChrgDescDoc = isnull(cd, 0)     --commented by aparna 31 dec 2018
    SELECT @strDisChrgDescDoc = ISNULL(dcd, '')
    FROM cd_dcd
    WHERE typ = 19
    AND cd = @pDiscSts;
    SELECT @strPtnName = ISNULL(C.DCD, '') + ' ' + mst.ptn_lst_nm + ' ' + mst.ptn_frst_nm + ' ' + mst.ptn_mid_nm,
    @strAgeGender = ISNULL(CASE
    WHEN mst.brth_dt IS NULL
    THEN
    (
    SELECT([DBO].[CalMax_DOB](
    (
    SELECT DATEADD(Year, -1 * mst.age_yy, mst.crt_dt)
    ), GETDATE()
    ))
    )
    ELSE
    (
    SELECT [DBO].[CalMax_DOB](mst.brth_dt, GETDATE())
    )
END, '') + ' / ' + mst.SEX, --'MaxAge/Gender' ,  --RasikV 20180919


@pBedNo = ISNULL(vst.bed_no, '')
FROM ip_ptn_vst vst
INNER JOIN ptn_mst1 mst ON vst.ptn_no = mst.ptn_no
LEFT JOIN CD_DCD C ON mst.ttl_cd = C.CD
AND C.TYP = 3
LEFT JOIN doc_mst doc ON vst.doc_cd = doc.doc_cd
WHERE vst.ip_no = @pIPNo
AND doc.doc_cd = @pDocCd;
SELECT SMS_TYPE AS SMSTyp,
@pCategoryCd AS Category,
@strPtnName PTN_NAME,
@strAgeGender 'MaxAge_Gender',
@pIPNo IP_NO,
'' WARD_NAME,
@pBedNo BED_NO,
RegNo,
ISNULL(MobileNo, '') MOBILE_NO,
@DocName Doc_Name,
@strDisChrgDescDoc Discharge_Status
FROM SMS_GRP_DTL
WHERE IsActive = 1
AND SMS_TYPE = @pSubModCd
AND CategoryTyp = @pCategoryCd; --shital 20200314
END;
-------------------------shivkumar 22/03/2022 kin mobile number and cancel discharge----------------------------------------------
ELSE
IF @pSubModCd = 447
AND @pCategoryCd = 2   --(DICHARGE SMS DOC)
BEGIN
    DECLARE @strDisChrgDescDoc1 VARCHAR(90);
    --SELECT @strDisChrgDescDoc = isnull(cd, 0)     --commented by aparna 31 dec 2018
    SELECT @strDisChrgDescDoc1 = ISNULL(dcd, '')
    FROM cd_dcd
    WHERE typ = 19
    AND cd = @pDiscSts;
    SELECT @pSubModCd SMS_Typ,
    @pCategoryCd Category,
    ISNULL(C.DCD, '') + ' ' + mst.ptn_lst_nm + ' ' + mst.ptn_frst_nm + ' ' + mst.ptn_mid_nm PTN_NAME,
    ISNULL(CASE
    WHEN mst.brth_dt IS NULL
    THEN
    (
    SELECT([DBO].[CalMax_DOB](
    (
    SELECT DATEADD(Year, -1 * mst.age_yy, mst.crt_dt)
    ), GETDATE()
    ))
    )
    ELSE
    (
    SELECT [DBO].[CalMax_DOB](mst.brth_dt, GETDATE())
    )
END, '') + ' / ' + mst.SEX 'MaxAge_Gender', --'MaxAge/Gender' ,  --RasikV 20180919
@pIPNo IP_NO,
ISNULL(vst.bed_no, '') BED_NO,
@strDisChrgDescDoc1 Discharge_Status,
ISNULL(doc.MobileNo, '') MOBILE_NO,
GETDATE() AS DateTime
FROM ip_ptn_vst vst
INNER JOIN ptn_mst1 mst ON vst.ptn_no = mst.ptn_no
LEFT JOIN CD_DCD C ON mst.ttl_cd = C.CD
AND C.TYP = 3
LEFT JOIN doc_mst doc ON vst.doc_cd = doc.doc_cd
WHERE vst.ip_no = @pIPNo
AND doc.doc_cd = @pDocCd;
END;
ELSE
IF @pSubModCd = 447
AND @pCategoryCd = 4
BEGIN
    IF @pPtnNo IS NOT NULL
    AND @pPtnNo != 0
    BEGIN
        BEGIN
            SELECT @Hsp_Nm = ISNULL(hsp_lng_nm, '')
            FROM instal;
            SELECT @pSubModCd SMS_Typ,
            @pCategoryCd Category,
            ISNULL(C.DCD, '') Initial,
            B.ptn_lst_nm + ' ' + B.ptn_frst_nm + ' ' + B.ptn_mid_nm PTN_NAME,
            @pIPNo IP_NO,
            '' WARD_NAME,
            CASE
            WHEN @pBedNo IS NOT NULL
            AND @pBedNo != '0'
            THEN @pBedNo
            ELSE ''
        END BED_NO,
        A.kin_mobile AS MOBILE_NO,
        @strDocName Doc_Name,
        @pWardContactNo WardContactNo,
        @Hsp_Nm Hsp_Name
        FROM ip_ptn_vst vst
        INNER JOIN PTN_MST1 B ON vst.ptn_no = B.ptn_no
        LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
        AND C.TYP = 3
        INNER JOIN ptn_mst2 A ON b.ptn_no = A.ptn_no
        WHERE vst.ip_no = @pIPNo;
    END;
END;
END;

--- cancel discharge kin details---
ELSE
IF @pSubModCd = 447
AND @pCategoryCd = 5
BEGIN
    IF @pPtnNo IS NOT NULL
    AND @pPtnNo != 0
    BEGIN
        BEGIN
            SELECT @Hsp_Nm = ISNULL(hsp_lng_nm, '')
            FROM instal;
            SELECT @pSubModCd SMS_Typ,
            @pCategoryCd Category,
            ISNULL(C.DCD, '') Initial,
            B.ptn_lst_nm + ' ' + B.ptn_frst_nm + ' ' + B.ptn_mid_nm PTN_NAME,
            @pIPNo IP_NO,
            '' WARD_NAME,
            CASE
            WHEN @pBedNo IS NOT NULL
            AND @pBedNo != '0'
            THEN @pBedNo
            ELSE ''
        END BED_NO,
        A.kin_mobile AS MOBILE_NO,
        @strDocName Doc_Name,
        @pWardContactNo WardContactNo,
        @Hsp_Nm Hsp_Name,
        GETDATE() AS DateTime
        FROM ip_ptn_vst vst
        INNER JOIN PTN_MST1 B ON vst.ptn_no = B.ptn_no
        LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
        AND C.TYP = 3
        INNER JOIN ptn_mst2 A ON b.ptn_no = A.ptn_no
        WHERE vst.ip_no = @pIPNo;
    END;
END;
END;

------end shivkumar 22/03/2022------------------------------------------------------------------------------------------------
--  ********************
ELSE
IF @pSubModCd = 460
AND @pCategoryCd = 1   --------or @pSubModCd = 460 (New Patient Master Index) and @pCategoryCd = 1(IP Patient) -- Added By Amol 27-07-2017


BEGIN
    SELECT @pSubModCd SMS_Typ,
    @pCategoryCd Category,
    ptn_no PTN_NO,
    ISNULL(C.DCD, '') + ' ' + B.ptn_lst_nm + ' ' + B.ptn_frst_nm + ' ' + B.ptn_mid_nm PTN_NAME,
    ISNULL(CASE
    WHEN B.brth_dt IS NULL
    THEN
    (
    SELECT([DBO].[CalMax_DOB](
    (
    SELECT DATEADD(Year, -1 * b.age_yy, b.crt_dt)
    ), GETDATE()
    ))
    )
    ELSE
    (
    SELECT [DBO].[CalMax_DOB](B.brth_dt, GETDATE())
    )
END, '') + ' / ' + B.SEX 'MaxAge_Gender', --'MaxAge/Gender' ,  --RasikV 20180919
ISNULL(B.mobile, '') MOBILE_NO
FROM PTN_MST1(NOLOCK) B
LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
AND C.TYP = 3
WHERE ptn_no = @pPtnNo;
END;
ELSE
IF @pSubModCd = 553
AND @pCategoryCd = 1
--------@pSubModCd = 553 (INSURANCE REGISTRATION) and @pCategoryCd = 1(IPPtn) -- Pragya : 30-oct-2017
BEGIN
    SELECT ISNULL(C.DCD, '') + ' ' + B.ptn_lst_nm + ' ' + B.ptn_frst_nm + ' ' + B.ptn_mid_nm Ptn_Name,
    ISNULL(CASE
    WHEN B.brth_dt IS NULL
    THEN
    (
    SELECT([DBO].[CalMax_DOB](
    (
    SELECT DATEADD(Year, -1 * b.age_yy, b.crt_dt)
    ), GETDATE()
    ))
    )
    ELSE
    (
    SELECT [DBO].[CalMax_DOB](B.brth_dt, GETDATE())
    )
END, '') + ' / ' + B.SEX 'MaxAge_Gender', --'MaxAge/Gender' ,  --RasikV 20180919


A.IP_NO Ptn_IP_No,
ISNULL(D.dcd, '') WardDesc,
A.bed_no Bed_No,
ISNULL(B.Mobile, '0') MOBILENO,
ISNULL(E.MobileNo, '0') DocMobileNo
FROM IP_PTN_VST A
JOIN PTN_MST1 B ON A.PTN_NO = B.PTN_NO
LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
AND C.TYP = 3
LEFT JOIN CD_DCD D ON A.wrd_cd = D.CD
AND D.TYP = 2
LEFT JOIN DOC_MST E ON A.doc_cd = E.doc_cd
AND e.DOC_STS_CD = 1
WHERE A.IP_NO = @pIpNo;
END;
ELSE
IF @pSubModCd = 553
AND @pCategoryCd = 2
--------or @pSubModCd = 553 (INSURANCE REGISTRATION) and @pCategoryCd = 2(OP Patient) -- Pragya : 31-oct-2017
BEGIN
    SELECT ptn_no Ptn_IP_No,
    ISNULL(C.DCD, '') + ' ' + B.ptn_lst_nm + ' ' + B.ptn_frst_nm + ' ' + B.ptn_mid_nm PtnName,
    ISNULL(CASE
    WHEN B.brth_dt IS NULL
    THEN
    (
    SELECT([DBO].[CalMax_DOB](
    (
    SELECT DATEADD(Year, -1 * b.age_yy, b.crt_dt)
    ), GETDATE()
    ))
    )
    ELSE
    (
    SELECT [DBO].[CalMax_DOB](B.brth_dt, GETDATE())
    )
END, '') + ' / ' + B.SEX 'MaxAge_Gender', --'MaxAge/Gender' ,  --RasikV 20180919


ISNULL(B.mobile, '') MOBILENO
FROM PTN_MST1(NOLOCK) B
LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
AND C.TYP = 3
WHERE ptn_no = @pPtnNo;
END;
ELSE
IF @pSubModCd = 553
AND @pCategoryCd = 3
--------or @pSubModCd = 553 (INSURANCE REGISTRATION) and @pCategoryCd = 3(DOCOTR) -- Pragya : 31-oct-2017


BEGIN
    SELECT ISNULL(C.DCD, '') + ' ' + B.ptn_lst_nm + ' ' + B.ptn_frst_nm + ' ' + B.ptn_mid_nm PtnName,
    ISNULL(CASE
    WHEN B.brth_dt IS NULL
    THEN
    (
    SELECT([DBO].[CalMax_DOB](
    (
    SELECT DATEADD(Year, -1 * b.age_yy, b.crt_dt)
    ), GETDATE()
    ))
    )
    ELSE
    (
    SELECT [DBO].[CalMax_DOB](B.brth_dt, GETDATE())
    )
END, '') + ' / ' + B.SEX 'MaxAge_Gender', --'MaxAge/Gender' ,  --RasikV 20180919


A.IP_NO Ptn_IP_No,
ISNULL(D.dcd, '') WardDesc,
A.bed_no Bed_No,
ISNULL(E.MobileNo, '0') MOBILENO
FROM IP_PTN_VST A
JOIN PTN_MST1 B ON A.PTN_NO = B.PTN_NO
LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
AND C.TYP = 3
LEFT JOIN CD_DCD D ON A.wrd_cd = D.CD
AND D.TYP = 2
LEFT JOIN DOC_MST E ON A.doc_cd = E.doc_cd
AND e.DOC_STS_CD = 1
WHERE A.IP_NO = @pIpNo;
END;
ELSE
IF @pSubModCd = 554
AND @pCategoryCd = 1
--------or @pSubModCd = 554 (INSURANCE Application) and @pCategoryCd = 1(IP PTN) -- Pragya : 31-oct-2017


BEGIN
    SELECT ISNULL(reg.REG_NO, 0) RegNo,
    ISNULL(reg.REG_TYP, '') RegTyp,
    ISNULL(reg.PTN_NO, 0) PtnNo,
    ISNULL(reg.IP_NO, 0) IpNo,
    reg.ip_op IpOp,
    CASE
    WHEN reg.reg_typ = 'I'
    THEN reg.INS_ID
    ELSE reg.AR_CD
END InsCmpCd,
CASE
WHEN reg.reg_typ = 'I'
THEN ISNULL([dbo].[FnInsuranceCodeDesc](@pcocd, @pdivcd, @ploccd, 1, ISNULL(INS_ID, 0)), '')
ELSE ISNULL(armst.ar_lng_nm, '')
END InsCmpName,
CASE
WHEN REG.IP_OP = 'I'
THEN
(
SELECT ISNULL(Mobile, '0')
FROM PTN_MST1
WHERE Mobile <> '0'
AND ptn_no IN
(
SELECT ptn_no
FROM ip_ptn_vst
WHERE ip_no = @pIPNo
)
)
END MobileNo
FROM IP_INS_REG reg
LEFT JOIN AR_MST armst ON reg.Ar_cd = armst.ar_cd
AND armst.ar_sts_cd = 1
WHERE reg.REG_NO = @pInsRegNo;
END;
ELSE
IF @pSubModCd = 554
AND @pCategoryCd = 2
--------or @pSubModCd = 554 (INSURANCE Application) and @pCategoryCd = 2(OP PTN) -- Pragya : 31-oct-2017
BEGIN
    SELECT ISNULL(reg.REG_NO, 0) RegNo,
    ISNULL(reg.REG_TYP, '') RegTyp,
    ISNULL(reg.PTN_NO, 0) PtnNo,
    ISNULL(reg.IP_NO, 0) IpNo,
    reg.ip_op IpOp,
    CASE
    WHEN reg.reg_typ = 'I'
    THEN reg.INS_ID
    ELSE reg.AR_CD
END InsCmpCd,
CASE
WHEN reg.reg_typ = 'I'
THEN ISNULL([dbo].[FnInsuranceCodeDesc](1, 1, 1, 1, ISNULL(INS_ID, 0)), '')
ELSE armst.ar_lng_nm
END InsCmpName,
CASE
WHEN REG.IP_OP = 'O'
THEN
(
SELECT ISNULL(Mobile, '0')
FROM PTN_MST1
WHERE ISNULL(Mobile, '0') <> '0'
AND ptn_no = @pPtnNo
)
END MobileNo
FROM IP_INS_REG reg
LEFT JOIN AR_MST armst ON reg.Ar_cd = armst.ar_cd
AND armst.ar_sts_cd = 1
WHERE reg.REG_NO = @pInsRegNo;
END;
ELSE
IF @pSubModCd = 554
AND @pCategoryCd = 3
--------or @pSubModCd = 554 (INSURANCE Application) and @pCategoryCd = 3(DocCd) -- Pragya : 31-oct-2017


BEGIN
    SELECT ISNULL(reg.REG_NO, 0) RegNo,
    ISNULL(reg.REG_TYP, '') RegTyp,
    ISNULL(reg.PTN_NO, 0) PtnNo,
    ISNULL(reg.IP_NO, 0) IpNo,
    reg.ip_op IpOp,
    CASE
    WHEN reg.reg_typ = 'I'
    THEN reg.INS_ID
    ELSE reg.AR_CD
END InsCmpCd,
CASE
WHEN reg.reg_typ = 'I'
THEN ISNULL([dbo].[FnInsuranceCodeDesc](@pcocd, @pdivcd, @ploccd, 1, ISNULL(INS_ID, 0)), '')
ELSE armst.ar_lng_nm
END InsCmpName,
(
SELECT MOBILEno
FROM doc_mst
WHERE MOBILEno <> '0'
AND DOC_STS_CD = 1
AND doc_cd IN
(
SELECT doc_cd
FROM ip_ptn_vst
WHERE ip_no = @pIPNo
)
) MobileNo
FROM IP_INS_REG reg
LEFT JOIN AR_MST armst ON reg.Ar_cd = armst.ar_cd
AND armst.ar_sts_cd = 1
WHERE reg.REG_NO = @pInsRegNo;
END;
ELSE
IF @pSubModCd = 0
AND @pCategoryCd = 0
BEGIN
    SELECT *
    FROM IP_PTN_VST
    WHERE ip_no = @pIPNo;
END;
ELSE
IF @pSubModCd = 606
AND @pCategoryCd = 51  --[MAINTENANCE TRACKER] RasikV 20180605


BEGIN
    DECLARE @DeptDcd VARCHAR(50), @ItemDcd VARCHAR(50), @PriorityDcd VARCHAR(70);
    SELECT @DeptDcd = ISNULL(DEPT_DESC, '')
    FROM EMS.EQP_DEPT(NOLOCK)
    WHERE COCD = @pcocd
    AND divn = @pdivcd
    AND locn = @ploccd
    AND DEPT_CD = @pFrmDeptCd;
    SELECT @ItemDcd = ISNULL(ItemDesc, '')
    FROM MTRITEMMST(NOLOCK)
    WHERE COCD = @pcocd
    AND DivCd = @pdivcd
    AND LocCd = @ploccd
    AND ItemCd = @pItemCd;
    SELECT @PriorityDcd = ISNULL(dcd, '')
    FROM cd_dcd(NOLOCK)
    WHERE typ = 5026
    AND COCD = @pcocd
    AND DivCd = @pdivcd
    AND LocCd = @ploccd
    AND cd = @pPriorityCd;
    SELECT @pSubModCd [SMS_Typ],
    @pCategoryCd [Category],
    @pCompNo [COMPNO],
    @pCompDt [COMPDT],
    @pUsrNm [USERNAME],
    @DeptDcd [FROMDEPT],
    @ItemDcd [ITEMDESC],
    @pCompDesc [COMPDESC],
    @PriorityDcd [PRIORITY],
    ISNULL(deptempmob, '') [MOBILE_NO]
    FROM EMS.eqpdeptEmp
    WHERE cocd = @pcocd
    AND divcd = @pdivcd
    AND loccd = @ploccd
    AND deptcd = @pToDeptCd
    AND ISNULL(deptempmob, '') <> ''
    AND deptempIsActive = 1;
END;
ELSE
IF @pSubModCd = 412
AND @pCategoryCd = 52  --[OT SCHEDULING] RasikV 20180918
BEGIN
    DECLARE @FctName VARCHAR(100), @PtnName VARCHAR(300), @Sex VARCHAR(50);
    SELECT @FctName = ISNULL(fct_name, '')
    FROM fct_mst(NOLOCK)
    WHERE fct_cat_code = 1
    AND fct_main_code = 1
    AND fct_code = @pFctCd;
    SELECT @PtnName = ISNULL(ISNULL(C.DCD, '') + ' ' + ISNULL(B.ptn_lst_nm, '') + ' ' + ISNULL(B.ptn_frst_nm, '') + ' ' + ISNULL(B.ptn_mid_nm, ''),''),
    @Sex = ISNULL(CASE
    WHEN B.brth_dt IS NULL
    THEN
    (
    SELECT([DBO].[CalMax_DOB](
    (
    SELECT DATEADD(Year, -1 * b.age_yy, b.crt_dt)
    ), GETDATE()
    ))
    )
    ELSE
    (
    SELECT [DBO].[CalMax_DOB](B.brth_dt, GETDATE())
    )
END, '') + ' / ' + ISNULL(B.SEX, '')
FROM IP_PTN_VST A
JOIN PTN_MST1 B ON A.PTN_NO = B.PTN_NO
LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
AND C.TYP = 3
WHERE A.IP_NO = @pIpNo;
SELECT @pSubModCd [SMS_Typ],
@pCategoryCd [Category],
[SenderCd],
-- [SenderName],
SenderMobNo [MOBILE_NO],
@pFctCd [FctCd],
@FctName [OT_NAME],
@pIpNo [IP_NO],
@PtnName [PTN_NAME],
@Sex [MaxAge_Gender],
@pApptNo [APPT_NO],
@pApptDt [APPT_DT],
@pApptFrmTm [APPT_FRMTM],
@pApptToTm [APPT_TOTM]
FROM
(
SELECT 0 [IpNo],
'' [Name],
'' [Sex],
ISNULL(A.doc_cd, '') [SenderCd],
ISNULL(ISNULL(C.DCD, '') + ' ' + ISNULL(A.doc_lst_nm, '') + ' ' + ISNULL(A.doc_frst_nm, '') + ' ' + ISNULL(A.doc_mid_nm, ''), '') [S
enderName],
ISNULL(A.MobileNo, '') [SenderMobNo]
FROM doc_mst A(NOLOCK)
LEFT JOIN CD_DCD C(NOLOCK) ON A.ttl_cd = C.CD
AND C.TYP = 3
WHERE A.doc_cd = @pDocCd
AND ISNULL(A.MobileNo, '') <> ''
UNION ALL
SELECT 0 [IpNo],
'' [Name],
'' [Sex],
ISNULL(EmpID, '') [SenderCd],
ISNULL(EmpName, '') [SenderName],
ISNULL(HomePhone, '') [SenderMobNo]
FROM PersonalDetails(NOLOCK)
WHERE EmpID = @pEmpId
AND ISNULL(HomePhone, '') <> ''
) TBl
WHERE ISNULL(SenderMobNo, '') <> '';
END;
ELSE
IF @pSubModCd = 419
AND @pCategoryCd = 2

/* Use Ip Reservation Module*/

BEGIN
    SELECT @pSubModCd SMS_Typ,
    @pCategoryCd Category,
    ISNULL(I.IPRsvPtnTitleDcd, '') + ' ' + I.IPRsvPtnLstNm + ' ' + I.IPRsvPtnFrstNm + ' ' + I.IPRsvPtnMidNm PTN_NAME,
    ISNULL(CASE
    WHEN I.IPRsvPtnDOB IS NULL
    THEN
    (
    SELECT([DBO].[CalMax_DOB](
    (
    SELECT DATEADD(Year, -1 * I.IPRsvPtnAgeYY, I.IPRsvDt)
    ), GETDATE()
    ))
    )
    ELSE
    (
    SELECT [DBO].[CalMax_DOB](I.IPRsvPtnDOB, GETDATE())
    )
END, '') + ' / ' + I.IPRsvPtnGender 'MaxAge_Gender',
@pIPNo IP_NO,
I.IPRsvNo RESERV_NO,
'' WARD_NAME,
IpRsvPrefBedNo BED_NO,
ISNULL(I.IPRsvPtnMobile, '') MOBILE_NO,
--ISNULL(C.DCD, '') + ' ' +
E.doc_lst_nm + ' ' + E.doc_frst_nm + ' ' + E.doc_mid_nm Doc_Name
FROM IpReservation I(NOLOCK)
LEFT JOIN CD_DCD C(NOLOCK) ON I.IPRsvPtnTitleCd = C.CD
AND C.TYP = 3
LEFT JOIN DOC_MST E(NOLOCK) ON I.IPRsvDocCd = E.doc_cd
WHERE I.IPRsvNo = @pRsvNo
AND I.cocd = @pcocd
AND I.divcd = @pdivcd
AND I.loccd = @ploccd;
END;
ELSE
IF @pSubModCd = 407
AND @pCategoryCd = 4
BEGIN
    DECLARE @strKinPtnName VARCHAR(60);
    DECLARE @strKinAgeGender VARCHAR(60);
    IF @pPtnNo IS NOT NULL
    AND @pPtnNo != 0
    BEGIN
        SELECT @strKinPtnName = (ISNULL(C.DCD, '') + ' ' + ISNULL(B.ptn_lst_nm, '') + ' ' + ISNULL(B.ptn_frst_nm, '') + ' ' + ISNULL(B.ptn_mid_nm, '')),
        @strKinAgeGender = ISNULL(CASE
        WHEN B.brth_dt IS NULL
        THEN
        (
        SELECT([DBO].[CalMax_DOB](
        (
        SELECT DATEADD(Year, -1 * b.age_yy, b.crt_dt)
        ), GETDATE()
        ))
        )
        ELSE
        (
        SELECT [DBO].[CalMax_DOB](B.brth_dt, GETDATE())
        )
    END, '') + ' / ' + B.SEX,
    @pKinMobile = (CASE
    WHEN @pKinMobile IS NOT NULL
    AND @pKinMobile != ''
    THEN @pKinMobile
    ELSE ''
END),
@pBedNo = CASE
WHEN @pBedNo IS NOT NULL
AND @pBedNo != '0'
THEN @pBedNo
ELSE '0'
END
FROM PTN_MST1 B
LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
AND C.TYP = 3
WHERE b.ptn_NO = @pPtnNo;
END;
SELECT @pSubModCd SMS_Typ,
@pCategoryCd Category,
@strKinPtnName PTN_NAME,
@strKinAgeGender 'MaxAge_Gender',
@pIPNo IP_NO,
'' WARD_NAME,
@pBedNo BED_NO,
@pKinMobile MOBILE_NO,
ISNULL(C.DCD, '') + ' ' + ISNULL(doc.doc_lst_nm, '') + ' ' + ISNULL(doc.doc_frst_nm, '') + ' ' + ISNULL(doc.doc_mid_nm, '') Doc_Name
FROM doc_mst doc
LEFT JOIN CD_DCD C ON doc.ttl_cd = C.CD
AND C.TYP = 3
WHERE doc.doc_cd = @pDocCd

--satish sir start

UNION ALL --Yoga Session

SELECT SMS_Type SMS_Typ,
CategoryTyp Category,
@strKinPtnName PTN_NAME,
@strKinAgeGender 'MaxAge_Gender',
@pIPNo IP_NO,
'' WARD_NAME,
@pBedNo BED_NO,
@pKinMobile MOBILE_NO,
--ISNULL(C.DCD, '')+' '+ISNULL(doc.doc_lst_nm, '')+' '+ISNULL(doc.doc_frst_nm, '')+' '+ISNULL(doc.doc_mid_nm, '') Doc_Name


'' Doc_Name
FROM SMS_MST sms
WHERE SMS_Type = 407
AND CategoryTyp = 2
AND Active_Flag = 'Y'
AND @Rule9171 = 'Y'

--end

UNION ALL

--shital 20200314 start
SELECT SMSType AS SMSTyp,
@pCategoryCd AS Category,
PersonName PTN_NAME,
@strAgeGender 'MaxAge_Gender',
@pIPNo IP_NO,
'' WARD_NAME,
@pBedNo BED_NO,
ISNULL(MobileNo, '') MOBILE_NO,
'' Doc_Name
FROM SMS_Mst_Forward
WHERE CoCd = @pcocd
AND LocCd = @ploccd
AND DivCd = @pdivcd
AND Active_Flag = 'Y'
AND ISNULL(AdmDocCdIs, 0) = 0
AND SMSType = @pSubModCd
AND CategoryType = @pCategoryCd;  --shital 20200314
--end

END;
ELSE
IF @pSubModCd = 407  -- Nikita 20191003
AND @pCategoryCd = 5
BEGIN
    DECLARE @strPtnName1 VARCHAR(60);
    DECLARE @strAgeGender1 VARCHAR(60);
    IF @pPtnNo IS NOT NULL
    AND @pPtnNo != 0
    BEGIN
        SELECT @strPtnName1 = (ISNULL(C.DCD, '') + ' ' + ISNULL(B.ptn_lst_nm, '') + ' ' + ISNULL(B.ptn_frst_nm, '') + ' ' + ISNULL(B.ptn_mid_nm, '')),
        @strAgeGender1 = ISNULL(CASE
        WHEN B.brth_dt IS NULL
        THEN
        (
        SELECT([DBO].[CalMax_DOB](
        (
        SELECT DATEADD(Year, -1 * b.age_yy, b.crt_dt)
        ), GETDATE()
        ))
        )
        ELSE
        (
        SELECT [DBO].[CalMax_DOB](B.brth_dt, GETDATE())
        )
    END, '') + ' / ' + B.SEX,
    @pBedNo = CASE
    WHEN @pBedNo IS NOT NULL
    AND @pBedNo != '0'
    THEN @pBedNo
    ELSE '0'
END
FROM PTN_MST1 B
LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
AND C.TYP = 3
WHERE b.ptn_NO = @pPtnNo;
END;
SELECT @pSubModCd SMS_Typ,
@pCategoryCd Category,
@strPtnName1 PTN_NAME,
@strAgeGender1 'MaxAge_Gender',
@pIPNo IP_NO,
'' WARD_NAME,
@pBedNo BED_NO,
ISNULL(C.DCD, '') + ' ' + ISNULL(Trndoc.TraineDocLstNm, '') + ' ' + ISNULL(Trndoc.TraineDocFrstNm, '') + ' ' + ISNULL(Trndoc.TraineDocMidNm, '') Doc_Name,
ISNULL(Trndoc.TraineeDocMobile, '') MOBILE_NO
FROM TraineeDocMst Trndoc
LEFT JOIN CD_DCD C ON Trndoc.TraineDocTtl = C.CD
AND C.TYP = 3
WHERE Trndoc.TranieDocCd = @pDocCd;
END;
ELSE
IF @pSubModCd = 406  -- Nikita 20191003
AND @pCategoryCd = 5
BEGIN
    DECLARE @strPtnName2 VARCHAR(60);
    DECLARE @strAgeGender2 VARCHAR(60);
    IF @pPtnNo IS NOT NULL
    AND @pPtnNo != 0
    BEGIN
        SELECT @strPtnName2 = (ISNULL(C.DCD, '') + ' ' + ISNULL(B.ptn_lst_nm, '') + ' ' + ISNULL(B.ptn_frst_nm, '') + ' ' + ISNULL(B.ptn_mid_nm, '')),
        @strAgeGender2 = ISNULL(CASE
        WHEN B.brth_dt IS NULL
        THEN
        (
        SELECT([DBO].[CalMax_DOB](
        (
        SELECT DATEADD(Year, -1 * b.age_yy, b.crt_dt)
        ), GETDATE()
        ))
        )
        ELSE
        (
        SELECT [DBO].[CalMax_DOB](B.brth_dt, GETDATE())
        )
    END, '') + ' / ' + B.SEX,
    @pBedNo = CASE
    WHEN @pBedNo IS NOT NULL
    AND @pBedNo != '0'
    THEN @pBedNo
    ELSE '0'
END
FROM PTN_MST1 B
LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
AND C.TYP = 3
WHERE b.ptn_NO = @pPtnNo;
END;
SELECT @pSubModCd SMS_Typ,
@pCategoryCd Category,
@strPtnName2 PTN_NAME,
@strAgeGender2 'MaxAge_Gender',
@pIPNo IP_NO,
'' WARD_NAME,
@pBedNo BED_NO,
ISNULL(C.DCD, '') + ' ' + ISNULL(Trndoc.TraineDocLstNm, '') + ' ' + ISNULL(Trndoc.TraineDocFrstNm, '') + ' ' + ISNULL(Trndoc.TraineDocMidNm, '') Doc_Name,
ISNULL(Trndoc.TraineeDocMobile, '') MOBILE_NO
FROM TraineeDocMst Trndoc
LEFT JOIN CD_DCD C ON Trndoc.TraineDocTtl = C.CD
AND C.TYP = 3
WHERE Trndoc.TranieDocCd = @pDocCd;
END;
ELSE
IF @pSubModCd = 628  -- Nikita 20191003
AND @pCategoryCd = 5
BEGIN
    DECLARE @strPtnName3 VARCHAR(60);
    DECLARE @strAgeGender3 VARCHAR(60);
    IF @pPtnNo IS NOT NULL
    AND @pPtnNo != 0
    BEGIN
        SELECT @strPtnName3 = (ISNULL(C.DCD, '') + ' ' + ISNULL(B.ptn_lst_nm, '') + ' ' + ISNULL(B.ptn_frst_nm, '') + ' ' +
        ISNULL(B.ptn_mid_nm, '')),
        @strAgeGender3 = ISNULL(CASE
        WHEN B.brth_dt IS NULL
        THEN
        (
        SELECT([DBO].[CalMax_DOB](
        (
        SELECT DATEADD(Year, -1 * b.age_yy, b.crt_dt)
        ), GETDATE()
        ))
        )
        ELSE
        (
        SELECT [DBO].[CalMax_DOB](B.brth_dt, GETDATE())
        )
    END, '') + ' / ' + B.SEX,
    @pBedNo = CASE
    WHEN @pBedNo IS NOT NULL
    AND @pBedNo != '0'
    THEN @pBedNo
    ELSE '0'
END
FROM PTN_MST1 B
LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
AND C.TYP = 3
WHERE b.ptn_NO = @pPtnNo;
END;
SELECT @pSubModCd SMS_Typ,
@pCategoryCd Category,
@strPtnName3 PTN_NAME,
@strAgeGender3 'MaxAge_Gender',
@pIPNo IP_NO,
'' WARD_NAME,
@pBedNo BED_NO,
ISNULL(C.DCD, '') + ' ' + ISNULL(Trndoc.TraineDocLstNm, '') + ' ' + ISNULL(Trndoc.TraineDocFrstNm, '') + ' ' + ISNULL(Trndoc.TraineDocMidNm, '') Doc_Name,
ISNULL(Trndoc.TraineeDocMobile, '') MOBILE_NO
FROM TraineeDocMst Trndoc
LEFT JOIN CD_DCD C ON Trndoc.TraineDocTtl = C.CD
AND C.TYP = 3
WHERE Trndoc.TranieDocCd = @pDocCd;
END;
ELSE
IF @pSubModCd = 404       -- Sana : 21-OCT-2019
AND @pCategoryCd = 3
BEGIN
    DECLARE @strPtnNameBedTrnsfrDoc VARCHAR(60);
    DECLARE @strAgeGenderBedTrnsfrDoc VARCHAR(60);
    IF @pPtnNo IS NOT NULL
    AND @pPtnNo != 0
    BEGIN
        SELECT @strPtnNameBedTrnsfrDoc = (ISNULL(C.DCD, '') + ' ' + ISNULL(B.ptn_lst_nm, '') + ' ' + ISNULL(B.ptn_frst_nm, '') + ' ' + ISNULL(B.ptn_mid_nm, '')),
        @strAgeGenderBedTrnsfrDoc = ISNULL(CASE
        WHEN B.brth_dt IS NULL
        THEN
        (
        SELECT([DBO].[CalMax_DOB](
        (
        SELECT DATEADD(Year, -1 * b.age_yy, b.crt_dt)
        ), GETDATE()
        ))
        )
        ELSE
        (
        SELECT [DBO].[CalMax_DOB](B.brth_dt, GETDATE())
        )
    END, '') + ' / ' + B.SEX,
    @pBedNo = CASE
    WHEN @pBedNo IS NOT NULL
    AND @pBedNo != '0'
    THEN @pBedNo
    ELSE '0'
END,
@pWardNo = CASE
WHEN @pWardNo IS NOT NULL
AND @pWardNo != ''
THEN @pWardNo
ELSE ''
END
FROM PTN_MST1 B
LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
AND C.TYP = 3
WHERE b.ptn_NO = @pPtnNo;
END;
SELECT @pSubModCd SMS_Typ,
@pCategoryCd Category,
@strPtnNameBedTrnsfrDoc PTN_NAME,
@strAgeGenderBedTrnsfrDoc 'MaxAge_Gender',
@pIPNo IP_NO,
@pWardNo WARD_NAME,
@pBedNo BED_NO,
ISNULL(doc.MobileNo, '') MOBILE_NO
FROM doc_mst doc
LEFT JOIN CD_DCD C ON doc.ttl_cd = C.CD
AND C.TYP = 3
WHERE doc.doc_cd = @pDocCd;
END;
ELSE
IF @pSubModCd = 404       -- Sana : 21-OCT-2019
AND @pCategoryCd = 4
BEGIN
    DECLARE @strPtnNameBedTrnsfrKin VARCHAR(60);
    DECLARE @strAgeGenderBedTrnsfrKin VARCHAR(60);
    IF @pPtnNo IS NOT NULL
    AND @pPtnNo != 0
    BEGIN
        SELECT @strPtnNameBedTrnsfrKin = (ISNULL(C.DCD, '') + ' ' + ISNULL(B.ptn_lst_nm, '') + ' ' + ISNULL(B.ptn_frst_nm, '') + ' ' + ISNULL(B.ptn_mid_nm, '')),
        @strAgeGenderBedTrnsfrKin = ISNULL(CASE
        WHEN B.brth_dt IS NULL
        THEN
        (
        SELECT([DBO].[CalMax_DOB](
        (
        SELECT DATEADD(Year, -1 * b.age_yy, b.crt_dt)
        ), GETDATE()
        ))
        )
        ELSE
        (
        SELECT [DBO].[CalMax_DOB](B.brth_dt, GETDATE())
        )
    END, '') + ' / ' + B.SEX,
    @pBedNo = CASE
    WHEN @pBedNo IS NOT NULL
    AND @pBedNo != '0'
    THEN @pBedNo
    ELSE '0'
END,
@pWardNo = CASE
WHEN @pWardNo IS NOT NULL
AND @pWardNo != ''
THEN @pWardNo
ELSE ''
END,
@pKinMobile = (CASE
WHEN @pKinMobile IS NOT NULL
AND @pKinMobile != ''
THEN @pKinMobile
ELSE ''
END)
FROM PTN_MST1 B
LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
AND C.TYP = 3
WHERE b.ptn_NO = @pPtnNo;
END;
SELECT @pSubModCd SMS_Typ,
@pCategoryCd Category,
@strPtnNameBedTrnsfrKin PTN_NAME,
@strAgeGenderBedTrnsfrKin 'MaxAge_Gender',
@pIPNo IP_NO,
@pWardNo WARD_NAME,
@pBedNo BED_NO,
@pKinMobile MOBILE_NO,
ISNULL(C.DCD, '') + ' ' + ISNULL(doc.doc_lst_nm, '') + ' ' + ISNULL(doc.doc_frst_nm, '') + ' ' + ISNULL(doc.doc_mid_nm, '') Doc_Name
FROM doc_mst doc
LEFT JOIN CD_DCD C ON doc.ttl_cd = C.CD
AND C.TYP = 3
WHERE doc.doc_cd = @pDocCd;
END;

--shital 20210427 start

ELSE
IF @pSubModCd = 404       -- shital 20210427
AND @pCategoryCd = 6
BEGIN
    IF @pPtnNo IS NOT NULL
    AND @pPtnNo != 0
    BEGIN
        SET @pWardContactNo = STUFF(
        (
        SELECT ',' + ContactMobile
        FROM WardContactMst
        WHERE WardCd = @pWardNo
        AND cocd = @pcocd
        AND divcd = @pdivcd
        AND loccd = @ploccd
        AND IsActive = 1 FOR XML PATH('')
        ), 1, 1, '');
        IF @pWardContactNo != ''
        OR @pWardContactNo IS NOT NULL
        BEGIN
            IF @pKinMobile != '0'
            OR @pKinMobile != ''
            OR @pKinMobile IS NOT NULL
            BEGIN
                SELECT @Hsp_Nm = ISNULL(hsp_lng_nm, '')
                FROM instal;
                SELECT @pSubModCd SMS_Typ,
                @pCategoryCd Category,
                ISNULL(C.DCD, '') Initial,
                B.ptn_lst_nm + ' ' + B.ptn_frst_nm + ' ' + B.ptn_mid_nm PTN_NAME,
                @pIPNo IP_NO,
                '' WARD_NAME,
                CASE
                WHEN @pBedNo IS NOT NULL
                AND @pBedNo != '0'
                THEN @pBedNo
                ELSE ''
            END BED_NO,
            (CASE
            WHEN @pKinMobile IS NOT NULL
            AND @pKinMobile != ''
            THEN @pKinMobile
            ELSE ''
        END) MOBILE_NO,
        @strDocName Doc_Name,
        @pWardContactNo WardContactNo,
        @Hsp_Nm Hsp_Name,
        CASE
        WHEN @pFRM_BED_NO IS NOT NULL
        AND @pFRM_BED_NO != '0'
        THEN @pFRM_BED_NO
        ELSE ''
    END FRM_BED_NO
    FROM PTN_MST1 B
    LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
    AND C.TYP = 3
    WHERE b.ptn_NO = @pPtnNo;
END;
END;
END;
END;
ELSE
IF @pSubModCd = 404
AND @pCategoryCd = 5
BEGIN
    IF @pPtnNo IS NOT NULL
    AND @pPtnNo != 0
    BEGIN
        SET @pWardContactNo = STUFF(
        (
        SELECT ',' + ContactMobile
        FROM WardContactMst
        WHERE WardCd = @pWardNo
        AND cocd = @pcocd
        AND divcd = @pdivcd
        AND loccd = @ploccd
        AND IsActive = 1 FOR XML PATH('')
        ), 1, 1, '');
        IF @pWardContactNo != ''
        OR @pWardContactNo IS NOT NULL
        BEGIN
            SELECT @Hsp_Nm = ISNULL(hsp_lng_nm, '')
            FROM instal;
            SELECT @pSubModCd SMS_Typ,
            @pCategoryCd Category,
            ISNULL(C.DCD, '') Initial,
            B.ptn_lst_nm + ' ' + B.ptn_frst_nm + ' ' + B.ptn_mid_nm PTN_NAME,
            @pIPNo IP_NO,
            '' WARD_NAME,
            CASE
            WHEN @pBedNo IS NOT NULL
            AND @pBedNo != '0'
            THEN @pBedNo
            ELSE ''
        END BED_NO,
        ISNULL(B.mobile, '') MOBILE_NO,
        @strDocName Doc_Name,
        @pWardContactNo WardContactNo,
        @Hsp_Nm Hsp_Name
        FROM PTN_MST1 B
        LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
        AND C.TYP = 3
        WHERE b.ptn_NO = @pPtnNo;
    END;
END;
END

--shital 20210427 end
--shital 20210916 sTART                      ;    ;    ;          ;
ELSE
IF @pSubModCd = 404       -- shital 20210427
AND @pCategoryCd = 8
BEGIN
    IF @pPtnNo IS NOT NULL
    AND @pPtnNo != 0
    BEGIN

        --              set @pWardContactNo =stuff(
        --(select ',' + ContactMobile  from WardContactMst where WardCd=@pWardNo

        --      and cocd=@pcocd and divcd=@pdivcd and loccd=@ploccd and IsActive=1 for xml path('')) ,1,1,''
        --      )

        SELECT @strDocName = ISNULL(C.DCD, '') + ' ' + ISNULL(doc.doc_lst_nm, '') + ' ' + ISNULL(doc.doc_frst_nm, '') + ' ' + ISNULL(doc.doc_mid_nm, '')
        FROM doc_mst Doc
        LEFT JOIN CD_DCD C ON doc.ttl_cd = C.CD
        AND C.TYP = 3
        WHERE doc_cd = @pDocCd;
        SELECT @Hsp_Nm = ISNULL(hsp_lng_nm, '')
        FROM instal;
        SELECT
        -- ISNULL(C.DCD, '')Initial

        @strPtnName = B.ptn_lst_nm + ' ' + B.ptn_frst_nm + ' ' + B.ptn_mid_nm,
        @strAgeGender = ISNULL(CASE
        WHEN B.brth_dt IS NULL
        THEN
        (
        SELECT([DBO].[CalMax_DOB](
        (
        SELECT DATEADD(Year, -1 * b.age_yy, b.crt_dt)
        ), GETDATE()
        ))
        )
        ELSE
        (
        SELECT [DBO].[CalMax_DOB](B.brth_dt, GETDATE())
        )
    END, '') + ' / ' + B.SEX
    FROM PTN_MST1 B
    LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
    AND C.TYP = 3
    WHERE b.ptn_NO = @pPtnNo;
    SELECT @pSubModCd SMS_Typ,
    @pCategoryCd AS Category,
    @strPtnName PTN_NAME,
    @Hsp_Nm Hsp_Name,
    @pIPNo IP_NO,
    @strAgeGender 'MaxAge_Gender',
    @pWardNo WARD_NAME,
    @pBedNo BED_NO,
    RegNo,
    ISNULL(MobileNo, '') MOBILE_NO,
    CASE
    WHEN @pFRM_BED_NO IS NOT NULL
    AND @pFRM_BED_NO != '0'
    THEN @pFRM_BED_NO
    ELSE ''
END FRM_BED_NO,
@strDocName Doc_Name
FROM SMS_GRP_DTL
WHERE IsActive = 1
AND SMS_TYPE = @pSubModCd
AND CategoryTyp = @pCategoryCd; --shital 20200314


END;
END
--shital 20210916 end                      ;
----------shivkumar 25/04/2022 Bed Transfer dirrect to sms to kin mobile ;    ;          ;
ELSE
IF @pSubModCd = 404
AND @pCategoryCd = 7
BEGIN
    IF @pPtnNo IS NOT NULL
    AND @pPtnNo != 0
    BEGIN
        BEGIN
            SELECT @Hsp_Nm = ISNULL(hsp_lng_nm, '')
            FROM instal;
            SELECT @pSubModCd SMS_Typ,
            @pCategoryCd Category,
            ISNULL(C.DCD, '') Initial,
            B.ptn_lst_nm + ' ' + B.ptn_frst_nm + ' ' + B.ptn_mid_nm PTN_NAME,
            @pIPNo IP_NO,
            @pWardNo WARD_NAME,
            CASE
            WHEN @pBedNo IS NOT NULL
            AND @pBedNo != '0'
            THEN @pBedNo
            ELSE ''
        END BED_NO,
        CASE
        WHEN vst.KinMobNo IS NULL
        OR vst.KinMobNo = ''
        THEN A.kin_mobile
        ELSE vst.KinMobNo
    END MOBILE_NO,
    -- A.kin_mobile AS MOBILE_NO,

    @strDocName Doc_Name,
    @pWardContactNo WardContactNo,
    @Hsp_Nm Hsp_Name,
    ISNULL(CASE
    WHEN B.brth_dt IS NULL
    THEN
    (
    SELECT([DBO].[CalMax_DOB](
    (
    SELECT DATEADD(Year, -1 * b.age_yy, b.crt_dt)
    ), GETDATE()
    ))
    )
    ELSE
    (
    SELECT [DBO].[CalMax_DOB](B.brth_dt, GETDATE())
    )
END, '') + ' / ' + B.SEX MaxAge_Gender
FROM ip_ptn_vst vst
INNER JOIN PTN_MST1 B ON vst.ptn_no = B.ptn_no
LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
AND C.TYP = 3
INNER JOIN ptn_mst2 A ON b.ptn_no = A.ptn_no
WHERE vst.ip_no = @pIPNo;
END;
END;
END;

----------------end shivkumar 25/03/2022
ELSE
---------------shivkumar 07/06/2022  op post voucher for payment against------------
IF(@pSubModCd = 421
AND @pCategoryCd = 2)
BEGIN
    SELECT @strPtnName =PTN_NAME,
    @pPtnNo = ptn_no,
    @pKinMobile=mobile,
    @pAmount = amt,
    @pVoucherNo = voucherno
    FROM
    (
    SELECT B.PTN_NO,
    ISNULL(C.DCD, '') + ' ' + b.ptn_lst_nm + ' ' + b.ptn_frst_nm + ' ' + b.ptn_mid_nm PTN_NAME,
    ISNULL(B.mobile, '') mobile,

    @pVoucherNo voucherno,
    @pAmount amt
    FROM PTN_MST1 B
    LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
    AND C.TYP = 3
    WHERE B.PTN_NO = @pPtnNo
    ) Tbl
    WHERE tbl.PTN_NO = @pPtnNo;
    SELECT @pSubModCd [SMS_Typ],
    @pCategoryCd [Category],

    @strPtnName [PTN_NAME],
    @pPtnNo [PTN_NO],
    @pKinMobile[MOBILE_NO],
    @pAmount [Amount],
    @pVoucherNo [Voucher_NO];
END;
------------end shivkumar 07/06/2022

ELSE
BEGIN                                --========================================================== Afrin 20220517
    IF(@pSubModCd = 404
    AND @pCategoryCd = 9
    AND @pWardNo <> '')
    BEGIN
        --PRINT 'here';
        --DECLARE @docCd INT, @DocName VARCHAR(MAX), @ClassName VARCHAR(20), @ptnTypDesc VARCHAR(70), @AdmDt DATETIME, @AdmTm DATETIME;
        IF @pPtnNo IS NOT NULL
        AND @pPtnNo != 0
        BEGIN
            SELECT @strPtnName = (ISNULL(C.DCD, '') + ' ' + ISNULL(B.ptn_lst_nm, '') + ' ' + ISNULL(B.ptn_frst_nm, '') + ' ' + ISNULL(B.ptn_mid_nm, '')),
            @strAgeGender = ISNULL(CASE
            WHEN B.brth_dt IS NULL
            THEN
            (
            SELECT([DBO].[CalMax_DOB](
            (
            SELECT DATEADD(Year, -1 * b.age_yy, b.crt_dt)
            ), GETDATE()
            ))
            )
            ELSE
            (
            SELECT [DBO].[CalMax_DOB](B.brth_dt, GETDATE())
            )
        END, '') + ' / ' + B.SEX
        FROM PTN_MST1 B
        LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
        AND C.TYP = 3
        WHERE b.ptn_NO = @pPtnNo;
    END;
    SELECT @DocName = ISNULL(C.DCD, '') + ' ' + ISNULL(doc.doc_lst_nm, '') + ' ' + ISNULL(doc.doc_frst_nm, '') + ' ' + ISNULL(doc.doc_mid_nm, ''),
    @docCd = doc.doc_cd
    FROM doc_mst doc
    LEFT JOIN CD_DCD C ON doc.ttl_cd = C.CD
    AND C.TYP = 3
    WHERE doc.doc_cd = @pDocCd;
    SELECT @ClassName =
    (
    SELECT ptn_cls_dcd
    FROM ptn_cls_mst(NOLOCK)
    WHERE ptn_cls_cd = @pPtnClassCd
    );
    SELECT @ptnTypDesc =
    (
    SELECT PtnTypDesc
    FROM PtnTypeMst(NOLOCK)
    WHERE PtnTypCd = @pPtnTypeCd
    );
    SELECT @pSubModCd AS SMS_Typ,
    @pCategoryCd AS Category,
    @strPtnName PTN_NAME,
    @strAgeGender 'MaxAge_Gender',
    @pIPNo IP_NO,
    '' WARD_NAME,
    @pBedNo BED_NO,
    ISNULL(ContactMobile, '') MOBILE_NO,
    @DocName Doc_Name,
    @ClassName class,
    @ptnTypDesc ptnTyp,
    @pAdmTm DOA,
    @pFRM_BED_NO FRM_BED_NO
    FROM WardContactMst
    WHERE WardCd = @pWardNo
    AND cocd = @pcocd
    AND divcd = @pdivcd
    AND loccd = @ploccd
    AND IsActive = 1
    AND SendBedTnsfrAlertToContactPerson = 1;
END;  --end
--===========================================================  Afrin 20220517 end code

ELSE
IF @pSubModCd = 418
OR @pSubModCd = 1043
AND @pCategoryCd = 1
BEGIN
    DECLARE @PtnTtl VARCHAR(70), @PtnFrstNm VARCHAR(100), @PtnLstNm VARCHAR(100), @HspNm VARCHAR(50), @mobile VARCHAR(20), @DocNm VARCHAR(50);
    SELECT @HspNm = ISNULL(hsp_lng_nm, '')
    FROM instal;
    SET @DocNm = dbo.fn_Doc_Name(@pDocCd);
    SET @DocSpeciality = dbo.fn_Doc_Speciality(@pDocCd); --#Payal 20250531
    SELECT @PtnTtl = PtnTtl,
    @PtnFrstNm = ptn_frst_nm,
    @PtnLstNm = ptn_lst_nm,
    @mobile = mobile
    FROM
    (
    SELECT B.PTN_NO,
    ISNULL(C.DCD, '') PtnTtl,
    ISNULL(B.ptn_frst_nm, '') ptn_frst_nm,
    ISNULL(B.ptn_lst_nm, '') ptn_lst_nm,
    ISNULL(B.mobile, '') mobile
    FROM PTN_MST1 B --ON A.PTN_NO = B.PTN_NO


    LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
    AND C.TYP = 3
    WHERE B.PTN_NO = @pPtnNo
    UNION ALL
    SELECT B.PTN_NO,
    ISNULL(C.DCD, '') PtnTtl,
    ISNULL(B.ptn_frst_nm, '') ptn_frst_nm,
    ISNULL(B.ptn_lst_nm, '') ptn_lst_nm,
    ISNULL(B.mobile, '') mobile
    FROM PTN_MST1 B
    LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
    AND C.TYP = 3
    ) Tbl
    WHERE tbl.PTN_NO = @pPtnNo;
    SELECT																									@pSubModCd [SMS_Typ],
    @pCategoryCd [Category],
    @HspNm [Hsp_Name],
    @mobile [MOBILE_NO],
    @PtnTtl [Ptn_Title],
    @PtnFrstNm [Ptn_First_Name],
    @PtnLstNm [PTN_LAST_NAME],
    CONVERT(DATETIME, CONVERT(CHAR(8), @pApptDt, 112) + ' ' + CONVERT(CHAR(8), @pApptFrmTm, 109)) [App_DtTm],
    @pApptNo [App_No],
    case when @pSubModCd = 1043 then @DocNm + ' ('+ @DocSpeciality +')' else @DocNm end   [Doc_Name];  --#Payal 20250616
END;
ELSE
IF @pSubModCd = 418
OR @pSubModCd = 1043
AND @pCategoryCd = 2  --[Shift Doctor Appointment For patient] Aarti 16 Jan 2020


BEGIN
    SELECT @HspNm = ISNULL(hsp_lng_nm, '')
    FROM instal;
    SET @DocNm = dbo.fn_Doc_Name(@pDocCd);
    SELECT @PtnTtl = PtnTtl,
    @PtnFrstNm = ptn_frst_nm,
    @PtnLstNm = ptn_lst_nm,
    @mobile = mobile
    FROM
    (
    SELECT B.PTN_NO,
    ISNULL(C.DCD, '') PtnTtl,
    ISNULL(B.ptn_frst_nm, '') ptn_frst_nm,
    ISNULL(B.ptn_lst_nm, '') ptn_lst_nm,
    ISNULL(B.mobile, '') mobile
    FROM PTN_MST1 B --ON A.PTN_NO = B.PTN_NO


    LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
    AND C.TYP = 3
    WHERE B.PTN_NO = @pPtnNo
    UNION ALL
    SELECT B.PTN_NO,
    ISNULL(C.DCD, '') PtnTtl,
    ISNULL(B.ptn_frst_nm, '') ptn_frst_nm,
    ISNULL(B.ptn_lst_nm, '') ptn_lst_nm,
    ISNULL(B.mobile, '') mobile
    FROM PTN_MST1 B
    LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
    AND C.TYP = 3
    ) Tbl
    WHERE tbl.PTN_NO = @pPtnNo;
    SELECT @pSubModCd [SMS_Typ],
    @pCategoryCd [Category],
    @mobile [MOBILE_NO],
    @PtnTtl [Ptn_Title],
    @PtnFrstNm [Ptn_First_Name],
    @PtnLstNm [PTN_LAST_NAME],
    CONVERT(DATETIME, CONVERT(CHAR(8), @pApptDt, 112) + ' ' + CONVERT(CHAR(8), @pApptFrmTm, 109)) [App_DtTm],
    @pApptNo [App_No],
    @DocNm [Doc_Name],
    @pOldApptNo [old_App_No];
END;
ELSE
IF @pSubModCd = 418
OR @pSubModCd = 1043
AND @pCategoryCd = 4  --[Cancel Doctor Appointment For patient] Aarti 16 Jan 2020

BEGIN
    SELECT @HspNm = ISNULL(hsp_lng_nm, '')
    FROM instal;
    SET @DocNm = dbo.fn_Doc_Name(@pDocCd);
    SELECT @PtnTtl = PtnTtl,
    @PtnFrstNm = ptn_frst_nm,
    @PtnLstNm = ptn_lst_nm,
    @mobile = mobile
    FROM
    (
    SELECT B.PTN_NO,
    ISNULL(C.DCD, '') PtnTtl,
    ISNULL(B.ptn_frst_nm, '') ptn_frst_nm,
    ISNULL(B.ptn_lst_nm, '') ptn_lst_nm,
    ISNULL(B.mobile, '') mobile
    FROM PTN_MST1 B --ON A.PTN_NO = B.PTN_NO


    LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
    AND C.TYP = 3
    WHERE B.PTN_NO = @pPtnNo
    UNION ALL
    SELECT B.PTN_NO,
    ISNULL(C.DCD, '') PtnTtl,
    ISNULL(B.ptn_frst_nm, '') ptn_frst_nm,
    ISNULL(B.ptn_lst_nm, '') ptn_lst_nm,
    ISNULL(B.mobile, '') mobile
    FROM PTN_MST1 B
    LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
    AND C.TYP = 3
    ) Tbl
    WHERE tbl.PTN_NO = @pPtnNo;
    SELECT @pSubModCd [SMS_Typ],
    @pCategoryCd [Category],
    @HspNm [Hsp_Name],
    @mobile [MOBILE_NO],
    @PtnTtl [Ptn_Title],
    @PtnFrstNm [Ptn_First_Name],
    @PtnLstNm [PTN_LAST_NAME],
    CONVERT(DATETIME, CONVERT(CHAR(8), @pApptDt, 112) + ' ' + CONVERT(CHAR(8), @pApptFrmTm, 109)) [App_DtTm],
    @pApptNo [App_No],
    @DocNm [Doc_Name];
END;
ELSE
IF @pSubModCd = 1043
AND @pCategoryCd = 5  --[FollowUp Message to Ptn] Maitri 20200312


BEGIN
    SELECT @HspNm = ISNULL(hsp_lng_nm, '')
    FROM instal;
    SET @DocNm = dbo.fn_Doc_Name(@pDocCd);
    SELECT @PtnTtl = PtnTtl,
    @PtnFrstNm = ptn_frst_nm,
    @PtnLstNm = ptn_lst_nm,
    @mobile = mobile
    FROM
    (
    SELECT B.PTN_NO,
    ISNULL(C.DCD, '') PtnTtl,
    ISNULL(B.ptn_frst_nm, '') ptn_frst_nm,
    ISNULL(B.ptn_lst_nm, '') ptn_lst_nm,
    ISNULL(B.mobile, '') mobile
    FROM PTN_MST1 B --ON A.PTN_NO = B.PTN_NO


    LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
    AND C.TYP = 3
    WHERE B.PTN_NO = @pPtnNo
    UNION ALL
    SELECT B.PTN_NO,
    ISNULL(C.DCD, '') PtnTtl,
    ISNULL(B.ptn_frst_nm, '') ptn_frst_nm,
    ISNULL(B.ptn_lst_nm, '') ptn_lst_nm,
    ISNULL(B.mobile, '') mobile
    FROM PTN_MST1 B
    LEFT JOIN CD_DCD C ON B.ttl_cd = C.CD
    AND C.TYP = 3
    ) Tbl
    WHERE tbl.PTN_NO = @pPtnNo;
    SELECT @pSubModCd [SMS_Typ],
    @pCategoryCd [Category],
    @HspNm [Hsp_Name],
    @mobile [MOBILE_NO],
    @PtnTtl [Ptn_Title],
    @PtnFrstNm [Ptn_First_Name],
    @PtnLstNm [PTN_LAST_NAME],
    CONVERT(DATETIME, CONVERT(CHAR(8), @pApptDt, 112) + ' ' + CONVERT(CHAR(8), @pApptFrmTm, 109)) [App_DtTm],
    @pApptNo [App_No],
    @DocNm [Doc_Name];
END;

----*****----
END;--Afrin; 20220517
--****---
END;--Afrin 20220517
END;
GO

/* 18 / 26  NST_InsSmsDtl - discharge SMS: queue the message */
IF OBJECT_ID(N'dbo.NST_InsSmsDtl', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_InsSmsDtl;
GO
                
CREATE PROCEDURE [dbo].[NST_InsSmsDtl]              
-- Add the parameters for the stored procedure here                
@PSMSSRL        INT,             
@PSMSSUBSRL     INT,             
@PSMSTYPE       INT,             
@PSMSSTSCD      INT,             
@PSMSMOBILE     VARCHAR(50),             
--@PSMSMESSAGE    VARCHAR(500),             
          
@PSMSMESSAGE    NVARCHAR(max),             
@PSMSTIMETOSEND DATETIME,             
@PSMSCRTBY      VARCHAR(16)='',             
@PSMSCRTTM      DATETIME,             
@PSMSSENTTM     DATETIME,             
@PSMSPARTS      INT,             
@PPTNNO         VARCHAR(20),             
@PVCHNO         VARCHAR(200),             
@PCATEGORYTYP   INT          = 0, --Added BY Trupti 24 JUL 2021           
@PEVENTSCHNO bigint      = 0,  -- Neha 20210903      
@pSMSSrNo       INT          = 0 OUTPUT            
AS            
     DECLARE @SMS_Chk INT, @SMS_Srl INT, @PSmsStsDesc VARCHAR(50),@IsPtnNo Bit;            
    BEGIN            
        --Trupti  26 JUL 2021            
  select @IsPtnNo= Isnumeric(@pPTNNo)            
        IF ( @IsPtnNo=1)            
            BEGIN            
                --If Block SMS For Patient Type            
                IF EXISTS            
                (            
                    SELECT ISNULL(IsBlockPtnSms, 0)            
                    FROM ptn_mst1 a            
                         JOIN PtnTypeMst b ON a.bill_type = b.PtnTypCd            
                                              AND ISNULL(IsBlockPtnSms, 0) = 1            
                    WHERE a.ptn_no =   @PPTNNO             
                )            
                    BEGIN            
                        SET @pSMSSTSCD = 99; ---For Blocked            
                END;            
        END;            
        SET @PSmsStsDesc = CASE            
                               WHEN @pSMSSTSCD = 0            
                               THEN 'Pending'            
                               WHEN @pSMSSTSCD = 1            
                               THEN 'Sent'            
                               WHEN @pSMSSTSCD = 2            
                               THEN 'Invalid Mobile No'            
                               WHEN @pSMSSTSCD = 3            
                               THEN 'SMS Type Inactive'            
                               WHEN @pSMSSTSCD = 4            
                               THEN 'Timed Out'            
                               WHEN @pSMSSTSCD = 99            
                               THEN 'Blocked'            
                           END;            
            
        --Trupti  26 JUL 2021            
            
        UPDATE SMS_Param            
          SET             
              SMS_Last_No = SMS_Last_No + 1;            
        SELECT @SMS_Srl = SMS_Last_No            
        FROM SMS_Param;       
		
       --  To Check SMS TYPE is Whatsapp OR Not Payal 20250123 
       Declare @pIsWhatsapp char = '',
	           @pWhatsappMsg NVARCHAR(max) = ''
	   Select @pIsWhatsapp = ISNULL(IsWhatsapp,'N')  
	         from SMS_Mst 
			 where SMS_Type = @PSMSTYPE And 
			 CategoryTyp = @PCATEGORYTYP 
     if @pIsWhatsapp = 'Y'
	    SET @pIsWhatsapp = @PSMSMESSAGE


      INSERT INTO sms_dtl  
                  (sms_srl,  
                   sms_subsrl,  
                   sms_type,  
                   sms_sts_cd,  
                   sms_mobile,  
                   sms_message,  
                   sms_timetosend,  
                   sms_crt_by,  
                   sms_crt_tm,  
                   sms_sent_tm,  
                   sms_parts,  
                   ptn_no,  
                   vch_no,  
                   categorytyp,  
                   smsstsdesc,  
                   eventschno, --Neha 20210903
				   Whatsapp_Message,
				   LastRetryNo
      )  
      VALUES      ( @SMS_Srl,  
                    @pSMSSUBSRL,  
                    @pSMSTYPE,  
                    @pSMSSTSCD,  
                    @pSMSMOBILE,  
                    @pSMSMESSAGE,  
                    Getdate(),  
                    @pSMSCRTBY,  
                    Getdate(),  
                    Getdate(),  
                    @pSMSPARTS,  
                    @pPTNNO,  
                    @pVCHNO,  
                    @PCATEGORYTYP,  
                    @PSmsStsDesc,  
                    @PEVENTSCHNO,
					@pWhatsappMsg,
					0);  
  
      SELECT @pSMSSrNo = @SMS_Srl;  
    END;
GO

/* 19 / 26  NST_ChkSysLock - system lock check */
IF OBJECT_ID(N'dbo.NST_ChkSysLock', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_ChkSysLock;
GO
CREATE PROCEDURE dbo.NST_ChkSysLock
AS
BEGIN
    -- clsCommonModule.ChkSysLock: SELECT dbo.[FnCheckSysLock](); value '0' means the system is locked.
    SET NOCOUNT ON;
    SELECT dbo.[FnCheckSysLock]() AS SysLock;
END
GO

/* 20 / 26  NST_SelServerDateTime - server date / time */
IF OBJECT_ID(N'dbo.NST_SelServerDateTime', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelServerDateTime;
GO
CREATE PROCEDURE dbo.NST_SelServerDateTime
AS
BEGIN
    -- commonFunctions.GetServerDateTime: SELECT Getdate() ServerDateTime
    SET NOCOUNT ON;
    SELECT GETDATE() AS ServerDateTime;
END
GO

/* 21 / 26  NST_SelIPWardEvnt - PATIENT TRACKING (location column): ward events of a patient */
IF OBJECT_ID(N'dbo.NST_SelIPWardEvnt', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelIPWardEvnt;
GO
CREATE PROCEDURE dbo.NST_SelIPWardEvnt
    @cocd  CHAR(3),
    @divcd SMALLINT,
    @loccd SMALLINT,
    @IPNO  BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH tab AS
    (
        SELECT  a.RecID,
                ISNULL(a.EventID, 0)                                              AS EventId,
                c.EventName                                                       AS EventDesc,
                c.PtnLocnStatusText                                               AS LocName,
                a.CrtUsrID,
                a.CrtDtTm,
                ISNULL(a.EventDt, CONVERT(date, '1900-01-01'))                    AS EventDt,
                ISNULL(CAST(a.EventTime AS datetime), '1900-01-01 00:00:00.000')  AS EventTime,
                a.Remark,
                ISNULL(a.IsMarked, 0)                                             AS IsMarked,
                a.EventIDDependOn,
                (CASE WHEN a.EventID IN (1, 5, 15, 40, 50) THEN 1
                      WHEN ISNULL(a.EventDt, '') <> '' THEN 1
                      ELSE ISNULL(b.IsMarked, 0) END)                             AS IsMarkedDepend
        FROM    IPWardEvnt (NOLOCK) a
                JOIN IPWardEvntMst c ON c.EventID = a.EventID AND a.cocd = c.cocd AND a.divcd = c.divcd AND a.loccd = c.loccd
                LEFT JOIN IPWardEvnt (NOLOCK) b ON a.EventIDDependOn = b.EventID AND a.IPNo = b.IPNo AND a.IsMarked = 0
        WHERE   a.cocd = @cocd AND a.divcd = @divcd AND a.loccd = @loccd AND a.IPNo = @IPNO
    )
    SELECT DISTINCT *
    FROM   tab
    WHERE  tab.RecID NOT IN (SELECT RecID FROM tab WHERE IsMarkedDepend = 0)
    ORDER BY RecID DESC;
END
GO

/* 22 / 26  NST_SaveIPWardEvnt - PATIENT TRACKING (location column): SAVE the current event */
IF OBJECT_ID(N'dbo.NST_SaveIPWardEvnt', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SaveIPWardEvnt;
GO
CREATE PROCEDURE dbo.NST_SaveIPWardEvnt
    @cocd       CHAR(3),
    @divcd      SMALLINT,
    @loccd      SMALLINT,
    @IPNO       BIGINT,
    @RecID      BIGINT,
    @EventID    INT,
    @EventDt    DATE,
    @EventTime  TIME(0),
    @Remark     VARCHAR(150) = '',
    @UserId     VARCHAR(16)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @now DATETIME = GETDATE(), @prev DATETIME, @evName VARCHAR(50), @locTxt VARCHAR(50);

    BEGIN TRAN;

        -- only the pending (not yet marked) row of this patient can be saved
        IF NOT EXISTS (SELECT 1 FROM IPWardEvnt WITH (UPDLOCK)
                       WHERE cocd = @cocd AND divcd = @divcd AND loccd = @loccd
                         AND IPNo = @IPNO AND RecID = @RecID AND EventID = @EventID AND ISNULL(IsMarked, 0) = 0)
        BEGIN
            ROLLBACK;
            SELECT 0 AS Done;
            RETURN;
        END

        -- actual date/time of the previous marked event (kept for the TAT report)
        SELECT TOP (1) @prev = CAST(EventDt AS DATETIME) + CAST(EventTime AS DATETIME)
        FROM   IPWardEvnt
        WHERE  cocd = @cocd AND divcd = @divcd AND loccd = @loccd AND IPNo = @IPNO
               AND RecID < @RecID AND ISNULL(IsMarked, 0) = 1 AND EventDt IS NOT NULL
        ORDER BY RecID DESC;

        EXEC dbo.SPUpdIPWardEvnt
             @cocd = @cocd, @divcd = @divcd, @loccd = @loccd, @IPNO = @IPNO,
             @EventID = @EventID, @EventDt = @EventDt, @EventTime = @EventTime, @Remark = @Remark,
             @UpdtUsrID = @UserId, @RecID = @RecID, @UpdtDtTm = @now, @PrevDtTm = @prev;

        SELECT @evName = EventName, @locTxt = PtnLocnStatusText
        FROM   IPWardEvntMst
        WHERE  cocd = @cocd AND divcd = @divcd AND loccd = @loccd AND EventID = @EventID;

        EXEC dbo.spInsUpdIPCurrentLocn
             @pcocd = @cocd, @pdivcd = @divcd, @ploccd = @loccd, @pIPNo = @IPNO,
             @pEventType = 'Ward', @pEventID = @EventID, @pEventName = @evName, @pLocName = @locTxt,
             @pCrtDtTm = @now, @pCrtUsrID = @UserId;

    COMMIT;
    SELECT 1 AS Done;
END
GO

/* 23 / 26  NST_SelActiveLogin - active legacy login of a user (used only by the stand-alone development session) */
IF OBJECT_ID(N'dbo.NST_SelActiveLogin', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelActiveLogin;
GO
CREATE PROCEDURE dbo.NST_SelActiveLogin
    @pUserId VARCHAR(16)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (1) LogSrNo
    FROM   dbo.LogInOutDetail
    WHERE  UserId = @pUserId AND LogOutDtTm IS NULL
    ORDER BY LogSrNo DESC;
END
GO

/* 24 / 26  NST_SelUserRights - module rights of a user */
IF OBJECT_ID(N'dbo.NST_SelUserRights', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelUserRights;
GO
CREATE PROCEDURE dbo.NST_SelUserRights
    @pCoCd     VARCHAR(10),
    @pDiv      INT,
    @pLoc      INT,
    @pUserId   VARCHAR(50),
    @pModCd    INT,
    @pSubModCd INT
AS
BEGIN
    /* Replaces CmnSecurityFun.UserRights(Cocd, div, loc, UserId, ModCd, SubModCd).
       Result: ONE row, ONE column - the rights string exactly as the WCF method returned it,
       e.g. 'True;True;True;True;True'  (Access;Save;Delete;Print;Auth).
       Empty string / no row = no rights to the module (the app then exits to the dashboard). */
    SET NOCOUNT ON;
    -- Same source as EMR2.SpSelUsrRights (s_userdet), returned as the legacy 'Access;Save;Delete;Print;Auth' string.
    SELECT  CASE WHEN ISNULL([Access], 0) = 1 THEN 'True' ELSE 'False' END + ';' +
            CASE WHEN ISNULL([Save],   0) = 1 THEN 'True' ELSE 'False' END + ';' +
            CASE WHEN ISNULL([Delete], 0) = 1 THEN 'True' ELSE 'False' END + ';' +
            CASE WHEN ISNULL([Print],  0) = 1 THEN 'True' ELSE 'False' END + ';' +
            CASE WHEN ISNULL([Auth],   0) = 1 THEN 'True' ELSE 'False' END AS Rights
    FROM    dbo.s_userdet
    WHERE   UserID = @pUserId AND ModCd = @pModCd AND SubModCd = @pSubModCd;
END
GO

/* 25 / 26  NST_SelMessages - module messages (msgmst) */
IF OBJECT_ID(N'dbo.NST_SelMessages', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelMessages;
GO
CREATE PROCEDURE dbo.NST_SelMessages
    @pCoCd     VARCHAR(10),
    @pDiv      INT,
    @pLoc      INT,
    @pModCd    INT,
    @pSubModCd INT
AS
BEGIN
    /* Replaces CmnSecurityFun.GetmsgmstList(companycode, div, loc, modcd, submodcd).
       Result columns: MsgSrno INT, MsgDesc VARCHAR - the module's validation messages
       (the legacy page used serial numbers 3, 4, 5, 6, 7, 9, 13, 31, 33, 34). */
    SET NOCOUNT ON;
    -- Same query as dbo.SpSelmsgmst.
    SELECT CAST(msgsrno AS INT) AS MsgSrno, msgdesc AS MsgDesc
    FROM   dbo.msgmst
    WHERE  msgmodcd = @pModCd AND msgsubmodcd = @pSubModCd;
END
GO

/* 26 / 26  NST_SelRevenueDate - revenue date (hsp_in_dt) */
IF OBJECT_ID(N'dbo.NST_SelRevenueDate', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelRevenueDate;
GO
CREATE PROCEDURE dbo.NST_SelRevenueDate @pCoCd VARCHAR(10), @pDiv INT, @pLoc INT AS BEGIN SET NOCOUNT ON; SELECT TOP (1) rev_dt AS RevenueDate FROM dbo.hsp_in_dt; END
GO

/* ---------------------------------------------------------------- 4. permissions (optional) ---- */
DECLARE @GrantTo SYSNAME = NULL;          -- e.g. N'NurseStationApp' : the database user the application connects as
IF @GrantTo IS NOT NULL
BEGIN
    DECLARE @sql NVARCHAR(MAX) = N'';
    SELECT @sql = @sql + N'GRANT EXECUTE ON dbo.' + QUOTENAME(name) + N' TO ' + QUOTENAME(@GrantTo) + N';' + CHAR(10)
    FROM sys.procedures WHERE schema_id = SCHEMA_ID(N'dbo') AND name LIKE N'NST[_]%';
    EXEC (@sql);
    PRINT N'EXECUTE granted to ' + @GrantTo;
END
GO

/* ---------------------------------------------------------------- 5. result ---- */
DECLARE @found INT = (SELECT COUNT(*) FROM sys.procedures WHERE schema_id = SCHEMA_ID(N'dbo') AND name IN (
       N'NST_SelPatientList',
       N'NST_SelUserPtnTyp',
       N'NST_SelRule',
       N'NST_SrchCodeDecode',
       N'NST_SrchDoctor',
       N'NST_SelMRDRecCount',
       N'NST_SelUserDet',
       N'NST_SelLOSConfig',
       N'NST_SelLOSByIp',
       N'NST_UpdLOSConfirm',
       N'NST_UpdLOSSkip',
       N'NST_UpdLOSExtend',
       N'NST_InsLOSActionLog',
       N'NST_SelNetIdByModule',
       N'NST_SelSmsParam',
       N'NST_SelSmsMst',
       N'NST_SelSmsReplaceData',
       N'NST_InsSmsDtl',
       N'NST_ChkSysLock',
       N'NST_SelServerDateTime',
       N'NST_SelIPWardEvnt',
       N'NST_SaveIPWardEvnt',
       N'NST_SelActiveLogin',
       N'NST_SelUserRights',
       N'NST_SelMessages',
       N'NST_SelRevenueDate'))
IF @found = 26 PRINT N'NST install complete: 26 procedures.';
ELSE RAISERROR(N'NST install INCOMPLETE: %d of 26 procedures exist. Scroll up for the first error.', 16, 1, @found);
GO
