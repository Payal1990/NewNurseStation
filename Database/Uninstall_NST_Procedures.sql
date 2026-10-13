/* =====================================================================================
   NURSE STATION (new Nursing Workbench) - REMOVE ALL STORED PROCEDURES

   Drops every dbo.NST_* procedure created by Install_NST_Procedures.sql, plus the ones
   earlier versions of the application used. Use it to roll the database side back.

     * Only dbo.NST_* procedures are dropped. No table, data or legacy procedure is touched.
     * Safe to re-run: a procedure that does not exist is skipped.
     * The application stops working without these procedures (the legacy Nurse Station is not affected).
===================================================================================== */

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'dbo.NST_SelPatientList', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelPatientList;
IF OBJECT_ID(N'dbo.NST_SelUserPtnTyp', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelUserPtnTyp;
IF OBJECT_ID(N'dbo.NST_SelRule', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelRule;
IF OBJECT_ID(N'dbo.NST_SrchCodeDecode', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SrchCodeDecode;
IF OBJECT_ID(N'dbo.NST_SrchDoctor', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SrchDoctor;
IF OBJECT_ID(N'dbo.NST_SelMRDRecCount', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelMRDRecCount;
IF OBJECT_ID(N'dbo.NST_SelUserDet', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelUserDet;
IF OBJECT_ID(N'dbo.NST_SelLOSConfig', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelLOSConfig;
IF OBJECT_ID(N'dbo.NST_SelLOSByIp', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelLOSByIp;
IF OBJECT_ID(N'dbo.NST_UpdLOSConfirm', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_UpdLOSConfirm;
IF OBJECT_ID(N'dbo.NST_UpdLOSSkip', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_UpdLOSSkip;
IF OBJECT_ID(N'dbo.NST_UpdLOSExtend', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_UpdLOSExtend;
IF OBJECT_ID(N'dbo.NST_InsLOSActionLog', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_InsLOSActionLog;
IF OBJECT_ID(N'dbo.NST_SelNetIdByModule', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelNetIdByModule;
IF OBJECT_ID(N'dbo.NST_SelSmsParam', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelSmsParam;
IF OBJECT_ID(N'dbo.NST_SelSmsMst', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelSmsMst;
IF OBJECT_ID(N'dbo.NST_SelSmsReplaceData', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelSmsReplaceData;
IF OBJECT_ID(N'dbo.NST_InsSmsDtl', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_InsSmsDtl;
IF OBJECT_ID(N'dbo.NST_ChkSysLock', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_ChkSysLock;
IF OBJECT_ID(N'dbo.NST_SelServerDateTime', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelServerDateTime;
IF OBJECT_ID(N'dbo.NST_SelIPWardEvnt', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelIPWardEvnt;
IF OBJECT_ID(N'dbo.NST_SaveIPWardEvnt', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SaveIPWardEvnt;
IF OBJECT_ID(N'dbo.NST_SelActiveLogin', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelActiveLogin;
IF OBJECT_ID(N'dbo.NST_SelUserRights', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelUserRights;
IF OBJECT_ID(N'dbo.NST_SelMessages', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelMessages;
IF OBJECT_ID(N'dbo.NST_SelRevenueDate', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelRevenueDate;
IF OBJECT_ID(N'dbo.NST_SelWardListByUser', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelWardListByUser;
IF OBJECT_ID(N'dbo.NST_SelDoctor', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelDoctor;
IF OBJECT_ID(N'dbo.NST_SelCodeDecode', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelCodeDecode;
IF OBJECT_ID(N'dbo.NST_SelCodeDecodeList', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelCodeDecodeList;
IF OBJECT_ID(N'dbo.NST_UpdDefaultWard', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_UpdDefaultWard;
IF OBJECT_ID(N'dbo.NST_MarkArrivedOnBed', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_MarkArrivedOnBed;
IF OBJECT_ID(N'dbo.NST_SelIPCurrentLocn', N'P') IS NOT NULL DROP PROCEDURE dbo.NST_SelIPCurrentLocn;
GO

DECLARE @left INT = (SELECT COUNT(*) FROM sys.procedures WHERE schema_id = SCHEMA_ID(N'dbo') AND name LIKE N'NST[_]%');
IF @left = 0 PRINT N'NST procedures removed.';
ELSE PRINT CAST(@left AS NVARCHAR(10)) + N' other dbo.NST_ procedure(s) remain (not created by the installer); left untouched.';
GO
