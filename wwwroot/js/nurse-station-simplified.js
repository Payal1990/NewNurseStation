/* =====================================================================
   Nurse Station — Simplified tablet client (PatientQuery pattern).

   Key differences from complex iframe/window management:
   - No iframe/window state management
   - Modules open as direct navigation (new tab/window or inline, per config)
   - Exit is a simple redirect to the host dashboard
   - LaunchContext preserved through all module URLs
   ===================================================================== */
(function ($) {
    'use strict';

    var TAP_SLOP = 10;              // px of movement that turns a tap into a scroll
    var TAP_MAX_MS = 700;

    var state = {
        init: null,
        all: null,                  // full list from the server
        rows: [],                   // filtered view that is rendered
        fetchedAt: null,
        offline: false,
        refreshing: null,
        selectedIp: null,
        gate: {},                   // ipNo -> true when LOS gate blocks the menu
        view: 'G',
        loaded: false,
        lastPointerType: 'mouse',
        menuIp: null,
        page: 1,
        links: {},                  // 'ip|key' -> { url, at }: module links prepared in the background
        advice: {},                 // ipNo -> latest discharge-advice detail (from dschg_adv)
        prefSeq: 0,
        prefTimer: null,
        los: null,
        launchContext: {},          // ModCd, SubModCode, User, Location, CoCd, DivCd, LocCd, Ref from init
        watchTimer: null,
    };

    // ------------------------------------------------------------------ utils
    function esc(v) {
        return String(v == null ? '' : v).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    }
    function el(id) { return document.getElementById(id); }
    function msg(n) { return (state.init && state.init.messages && state.init.messages[n]) || ''; }

    function alertMsg(text, cb) {
        if (!text) { if (cb) cb(); return; }
        if (window.alertify && alertify.alert) {
            // Track that a modal alert is open so the background auto-refresh doesn't re-render the grid
            // (a visible "flash") while the user is reading / dismissing it.
            state.alertOpen = (state.alertOpen || 0) + 1;
            alertify.alert(esc(text), function () {
                state.alertOpen = Math.max(0, (state.alertOpen || 1) - 1);
                if (cb) cb();
            });
        }
        else { window.alert(text); if (cb) cb(); }
    }

    var busyCount = 0, busyTimer = null;
    function busy(on) {
        busyCount += on ? 1 : -1;
        if (busyCount > 0 && !busyTimer) busyTimer = setTimeout(function () { el('nsBusy').hidden = false; }, 300);
        if (busyCount <= 0) { busyCount = 0; clearTimeout(busyTimer); busyTimer = null; el('nsBusy').hidden = true; }
    }

    function api(path, body) {
        busy(true);
        return fetch('api/ns/' + withContext(path), {
            method: body === undefined ? 'GET' : 'POST',
            headers: body === undefined ? {} : { 'Content-Type': 'application/json' },
            body: body === undefined ? undefined : JSON.stringify(body),
            credentials: 'same-origin',
            cache: 'no-store',
        }).then(function (r) {
            return r.json().catch(function () { return {}; }).then(function (data) {
                if (r.status === 401 && data.sessionExpired) { location.href = './'; throw new Error('session'); }
                if (!r.ok) throw new Error(data.message || data.title || ('Request failed (' + r.status + ')'));
                return data;
            });
        }).finally(function () { busy(false); });
    }

    function apiQuiet(path, body) {
        return fetch('api/ns/' + withContext(path), {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body), credentials: 'same-origin', cache: 'no-store',
        }).then(function (r) {
            return r.json().catch(function () { return {}; }).then(function (data) {
                if (r.status === 401 && data.sessionExpired) { location.href = './'; throw new Error('session'); }
                if (!r.ok) throw new Error(data.message || ('Request failed (' + r.status + ')'));
                return data;
            });
        });
    }

    function fail(err) { if (err && err.message !== 'session') alertMsg(err.message); }

    function store(key, val) { try { localStorage.setItem(key, JSON.stringify(val)); } catch (e) { } }

    function sset(key, val) { try { sessionStorage.setItem(key, JSON.stringify(val)); } catch (e) { } }
    function sget(key) { try { return JSON.parse(sessionStorage.getItem(key)); } catch (e) { return null; } }
    function dataKey() { return 'ns.data.' + ((state.init && state.init.cacheKey) || 'anon'); }
    function clientMode() { return !state.init || state.init.filterMode !== 'Server'; }
    function load(key) { try { return JSON.parse(localStorage.getItem(key)); } catch (e) { return null; } }

    function rowByIp(ip) {
        for (var i = 0; i < state.rows.length; i++) if (String(state.rows[i].ipNo) === String(ip)) return state.rows[i];
        return null;
    }

    function withContext(path) {
        var q = buildContextQuery();
        return q ? path + (path.indexOf('?') === -1 ? q : '&' + q.slice(1)) : path;
    }

    // Build query string from LaunchContext for API calls
    function buildContextQuery() {
        var parts = [];
        if (state.launchContext.modcd) parts.push('modcd=' + encodeURIComponent(state.launchContext.modcd));
        if (state.launchContext.submodcode) parts.push('submodcode=' + encodeURIComponent(state.launchContext.submodcode));
        if (state.launchContext.user) parts.push('user=' + encodeURIComponent(state.launchContext.user));
        if (state.launchContext.location) parts.push('location=' + encodeURIComponent(state.launchContext.location));
        if (state.launchContext.cocd) parts.push('cocd=' + encodeURIComponent(state.launchContext.cocd));
        if (state.launchContext.divcd) parts.push('divcd=' + encodeURIComponent(state.launchContext.divcd));
        if (state.launchContext.loccd) parts.push('loccd=' + encodeURIComponent(state.launchContext.loccd));
        if (state.launchContext.ref) parts.push('ref=' + encodeURIComponent(state.launchContext.ref));
        return parts.length > 0 ? '?' + parts.join('&') : '';
    }

    // ------------------------------------------------------------------ init (Page_Load)
    function start() {
        document.addEventListener('contextmenu', function (e) { e.preventDefault(); });

        // Break out of legacy iframe/frame to fill the full screen
        try {
            if (window.self !== window.top) {
                window.top.location.href = window.location.href;
                return;
            }
        } catch (e) { /* cross-origin frame — can't break out, continue inside */ }

        var cachedInit = sget('ns.init');
        if (cachedInit) {
            boot(cachedInit);
            var cached = sget(dataKey());
            if (cached && cached.rows) {
                state.all = cached.rows;
                state.fetchedAt = cached.at;
                state.loaded = true;
                applyFilters({ keepScroll: true });
                loadAdvice();
                showSync();
            }
        }

        api('init').then(function (d) {
            sset('ns.init', d);
            // Extract and store LaunchContext from init response
            if (d.launchContext) {
                state.launchContext = d.launchContext;
            }
            if (!cachedInit) { boot(d); search({ refresh: true }); return; }
            state.init = d;
            if (window.NsTheme) NsTheme.load(d.theme);
            if (d.blocked) { alertMsg(d.blocked); return; }
            if (d.forceExit) { exitTo(d.exitUrl); return; }
            search({ refresh: true, keepScroll: true, quiet: true });
        }).catch(function (err) {
            if (cachedInit) { state.offline = true; showSync(); return; }
            fail(err);
        });

        startAutoRefresh();
    }

    function boot(d) {
        state.init = d;
        if (window.NsTheme) NsTheme.load(d.theme);
        if (d.blocked) { alertMsg(d.blocked); return; }
        if (d.forceExit) { exitTo(d.exitUrl); return; }

        fillHeader(d.header);
        fillPatientTypes(d.ptnTypes, d.defaultPtnTyp);
        el('tdmrd').hidden = !d.showMrd;

        state.view = load('ns.view') || (window.matchMedia('(max-width: 700px)').matches ? 'C' : (d.defaultView || 'G'));
        setView(state.view, true);

        if (d.ptnTypeError) { alertMsg(d.ptnTypeError); return; }

        if (d.preselectIpNo) state.selectedIp = String(d.preselectIpNo);
        restoreFilters();
    }

    function fillHeader(h) {
        if (!h) return;
        el('lblClient').textContent = h.company || '';
        el('lblDiv').textContent = h.division || '';
        el('lblLoc').textContent = h.location || '';
        el('lblUser').textContent = h.user || '';
        el('userAvatar').textContent = (h.user || '?').trim().split(/\s+/).map(function (w) { return w[0]; }).join('').slice(0, 2).toUpperCase();
        el('lblAppName').textContent = h.appName || '';
        el('lblBottomText').textContent = h.bottomText || '';
        if (h.clientImg) el('imgClient').src = h.clientImg;
        if (h.sofImg) el('imgSof').src = h.sofImg;
        document.title = 'CARE @ WORKS - ' + (h.appName || 'NURSE STATION');
    }

    function fillPatientTypes(list, def) {
        var ddl = el('ddlPtnTypByUser');
        var html = '<option value="ALL">ALL</option>';
        (list || []).forEach(function (p) { html += '<option value="' + esc(p.code) + '">' + esc(p.desc) + '</option>'; });
        ddl.innerHTML = html;
        ddl.value = def != null ? String(def) : 'ALL';       // the user's default patient type
        if (!ddl.value) ddl.value = 'ALL';
    }

    // ------------------------------------------------------------------ search (SearchResult)
    function criteria() {
        function codeIf(codeId, descId) {
            var c = el(codeId).value.trim(), d = el(descId).value.trim();
            return c !== '' && d !== '' ? Number(c) || 0 : 0;
        }
        var ptn = el('ddlPtnTypByUser').value;
        return {
            wardCd: codeIf('txtWardCd', 'txtWardDesc'),
            docCd: codeIf('txtDocCd', 'txtDocName'),
            spltyCd: codeIf('txtSpecialityCd', 'txtSpecialityDCd'),
            ptnTyp: ptn === 'ALL' ? 0 : Number(ptn) || 0,
            mrdStatus: Number(el('drpmrdsts').value) || 0,
            vulnerable: el('chkIsVuln').checked,
            isolated: el('chkIsIsolated').checked,
            hwc: el('chkHWC').checked,
            arrivedOnBed: el('chkIsArrivedOnBed').checked,
        };
    }

    function search(opts) {
        opts = opts || {};

        if (!clientMode()) {
            return fetchPatients(criteria(), opts).then(function (d) {
                state.all = d.rows || [];
                applyFilters(opts);
                loadAdvice();
            });
        }

        if (state.all && !opts.refresh) {
            applyFilters(opts);
            return Promise.resolve();
        }
        return refreshData(opts);
    }

    var NEUTRAL = { wardCd: 0, docCd: 0, spltyCd: 0, ptnTyp: 0, mrdStatus: 0, vulnerable: false, isolated: false, hwc: false, arrivedOnBed: false };

    function refreshData(opts) {
        if (state.refreshing) return state.refreshing;
        state.refreshing = fetchPatients(NEUTRAL, opts).then(function (d) {
            state.all = d.rows || [];
            state.fetchedAt = d.fetchedAt || new Date().toISOString();
            state.offline = false;
            state.gate = {};
            sset(dataKey(), { at: state.fetchedAt, rows: state.all });
            applyFilters({ keepScroll: true });
            loadAdvice();
        }).catch(function (err) {
            if (err && err.message === 'session') return;
            state.offline = true;
            if (!state.all) { if (!opts || !opts.quiet) fail(err); return; }
            applyFilters({ keepScroll: true });
        }).finally(function () {
            state.refreshing = null;
            showSync();
        });
        return state.refreshing;
    }

    function fetchPatients(q, opts) {
        return (opts && opts.quiet ? apiQuiet('patients', q) : api('patients', q));
    }

    // Fetch the latest discharge-advice detail (who / when / remark) for every patient that has advice given,
    // then repaint so the Patient No. tooltip and the Discharge Advice modal show the real record.
    function loadAdvice() {
        if (!state.all || !state.all.length) { state.advice = {}; return; }
        var ips = state.all.filter(function (x) { return (x.dschgAdvSts || '').toLowerCase() === 'given'; })
                           .map(function (x) { return Number(x.ipNo); });
        if (!ips.length) { state.advice = {}; return; }
        apiQuiet('advice', { ipNos: ips }).then(function (r) {
            var map = {};
            ((r && r.advice) || []).forEach(function (a) { map[a.ipNo] = a; });
            state.advice = map;
            render({ keepScroll: true });
        }).catch(function () { });
    }

    function mrdStatusOf(reqNo) {
        if (!reqNo) return 0;
        var p = String(reqNo).split('_');
        return Number(p[0]) && Number(p[1]) ? Number(p[1]) : 0;
    }

    function applyFilters(opts) {
        if (!state.all) return;
        var c = criteria();
        state.rows = state.all.filter(function (x) {
            if (!clientMode()) return true;
            if (c.wardCd && x.wardCd !== c.wardCd) return false;
            if (c.docCd && x.doctorCd !== c.docCd) return false;
            if (c.spltyCd && Number(x.spltyCd) !== c.spltyCd) return false;
            if (c.ptnTyp && x.ptnTypCd !== c.ptnTyp) return false;
            if (c.vulnerable && !x.isPtnVulnerable) return false;
            if (c.isolated && !x.isIsolated) return false;
            if (c.hwc && !x.hwc) return false;
            if (c.arrivedOnBed && !x.isArrivedOnBed) return false;
            if (c.mrdStatus && mrdStatusOf(x.reqNo) !== c.mrdStatus) return false;
            return true;
        });
        state.loaded = true;
        if (!(opts && opts.keepScroll)) state.page = 1;
        render({ keepScroll: !!(opts && opts.keepScroll) });
    }

    function replaceRow(row) {
        [state.all, state.rows].forEach(function (list) {
            if (!list) return;
            for (var i = 0; i < list.length; i++) if (String(list[i].ipNo) === String(row.ipNo)) list[i] = row;
        });
        if (state.all) sset(dataKey(), { at: state.fetchedAt, rows: state.all });
    }

    function showSync() {
        var at = state.fetchedAt ? new Date(state.fetchedAt) : null;
        var t = at && !isNaN(at) ? at.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : '';
        var b = el('syncBanner');
        if (state.offline && state.all) {
            b.innerHTML = '<b>Offline</b> &mdash; showing the list from ' + esc(t || 'earlier') + '. Server not reachable; retrying automatically. <button type="button" id="syncRetry" class="btn btn-ghost">Retry now</button>';
            b.hidden = false;
            el('syncRetry').onclick = function () { search({ refresh: true, keepScroll: true }); };
        } else {
            b.hidden = true;
        }
    }

    function startAutoRefresh() {
        function due() {
            var secs = (state.init && state.init.autoRefreshSeconds) || 120;
            return !state.fetchedAt || (Date.now() - new Date(state.fetchedAt).getTime()) >= secs * 1000;
        }
        function idle() {
            var a = document.activeElement;
            // Don't refresh while the user is busy with a popup: an open alert, the row menu, or any of the
            // modal panels (LOS, patient tracking, count details). Refreshing re-renders the grid behind them,
            // which shows as a disruptive "flash" — and on a flaky network the online handler can do it repeatedly.
            return document.visibilityState === 'visible' && !state.alertOpen &&
                el('custommenu').hidden && el('losPopup').hidden &&
                (!el('trkPopup') || el('trkPopup').hidden) && (!el('cntPopup') || el('cntPopup').hidden) &&
                !(a && /^(INPUT|SELECT|TEXTAREA)$/.test(a.tagName));
        }
        setInterval(function () {
            if (state.init && (due() || state.offline) && idle()) search({ refresh: true, keepScroll: true, quiet: true });
        }, 15000);
        document.addEventListener('visibilitychange', function () {
            if (document.visibilityState === 'visible' && state.init && due() && idle()) search({ refresh: true, keepScroll: true, quiet: true });
        });
        // Reconnect: only refresh if the data is actually stale/offline AND no popup is open — otherwise a flaky
        // link firing repeated "online" events would flash the grid every few seconds.
        window.addEventListener('online', function () { if (state.init && (due() || state.offline) && idle()) search({ refresh: true, keepScroll: true, quiet: true }); });
    }

    // ------------------------------------------------------------------ filter panel
    var FILTER_CHECKS = ['chkIsVuln', 'chkIsIsolated', 'chkHWC', 'chkIsArrivedOnBed'];
    var FILTER_VALUES = ['txtWardCd', 'txtWardDesc', 'txtDocCd', 'txtDocName', 'txtSpecialityCd', 'txtSpecialityDCd', 'ddlPtnTypByUser', 'drpmrdsts'];

    function syncBoxes() {
        $('.sbox[data-code]').each(function () {
            var inp = this.querySelector('.sbox-in');
            inp.value = el(this.getAttribute('data-desc')).value;
            inp.dataset.sel = inp.value;
        });
    }

    function saveFilters() {
        var f = {};
        FILTER_VALUES.forEach(function (id) { f[id] = el(id).value; });
        FILTER_CHECKS.forEach(function (id) { f[id] = el(id).checked; });
        store('ns.savedFilters', f);
        if (window.alertify && alertify.success) alertify.success('Filters saved');
    }

    function restoreFilters() {
        var f = load('ns.savedFilters');
        if (!f) return;
        FILTER_VALUES.concat(FILTER_CHECKS).forEach(function (id) {
            var e = el(id);
            if (!e || !(id in f)) return;
            if (e.type === 'checkbox') e.checked = !!f[id]; else e.value = f[id];
        });
        if (!el('ddlPtnTypByUser').value) el('ddlPtnTypByUser').value = 'ALL';
        syncBoxes();
    }

    // ------------------------------------------------------------------ rendering
    var ICON = function (src, title) { return '<img class="ns-flag" width="18" height="18" src="Images/' + src + '" title="' + esc(title) + '" alt="' + esc(title) + '" />'; };

    function mrdText(reqNo) {
        if (!reqNo) return 'Not Sent';
        var p = String(reqNo).split('_'), no = Number(p[0]) || 0, st = Number(p[1]) || 0;
        if (!no || !st) return 'Not Sent';
        return { 1: 'Requested', 5: 'Requested', 2: 'Created', 4: 'Returned', 3: 'Rejected' }[st] || '';
    }

    function patientFlags(x) {
        var f =
            (x.isNewAdmission ? '<img class="ns-flag" width="18" height="18" src="Images/Bellimg.png" title="New Admission" alt="New admission" />' : '') +
            (x.isHighRisk ? '<img class="ns-flag" width="18" height="18" src="Images/no.jpg" title="High Risk Patient" alt="High risk" />' : '') +
            (x.hwc ? '<img class="ns-flag" width="18" height="18" src="Images/HWC.png" title="HWC PATIENT" alt="HWC" />' : '') +
            (x.isIsolated ? '<img class="ns-flag" width="18" height="18" src="Images/isolated_ptn_16px.png" title="This Patient is Isolated" alt="Isolated" />' : '') +
            (x.isPtnVulnerable ? '<span class="ns-flag-warn" title="This Patient is Vulnerable">&#9888;</span>' : '');
        return f ? '<span class="ns-flags">' + f + '</span>' : '';
    }

    // Advising doctor name for a discharge-advice record. The advice carries only doc_cd, so when it matches
    // the patient's attending doctor we show that name; otherwise the code (the doctor master isn't loaded here).
    function adviceDoctorName(x, adv) {
        if (adv && adv.docCd && x.doctorCd && Number(adv.docCd) === Number(x.doctorCd)) return String(x.doctorName || '').trim();
        if (adv && adv.docCd) return 'Doctor #' + adv.docCd;
        return String(x.doctorName || '').trim();
    }

    // Icons shown next to the Patient No. — new admission and discharge-advice-given, each with a tooltip.
    // Discharge-advice details (who / when / remark) come from the dschg_adv table via /api/ns/advice.
    function admAdviceMarkers(x) {
        var m = '';
        if (x.isNewAdmission) {
            var adm = (x.admDtTm || '').replace(/\s+/g, ' ').trim();
            var t = 'New admission' + (adm ? ' • Admitted ' + adm : '') + (x.doctorName ? ' • Dr ' + String(x.doctorName).trim() : '');
            m += '<img class="ns-mark" width="16" height="16" src="Images/Bellimg.png" title="' + esc(t) + '" alt="New admission" />';
        }
        if ((x.dschgAdvSts || '').toLowerCase() === 'given') {
            var adv = state.advice[x.ipNo];
            var parts = ['Discharge advice given'];
            if (adv && adv.adviceDateTime) parts.push(adv.adviceDateTime);
            var dn = adviceDoctorName(x, adv);
            if (dn) parts.push('By ' + dn);
            if (adv && adv.remark) parts.push('“' + adv.remark + '”');
            m += '<img class="ns-mark" width="16" height="16" src="Images/yes.jpg" title="' + esc(parts.join(' • ')) + '" alt="Discharge advice given" />';
        }
        return m ? ' <span class="ns-pn-marks">' + m + '</span>' : '';
    }

    function columns() {
        var cols = [
            { h: 'SEL', cls: 'ns-sel', stk: 'ns-sticky-col', r: function (x) { return '<input type="checkbox" tabindex="-1" aria-label="Select"' + (String(x.ipNo) === String(state.selectedIp) ? ' checked' : '') + ' />'; } },
            { h: 'PATIENTS NAME', zone: 'menu', cls: 'ns-name', stk: 'ns-sticky-col2', r: function (x) { return '<span class="ns-nm">' + esc(x.patientFullName) + '</span>' + patientFlags(x); } },
            { h: 'IP NO', zone: 'menu', stk: 'ns-sticky-col3', cls: function (x) { return x.folioClosed ? 'folio' : ''; }, title: function (x) { return x.folioClosed ? 'Final Bill is Prepared And Folio is Closed.' : ''; }, r: function (x) { return esc(x.ipNo); } },
            { h: 'PATIENT NO', zone: 'menu', stk: 'ns-sticky-col4', r: function (x) { return '<span class="ns-pn">' + esc(x.patientNo) + '</span>' + admAdviceMarkers(x); } },
            { h: 'BLOOD GROUP', r: function (x) { return esc(x.bloodGroup); } },
            { h: 'LOCATION', r: function (x) { return x.locName ? '<span class="lnkmark" data-zone="loc" role="button" title="Tap to view / mark patient location">' + esc(x.locName) + '</span>' : ''; } },
            { h: 'AGE TYPE', r: function (x) { return esc(x.ageType); } },
            { h: 'AGE', r: function (x) { return esc(x.age); } },
            { h: 'GENDER', r: function (x) { return esc(x.gender); } },
            { h: 'PRV BMI', r: function (x) { return esc(x.lastBmiIndex); } },
            { h: 'BED NO', r: function (x) { return esc(x.bedNo); } },
            { h: 'BED TYPE', r: function (x) { return esc(x.bedTypDesc); } },
            { h: 'MOBILE NO', r: function (x) { return esc(x.mobile); } },
            { h: 'DOCTOR NAME', cls: 'wrap', r: function (x) { return esc(x.doctorName); } },
            { h: 'WARD NAME', cls: 'wrap', r: function (x) { return esc(x.wardDCd); } },
            { h: 'DSCHRG STATUS', r: function (x) { return esc(x.dschrgSts); } },
        ];
        if (state.init && state.init.showMrd) cols.push({ h: 'MRD STATUS', r: function (x) { return esc(mrdText(x.reqNo)); } });
        cols.push(
            { h: 'ADM DATE & TIME', r: function (x) { return esc(x.admDtTm); } },
            { h: 'PATIENT CLASS', r: function (x) { return esc(x.ptnClass); } },
            { h: 'CREDIT COMPANY', cls: 'wrap', r: function (x) { return esc(x.creditCompany); } },
            { h: 'PATIENT SOURCE', r: function (x) { return esc(x.ptnSrc); } },
            { h: 'ROOM NAME', r: function (x) { return esc(x.roomName); } },
            { h: 'PATIENT TYPE', r: function (x) { return esc(x.ptnTypDesc); } },
            { h: 'NO DUES', r: function (x) { return x.noDues ? ICON('No_due_bill.png', 'This Patient is Marked with No Due clearance.') : ''; } },
            { h: 'DIET ASSIGNED', r: function (x) { return x.isDietAssigned ? ICON('diet-meal-24px.png', 'Diet Assigned to this patient.') : ''; } },
            { h: 'NEWLY ADMITTED', r: function (x) { return x.isNewAdmission ? ICON('Bellimg.png', 'New Admission') : ''; } },
            { h: 'OT BOOKED', r: function (x) { return x.otBooked ? ICON('ImgRd.jpg', 'OT Booked') : ''; } },
            { h: 'OT CLEARANCE', r: function (x) { return esc(x.otClearance); } },
            { h: 'E.LOS', r: function (x) { return '<span class="los-link" data-zone="los" role="button" title="Tap to extend length of stay">' + esc(x.los) + '</span>'; } },
            { h: 'A.LOS', r: function (x) { return esc(x.aLos); } }
        );
        return cols;
    }

    function searchKey(x) {
        return [x.patientFullName, x.ipNo, x.patientNo].join(' ').toLowerCase();
    }

    function rowHtml(x, cols) {
        var sel = String(x.ipNo) === String(state.selectedIp);
        var rowCls = [];
        if (sel) rowCls.push('Setrow-highlight');
        if (x.folioClosed) rowCls.push('folio-row');
        var html = '<tr data-ip="' + esc(x.ipNo) + '" data-q="' + esc(searchKey(x)) + '"' + (rowCls.length ? ' class="' + rowCls.join(' ') + '"' : '') + '>';
        cols.forEach(function (c) {
            var cls = ((typeof c.cls === 'function' ? c.cls(x) : (c.cls || '')) + ' ' + (c.stk || '')).trim();
            var title = c.title ? c.title(x) : '';
            html += '<td' + (cls ? ' class="' + cls + '"' : '') + (c.zone ? ' data-zone="' + c.zone + '"' : '') + (title ? ' title="' + esc(title) + '"' : '') + '>' + c.r(x) + '</td>';
        });
        return html + '</tr>';
    }

    function render(opts) {
        var wrapG = el('pnlgrdview'), wrapC = el('pnlcardview');
        var keep = opts && opts.keepScroll;
        var sg = { t: wrapG.scrollTop, l: wrapG.scrollLeft }, sc = { t: wrapC.scrollTop };

        var cols = columns();
        el('grdInPatientDtl').tHead.innerHTML = '<tr>' + cols.map(function (c) {
            return '<th' + (c.stk ? ' class="' + c.stk + '"' : '') + '>' + esc(c.h) + '</th>';
        }).join('') + '</tr>';
        var list = matchedRows();
        var pages = Math.max(1, Math.ceil(list.length / PAGE_SIZE));
        if (state.page > pages) state.page = pages;
        if (state.page < 1) state.page = 1;
        var from = (state.page - 1) * PAGE_SIZE;
        el('grdInPatientDtl').tBodies[0].innerHTML = list.slice(from, from + PAGE_SIZE).map(function (x) { return rowHtml(x, cols); }).join('');
        el('gridEmpty').hidden = list.length > 0;
        el('lblTotalCount').textContent = list.length;
        renderSummary(list);
        renderPager(list.length, pages, from);

        renderCards(list.slice(from, from + PAGE_SIZE));

        if (keep) { wrapG.scrollTop = sg.t; wrapG.scrollLeft = sg.l; wrapC.scrollTop = sc.t; }
        else { wrapG.scrollTop = 0; wrapG.scrollLeft = 0; wrapC.scrollTop = 0; }
    }

    function renderCards(list) {
        var byWard = [], idx = {};
        list.forEach(function (x) {
            if (!(x.wardCd in idx)) { idx[x.wardCd] = byWard.length; byWard.push({ w: x, list: [] }); }
            byWard[idx[x.wardCd]].list.push(x);
        });

        function genderBadge(gender) {
            var m = { male: ['M', 'male', 'Male'], female: ['F', 'female', 'Female'], transgender: ['T', 'trans', 'Transgender'] }[(gender || '').toLowerCase()];
            return m ? '<span class="gbadge ' + m[1] + '" title="' + m[2] + '">' + m[0] + '</span>' : '';
        }

        function field(label, value) {
            return '<div class="kvc"><span>' + label + '</span><b>' + (value === '' || value == null ? '&mdash;' : value) + '</b></div>';
        }

        var showMrd = state.init && state.init.showMrd;
        var html = byWard.map(function (g) {
            var w = g.w;
            var cards = g.list.map(function (x) {
                var sel = String(x.ipNo) === String(state.selectedIp);
                var flags =
                    (x.hwc ? ICON('HWC.png', 'HWC') : '') +
                    (x.isNewAdmission ? ICON('Bellimg.png', 'New Admitted Patient') : '') +
                    (x.isHighRisk ? ICON('no.jpg', 'High Risk Patient') : '') +
                    ((x.dschgAdvSts || '').toLowerCase() === 'given' ? ICON('yes.jpg', 'Discharge Advice Given') : '') +
                    (x.isIsolated ? ICON('isolated_ptn_16px.png', 'This Patient is Isolated') : '') +
                    (x.locName ? '<span class="lnkmark" data-zone="loc" role="button">' + esc(x.locName) + '</span>' : '') +
                    (x.folStsCd === 2 ? '<span class="tag tag-folio" title="Folio Closed">Folio closed</span>' : '');
                return '<div class="row_dd2' + (sel ? ' selected' : '') + (x.folioClosed ? ' folio-card' : '') + '" data-ip="' + esc(x.ipNo) + '" data-q="' + esc(searchKey(x)) + '">' +
                    '<div class="pc-head">' +
                        '<div class="pc-title" data-zone="menu"><div class="ns-name">' + esc(x.patientFullName) + '</div>' +
                        '<div class="pc-sub">IP <b>' + esc(x.ipNo) + '</b> &middot; Ptn <b>' + esc(x.patientNo) + '</b></div></div>' +
                        '<div class="pc-bed"><small>Bed</small>' + (esc(x.bedNo) || '&mdash;') + '</div>' +
                    '</div>' +
                    '<div class="pc-doc" title="' + esc('Doctor (' + (x.spltyDesc || '') + ')') + '">' + genderBadge(x.gender) + '<span>' + esc(x.doctorName) + '</span></div>' +
                    '<div class="pc-grid">' +
                        field('Age', esc(x.age)) +
                        field('Bed type', esc(x.bedTypDesc)) +
                        field('Class', esc(x.ptnClass)) +
                        field('Mobile', esc(x.mobile)) +
                        field('Admitted', esc(x.admDtTm)) +
                        (showMrd ? field('MRD', esc(mrdText(x.reqNo))) : field('Type', esc(x.ptnTypDesc))) +
                    '</div>' +
                    (flags ? '<div class="pc-flags">' + flags + '</div>' : '') +
                    '</div>';
            }).join('');

            var stats = [['Blood req.', w.bloodReqCount], ['Lab req.', w.labReqCount], ['Radiology req.', w.radReqCount],
                         ['Procedure req.', w.procReqCount], ['Medicine req.', w.medReqCount], ['Ward req.', w.wardReqCount],
                         ['VIP patients', w.vipPtnCount], ['Sample rejected', w.sampleRejPtnCount], ['Credit company', w.crdCmpPtnCount]];

            return '<section class="ns-ward">' +
                '<div class="ns-ward-title">' + esc(w.wardDCd) + ' &middot; ' + g.list.length + '</div>' +
                '<div class="ns-ward-stats">' + stats.map(function (r) {
                    var n = r[1] == null ? 0 : r[1];
                    return '<div class="stat' + (Number(n) > 0 ? '' : ' zero') + '"><b>' + esc(n) + '</b><span>' + r[0] + '</span></div>';
                }).join('') + '</div>' +
                '<div class="ns-cards">' + cards + '</div>' +
                '</section>';
        }).join('');
        el('pnlcardview').innerHTML = html || '<div class="ns-empty">No Results Found</div>';
    }

    // ------------------------------------------------------------------ summary counts + details modal
    var SUMMARY = [
        { key: 'new',   label: 'New Admission',      icon: 'Bellimg.png',           test: function (x) { return x.isNewAdmission; } },
        { key: 'adv',   label: 'Discharge Advice',   icon: 'yes.jpg',               test: function (x) { return (x.dschgAdvSts || '').toLowerCase() === 'given'; } },
        { key: 'rd',    label: 'Ready to Discharge', icon: 'ImgRd.jpg',             test: function (x) { return x.readyToDschrge; } },
        { key: 'plan',  label: 'Discharge Planning', icon: 'ImgRd.jpg',             test: function (x) { return x.dschgPlanning; } },
        { key: 'high',  label: 'High Risk',          icon: 'no.jpg',                test: function (x) { return x.isHighRisk; } },
        { key: 'iso',   label: 'Isolated',           icon: 'isolated_ptn_16px.png', test: function (x) { return x.isIsolated; } },
        { key: 'folio', label: 'Folio Closed',       swatchClass: 'folio',          test: function (x) { return x.folioClosed; } }
    ];

    function renderSummary(list) {
        var box = el('nsSummary');
        if (!box) return;
        box.innerHTML = SUMMARY.map(function (c) {
            var n = 0;
            for (var i = 0; i < list.length; i++) if (c.test(list[i])) n++;
            var ic = c.swatchClass ? '<i class="swatch ' + c.swatchClass + '"></i>' : '<img src="Images/' + c.icon + '" width="16" height="16" alt="" />';
            return '<button type="button" class="ns-sum-chip' + (n ? '' : ' zero') + '" data-cat="' + c.key + '"' + (n ? '' : ' disabled') + ' title="' + esc(c.label + ': ' + n) + '">' +
                ic + '<span class="ns-sum-label">' + esc(c.label) + '</span><b class="ns-sum-n">' + n + '</b></button>';
        }).join('');
    }

    function openCountModal(key) {
        var cat = null;
        for (var i = 0; i < SUMMARY.length; i++) if (SUMMARY[i].key === key) cat = SUMMARY[i];
        if (!cat) return;
        var list = matchedRows().filter(cat.test);
        el('cntTitle').textContent = cat.label;
        el('cntCount').textContent = list.length + (list.length === 1 ? ' patient' : ' patients');
        var isAdv = key === 'adv';
        var detailHead = key === 'new' ? 'Admitted' : (isAdv ? 'Advised On' : 'Status');
        var docHead = isAdv ? 'Advised By' : 'Doctor';
        var extraHead = isAdv ? '<th>Remark</th>' : '';
        el('cntBody').innerHTML = list.length
            ? '<table class="cnt-table"><thead><tr><th>Patient</th><th>IP No</th><th>Bed</th><th>Ward</th><th>' + docHead + '</th><th>' + detailHead + '</th>' + extraHead + '</tr></thead><tbody>' +
                list.map(function (x) {
                    var adv = state.advice[x.ipNo];
                    var doctor = isAdv ? adviceDoctorName(x, adv) : (x.doctorName || '').trim();
                    var detail = key === 'new' ? (esc((x.admDtTm || '').replace(/\s+/g, ' ').trim()) || '&mdash;')
                               : isAdv ? (esc((adv && adv.adviceDateTime) || '') || '&mdash;')
                               : esc(x.dschrgSts || '');
                    var extra = isAdv ? '<td>' + (esc((adv && adv.remark) || '') || '&mdash;') + '</td>' : '';
                    return '<tr data-ip="' + esc(x.ipNo) + '" tabindex="0"><td class="cnt-nm">' + esc(x.patientFullName) + '</td><td>' + esc(x.ipNo) +
                        '</td><td>' + (esc(x.bedNo) || '&mdash;') + '</td><td>' + (esc(x.wardDCd) || '&mdash;') + '</td><td>' + (esc(doctor) || '&mdash;') +
                        '</td><td>' + detail + '</td>' + extra + '</tr>';
                }).join('') + '</tbody></table>'
            : '<div class="ns-empty">No patients in this category.</div>';
        el('cntOverlay').hidden = false;
        el('cntPopup').hidden = false;
    }

    function hideCountModal() {
        el('cntOverlay').hidden = true;
        el('cntPopup').hidden = true;
    }

    // Jump to a patient's page and select it (used from the count modal).
    function gotoPatient(ip) {
        var list = matchedRows(), idx = -1;
        for (var i = 0; i < list.length; i++) if (String(list[i].ipNo) === String(ip)) { idx = i; break; }
        if (idx >= 0) { state.page = Math.floor(idx / PAGE_SIZE) + 1; render({ keepScroll: false }); }
        selectRow(ip);
    }

    var PAGE_SIZE = 20;

    function matchedRows() {
        var words = el('txtPatientName').value.toLowerCase().trim().split(/\s+/).filter(Boolean);
        if (!words.length) return state.rows;
        return state.rows.filter(function (x) {
            var q = searchKey(x);
            return words.every(function (w) { return q.indexOf(w) !== -1; });
        });
    }

    function applyNameFilter() {
        state.page = 1;
        render({ keepScroll: false });
    }

    function renderPager(total, pages, from) {
        var box = el('gridPager');
        if (total <= PAGE_SIZE) { box.hidden = true; box.innerHTML = ''; return; }
        box.hidden = false;
        var cur = state.page, nums = [];
        for (var p = 1; p <= pages; p++) if (p === 1 || p === pages || Math.abs(p - cur) <= 1) nums.push(p);
        var html = '<span class="pg-info">' + (from + 1) + '&ndash;' + Math.min(from + PAGE_SIZE, total) + ' of ' + total + '</span><div class="pg-btns">' +
            '<button type="button" data-pg="' + (cur - 1) + '"' + (cur === 1 ? ' disabled' : '') + ' aria-label="Previous page">&lsaquo;</button>';
        var last = 0;
        nums.forEach(function (p) {
            if (p - last > 1) html += '<span class="pg-gap">&hellip;</span>';
            html += '<button type="button" data-pg="' + p + '"' + (p === cur ? ' class="on" aria-current="page"' : '') + '>' + p + '</button>';
            last = p;
        });
        html += '<button type="button" data-pg="' + (cur + 1) + '"' + (cur === pages ? ' disabled' : '') + ' aria-label="Next page">&rsaquo;</button></div>';
        box.innerHTML = html;
    }

    function setView(v, silent) {
        state.view = v;
        el('pnlgrdview').hidden = v !== 'G';
        el('pnlcardview').hidden = v !== 'C';
        $('#btnGridview').toggleClass('active', v === 'G');
        $('#btncardview').toggleClass('active', v === 'C');
        store('ns.view', v);
        if (!silent) hideMenu();
    }

    // ------------------------------------------------------------------ selection
    function paintSelection() {
        var ip = String(state.selectedIp);
        $('#grdInPatientDtl tbody tr').each(function () {
            var on = this.getAttribute('data-ip') === ip;
            this.classList.toggle('Setrow-highlight', on);
            var cb = this.querySelector('input[type=checkbox]');
            if (cb) cb.checked = on;
        });
        $('#pnlcardview .row_dd2').each(function () { this.classList.toggle('selected', this.getAttribute('data-ip') === ip); });
    }

    function selectRow(ip) {
        hideMenu();
        state.selectedIp = String(ip);
        paintSelection();

        var seq = state.selectSeq = (state.selectSeq || 0) + 1;
        return apiQuiet('rowselect', { ipNo: Number(ip) }).then(function (g) {
            if (seq !== state.selectSeq || String(state.selectedIp) !== String(ip)) return;
            state.gate[ip] = !!g.blockMenu;
            if (g.showPopup) { hideMenu(); showLos(ip, g); return; }
            if (g.blockMenu) { hideMenu(); return; }
            prefetchLinks(ip);
        }).catch(function (err) {
            if (window.console) console.warn('LOS check failed for IP ' + ip + ':', err && err.message);
        });
    }

    // ------------------------------------------------------------------ tap / click / right-click
    function bindPointer(container, itemSelector) {
        var press = null;

        function cancel() {
            if (press) press.item.classList.remove('ns-pressed');
            press = null;
        }

        container.addEventListener('pointerdown', function (e) {
            state.lastPointerType = e.pointerType || 'mouse';
            if (e.button !== 0) return;
            var item = e.target.closest(itemSelector);
            if (!item) return;
            press = { item: item, target: e.target, x: e.clientX, y: e.clientY, t: Date.now(), type: e.pointerType || 'mouse', id: e.pointerId };
            item.classList.add('ns-pressed');
        });
        container.addEventListener('pointermove', function (e) {
            if (!press || e.pointerId !== press.id) return;
            if (Math.abs(e.clientX - press.x) > TAP_SLOP || Math.abs(e.clientY - press.y) > TAP_SLOP) cancel();
        });
        container.addEventListener('pointercancel', cancel);
        container.addEventListener('pointerup', function (e) {
            if (!press || e.pointerId !== press.id) return;
            var p = press;
            cancel();
            if (Date.now() - p.t > TAP_MAX_MS && p.type === 'mouse') return;
            onTap(p.item, p.target, e.clientX, e.clientY);
        });

        // Right-click (mouse) and press-and-hold (touch) behave like a tap on the same spot.
        container.addEventListener('contextmenu', function (e) {
            e.preventDefault();
            var item = e.target.closest(itemSelector);
            if (item) onTap(item, e.target, e.clientX, e.clientY);
        });
    }

    // A tap on the patient name / IP no. / patient no. opens the module menu and a tap on the location opens the
    // location popup, but only for the selected row. A tap anywhere else in the row selects it.
    var NEED_SELECT = 'Please select a patient first to view details or perform actions.';

    function onTap(item, target, x, y) {
        var now = Date.now();
        if (now - (state.lastTapAt || 0) < 350) return;       // a press-and-hold fires both pointerup and contextmenu
        state.lastTapAt = now;

        var ip = item.getAttribute('data-ip');
        var zoneEl = target && target.closest ? target.closest('[data-zone]') : null;
        var zone = zoneEl ? zoneEl.getAttribute('data-zone') : '';
        var isCard = state.view === 'C';

        if (zone === 'loc') {
            if (String(state.selectedIp) !== String(ip)) { selectRow(ip); }
            hideMenu(); openLocation(ip); return;
        }

        if (zone === 'los') {
            hideMenu();
            state.selectedIp = String(ip);
            paintSelection();
            openExtend(ip);
            return;
        }

        if (isCard) {
            if (String(state.selectedIp) !== String(ip)) {
                selectRow(ip).then(function () {
                    if (!state.gate[ip]) openMenu(ip, x, y);
                });
            } else {
                if (state.gate[ip]) { selectRow(ip); return; }
                openMenu(ip, x, y);
            }
            return;
        }

        if (!zone) { selectRow(ip); return; }
        if (String(state.selectedIp) !== String(ip)) { hideMenu(); alertMsg(NEED_SELECT); return; }
        if (state.gate[ip]) { selectRow(ip); return; }
        openMenu(ip, x, y);
    }

    // ------------------------------------------------------------------ patient tracking (legacy page behind the Location link)
    function openLocation(ip) {
        api('tracking?ipNo=' + encodeURIComponent(ip)).then(function (d) {
            if (!d.ok) { alertMsg(d.message); return; }
            state.trk = { ip: String(ip) };
            fillTracking(d.tracking);
            el('trkOverlay').hidden = false;
            el('trkPopup').hidden = false;
        }).catch(fail);
    }

    function hideTracking() {
        el('trkOverlay').hidden = true;
        el('trkPopup').hidden = true;
        state.trk = null;
    }

    function resetTrackingFields() {
        var t = state.trk && state.trk.data;
        if (!t) return;
        el('trkDate').value = t.nowDate;
        el('trkTime').value = t.nowTime;
        el('trkRemark').value = '';
    }

    function fillTracking(t) {
        state.trk.data = t;
        var p = t.patient;
        var info = [['IP No', p.ipNo], ['Patient No', p.patientNo], ['Patient', p.name], ['Age / Gender', p.ageGender],
                    ['Class', p.cls], ['Bed No', p.bedNo], ['Ward', p.ward], ['Doctor', p.doctor],
                    ['Adm / Disch', p.status], ['Adm Date', p.admDate]];
        el('trkInfo').innerHTML = info.map(function (r) {
            return '<div><dt>' + esc(r[0]) + '</dt><dd>' + (r[1] === '' || r[1] == null ? '&mdash;' : esc(r[1])) + '</dd></div>';
        }).join('');

        var cur = t.current;
        el('trkCurrent').hidden = !cur;
        el('trkNone').hidden = !!cur;
        el('trkSave').hidden = !cur;
        el('trkClear').hidden = !cur;
        if (cur) {
            el('trkEvName').textContent = cur.eventName;
            el('trkEvId').textContent = cur.eventId;
            el('trkDate').max = t.nowDate;
            if (t.minAt) el('trkDate').min = t.minAt.slice(0, 10); else el('trkDate').removeAttribute('min');
            resetTrackingFields();
        }

        el('trkTable').tBodies[0].innerHTML = t.events.map(function (e) {
            return '<tr' + (e.pending ? ' class="pend"' : '') + '><td>' + esc(e.recId) + '</td><td>' + esc(e.eventId) + '</td><td>' + esc(e.eventName) +
                '</td><td>' + esc(e.date || '') + '</td><td>' + esc(e.time || '') + '</td><td>' + esc(e.remark || '') + '</td></tr>';
        }).join('') || '<tr><td colspan="6" class="trk-empty">No events recorded.</td></tr>';
    }

    function bindTracking() {
        el('trkClose').addEventListener('click', hideTracking);
        el('trkBack').addEventListener('click', hideTracking);
        el('trkOverlay').addEventListener('click', hideTracking);
        el('trkClear').addEventListener('click', resetTrackingFields);

        el('trkSave').addEventListener('click', function () {
            var t = state.trk && state.trk.data;
            if (!t || !t.current) return;
            if (!el('trkDate').value) { alertMsg('Please enter the actual date.'); return; }
            if (!el('trkTime').value) { alertMsg('Please enter the actual time.'); return; }
            el('trkSave').disabled = true;
            api('tracking/save', {
                ipNo: Number(state.trk.ip), recId: t.current.recId, eventId: t.current.eventId,
                date: el('trkDate').value, time: el('trkTime').value, remark: el('trkRemark').value,
            }).then(function (r) {
                el('trkSave').disabled = false;
                if (r.tracking && state.trk) fillTracking(r.tracking);
                if (!r.ok) { alertMsg(r.message); return; }
                replaceRow(r.row);
                render({ keepScroll: true });
                paintSelection();
                if (window.alertify && alertify.success) alertify.success(r.message);
            }).catch(function (err) { el('trkSave').disabled = false; fail(err); });
        });
    }

    // ------------------------------------------------------------------ row menu (#custommenu)
    var MENU_ICON = {
        DFS: ['#2f6fd6', 'DF'], MD: ['#16a34a', 'Rx'], IPASS: ['#7c3aed', 'IP'],
        NCP: ['#0aa5a5', 'CP'], NAA: ['#f59e0b', 'NA'], DPN: ['#db2777', 'PN'],
        DFSN: ['#2563eb', 'DN'], NCPN: ['#0d9488', 'CN'], POC: ['#ea580c', 'PO'],
        INA: ['#8b5cf6', 'NN'],
    };

    function openMenu(ip, x, y) {
        var d = state.init || {}, row = rowByIp(ip);
        if (!row) return;
        var all = d.menu && d.menu.length ? d.menu : [];
        var vis = d.menuVisible;
        var items = all.filter(function (m) { return !vis || vis[m.key] !== false; });
        if (!items.length) { alertMsg('You do not have rights to any nursing form.'); return; }

        var menu = el('custommenu');
        menu.querySelector('ul').innerHTML = items.map(function (m) {
            var ic = MENU_ICON[m.key] || ['#507CD1', m.key.slice(0, 2)];
            return '<li><a href="#" role="menuitem" data-key="' + esc(m.key) + '"><span class="mi" style="background:' + ic[0] + '">' + ic[1] + '</span>' + esc(m.title) + '</a></li>';
        }).join('');
        el('menuPtnName').textContent = row.patientFullName;
        el('menuPtnIp').textContent = 'IP No. ' + row.ipNo + '  |  Bed ' + (row.bedNo || '-');
        state.menuIp = String(ip);

        var sheet = window.matchMedia('(max-width: 600px)').matches;
        menu.classList.toggle('sheet', sheet);
        menu.hidden = false;
        if (sheet) return;
        menu.style.left = '0px'; menu.style.top = '0px';
        var w = menu.offsetWidth, h = menu.offsetHeight, vw = window.innerWidth, vh = window.innerHeight;
        menu.style.left = Math.max(8, Math.min(x, vw - w - 8)) + 'px';
        menu.style.top = Math.max(8, Math.min(y, vh - h - 8)) + 'px';
    }

    function hideMenu() {
        el('custommenu').hidden = true;
        state.menuIp = null;
    }

    // ------------------------------------------------------------------ module opening (SIMPLIFIED)
    // Opens a module by navigating to its URL directly. No iframe/window state management.
    var LINK_TTL_MS = 20 * 60 * 1000;      // the signed EMR links stay valid for 30 minutes

    function readyLink(ip, key) {
        var l = state.links[ip + '|' + key];
        return l && Date.now() - l.at < LINK_TTL_MS ? l.url : null;
    }

    // While a patient stays selected, prepare all module links in one batch request
    // so tapping any module opens it straight away.
    function prefetchLinks(ip) {
        clearTimeout(state.prefTimer);
        var seq = ++state.prefSeq;
        state.prefTimer = setTimeout(function () {
            if (seq !== state.prefSeq || String(state.selectedIp) !== String(ip)) return;
            var d = state.init || {}, vis = d.menuVisible;
            var keys = (d.menu || []).map(function (m) { return m.key; }).filter(function (k) {
                return (!vis || vis[k] !== false) && !readyLink(ip, k);
            });
            if (!keys.length) return;
            apiQuiet('prefetch', { ipNo: Number(ip), keys: keys }).then(function (r) {
                if (seq !== state.prefSeq) return;
                var links = r && r.links;
                if (!links) return;
                var now = Date.now();
                links.forEach(function (l) {
                    if (l.url) state.links[ip + '|' + l.key] = { url: l.url, at: now };
                });
            }).catch(function () { });
        }, 100);
    }

    // When a module is opened in its own tab we make its Exit close that tab — and ONLY its Exit. Two same-origin
    // hooks, re-applied on a short poll so they survive the module's own postbacks:
    //   1. Exit-button intercept: a capturing click handler on the button labelled exactly "Exit" stops the
    //      module's own exit code and closes the tab instead. No navigation happens, so there's no dashboard/login
    //      flash. Every other button (Save, Print, Med Report, …) is left completely alone.
    //   2. Exit-function overrides: GoToMainMenu() and friends are replaced to just close the tab.
    // We deliberately do NOT close on navigation — reaching the shell, leaving the module's folder, or opening a
    // report in the same tab. That navigation-based close was what shut the tab when buttons like "Med Report"
    // opened another page. Only Exit closes the tab now. We never change a module's code.
    // NOTE: these hooks need the module tab to be on OUR origin (true when this app is served from the legacy
    // suite's origin). A module that self-closes via window.close() still works regardless of origin.
    function watchForExit(win, moduleUrl) {
        if (!win) return;
        var timer = setInterval(function () {
            if (!win || win.closed) { clearInterval(timer); return; }
            try {
                var doc = win.document;                    // throws while the tab is cross-origin — caught below
                if (doc) {
                    var ctrls = doc.querySelectorAll('input[type="button"],input[type="submit"],button,a');
                    for (var i = 0; i < ctrls.length; i++) {
                        var b = ctrls[i];
                        if (b.__nsExit) continue;
                        if ((b.value || b.textContent || '').trim().toLowerCase() === 'exit') {
                            b.__nsExit = true;
                            b.addEventListener('click', function (ev) {
                                try { ev.preventDefault(); ev.stopImmediatePropagation(); } catch (e) { }
                                try { win.close(); } catch (e) { }
                            }, true);
                        }
                    }
                }
                // Also neutralise the known AJAX exit helpers (can be invoked without a button click).
                ['GoToMainMenu', 'GoToMainPage', 'RedirectToDashboard', 'ExitPage'].forEach(function (fn) {
                    if (typeof win[fn] === 'function' && win[fn].__nsClose !== true) {
                        var closer = function () { try { win.close(); } catch (e) { } };
                        closer.__nsClose = true;
                        win[fn] = closer;
                    }
                });
            } catch (e) { }                                // cross-origin or transient — keep polling
        }, 30);
        setTimeout(function () { clearInterval(timer); }, 8 * 60 * 60 * 1000);   // safety stop
    }

    function openModule(key, ip) {
        hideMenu();
        var row = rowByIp(ip);
        if (!row) return;

        var ready = readyLink(ip, key);
        if (ready) {                                       // prepared in the background: open straight away
            var direct = window.open(ready, '_blank');
            if (!direct) window.location.href = ready;     // pop-ups blocked: fall back to this tab
            // Keep window.opener intact: some legacy modules' Exit button closes its own tab via window.close(),
            // which Chrome blocks once the opener is severed. watchForExit still handles modules that navigate away.
            else watchForExit(direct, ready);
            return;
        }

        // The tab must be opened synchronously inside the tap, otherwise popup blockers stop it.
        // We leave it blank (no "Opening…" placeholder) and just point it at the module once ready.
        var tab = window.open('', '_blank');
        function closeTab() { if (tab) { try { tab.close(); } catch (e) { } } }

        api('open', { key: key, ipNo: Number(row.ipNo), ptnNo: Number(row.patientNo) }).then(function (result) {
            if (!result || !(result.ok || result.Ok)) {
                closeTab();
                alertMsg((result && (result.message || result.Message)) || 'Unable to open module.');
                return;
            }
            var url = result.url || result.Url;
            // Keep window.opener intact so the module's own Exit (window.close) can close its tab; Chrome blocks
            // window.close() on a tab whose opener was severed. watchForExit still handles navigate-away modules.
            if (tab) { tab.location.href = url; watchForExit(tab, url); }
            else window.location.href = url;              // pop-ups blocked: fall back to this tab
        }).catch(function (err) { closeTab(); fail(err); });
    }

    // ------------------------------------------------------------------ exit (SIMPLIFIED)
    function exitTo(url) {
        // Simple redirect to host dashboard — no complex pattern matching
        if (url) {
            try { window.parent.location.href = url; } catch (e) { window.location.href = url; }
        }
    }

    // ------------------------------------------------------------------ LOS popup
    function showLos(ip, g) {
        var row = rowByIp(ip);
        state.los = { ip: String(ip), gate: g, skipLeft: g.skipLeft, currentLos: row ? row.los : 0 };
        el('losIp').textContent = (row ? row.patientFullName + '  ·  ' : '') + 'IP ' + ip;
        el('losContent1').textContent = g.content1;
        el('losContent2').textContent = g.content2;
        el('losCurrDischarge').textContent = g.currentExpectedDischarge;
        el('losSkipCount').textContent = g.skipLeft + ' of ' + g.skipLimit;
        el('losSkip').textContent = 'Skip (' + g.skipLimit + ')';
        el('losConfirm').disabled = !g.confirmEnabled;
        el('losSkip').disabled = !g.skipEnabled;
        el('losChange').hidden = false;
        el('losExtendPanel').hidden = true;
        el('losOverlay').hidden = false;
        el('losPopup').hidden = false;
    }

    function hideLos() {
        el('losOverlay').hidden = true;
        el('losPopup').hidden = true;
    }

    // Open the LOS popup straight on its Extend panel (triggered by tapping the E.LOS value in the grid).
    function openExtend(ip) {
        var row = rowByIp(ip);
        if (!row) return;
        state.los = { ip: String(ip), gate: null, skipLeft: 0, currentLos: row.los || 0 };
        el('losIp').textContent = (row.patientFullName ? row.patientFullName.trim() + '  ·  ' : '') + 'IP ' + ip;
        el('txtCurrentLOS').value = state.los.currentLos;
        el('txtNewLOS').value = '';
        el('lblExtendDischargeDt').textContent = '—';
        el('losChange').hidden = true;
        el('losExtendPanel').hidden = false;
        el('losOverlay').hidden = false;
        el('losPopup').hidden = false;
        setTimeout(function () { try { el('txtNewLOS').focus(); } catch (e) { } }, 50);
    }

    function bindLos() {
        el('losClose').addEventListener('click', function () { hideLos(); state.los = null; });
        el('losBack').addEventListener('click', function () { hideLos(); state.los = null; });

        el('losConfirm').addEventListener('click', function () {
            var ip = state.los.ip;
            api('los/confirm', { ipNo: Number(ip) }).then(function (r) {
                alertMsg(r.message);
                if (!r.ok) return;
                hideLos();
                search({ refresh: true, keepScroll: true }).then(function () {
                    state.selectedIp = ip;
                    state.gate[ip] = false;
                    paintSelection();
                });
            }).catch(fail);
        });

        el('losSkip').addEventListener('click', function () {
            var ip = state.los.ip;
            api('los/skip', { ipNo: Number(ip), skipLeft: state.los.skipLeft }).then(function (r) {
                if (!r.ok) { alertMsg(r.message); return; }
                state.gate[ip] = false;
                hideLos();
            }).catch(fail);
        });

        el('losExtend').addEventListener('click', function () {
            el('txtCurrentLOS').value = state.los.currentLos;
            el('txtNewLOS').value = '';
            el('lblExtendDischargeDt').textContent = '—';
            el('losChange').hidden = true;
            el('losExtendPanel').hidden = false;
        });

        var previewTimer = null;
        el('txtNewLOS').addEventListener('input', function () {
            this.value = this.value.replace(/[^0-9]/g, '');
            var v = this.value;
            clearTimeout(previewTimer);
            previewTimer = setTimeout(function () {
                if (!v) { el('lblExtendDischargeDt').textContent = '—'; return; }
                api('los/preview', { ipNo: Number(state.los.ip), currentLos: Number(state.los.currentLos) || 0, newLos: v })
                    .then(function (r) { el('lblExtendDischargeDt').textContent = r.text || '—'; }).catch(function () { });
            }, 250);
        });

        el('losDoExtend').addEventListener('click', function () {
            var ip = state.los.ip;
            api('los/extend', { ipNo: Number(ip), currentLos: Number(state.los.currentLos) || 0, newLos: el('txtNewLOS').value })
                .then(function (r) {
                    if (!r.ok) { alertMsg(r.message); return; }
                    if (r.gate) state.gate[ip] = !!r.gate.blockMenu;
                    if (r.row) replaceRow(r.row);
                    hideLos();
                    state.los = null;
                    state.selectedIp = String(ip);                 // the extended patient stays selected
                    render({ keepScroll: true });
                    paintSelection();
                    if (window.alertify && alertify.success) alertify.success(r.message); else alertMsg(r.message);
                }).catch(fail);
        });
    }

    // ------------------------------------------------------------------ search boxes (Speciality / Doctor / Ward)
    var boxSeq = 0, boxTimer = null, openBox = null;

    function boxParts(box) {
        return { input: box.querySelector('.sbox-in'), pop: box.querySelector('.sbox-pop'),
                 code: el(box.getAttribute('data-code')), desc: el(box.getAttribute('data-desc')), type: box.getAttribute('data-type') };
    }

    function closeBox() {
        if (!openBox) return;
        var p = boxParts(openBox);
        p.pop.hidden = true; p.pop.innerHTML = '';
        p.input.setAttribute('aria-expanded', 'false');
        openBox = null;
    }

    function pickBox(box, code, desc) {
        var p = boxParts(box);
        p.code.value = code; p.desc.value = desc;
        p.input.value = desc; p.input.dataset.sel = desc;
        closeBox();
        search();
    }

    function renderBox(box, items) {
        var p = boxParts(box);
        var html = '<div class="sbox-head"><b>' + items.length + ' result' + (items.length === 1 ? '' : 's') + '</b>' +
            '<span><kbd>&uarr;&darr;</kbd>Navigate</span><span><kbd>&crarr;</kbd>Select</span><span><kbd>Esc</kbd>Close</span></div>';
        if (!items.length) html += '<div class="sbox-empty">No match found</div>';
        else html += '<ul>' + items.map(function (it, i) {
            return '<li role="option" class="' + (i === 0 ? 'on' : '') + '" data-code="' + esc(it.code) + '" data-desc="' + esc(it.desc) + '">' +
                '<span class="sb-code">' + esc(it.code) + '</span><span class="sb-name">' + esc(it.desc) + '</span></li>';
        }).join('') + '</ul>';
        p.pop.innerHTML = html;
        p.pop.hidden = false;
        p.input.setAttribute('aria-expanded', 'true');
        openBox = box;
    }

    function queryBox(box) {
        var p = boxParts(box), seq = ++boxSeq;
        var q = p.input.value.trim();
        if (q === (p.input.dataset.sel || '') && q !== '') q = '';      // a chosen value: list everything again
        clearTimeout(boxTimer);
        boxTimer = setTimeout(function () {
            lookup('lookup/' + p.type + '?prefix=' + encodeURIComponent(q)).then(function (list) {
                if (seq !== boxSeq || document.activeElement !== p.input) return;
                renderBox(box, list);
            }).catch(function () { });
        }, 150);
    }

    function moveBox(dir) {
        if (!openBox) return;
        var items = openBox.querySelectorAll('.sbox-pop li');
        if (!items.length) return;
        var cur = 0;
        items.forEach(function (li, i) { if (li.classList.contains('on')) cur = i; li.classList.remove('on'); });
        var next = (cur + dir + items.length) % items.length;
        items[next].classList.add('on');
        items[next].scrollIntoView({ block: 'nearest' });
    }

    function bindSearchBoxes() {
        $('.sbox[data-code]').each(function () {
            var box = this, p = boxParts(box);
            p.input.dataset.sel = '';
            p.input.addEventListener('focus', function () { p.input.select(); queryBox(box); });
            p.input.addEventListener('input', function () {
                if (p.input.value.trim() === '' && p.code.value !== '') { p.code.value = ''; p.desc.value = ''; p.input.dataset.sel = ''; search(); }
                queryBox(box);
            });
            p.input.addEventListener('keydown', function (e) {
                if (e.key === 'ArrowDown') { e.preventDefault(); if (!openBox) queryBox(box); else moveBox(1); }
                else if (e.key === 'ArrowUp') { e.preventDefault(); moveBox(-1); }
                else if (e.key === 'Enter') {
                    e.preventDefault();
                    var on = box.querySelector('.sbox-pop li.on');
                    if (on) pickBox(box, on.getAttribute('data-code'), on.getAttribute('data-desc'));
                }
                else if (e.key === 'Escape') { closeBox(); p.input.value = p.input.dataset.sel || ''; }
            });
            p.input.addEventListener('blur', function () {
                setTimeout(function () {
                    if (document.activeElement === p.input) return;
                    p.input.value = p.input.dataset.sel || '';          // typed text that was not picked is dropped
                    if (openBox === box) closeBox();
                }, 120);
            });
            box.querySelector('.sbox-btn').addEventListener('click', function () { p.input.focus(); queryBox(box); });
            p.pop.addEventListener('pointerdown', function (e) {
                e.preventDefault();
                var li = e.target.closest('li');
                if (li) pickBox(box, li.getAttribute('data-code'), li.getAttribute('data-desc'));
            });
            p.pop.addEventListener('pointermove', function (e) {
                var li = e.target.closest('li');
                if (!li || li.classList.contains('on')) return;
                var cur = p.pop.querySelector('li.on'); if (cur) cur.classList.remove('on');
                li.classList.add('on');
            });
        });
    }

    function lookup(path) {
        return fetch('api/ns/' + withContext(path), { credentials: 'same-origin', cache: 'no-store' }).then(function (r) {
            return r.json().catch(function () { return []; }).then(function (data) {
                if (r.status === 401 && data && data.sessionExpired) { location.href = './'; throw new Error('session'); }
                if (!r.ok) throw new Error('Request failed (' + r.status + ')');
                return data;
            });
        });
    }

    // ------------------------------------------------------------------ other search inputs
    function clearAll() {
        FILTER_VALUES.forEach(function (id) { if (el(id).tagName !== 'SELECT') el(id).value = ''; });
        el('drpmrdsts').value = '0';
        var defType = state.init && state.init.defaultPtnTyp != null ? String(state.init.defaultPtnTyp) : 'ALL';
        el('ddlPtnTypByUser').value = defType;
        if (!el('ddlPtnTypByUser').value) el('ddlPtnTypByUser').value = 'ALL';
        FILTER_CHECKS.forEach(function (id) { el(id).checked = false; });
        el('txtPatientName').value = '';
        syncBoxes();
        try { localStorage.removeItem('ns.savedFilters'); } catch (e) { }
        search();
    }

    function bindSearchHeader() {
        bindSearchBoxes();

        var nameTimer = null;
        el('txtPatientName').addEventListener('input', function () { clearTimeout(nameTimer); nameTimer = setTimeout(applyNameFilter, 150); });
        el('txtPatientName').addEventListener('keydown', function (e) { if (e.key === 'Enter') { e.preventDefault(); e.target.blur(); } });
        el('btnPatientSearch').addEventListener('click', function () { el('txtPatientName').focus(); });

        el('ddlPtnTypByUser').addEventListener('change', function () { search(); });
        FILTER_CHECKS.forEach(function (id) { el(id).addEventListener('change', function () { search(); }); });
        el('drpmrdsts').addEventListener('change', function () { search(); });

        el('btnSaveFilter').addEventListener('click', saveFilters);

        el('gridPager').addEventListener('click', function (e) {
            var b = e.target.closest('button[data-pg]');
            if (!b || b.disabled) return;
            state.page = Number(b.getAttribute('data-pg'));
            hideMenu();
            render({ keepScroll: false });
        });
        el('btnGridview').addEventListener('click', function () { setView('G'); });
        el('btncardview').addEventListener('click', function () { setView('C'); });
        el('btnRefresh').addEventListener('click', function () { search({ refresh: true, keepScroll: true }); });
        el('btnClear').addEventListener('click', clearAll);
        el('btnexit').addEventListener('click', function () { exitTo(state.init ? state.init.exitUrl : './'); });

        // Summary count chips -> details modal
        var sum = el('nsSummary');
        if (sum) sum.addEventListener('click', function (e) {
            var b = e.target.closest('button[data-cat]');
            if (b && !b.disabled) openCountModal(b.getAttribute('data-cat'));
        });
        if (el('cntClose')) el('cntClose').addEventListener('click', hideCountModal);
        if (el('cntOverlay')) el('cntOverlay').addEventListener('click', hideCountModal);
        if (el('cntBody')) el('cntBody').addEventListener('click', function (e) {
            var tr = e.target.closest('tr[data-ip]');
            if (!tr) return;
            hideCountModal();
            setView('G', true);
            el('pnlgrdview').hidden = false; el('pnlcardview').hidden = true;
            $('#btnGridview').addClass('active'); $('#btncardview').removeClass('active');
            gotoPatient(tr.getAttribute('data-ip'));
        });
    }

    // ------------------------------------------------------------------ wiring
    $(function () {
        bindSearchHeader();
        bindPointer(el('grdInPatientDtl').tBodies[0], 'tr[data-ip]');
        bindPointer(el('pnlcardview'), '.row_dd2[data-ip]');
        bindLos();
        bindTracking();

        el('custommenu').addEventListener('click', function (e) {
            var a = e.target.closest('a[data-key]');
            if (!a) return;
            e.preventDefault();
            openModule(a.getAttribute('data-key'), state.menuIp);
        });
        document.addEventListener('pointerdown', function (e) {
            if (!e.target.closest('#custommenu')) hideMenu();
            if (openBox && !e.target.closest('.sbox')) closeBox();
        }, true);
        document.addEventListener('keydown', function (e) { if (e.key === 'Escape') { hideMenu(); hideCountModal(); } });
        ['pnlgrdview', 'pnlcardview'].forEach(function (id) { el(id).addEventListener('scroll', hideMenu, { passive: true }); });
        window.addEventListener('scroll', function () { if (!el('custommenu').classList.contains('sheet')) hideMenu(); }, { passive: true });
        window.addEventListener('resize', hideMenu);

        start();
    });
})(jQuery);
