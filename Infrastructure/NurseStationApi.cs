using System.Text.Json;
using NurseStationTablet.Services;
using Microsoft.Data.SqlClient;
using NurseStationTablet.Data;
using NurseStationTablet.Models;
using NurseStationTablet.Helpers;

namespace NurseStationTablet.Infrastructure;

/// <summary>
/// JSON endpoints behind the tablet page. Each endpoint is the server half of a legacy postback handler;
/// the comments name the Default.aspx.vb member it replaces.
/// </summary>
public static class NurseStationApi
{
    private const string RowsKey = "NS.Rows";
    private const string MsgKey = "NS.Messages";

    // Shown only when msgmst has no row for the number (legacy would show an empty popup).
    private static readonly Dictionary<int, string> FallbackMessages = new()
    {
        [3] = "Enter Valid Ward Code", [4] = "No patient list loaded", [5] = "This Doctor Status Is Inactive , Please Select Another Doctor.",
        [6] = "Entered Doctor code does not exist.", [7] = "Enter Valid Doctor Code", [9] = "Please select any record.",
        [13] = "Record Not Saved", [31] = "Enter Valid Ward Code", [33] = "Enter Valid Speciality Code", [34] = "Enter Valid Floor Code",
    };

    public static void MapNurseStationApi(this WebApplication app)
    {
        var api = app.MapGroup("/api/ns").AddEndpointFilter(async (ctx, next) =>
        {
            if (ctx.HttpContext.Session.GetNs() is null)
                return Results.Json(new { sessionExpired = true }, statusCode: 401);
            try { return await next(ctx); }
            catch (SqlException ex)
            {
                // e.g. an NST_ procedure not yet created, database unreachable, permission missing.
                ctx.HttpContext.RequestServices.GetRequiredService<ILoggerFactory>()
                    .CreateLogger("NurseStationApi").LogError(ex, "Database error on {Path}", ctx.HttpContext.Request.Path);
                return Results.Json(new { message = "Database error: " + ex.Message }, statusCode: 502);
            }
        });

        // Page_Load (Not IsPostBack): system lock, function rights, messages, patient types, default ward,
        // MRD rule, thumbnail-view rule 9278 and the tablet menu rights.
        api.MapGet("/init", (HttpContext ctx, NsRepository gw, SimplifiedModuleLauncher launcher, IConfiguration config, IWebHostEnvironment env, LegacyEmrBridge bridge) =>
        {
            var s = ctx.Session.GetNs()!;
            // If UserNickName is empty, try to fetch it from the database
            if (string.IsNullOrWhiteSpace(s.UserNickName))
            {
                if (gw.GetUserDet(s)?.UserNickName?.Trim() is { Length: > 0 } nick)
                    s.UserNickName = nick;
                else
                    s.UserNickName = s.UserId; // Fallback to UserId if nickname not found
            }
            // Open the legacy Nurse Station page in the background so the first EMR tap does not wait for it.
            if (!launcher.HasSsoSecret) _ = bridge.WarmUpAsync(s);

            // Extract LaunchContext from query parameters
            var modcd = ctx.Request.Query["modcd"].ToString();
            var submodcode = ctx.Request.Query["submodcode"].ToString();
            var user = ctx.Request.Query["user"].ToString();
            var location = ctx.Request.Query["location"].ToString();
            var cocd = ctx.Request.Query["cocd"].ToString();
            var divcd = ctx.Request.Query["divcd"].ToString();
            var loccd = ctx.Request.Query["loccd"].ToString();
            var @ref = ctx.Request.Query["ref"].ToString();

            // Build LaunchContext from query parameters
            var launchContext = new LaunchContext
            {
                ModCd = string.IsNullOrEmpty(modcd) ? null : modcd,
                SubModCode = string.IsNullOrEmpty(submodcode) ? null : submodcode,
                User = string.IsNullOrEmpty(user) ? null : user,
                Location = string.IsNullOrEmpty(location) ? null : location,
                CoCd = string.IsNullOrEmpty(cocd) ? null : cocd,
                DivCd = string.IsNullOrEmpty(divcd) ? null : (int.TryParse(divcd, out var dv) ? dv : null),
                LocCd = string.IsNullOrEmpty(loccd) ? null : (int.TryParse(loccd, out var lc) ? lc : null),
                Ref = string.IsNullOrEmpty(@ref) ? null : @ref
            };

            var exitUrl = launcher.BuildExitUrl(launchContext);

            if (gw.ChkSysLock(s)) return Results.Json(new { blocked = "System is Locked" });

            // FnRights: no rights for this module -> btnexit_Click
            if (!env.IsDevelopment() && string.IsNullOrEmpty(gw.UserRights(s, s.MainModCode, s.MainSubModCode)))
                return Results.Json(new { exitUrl, forceExit = true });

            var messages = gw.GetMessages(s).GroupBy(m => m.MsgSrno).ToDictionary(g => g.Key, g => g.First().MsgDesc.Trim());
            ctx.Session.SetString(MsgKey, JsonSerializer.Serialize(messages));

            var ptnTypes = gw.GetPtnTypListByUser(s);
            string? ptnTypeError = ptnTypes is null ? "User do not have access to any of the patient type." : null;
            var defPtnTyp = ptnTypes?.FirstOrDefault(p => p.DefAccess)?.PtnTypCd;

            var rule9278 = gw.GetRule(s, 9278);

            return Results.Json(new
            {
                header = new
                {
                    company = s.CompanyName, division = s.DivisionName, location = s.LocationName,
                    user = s.UserNickName, appName = string.IsNullOrEmpty(s.AppName) ? "NURSE STATION" : s.AppName,
                    clientImg = config["Legacy:ClientImg"], sofImg = config["Legacy:SofImg"], bottomText = config["Legacy:BottomText"],
                },
                exitUrl,
                messages,
                ptnTypeError,
                ptnTypes = ptnTypes?.Select(p => new { code = p.PtnTypCd, desc = p.PtnTypDesc }),
                defaultPtnTyp = defPtnTyp,
                showMrd = SafeGet(() => gw.GetMrdRecords(s)) == 1,
                defaultView = rule9278?.Data1 == "Y" ? "C" : "G",
                preselectIpNo = s.InpatientNo,
                menu = SimplifiedModuleLauncher.Modules.Select(m => new { key = m.Key, title = m.Title }),
                menuVisible = launcher.MenuVisibility(s),
                // Client = load the whole list once and filter/search in the browser; Server = query per filter change.
                filterMode = string.Equals(config["Tablet:FilterMode"], "Server", StringComparison.OrdinalIgnoreCase) ? "Server" : "Client",
                autoRefreshSeconds = config.GetValue("Tablet:AutoRefreshSeconds", 120),
                // Scopes the browser's cached list to this user + location (never shared between users on one tablet).
                cacheKey = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(
                    System.Text.Encoding.UTF8.GetBytes($"{s.UserId}|{s.CompanyCode}|{s.Div}|{s.Loc}")))[..16],
                // Colours come from the suite stylesheets this installation serves (same as CSS_serverpath);
                // empty = the copies bundled in wwwroot/CSS. Theme:Colors entries override individual tokens.
                theme = new
                {
                    cssPath = string.IsNullOrWhiteSpace(config["Theme:CssPath"]) ? "CSS" : config["Theme:CssPath"]!.TrimEnd('/'),
                    colors = config.GetSection("Theme:Colors").GetChildren()
                        .Where(c => !string.IsNullOrWhiteSpace(c.Value))
                        .ToDictionary(c => c.Key, c => c.Value),
                },
            });
        });

