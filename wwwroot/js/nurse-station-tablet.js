/* =====================================================================
   Nurse Station — tablet client.

   Interaction model
   - Touch / pen TAP on a row (or card): select it (same single-select rule as the legacy
     checkbox), run the LOS gate (legacy btnRowSet_Click), then open the row menu at the tap.
   - Mouse LEFT click: select only (legacy behaviour).
   - Mouse RIGHT click: legacy rule kept — the menu opens only if the row is already selected,
     otherwise "Please select any record."; a row blocked by the LOS gate never opens the menu.
   - A drag/scroll never counts as a tap; nothing ever calls focus() or scrollIntoView() on the
     grid, and refreshes restore the exact scroll offset — the grid does not jump.

   Module navigation
   - Each of the six modules has at most ONE instance. Re-opening it for the same patient just
     brings the existing instance back; for another patient the same instance is re-pointed.
   - "Frame" modules run inside host.html; their legacy exit (redirect of the parent to the
     dashboard) is trapped and control returns here. "Window" modules use one named tab each;
     when that tab is closed control returns here. No module code is modified.
   ===================================================================== */
(function ($) {
    'use strict';

    var TAP_SLOP = 10;              // px of movement that turns a tap into a scroll
    var TAP_MAX_MS = 700;

    var state = {
        init: null,
        all: null,                  // full list from the server (client-side data store)
        rows: [],                   // filtered view that is rendered (legacy ViewState("objInPatientHelpList"))
        fetchedAt: null,            // when "all" was loaded from the server
        offline: false,             // last refresh failed; showing cached data
        ipFilter: null,             // IP No. search result filter
        refreshing: null,           // in-flight refresh promise
        selectedIp: null,           // legacy hdnRptIpNo
        gate: {},                   // ipNo -> true when LOS gate blocks the menu (legacy lblAllowRightClick = "True")
        view: 'G',
        loaded: false,
        lastPointerType: 'mouse',
        menuIp: null,
        los: null,
        frames: {},                 // key -> { el, ip }
        windows: {},                // key -> { win, ip }
        activeFrame: null,
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
        if (window.alertify && alertify.alert) alertify.alert(esc(text), function () { if (cb) cb(); });
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
        return fetch('api/ns/' + path, {
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
        return fetch('api/ns/' + path, {
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

    // Patient data is cached in sessionStorage only (cleared when the tab/browser closes, never shared
    // between users on a shared tablet) and is scoped by a per-user key from the server.
    function sset(key, val) { try { sessionStorage.setItem(key, JSON.stringify(val)); } catch (e) { } }
    function sget(key) { try { return JSON.parse(sessionStorage.getItem(key)); } catch (e) { return null; } }
    function dataKey() { return 'ns.data.' + ((state.init && state.init.cacheKey) || 'anon'); }
    function clientMode() { return !state.init || state.init.filterMode !== 'Server'; }
    function load(key) { try { return JSON.parse(localStorage.getItem(key)); } catch (e) { return null; } }

    function rowByIp(ip) {
        for (var i = 0; i < state.rows.length; i++) if (String(state.rows[i].ipNo) === String(ip)) return state.rows[i];
        return null;
    }

    // ------------------------------------------------------------------ init (Page_Load)
    function start() {
        // Legacy page: $(document).contextmenu(function () { return false; });
        document.addEventListener('contextmenu', function (e) { e.preventDefault(); });

        // 1) Paint immediately from this tab's cache (no server needed).
        var cachedInit = sget('ns.init');
        if (cachedInit) {
            boot(cachedInit);
            var cached = sget(dataKey());
            if (cached && cached.rows) {
                state.all = cached.rows;
                state.fetchedAt = cached.at;
                state.loaded = true;
                applyFilters({ keepScroll: true });
                showSync();
            }
        }

        // 2) Refresh settings and data from the server in the background.
        api('init').then(function (d) {
            sset('ns.init', d);
            if (!cachedInit) { boot(d); search({ refresh: true }); return; }
            // Already on screen: take the fresh settings (rights, messages, theme) without resetting the user's filters.
            state.init = d;
            if (window.NsTheme) NsTheme.load(d.theme);
            if (d.blocked) { alertMsg(d.blocked); return; }
            if (d.forceExit) { exitTo(d.exitUrl); return; }
            search({ refresh: true, keepScroll: true, quiet: true });
        }).catch(function (err) {
            if (cachedInit) { state.offline = true; showSync(); return; }   // keep working from cache
            fail(err);
        });

        startAutoRefresh();
    }

    function boot(d) {
        state.init = d;
        if (window.NsTheme) NsTheme.load(d.theme);   // colours from this installation's suite CSS
        if (d.blocked) { alertMsg(d.blocked); return; }
        if (d.forceExit) { exitTo(d.exitUrl); return; }

        fillHeader(d.header);
        fillPatientTypes(d.ptnTypes, d.defaultPtnTyp);
        el('tdmrd').hidden = !d.showMrd;

        // Phones default to cards (the 30-column list is unusable on a small screen); a saved choice wins.
        state.view = load('ns.view') || (window.matchMedia('(max-width: 700px)').matches ? 'C' : (d.defaultView || 'G'));
        setView(state.view, true);

        if (d.ptnTypeError) { alertMsg(d.ptnTypeError); return; }   // legacy: Exit Sub before SearchResult

        if (d.preselectIpNo) {
            state.selectedIp = String(d.preselectIpNo);
            restoreFilters();
        } else if (d.defaultWard) {
            el('txtWardCd').value = d.defaultWard.code;
            el('txtWardDesc').value = d.defaultWard.desc;
            markCommitted('txtWardCd');
        }
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
        ddl.value = def != null ? String(def) : 'ALL';
        if (!ddl.value) ddl.value = 'ALL';
    }

    // ------------------------------------------------------------------ search (SearchResult)
    function criteria() {
        function codeIf(codeId, descId) {
            var c = el(codeId).value.trim(), d = el(descId).value.trim();
            return c !== '' && d !== '' ? Number(c) || 0 : 0;      // legacy: code only counts when description is filled
        }
        var ptn = el('ddlPtnTypByUser').value;
        return {
            wardCd: codeIf('txtWardCd', 'txtWardDesc'),
            docCd: codeIf('txtDocCd', 'txtDocName'),
            spltyCd: codeIf('txtSpecialityCd', 'txtSpecialityDCd'),
            flrNo: codeIf('txtFlr', 'txtFlrname'),
            ptnTyp: ptn === 'ALL' ? 0 : Number(ptn) || 0,
            mrdStatus: Number(el('drpmrdsts').value) || 0,
            vulnerable: el('chkIsVuln').checked,
            isolated: el('chkIsIsolated').checked,
            hwc: el('chkHWC').checked,
            arrivedOnBed: el('chkIsArrivedOnBed').checked,
        };
    }

    /**
     * Client mode (default): filters are applied in the browser over the list already loaded;
     * the server is only asked for data on first load, Refresh, background refresh, or after an action.
     * Server mode: every filter change queries the server (the legacy SearchResult behaviour).
     *   opts.refresh   - reload the list from the server
     *   opts.keepScroll- keep the scroll position when re-rendering
     *   opts.quiet     - background refresh: no busy overlay, no error popup (shows the offline notice instead)
     */
    function search(opts) {
        opts = opts || {};
        saveFilters();
        updateFilterSummary();

        if (!clientMode()) {
            return fetchPatients(criteria(), opts).then(function (d) {
                state.all = d.rows || [];
                applyFilters(opts);
            });
        }

        if (state.all && !opts.refresh) {                 // instant: no server call
            applyFilters(opts);
            return Promise.resolve();
        }
        return refreshData(opts);
    }

    var NEUTRAL = { wardCd: 0, docCd: 0, spltyCd: 0, flrNo: 0, ptnTyp: 0, mrdStatus: 0, vulnerable: false, isolated: false, hwc: false, arrivedOnBed: false };

    function refreshData(opts) {
        if (state.refreshing) return state.refreshing;
        state.refreshing = fetchPatients(NEUTRAL, opts).then(function (d) {
            state.all = d.rows || [];
            state.fetchedAt = d.fetchedAt || new Date().toISOString();
            state.offline = false;
            state.gate = {};
            sset(dataKey(), { at: state.fetchedAt, rows: state.all });
            applyFilters({ keepScroll: true });
        }).catch(function (err) {
            if (err && err.message === 'session') return;
            state.offline = true;
            if (!state.all) { if (!opts || !opts.quiet) fail(err); return; }
            applyFilters({ keepScroll: true });           // keep showing what we have
        }).finally(function () {
            state.refreshing = null;
            showSync();
        });
        return state.refreshing;
    }

    function fetchPatients(q, opts) {
        return (opts && opts.quiet ? apiQuiet('patients', q) : api('patients', q));
    }

    function mrdStatusOf(reqNo) {
        if (!reqNo) return 0;
        var p = String(reqNo).split('_');
        return Number(p[0]) && Number(p[1]) ? Number(p[1]) : 0;
    }

    /** The legacy SearchResult filters, applied in the browser over state.all. */
    function applyFilters(opts) {
        if (!state.all) return;
        var c = criteria();
        if (!el('txtIpNo').value.trim()) state.ipFilter = null;
        state.rows = state.all.filter(function (x) {
            if (state.ipFilter && String(x.ipNo) !== state.ipFilter) return false;
            if (!clientMode()) return true;               // server already filtered
            if (c.wardCd && x.wardCd !== c.wardCd) return false;
            if (c.docCd && x.doctorCd !== c.docCd) return false;
            if (c.spltyCd && Number(x.spltyCd) !== c.spltyCd) return false;
            if (c.flrNo && x.flrNo !== c.flrNo) return false;
            if (c.ptnTyp && x.ptnTypCd !== c.ptnTyp) return false;
            if (c.vulnerable && !x.isPtnVulnerable) return false;
            if (c.isolated && !x.isIsolated) return false;
            if (c.hwc && !x.hwc) return false;
            if (c.arrivedOnBed && !x.isArrivedOnBed) return false;
            if (c.mrdStatus && mrdStatusOf(x.reqNo) !== c.mrdStatus) return false;
            return true;
        });
        state.loaded = true;        // legacy: ViewState("objInPatientHelpList") IsNot Nothing
        render({ keepScroll: !!(opts && opts.keepScroll) });
        el('lblTotalCount').textContent = state.rows.length;
    }

    function replaceRow(row) {
        [state.all, state.rows].forEach(function (list) {
            if (!list) return;
            for (var i = 0; i < list.length; i++) if (String(list[i].ipNo) === String(row.ipNo)) list[i] = row;
        });
        if (state.all) sset(dataKey(), { at: state.fetchedAt, rows: state.all });
    }

    // "Updated 10:42" / offline notice
    function showSync() {
        var at = state.fetchedAt ? new Date(state.fetchedAt) : null;
        var t = at && !isNaN(at) ? at.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : '';
        el('lastUpdated').textContent = t ? 'Updated ' + t : '';
        var b = el('syncBanner');
        if (state.offline && state.all) {
            b.innerHTML = '<b>Offline</b> &mdash; showing the list from ' + esc(t || 'earlier') + '. Server not reachable; retrying automatically. <button type="button" id="syncRetry" class="btn btn-ghost">Retry now</button>';
            b.hidden = false;
            el('syncRetry').onclick = function () { search({ refresh: true, keepScroll: true }); };
        } else {
            b.hidden = true;
        }
    }

    // Quiet background refresh while the page is in use (not while a form/popup is open or the user is typing).
    function startAutoRefresh() {
        function due() {
            var secs = (state.init && state.init.autoRefreshSeconds) || 120;
            return !state.fetchedAt || (Date.now() - new Date(state.fetchedAt).getTime()) >= secs * 1000;
        }
        function idle() {
            var a = document.activeElement;
            return document.visibilityState === 'visible' && el('moduleHost').hidden && el('losPopup').hidden &&
                el('custommenu').hidden && !(a && /^(INPUT|SELECT|TEXTAREA)$/.test(a.tagName));
        }
        setInterval(function () {
            if (state.init && (due() || state.offline) && idle()) search({ refresh: true, keepScroll: true, quiet: true });
        }, 15000);
        document.addEventListener('visibilitychange', function () {
            if (document.visibilityState === 'visible' && state.init && due()) search({ refresh: true, keepScroll: true, quiet: true });
        });
        window.addEventListener('online', function () { if (state.init) search({ refresh: true, keepScroll: true, quiet: true }); });
    }

    // ------------------------------------------------------------------ filter panel (compact header)
    // Secondary filters live in a collapsible panel; whatever is active is shown as removable pills.
    function activeFilters() {
        var list = [];
        function code(label, codeId, descId) {
            if (el(codeId).value.trim() && el(descId).value.trim())
                list.push({ label: label, value: el(descId).value, clear: function () { el(codeId).value = ''; el(descId).value = ''; markCommitted(codeId); } });
        }
        code('Speciality', 'txtSpecialityCd', 'txtSpecialityDCd');
        code('Doctor', 'txtDocCd', 'txtDocName');
        code('Floor', 'txtFlr', 'txtFlrname');
        var ddl = el('ddlPtnTypByUser'), def = state.init && state.init.defaultPtnTyp != null ? String(state.init.defaultPtnTyp) : 'ALL';
        if (ddl.value && ddl.value !== def && ddl.value !== 'ALL')
            list.push({ label: 'Type', value: ddl.options[ddl.selectedIndex].text, clear: function () { ddl.value = 'ALL'; } });
        [['chkHWC', 'HWC'], ['chkIsVuln', 'Vulnerable'], ['chkIsIsolated', 'Isolated'], ['chkIsArrivedOnBed', 'Acknowledged']].forEach(function (c) {
            if (el(c[0]).checked) list.push({ label: '', value: c[1], clear: function () { el(c[0]).checked = false; } });
        });
        var mrd = el('drpmrdsts');
        if (!el('tdmrd').hidden && mrd.value !== '0')
            list.push({ label: 'MRD', value: mrd.options[mrd.selectedIndex].text, clear: function () { mrd.value = '0'; } });
        return list;
    }

    function updateFilterSummary() {
        var list = activeFilters(), box = el('activeFilters');
        el('filterBadge').textContent = list.length;
        el('filterBadge').hidden = list.length === 0;
        box.innerHTML = '';
        list.forEach(function (f) {
            var pill = document.createElement('span');
            pill.className = 'af';
            pill.innerHTML = (f.label ? esc(f.label) + ': ' : '') + '<b>' + esc(f.value) + '</b><button type="button" aria-label="Remove filter">&times;</button>';
            pill.querySelector('button').addEventListener('click', function () { f.clear(); search(); });
            box.appendChild(pill);
        });
    }

    function setFiltersOpen(open) {
        el('moreFilters').hidden = !open;
        el('btnMoreFilters').setAttribute('aria-expanded', open ? 'true' : 'false');
        store('ns.filtersOpen', open);
    }

    function saveFilters() {
        var ids = ['txtWardCd', 'txtWardDesc', 'txtDocCd', 'txtDocName', 'txtSpecialityCd', 'txtSpecialityDCd', 'txtFlr', 'txtFlrname', 'ddlPtnTypByUser'];
        var f = {};
        ids.forEach(function (id) { f[id] = el(id).value; });
        ['chkIsVuln', 'chkIsIsolated', 'chkHWC'].forEach(function (id) { f[id] = el(id).checked; });
        store('ns.filters', f);   // legacy kept these in cookies to restore after returning from a module
    }

    function restoreFilters() {
        var f = load('ns.filters');
        if (!f) return;
        Object.keys(f).forEach(function (id) {
            var e = el(id);
            if (!e) return;
            if (e.type === 'checkbox') e.checked = !!f[id]; else e.value = f[id];
        });
        ['txtWardCd', 'txtDocCd', 'txtSpecialityCd', 'txtFlr'].forEach(markCommitted);
    }

    // ------------------------------------------------------------------ rendering (client-side binding)
    var ICON = function (src, title) { return '<img class="ns-flag" src="Images/' + src + '" title="' + esc(title) + '" alt="' + esc(title) + '" />'; };

    function mrdText(reqNo) {
        if (!reqNo) return 'Not Sent';
        var p = String(reqNo).split('_'), no = Number(p[0]) || 0, st = Number(p[1]) || 0;
        if (!no || !st) return 'Not Sent';
        return { 1: 'Requested', 5: 'Requested', 2: 'Created', 4: 'Returned', 3: 'Rejected' }[st] || '';
    }

    // Column order = legacy grdInPatientDtl.
    function columns() {
        var cols = [
            { h: 'SEL', cls: 'ns-sel ns-sticky-col', r: function (x) { return '<input type="checkbox" tabindex="-1" aria-label="Select"' + (String(x.ipNo) === String(state.selectedIp) ? ' checked' : '') + ' />'; } },
            { h: '', cls: 'ns-ico', r: function (x) {
                return (x.hwc ? '<img src="Images/HWC.png" title="HWC PATIENT" alt="HWC" />' : '') +
                    (x.isIsolated ? '<img src="Images/isolated_ptn_16px.png" title="This Patient is Isolated" alt="Isolated" />' : '') +
                    (x.isPtnVulnerable ? '<span title="This Patient is Vulnerable">&#9888;</span>' : '');
            } },
            { h: 'BLOOD GROUP', r: function (x) { return esc(x.bloodGroup); } },
            { h: 'PATIENTS NAME', cls: 'wrap ns-sticky-col2 ns-name', r: function (x) { return esc(x.patientFullName); } },
            { h: 'IP NO', cls: function (x) { return x.folioClosed ? 'folio' : ''; }, title: function (x) { return x.folioClosed ? 'Final Bill is Prepared And Folio is Closed.' : ''; }, r: function (x) { return esc(x.ipNo); } },
            { h: 'PATIENT NO', r: function (x) { return esc(x.patientNo); } },
            { h: 'LOCATION', r: function (x) { return x.locName ? '<span class="lnkmark">' + esc(x.locName) + '</span>' : ''; } },
            { h: 'AGE TYPE', r: function (x) { return esc(x.ageType); } },
            { h: 'AGE', r: function (x) { return esc(x.age); } },
            { h: 'GENDER', r: function (x) { return esc(x.gender); } },
            { h: 'PERV.BMI', r: function (x) { return esc(x.lastBmiIndex); } },
            { h: 'BED NO', r: function (x) { return esc(x.bedNo); } },
            { h: 'BED TYPE', r: function (x) { return esc(x.bedTypDesc); } },
            { h: 'MOBILE NO', r: function (x) { return esc(x.mobile); } },
            { h: 'DOCTOR NAME', cls: 'wrap', r: function (x) { return esc(x.doctorName); } },
            { h: 'WARD NAME', cls: 'wrap', r: function (x) { return esc(x.wardDCd); } },
            { h: 'DSCHRG ADVICE', r: function (x) { return x.dschgAdvSts === 'Given' ? ICON('ImgRd.jpg', 'This Patient has given Discharge Advice') : ''; } },
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
            { h: 'RD', r: function (x) { return x.readyToDschrge ? ICON('ImgRd.jpg', 'Ready to discharge') : ''; } },
            { h: 'NO DUES', r: function (x) { return x.noDues ? ICON('No_due_bill.png', 'This Patient is Marked with No Due clearance.') : ''; } },
            { h: 'DIET ASSIGNED', r: function (x) { return x.isDietAssigned ? ICON('diet-meal-24px.png', 'Diet Assigned to this patient.') : ''; } },
            { h: 'NEWLY ADMITTED', r: function (x) { return x.isNewAdmission ? ICON('ImgRd.jpg', 'New Admission') : ''; } },
            { h: 'OT BOOKED', r: function (x) { return x.otBooked ? ICON('ImgRd.jpg', 'OT Booked') : ''; } },
            { h: 'OT CLEARANCE', r: function (x) { return esc(x.otClearance); } },
            { h: 'DSCHRG PLANNING', r: function (x) { return x.dschgPlanning ? ICON('ImgRd.jpg', 'Discharge Planning') : ''; } },
            { h: 'E.LOS', r: function (x) { return esc(x.los); } },
            { h: 'A.LOS', r: function (x) { return esc(x.aLos); } }
        );
        return cols;
    }

    function rowHtml(x, cols) {
        var sel = String(x.ipNo) === String(state.selectedIp);
        var html = '<tr data-ip="' + esc(x.ipNo) + '"' + (sel ? ' class="Setrow-highlight"' : '') + '>';
        cols.forEach(function (c) {
            var cls = typeof c.cls === 'function' ? c.cls(x) : (c.cls || '');
            var title = c.title ? c.title(x) : '';
            html += '<td' + (cls ? ' class="' + cls + '"' : '') + (title ? ' title="' + esc(title) + '"' : '') + '>' + c.r(x) + '</td>';
        });
        return html + '</tr>';
    }

    function render(opts) {
        var wrapG = el('pnlgrdview'), wrapC = el('pnlcardview');
        var keep = opts && opts.keepScroll;
        var sg = { t: wrapG.scrollTop, l: wrapG.scrollLeft }, sc = { t: wrapC.scrollTop };

        var cols = columns();
        el('grdInPatientDtl').tHead.innerHTML = '<tr>' + cols.map(function (c) {
            return '<th' + (c.cls && typeof c.cls === 'string' && c.cls.indexOf('ns-sticky') !== -1 ? ' class="' + c.cls.replace(/wrap|ns-name|ns-ico/g, '').trim() + '"' : '') + '>' + esc(c.h) + '</th>';
        }).join('') + '</tr>';
        el('grdInPatientDtl').tBodies[0].innerHTML = state.rows.map(function (x) { return rowHtml(x, cols); }).join('');
        el('gridEmpty').hidden = state.rows.length > 0;

        renderCards();
        applyNameFilter();

        if (keep) { wrapG.scrollTop = sg.t; wrapG.scrollLeft = sg.l; wrapC.scrollTop = sc.t; }
        else { wrapG.scrollTop = 0; wrapG.scrollLeft = 0; wrapC.scrollTop = 0; }
    }

    function renderCards() {
        // Card view = legacy rptPtnDtls (wards) + childrpt (patients) + ward counters.
        var byWard = [], idx = {};
        state.rows.forEach(function (x) {
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
                    (x.locName ? '<span class="lnkmark">' + esc(x.locName) + '</span>' : '') +
                    (x.folStsCd === 2 ? '<span class="tag tag-folio" title="Folio Closed">Folio closed</span>' : '');
                return '<div class="row_dd2' + (sel ? ' selected' : '') + '" data-ip="' + esc(x.ipNo) + '">' +
                    '<div class="pc-head">' +
                        '<div class="pc-title"><div class="ns-name">' + esc(x.patientFullName) + '</div>' +
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

    // FilterPtnNm: client-side filter on patient name (grid) / card text (thumbnail).
    function applyNameFilter() {
        var words = el('txtPatientName').value.toLowerCase().trim();
        $('#grdInPatientDtl tbody tr').each(function () {
            var name = $(this).find('td.ns-name').text().toLowerCase();
            this.style.display = words === '' || name.indexOf(words) !== -1 ? '' : 'none';
        });
        $('#pnlcardview .row_dd2').each(function () {
            this.style.display = words === '' || $(this).text().toLowerCase().indexOf(words) !== -1 ? '' : 'none';
        });
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

    // Legacy CheckOtherIsCheckedByGVID + btnRowSet_Click (without the scroll-jumping focus()).
    function selectRow(ip, openAt) {
        hideMenu();
        state.selectedIp = String(ip);
        paintSelection();

        // Open straight away (unless this row is already known to be LOS-blocked).
        if (openAt && !state.gate[ip]) openMenu(ip, openAt.x, openAt.y);

        var seq = state.selectSeq = (state.selectSeq || 0) + 1;
        return apiQuiet('rowselect', { ipNo: Number(ip) }).then(function (g) {
            if (seq !== state.selectSeq || String(state.selectedIp) !== String(ip)) return;   // a newer tap won
            state.gate[ip] = !!g.blockMenu;
            if (g.showPopup) { hideMenu(); showLos(ip, g); return; }
            if (g.blockMenu) { hideMenu(); return; }
        }).catch(function (err) {
            // LOS check unavailable: keep the menu usable (legacy behaviour on error).
            if (window.console) console.warn('LOS check failed for IP ' + ip + ':', err && err.message);
        });
    }

    function unselect() {
        state.selectedIp = null;
        paintSelection();
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
            press = { item: item, x: e.clientX, y: e.clientY, t: Date.now(), type: e.pointerType || 'mouse', id: e.pointerId };
            item.classList.add('ns-pressed');
        });
        container.addEventListener('pointermove', function (e) {
            if (!press || e.pointerId !== press.id) return;
            if (Math.abs(e.clientX - press.x) > TAP_SLOP || Math.abs(e.clientY - press.y) > TAP_SLOP) cancel();
        });
        container.addEventListener('pointercancel', cancel);   // browser took over to scroll
        container.addEventListener('pointerup', function (e) {
            if (!press || e.pointerId !== press.id) return;
            var p = press;
            cancel();
            if (Date.now() - p.t > TAP_MAX_MS && p.type === 'mouse') return;
            selectRow(p.item.getAttribute('data-ip'), { x: e.clientX, y: e.clientY });   // tap / click: select + menu
        });

        // Right-click (kept from the legacy page). Long-press on touch also raises contextmenu;
        // that is ignored because the tap path already handles touch.
        container.addEventListener('contextmenu', function (e) {
            e.preventDefault();
            if (state.lastPointerType !== 'mouse') return;
            var item = e.target.closest(itemSelector);
            if (!item) return;
            var ip = item.getAttribute('data-ip');
            if (String(ip) === String(state.selectedIp) && state.gate.hasOwnProperty(ip)) {
                if (state.gate[ip]) { hideMenu(); return; }                      // LOS-blocked row
                openMenu(ip, e.clientX, e.clientY);
                return;
            }
            selectRow(ip, { x: e.clientX, y: e.clientY });
        });
    }

    // ------------------------------------------------------------------ row menu (#custommenu)
    var MENU_ICON = {
        DFS: ['#2f6fd6', 'DF'], MD: ['#16a34a', 'Rx'], IPASS: ['#7c3aed', 'IP'],
        NCP: ['#0aa5a5', 'CP'], NAA: ['#f59e0b', 'NA'], DPN: ['#db2777', 'PN'],
    };
    var DEFAULT_MENU = [
        { key: 'DFS', title: 'Daily Flow Sheet' }, { key: 'MD', title: 'Medicine Administration' },
        { key: 'IPASS', title: 'I-Pass Handover Form' }, { key: 'NCP', title: 'Nurse Care Plan' },
        { key: 'NAA', title: 'Nursing Assessment - Adult' }, { key: 'DPN', title: 'Daily Progress Notes' },
    ];

    function openMenu(ip, x, y) {
        var d = state.init || {}, row = rowByIp(ip);
        if (!row) return;
        var all = d.menu && d.menu.length ? d.menu : DEFAULT_MENU;
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
        if (sheet) return;                              // phones: bottom sheet, positioned by CSS
        menu.style.left = '0px'; menu.style.top = '0px';
        var w = menu.offsetWidth, h = menu.offsetHeight, vw = window.innerWidth, vh = window.innerHeight;
        menu.style.left = Math.max(8, Math.min(x, vw - w - 8)) + 'px';
        menu.style.top = Math.max(8, Math.min(y, vh - h - 8)) + 'px';
    }

    function hideMenu() {
        el('custommenu').hidden = true;
        state.menuIp = null;
    }

    // ------------------------------------------------------------------ module navigation
    function openModule(key, ip) {
        hideMenu();
        var row = rowByIp(ip);
        if (!row) return;
        var mode = (state.init.hostModes || {})[key] || 'Frame';
        if (mode === 'Window') openInWindow(key, row); else openInFrame(key, row);
    }

    function openInFrame(key, row) {
        var inst = state.frames[key];
        if (inst && inst.ip === String(row.ipNo)) { showHost(key, row); return; }   // reuse: same instance, no reload

        api('open', { key: key, ipNo: row.ipNo }).then(function (r) {
            if (!r.ok) { alertMsg(r.message); return; }
            if (!inst) {
                var f = document.createElement('iframe');
                f.title = r.title;
                f.setAttribute('allow', 'clipboard-read; clipboard-write; fullscreen');
                f.addEventListener('load', function () { onHostFrameLoad(key, f); });
                el('hostFrames').appendChild(f);
                inst = state.frames[key] = { el: f, ip: null, title: r.title };
            }
            inst.ip = String(row.ipNo);
            inst.el.src = 'host.html?k=' + encodeURIComponent(key) +
                '&x=' + encodeURIComponent((state.init.exitPatterns || []).join('|')) +
                '&u=' + encodeURIComponent(r.url);
            showHost(key, row);
        }).catch(fail);
    }

    // host.html replaced by something else = the module redirected its parent (its legacy "exit").
    function onHostFrameLoad(key, f) {
        var ours = false;
        try { ours = /\/host\.html$/i.test(f.contentWindow.location.pathname); } catch (e) { ours = false; }
        if (!ours && f.getAttribute('src')) closeInstance(key, true);
    }

    function showHost(key, row) {
        Object.keys(state.frames).forEach(function (k) { state.frames[k].el.classList.toggle('active', k === key); });
        state.activeFrame = key;
        el('hostTitle').textContent = state.frames[key] ? state.frames[key].title : '';
        el('hostPatient').textContent = row ? (row.patientFullName + '  |  IP ' + row.ipNo + '  |  Bed ' + (row.bedNo || '-')) : '';
        el('moduleHost').hidden = false;
    }

    // Back button: hide, keep the instance alive for instant re-open.
    function backToNurseStation() {
        el('moduleHost').hidden = true;
        state.activeFrame = null;
        returnedToNurseStation();
    }

    // Module exited: drop its instance and return.
    function closeInstance(key, fromExit) {
        var inst = state.frames[key];
        if (inst) {
            inst.el.removeAttribute('src');
            inst.el.parentNode && inst.el.parentNode.removeChild(inst.el);
            delete state.frames[key];
        }
        if (fromExit && (state.activeFrame === key || state.activeFrame === null)) {
            el('moduleHost').hidden = true;
            state.activeFrame = null;
            returnedToNurseStation();
        }
    }

    function openInWindow(key, row) {
        var name = 'NS_MODULE_' + key;
        var inst = state.windows[key];
        if (inst && inst.win && !inst.win.closed && inst.ip === String(row.ipNo)) { inst.win.focus(); return; }

        // Open (or re-acquire) the single named tab synchronously, inside the tap, so it is not
        // popup-blocked; '' never reloads a tab that already exists under this name.
        var win = inst && inst.win && !inst.win.closed ? inst.win : window.open('', name);
        if (!win) { alertMsg('Please allow pop-ups for Nurse Station to open ' + key + '.'); return; }
        var fresh = !inst || inst.win !== win;

        api('open', { key: key, ipNo: row.ipNo }).then(function (r) {
            if (!r.ok) { if (fresh) { try { win.close(); } catch (e) { } } alertMsg(r.message); return; }
            win.location.href = r.url;
            try { win.focus(); } catch (e) { }
            state.windows[key] = { win: win, ip: String(row.ipNo) };
            watchWindows();
        }).catch(function (err) { if (fresh) { try { win.close(); } catch (e) { } } fail(err); });
    }

    // Closing a module tab hands control back to Nurse Station.
    function watchWindows() {
        if (state.watchTimer) return;
        state.watchTimer = setInterval(function () {
            var open = 0, closedAny = false;
            Object.keys(state.windows).forEach(function (k) {
                var w = state.windows[k];
                if (!w.win || w.win.closed) { delete state.windows[k]; closedAny = true; } else open++;
            });
            if (closedAny) { try { window.focus(); } catch (e) { } returnedToNurseStation(); }
            if (!open) { clearInterval(state.watchTimer); state.watchTimer = null; }
        }, 1000);
    }

    function returnedToNurseStation() {
        search({ refresh: true, keepScroll: true, quiet: true });   // modules may have changed patient data
    }

    function exitTo(url) {
        // btnexit_Click: window.parent.location.href = SubMenuPath
        try { window.parent.location.href = url; } catch (e) { window.location.href = url; }
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

    function bindLos() {
        // btnClose_Click / btnextendback_Click: close and clear the selection.
        el('losClose').addEventListener('click', function () { hideLos(); unselect(); state.los = null; });
        el('losBack').addEventListener('click', function () { hideLos(); unselect(); state.los = null; });

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
                    alertMsg(r.message);
                    if (!r.ok) return;
                    if (r.row) {
                        replaceRow(r.row);
                        render({ keepScroll: true });
                        state.los.currentLos = r.row.los;
                    }
                    if (r.gate) {
                        state.gate[ip] = !!r.gate.blockMenu;
                        el('losCurrDischarge').textContent = r.gate.currentExpectedDischarge;
                        el('losConfirm').disabled = false;
                    }
                    el('txtCurrentLOS').value = state.los.currentLos;
                    el('txtNewLOS').value = '';
                    el('lblExtendDischargeDt').textContent = '—';
                }).catch(fail);
        });
    }

    // ------------------------------------------------------------------ code fields (ward / speciality / doctor / floor)
    var FIELD = {
        txtWardCd: { type: 'ward', desc: 'txtWardDesc', after: function () { el('txtIpNo').value = ''; el('txtPatientName').value = ''; } },
        txtSpecialityCd: { type: 'speciality', desc: 'txtSpecialityDCd', after: null },
        txtDocCd: { type: 'doctor', desc: 'txtDocName', after: function () { el('txtIpNo').value = ''; el('txtPatientName').value = ''; } },
        txtFlr: { type: 'floor', desc: 'txtFlrname', after: null },
    };

    function markCommitted(id) { var e = el(id); if (e) e.dataset.committed = e.value; }

    function commitCode(id) {
        var input = el(id), f = FIELD[id];
        hideSuggest();
        if (input.value === input.dataset.committed) return;
        var code = input.value.trim();
        api('validate/' + f.type + '?code=' + encodeURIComponent(code)).then(function (v) {
            if (v.ok) {
                input.value = v.code;
                el(f.desc).value = v.desc || '';
            } else {
                input.value = '';
                el(f.desc).value = '';
            }
            markCommitted(id);
            if (f.after) f.after();
            var go = function () { search(); };
            if (!v.ok) alertMsg(v.message, go); else go();            // legacy: always re-runs SearchResult
        }).catch(fail);
    }

    var suggestBox = null, suggestFor = null, suggestTimer = null, suggestSeq = 0;

    function hideSuggest() {
        if (suggestBox) { suggestBox.remove(); suggestBox = null; suggestFor = null; }
    }

    function showSuggest(id, items) {
        hideSuggest();
        if (!items.length) return;
        var input = el(id);
        suggestBox = document.createElement('ul');
        suggestBox.className = 'ns-suggest';
        suggestBox.setAttribute('role', 'listbox');
        suggestBox.innerHTML = items.slice(0, 50).map(function (it) {
            return '<li role="option" data-code="' + esc(it.code) + '" data-desc="' + esc(it.desc) + '"><span>' + esc(it.desc) + '</span><small>' + esc(it.code) + '</small></li>';
        }).join('');
        // pointerdown + preventDefault keeps focus in the input, so blur does not commit the half-typed text first.
        suggestBox.addEventListener('pointerdown', function (e) {
            e.preventDefault();
            var li = e.target.closest('li');
            if (!li) return;
            input.value = li.getAttribute('data-code');
            commitCode(id);
        });
        input.parentNode.appendChild(suggestBox);
        suggestFor = id;
    }

    function bindCodeFields() {
        Object.keys(FIELD).forEach(function (id) {
            var input = el(id);
            input.dataset.committed = '';
            input.addEventListener('input', function () {
                var v = input.value.trim(), seq = ++suggestSeq;
                clearTimeout(suggestTimer);
                if (v.length <= 1) { hideSuggest(); return; }          // legacy: prefix length <= 1 -> no lookup
                suggestTimer = setTimeout(function () {
                    api('lookup/' + FIELD[id].type + '?prefix=' + encodeURIComponent(v)).then(function (list) {
                        if (seq === suggestSeq && document.activeElement === input) showSuggest(id, list);
                    }).catch(function () { });
                }, 250);
            });
            input.addEventListener('keydown', function (e) {
                if (e.key === 'Enter') { e.preventDefault(); commitCode(id); input.blur(); }
                if (e.key === 'Escape') hideSuggest();
            });
            input.addEventListener('blur', function () { setTimeout(function () { if (document.activeElement !== input) commitCode(id); }, 120); });
        });

        el('txtWardDesc').addEventListener('click', function () { el('txtWardCd').focus(); });
    }

    // ------------------------------------------------------------------ other search inputs
    function ipNoChanged() {
        // txtIpNo_TextChanged: clears ward/doctor, shows only that IP (patient type -> ALL), or "IP Number Not Found".
        var ip = el('txtIpNo').value.trim();
        ['txtDocCd', 'txtDocName', 'txtWardCd', 'txtWardDesc'].forEach(function (id) { el(id).value = ''; });
        ['txtDocCd', 'txtWardCd'].forEach(markCommitted);
        if (!state.loaded) { alertMsg(msg(4)); return; }
        if (ip === '') { state.ipFilter = null; search(); return; }

        var key = String(Number(ip));
        var pool = clientMode() ? state.all : state.rows;
        var hit = (pool || []).filter(function (x) { return String(x.ipNo) === key; });
        if (hit.length) {
            state.ipFilter = key;
            el('txtPatientName').value = hit[0].patientFullName;
            el('ddlPtnTypByUser').value = 'ALL';
            search();
            return;
        }
        state.ipFilter = null;
        el('txtPatientName').value = '';
        alertMsg('IP Number Not Found', function () { el('txtIpNo').value = ''; search(); });
    }

    function clearAll() {
        // btnClear_Click
        ['txtDocCd', 'txtDocName', 'txtWardCd', 'txtWardDesc', 'txtIpNo', 'txtPatientName', 'txtSpecialityCd', 'txtFlr', 'txtFlrname', 'txtSpecialityDCd']
            .forEach(function (id) { el(id).value = ''; });
        el('drpmrdsts').value = '0';
        var d = state.init;
        el('ddlPtnTypByUser').value = d && d.defaultPtnTyp != null ? String(d.defaultPtnTyp) : 'ALL';
        if (!el('ddlPtnTypByUser').value) el('ddlPtnTypByUser').value = 'ALL';
        if (d && d.defaultWard) {
            el('txtWardCd').value = d.defaultWard.code;
            el('txtWardDesc').value = d.defaultWard.desc;
        }
        ['txtWardCd', 'txtDocCd', 'txtSpecialityCd', 'txtFlr'].forEach(markCommitted);
        search();
    }

    function bindSearchHeader() {
        bindCodeFields();

        var ipInput = el('txtIpNo');
        ipInput.addEventListener('input', function () { this.value = this.value.replace(/[^0-9]/g, ''); });   // ValidateNum
        ipInput.addEventListener('keydown', function (e) { if (e.key === 'Enter') { e.preventDefault(); ipInput.blur(); } });
        ipInput.addEventListener('change', ipNoChanged);

        el('txtPatientName').addEventListener('input', applyNameFilter);

        el('ddlPtnTypByUser').addEventListener('change', function () {
            el('txtIpNo').value = ''; el('txtPatientName').value = ''; search();
        });
        ['chkHWC', 'chkIsVuln', 'chkIsIsolated', 'chkIsArrivedOnBed'].forEach(function (id) { el(id).addEventListener('change', function () { search(); }); });
        el('drpmrdsts').addEventListener('change', function () { search(); });

        el('btnSetDefaultWard').addEventListener('click', function () {
            api('ward/default', { wardCd: Number(el('txtWardCd').value) || 0, wardDesc: el('txtWardDesc').value })
                .then(function (r) { alertMsg(r.message); }).catch(fail);
        });

        el('btnMoreFilters').addEventListener('click', function () { setFiltersOpen(el('moreFilters').hidden); });
        var savedOpen = load('ns.filtersOpen');
        setFiltersOpen(!!savedOpen);                    // collapsed by default; active filters show as tags

        el('btnGridview').addEventListener('click', function () { setView('G'); });
        el('btncardview').addEventListener('click', function () { setView('C'); });
        el('btnRefresh').addEventListener('click', function () { search({ refresh: true, keepScroll: true }); });
        el('btnClear').addEventListener('click', clearAll);
        el('btnexit').addEventListener('click', function () { exitTo(state.init ? state.init.exitUrl : './'); });
    }

    // ------------------------------------------------------------------ wiring
    $(function () {
        bindSearchHeader();
        bindPointer(el('grdInPatientDtl').tBodies[0], 'tr[data-ip]');
        bindPointer(el('pnlcardview'), '.row_dd2[data-ip]');
        bindLos();

        el('custommenu').addEventListener('click', function (e) {
            var a = e.target.closest('a[data-key]');
            if (!a) return;
            e.preventDefault();
            openModule(a.getAttribute('data-key'), state.menuIp);
        });
        document.addEventListener('pointerdown', function (e) {
            if (!e.target.closest('#custommenu')) hideMenu();
            if (suggestFor && !e.target.closest('.ns-code')) hideSuggest();
        }, true);
        document.addEventListener('keydown', function (e) { if (e.key === 'Escape') { hideMenu(); hideSuggest(); } });
        ['pnlgrdview', 'pnlcardview'].forEach(function (id) { el(id).addEventListener('scroll', hideMenu, { passive: true }); });
        window.addEventListener('scroll', function () { if (!el('custommenu').classList.contains('sheet')) hideMenu(); }, { passive: true });
        window.addEventListener('resize', hideMenu);

        el('hostBack').addEventListener('click', backToNurseStation);
        window.addEventListener('message', function (e) {
            if (e.origin !== location.origin || !e.data || e.data.type !== 'ns-module-exit') return;
            closeInstance(e.data.key, true);
        });

        start();
    });
})(jQuery);