        // SearchResult(True)
        api.MapPost("/patients", (HttpContext ctx, PatientSearch q, NsRepository gw) =>
        {
            var s = ctx.Session.GetNs()!;
            var rows = gw.GetPatients(s, q, 0, gw.GetRevenueDate(s));
            ctx.Session.SetString(RowsKey, JsonSerializer.Serialize(rows));
            return Results.Json(new { rows, total = rows.Count, fetchedAt = DateTime.Now.ToString("o") });
        });

        // Latest discharge-advice detail (who / when / remark) for the given patients, from the dschg_adv table.
        api.MapPost("/advice", (HttpContext ctx, AdviceRequest r, NsRepository gw) =>
        {
            var advice = gw.GetDischargeAdvice(r.IpNos ?? Array.Empty<long>());
            return Results.Json(new { advice });
        });

        // getWardByContentSearch / getDocByContentSearch / getSpcltyByContentSearch / getFlrByContentSearch
        api.MapGet("/lookup/{type}", (HttpContext ctx, string type, string? prefix, NsRepository gw) =>
        {
            var s = ctx.Session.GetNs()!;
            prefix = (prefix ?? "").Trim();

            Func<string, List<(string Code, string Desc)>>? source = type switch
            {
                "ward" => p => gw.SearchCodeDecode(s, NsRepository.CodeWard, p).Select(c => (c.Code.ToString(), (c.Decode ?? "").Trim().ToUpper())).ToList(),
                "speciality" => p => gw.SearchCodeDecode(s, NsRepository.CodeDoctorSpeciality, p).Select(c => (c.Code.ToString(), (c.Decode ?? "").Trim().ToUpper())).ToList(),
                "doctor" => p => gw.SearchDoctors(s, p).Select(d => (d.DoctorCode.ToString(), (d.DoctorFullName ?? "").Trim().ToUpper())).ToList(),
                _ => null,
            };
            if (source is null) return Results.Json(Array.Empty<object>());

            // The procedures match on name only; the box says "Code / Name", so numeric text also matches the code.
            var found = source(prefix);
            if (prefix.Length > 0 && prefix.All(char.IsDigit))
                found = source("").Where(x => x.Code.StartsWith(prefix)).Concat(found).ToList();

            return Results.Json(found.Where(x => x.Desc.Length > 0)
                .DistinctBy(x => x.Code).Take(300)
                .Select(x => new { code = x.Code, desc = x.Desc }));
        });

        // Location link -> PATIENT TRACKING page: the patient's ward events and the current (pending) event.
        api.MapGet("/tracking", (HttpContext ctx, long ipNo, NsRepository gw) =>
        {
            var s = ctx.Session.GetNs()!;
            var row = FindRow(ctx, ipNo);
            if (row is null) return Results.Json(new { ok = false, message = "Patient not found. Please refresh the list." });
            return Results.Json(new { ok = true, tracking = TrackingPayload(s, gw, row) });
        });

        // PATIENT TRACKING -> SAVE: record the actual date / time / remark of the current event.
        api.MapPost("/tracking/save", (HttpContext ctx, TrackSaveRequest r, NsRepository gw) =>
        {
            var s = ctx.Session.GetNs()!;
            var row = FindRow(ctx, r.IpNo);
            if (row is null) return Results.Json(new { ok = false, message = "Patient not found. Please refresh the list." });

            var ci = System.Globalization.CultureInfo.InvariantCulture;
            if (!DateTime.TryParseExact(r.Date, "yyyy-MM-dd", ci, System.Globalization.DateTimeStyles.None, out var date))
                return Results.Json(new { ok = false, message = "Please enter the actual date." });
            if (!TimeSpan.TryParseExact(r.Time, "hh\\:mm", ci, out var time))
                return Results.Json(new { ok = false, message = "Please enter the actual time." });
            var at = date.Date + time;
            if (at > DateTime.Now.AddMinutes(1))
                return Results.Json(new { ok = false, message = "Actual date / time cannot be in the future." });

            var events = gw.GetTracking(s, r.IpNo);
            var current = NsRepository.CurrentEvent(events);
            if (current is null || current.RecId != r.RecId || current.EventId != r.EventId)
                return Results.Json(new { ok = false, message = "This event is no longer pending. Please reopen the patient.", tracking = TrackingPayload(s, gw, row) });

            var prev = NsRepository.PreviousActual(events, current);
            if (prev is not null && at < prev.Value)
                return Results.Json(new { ok = false, message = "Actual date / time cannot be earlier than the previous event (" + prev.Value.ToString("dd/MM/yyyy HH:mm", ci) + ")." });

            if (gw.ChkSysLock(s)) return Results.Json(new { ok = false, message = msgOrDefault(ctx, 2, "System is Locked") });
            if (!gw.SaveTracking(s, r.IpNo, current, date, time, (r.Remark ?? "").Trim()))
                return Results.Json(new { ok = false, message = "This event is no longer pending. Please reopen the patient.", tracking = TrackingPayload(s, gw, row) });

            row.LocName = current.LocName;
            UpdateRow(ctx, row);
            return Results.Json(new { ok = true, message = current.EventName + " saved for " + row.PatientFullName.Trim() + ".", row, tracking = TrackingPayload(s, gw, row) });
        });

        // btnRowSet_Click — runs when a row is selected; decides whether the menu may open.
        api.MapPost("/rowselect", (HttpContext ctx, IpRequest r, LosService los) =>
        {
            var s = ctx.Session.GetNs()!;
            var row = FindRow(ctx, r.IpNo);
            if (row is null) return Results.Json(new LosGateResult());
            return Results.Json(los.Evaluate(s, row));
        });

        // btnConfirm_Click
        api.MapPost("/los/confirm", (HttpContext ctx, IpRequest r, LosService los) =>
            Results.Json(los.Confirm(ctx.Session.GetNs()!, r.IpNo)));

        // btnSkip_Click
        api.MapPost("/los/skip", (HttpContext ctx, SkipRequest r, LosService los) =>
            Results.Json(los.Skip(ctx.Session.GetNs()!, r.IpNo, r.SkipLeft)));

        // txtNewLOS_TextChanged
        api.MapPost("/los/preview", (HttpContext ctx, ExtendRequest r, NsRepository gw) =>
        {
            var row = FindRowEnsured(ctx, gw, r.IpNo);
            if (row is null || !int.TryParse(r.NewLos?.Trim(), out var days)) return Results.Json(new { text = "" });
            var dt = LosService.PreviewDischarge(row, r.CurrentLos, days);
            return Results.Json(new { text = dt is null ? "" : dt.Value.ToString("dd/MM/yyyy") + "   " + dt.Value.ToString("HH:mm") });
        });

        // btnExtendLOS_Click
        api.MapPost("/los/extend", (HttpContext ctx, ExtendRequest r, LosService los, NsRepository gw) =>
        {
            var row = FindRowEnsured(ctx, gw, r.IpNo);
            if (row is null) return Results.Json(new LosActionResult(false, "Ip number not found"));
            var result = los.Extend(ctx.Session.GetNs()!, row, r.CurrentLos, r.NewLos ?? "", Messages(ctx));
            if (result.Ok && result.Row is not null) UpdateRow(ctx, result.Row);
            return Results.Json(result);
        });

        // DFS_Click, MD_Click, ipass_Click, NCP_Click, lnkNrsngAstApp_Click, lnkdailyprgsnts_Click
        // Simplified: just return the URL with LaunchContext preserved; client opens it (new tab/window/iframe as needed)
        api.MapPost("/open", async (HttpContext ctx, OpenRequest r, SimplifiedModuleLauncher launcher, NsRepository gw, LegacyEmrBridge bridge) =>
        {
            var s = ctx.Session.GetNs()!;
            if (s.IsDevSession)
                s.RequestParameter = LegacyRef.Build(s, s.UserNickName, gw.GetActiveLogSrNo(s.UserId));

            // Extract LaunchContext from query parameters
            var modcd = ctx.Request.Query["modcd"].ToString();
            var submodcode = ctx.Request.Query["submodcode"].ToString();
            var user = ctx.Request.Query["user"].ToString();
            var location = ctx.Request.Query["location"].ToString();
            var cocd = ctx.Request.Query["cocd"].ToString();
            var divcd = ctx.Request.Query["divcd"].ToString();
            var loccd = ctx.Request.Query["loccd"].ToString();
            var @ref = ctx.Request.Query["ref"].ToString();

            var launchContext = new LaunchContext
            {
                ModCd = string.IsNullOrEmpty(modcd) ? null : modcd,
                SubModCode = string.IsNullOrEmpty(submodcode) ? null : submodcode,
                User = string.IsNullOrEmpty(user) ? null : user,
                Location = string.IsNullOrEmpty(location) ? null : location,
                CoCd = string.IsNullOrEmpty(cocd) ? null : cocd,
                DivCd = string.IsNullOrEmpty(divcd) ? null : (int.TryParse(divcd, out var dv) ? dv : null),
                LocCd = string.IsNullOrEmpty(loccd) ? null : (int.TryParse(loccd, out var lc) ? lc : null),
                Ref = string.IsNullOrEmpty(@ref) ? null : @ref
            };

            var row = FindRowEnsured(ctx, gw, r.IpNo);
            // The client tapped a specific patient row, so it already knows the IP / patient number. If the
            // server-side list can't resolve the row (stale/empty session after a timeout), use the numbers the
            // client sent — so a real selection never turns into a confusing "Please select any record." popup.
            var ipNo = row?.IpNo ?? r.IpNo;
            var ptnNo = row?.PatientNo ?? r.PtnNo;

            // EMR modules: without a local signing secret, the legacy Nurse Station page issues the signed link.
            string? bridged = null;
            var emrAction = SimplifiedModuleLauncher.EmrAction(r.Key);
            if (emrAction is not null && ipNo != 0 && !launcher.HasSsoSecret)
            {
                // Cold start (right after a deployment / app-pool recycle): the legacy page may still be warming
                // up, so the first attempt can come back empty. Retry briefly instead of giving up — this makes
                // the FIRST tap open the real signed module rather than closing with a "try again" message.
                for (var attempt = 0; attempt < 3 && bridged is null; attempt++)
                {
                    if (attempt > 0) await Task.Delay(500);
                    bridged = await bridge.GetEmrUrlAsync(s, ipNo, emrAction);
                }
            }

            var result = launcher.Build(s, launchContext, r.Key, ipNo, ptnNo, Messages(ctx), bridged);
            if (result.Ok && !r.Prefetch) s.InpatientNo = ipNo.ToString();      // a prefetch must not change which patient is remembered
            ctx.Session.SetNs(s);
            return Results.Json(result);
        });

        api.MapPost("/prefetch", async (HttpContext ctx, PrefetchRequest r, SimplifiedModuleLauncher launcher, NsRepository gw, LegacyEmrBridge bridge) =>
        {
            var s = ctx.Session.GetNs()!;
            if (s.IsDevSession)
                s.RequestParameter = LegacyRef.Build(s, s.UserNickName, gw.GetActiveLogSrNo(s.UserId));

            var row = FindRowEnsured(ctx, gw, r.IpNo);
            if (row is null) return Results.Json(new { links = Array.Empty<PrefetchLink>() });

            var launchContext = new LaunchContext();
            var msg = Messages(ctx);
            var tasks = r.Keys.Select(async key =>
            {
                string? bridged = null;
                var emrAction = SimplifiedModuleLauncher.EmrAction(key);
                if (emrAction is not null && !launcher.HasSsoSecret)
                    bridged = await bridge.GetEmrUrlAsync(s, row.IpNo, emrAction);

                var result = launcher.Build(s, launchContext, key, row.IpNo, row.PatientNo, msg, bridged);
                return new PrefetchLink(key, result.Ok ? result.Url : null);
            }).ToArray();

            var links = await Task.WhenAll(tasks);
            return Results.Json(new { links });
        });
    }

    // ---------------- helpers ----------------

    private static Func<int, string> Messages(HttpContext ctx)
    {
        var json = ctx.Session.GetString(MsgKey);
        var dict = json is null ? new Dictionary<int, string>() : JsonSerializer.Deserialize<Dictionary<int, string>>(json)!;
        return n => dict.TryGetValue(n, out var m) && !string.IsNullOrEmpty(m) ? m : FallbackMessages.GetValueOrDefault(n, "");
    }

    private static List<PatientRow> Rows(HttpContext ctx)
    {
        var json = ctx.Session.GetString(RowsKey);
        return json is null ? new() : JsonSerializer.Deserialize<List<PatientRow>>(json)!;
    }

    private static object TrackingPayload(NsSession s, NsRepository gw, PatientRow row)
    {
        var ci = System.Globalization.CultureInfo.InvariantCulture;
        var events = gw.GetTracking(s, row.IpNo);
        var current = NsRepository.CurrentEvent(events);
        var prev = current is null ? null : NsRepository.PreviousActual(events, current);
        var now = DateTime.Now;
        return new
        {
            patient = new
            {
                ipNo = row.IpNo,
                patientNo = row.PatientNo,
                name = row.PatientFullName.Trim(),
                ageGender = (row.Age ?? "").Trim() + " / " + row.Gender,
                cls = row.PtnClass,
                bedNo = row.BedNo,
                ward = row.WardDCd,
                doctor = (row.DoctorName ?? "").Trim(),
                status = row.DschrgSts == "Not Discharge" ? "ADMITTED" : (row.DschrgSts ?? "").ToUpperInvariant(),
                admDate = row.AdmDtTm,
            },
            events = events.Select(e => new
            {
                recId = e.RecId, eventId = e.EventId, eventName = e.EventName, pending = !e.IsMarked, remark = e.Remark,
                date = e.At?.ToString("dd/MM/yyyy", ci), time = e.At?.ToString("hh:mm tt", ci),
            }),
            current = current is null ? null : new { recId = current.RecId, eventId = current.EventId, eventName = current.EventName, locName = current.LocName },
            nowDate = now.ToString("yyyy-MM-dd", ci),
            nowTime = now.ToString("HH:mm", ci),
            minAt = prev?.ToString("yyyy-MM-dd'T'HH:mm", ci),
        };
    }

    private static string msgOrDefault(HttpContext ctx, int n, string fallback) =>
        Messages(ctx)(n) is { Length: > 0 } m ? m : fallback;

    private static PatientRow? FindRow(HttpContext ctx, long ipNo) => Rows(ctx).FirstOrDefault(r => r.IpNo == ipNo);

    // The session's row list can be empty after a session timeout, or on a fresh server session while the
    // browser still shows its cached list. On a miss, reload the list from the database (the same neutral
    // query the client's initial load uses) so opening a module / LOS action never fails with
    // "Please select any record" just because the server-side list had not been (re)populated yet.
    private static PatientRow? FindRowEnsured(HttpContext ctx, NsRepository gw, long ipNo)
    {
        var row = FindRow(ctx, ipNo);
        if (row is not null) return row;
        var s = ctx.Session.GetNs();
        if (s is null) return null;
        try
        {
            var rows = gw.GetPatients(s, new PatientSearch(), 0, gw.GetRevenueDate(s));
            ctx.Session.SetString(RowsKey, JsonSerializer.Serialize(rows));
            return rows.FirstOrDefault(r => r.IpNo == ipNo);
        }
        catch { return null; }
    }

    private static void UpdateRow(HttpContext ctx, PatientRow row)
    {
        var rows = Rows(ctx);
        var i = rows.FindIndex(r => r.IpNo == row.IpNo);
        if (i >= 0) rows[i] = row;
        ctx.Session.SetString(RowsKey, JsonSerializer.Serialize(rows));
    }

    private static int SafeGet(Func<int> f)
    {
        try { return f(); } catch { return 0; }
    }

    public sealed record IpRequest(long IpNo);
    public sealed record AdviceRequest(long[] IpNos);
    public sealed record TrackSaveRequest(long IpNo, long RecId, int EventId, string? Date, string? Time, string? Remark);
    public sealed record SkipRequest(long IpNo, int SkipLeft);
    public sealed record ExtendRequest(long IpNo, int CurrentLos, string? NewLos);
    public sealed record OpenRequest(string Key, long IpNo, long PtnNo = 0, bool Prefetch = false);
    public sealed record PrefetchRequest(long IpNo, string[] Keys);
    public sealed record PrefetchLink(string Key, string? Url);
}
