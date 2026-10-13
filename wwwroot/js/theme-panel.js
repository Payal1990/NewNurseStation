/* =====================================================================
   Nurse Station — Theme Panel
   Lets the user choose colour presets, field style and layout density.
   Preferences are stored in localStorage and re-applied on every load.
   ===================================================================== */
(function () {
    'use strict';

    var STORE_KEY = 'ns.appearance';

    // ---------- colour presets ----------
    var PRESETS = [
        { id: 'teal',     name: 'Teal',       header: '#1a4a5a', header2: '#2a6878', accent: '#0e8c74', sel: '#e4eef1', selBar: '#2a6878' },
        { id: 'blue',     name: 'Ocean Blue', header: '#1a3a6a', header2: '#2a5a8a', accent: '#2563eb', sel: '#e4ecf7', selBar: '#2a5a8a' },
        { id: 'slate',    name: 'Slate',      header: '#1e293b', header2: '#334155', accent: '#64748b', sel: '#e9ecf0', selBar: '#334155' },
        { id: 'aqua',     name: 'Aqua',       header: '#0e4a56', header2: '#0e7490', accent: '#06b6d4', sel: '#e1f2f5', selBar: '#0e7490' },
        { id: 'graphite', name: 'Graphite',   header: '#18181b', header2: '#3f3f46', accent: '#14b8a6', sel: '#e8eceb', selBar: '#3f3f46' }
    ];

    var FIELDS = [
        { id: 'rounded',    name: 'Rounded',    desc: 'Soft rounded corners' },
        { id: 'square',     name: 'Square',     desc: 'Clean sharp edges' },
        { id: 'outlined',   name: 'Outlined',   desc: 'Transparent with visible border' },
        { id: 'underlined', name: 'Underlined', desc: 'Minimal bottom-border only' }
    ];

    var DENSITIES = [
        { id: 'compact',     name: 'Compact',     desc: 'More data, less space' },
        { id: 'comfortable', name: 'Comfortable', desc: 'Balanced layout (default)' },
        { id: 'spacious',    name: 'Spacious',    desc: 'Generous padding and text' }
    ];

    // ---------- helpers ----------
    function el(id) { return document.getElementById(id); }
    function lum(hex) {
        var r = parseInt(hex.slice(1, 3), 16) / 255,
            g = parseInt(hex.slice(3, 5), 16) / 255,
            b = parseInt(hex.slice(5, 7), 16) / 255;
        r = r <= 0.03928 ? r / 12.92 : Math.pow((r + 0.055) / 1.055, 2.4);
        g = g <= 0.03928 ? g / 12.92 : Math.pow((g + 0.055) / 1.055, 2.4);
        b = b <= 0.03928 ? b / 12.92 : Math.pow((b + 0.055) / 1.055, 2.4);
        return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    }

    // ---------- state ----------
    var prefs = load();
    if (!PRESETS.some(function (p) { return p.id === prefs.color; })) prefs.color = 'teal';

    function load() {
        try {
            var s = JSON.parse(localStorage.getItem(STORE_KEY));
            if (s && s.color) return s;
        } catch (e) {}
        return { color: 'teal', field: 'rounded', density: 'comfortable' };
    }
    function save() {
        try { localStorage.setItem(STORE_KEY, JSON.stringify(prefs)); } catch (e) {}
    }

    // ---------- apply ----------
    function applyColor(id) {
        var p = PRESETS.filter(function (x) { return x.id === id; })[0];
        if (!p) p = PRESETS[0];
        var root = document.documentElement.style;
        root.setProperty('--header', p.header);
        root.setProperty('--header-2', p.header2);
        root.setProperty('--sel', p.sel);
        root.setProperty('--sel-bar', p.selBar);
        root.setProperty('--focus-ring', hexToRgba(p.header, .16));

        var meta = document.querySelector('meta[name="theme-color"]');
        if (meta) meta.setAttribute('content', p.header);
    }

    function hexToRgba(hex, a) {
        var r = parseInt(hex.slice(1, 3), 16),
            g = parseInt(hex.slice(3, 5), 16),
            b = parseInt(hex.slice(5, 7), 16);
        return 'rgba(' + r + ',' + g + ',' + b + ',' + a + ')';
    }

    function applyField(id) {
        var root = document.documentElement;
        if (id === 'rounded') root.removeAttribute('data-field');
        else root.setAttribute('data-field', id);
    }

    function applyDensity(id) {
        var root = document.documentElement;
        if (id === 'comfortable') root.removeAttribute('data-density');
        else root.setAttribute('data-density', id);
    }

    function applyAll() {
        applyColor(prefs.color);
        applyField(prefs.field);
        applyDensity(prefs.density);
    }

    // ---------- render panel ----------
    function renderSwatches() {
        var container = el('themeSwatches');
        if (!container) return;
        container.innerHTML = PRESETS.map(function (p) {
            var grad = 'linear-gradient(135deg,' + p.header + ' 0%,' + p.header2 + ' 55%,' + p.accent + ' 100%)';
            return '<button type="button" class="theme-swatch' + (prefs.color === p.id ? ' active' : '') + '" data-color="' + p.id + '">' +
                '<span class="swatch-preview" style="background:' + grad + '">' +
                    '<span class="swatch-accent" style="background:' + p.accent + '"></span>' +
                    '<span class="swatch-tick" aria-hidden="true"></span>' +
                '</span>' +
                '<span class="swatch-name">' + p.name + '</span>' +
            '</button>';
        }).join('');
    }

    function renderFields() {
        var container = el('themeFields');
        if (!container) return;
        container.innerHTML = FIELDS.map(function (f) {
            return '<button type="button" class="theme-opt' + (prefs.field === f.id ? ' active' : '') + '" data-field="' + f.id + '">' +
                '<span class="opt-preview fp-' + f.id + '"><span class="fp-row" style="width:60%"></span><span class="fp-row" style="width:100%"></span></span>' +
                '<span class="opt-name">' + f.name + '</span>' +
                '<span class="opt-tick" aria-hidden="true"></span>' +
            '</button>';
        }).join('');
    }

    function renderDensity() {
        var container = el('themeDensity');
        if (!container) return;
        container.innerHTML = DENSITIES.map(function (d) {
            return '<button type="button" class="theme-opt' + (prefs.density === d.id ? ' active' : '') + '" data-density="' + d.id + '">' +
                '<span class="opt-preview dp-rows dp-' + d.id + '"><span class="dp-bar"></span><span class="dp-bar"></span><span class="dp-bar"></span></span>' +
                '<span class="opt-name">' + d.name + '</span>' +
                '<span class="opt-tick" aria-hidden="true"></span>' +
            '</button>';
        }).join('');
    }

    function updateActive(container, attr, value) {
        if (!container) return;
        var items = container.querySelectorAll('[data-' + attr + ']');
        for (var i = 0; i < items.length; i++) {
            items[i].classList.toggle('active', items[i].getAttribute('data-' + attr) === value);
        }
    }

    // ---------- panel open / close ----------
    function showPanel() {
        renderSwatches();
        renderFields();
        renderDensity();
        el('themeOverlay').hidden = false;
        el('themePanel').hidden = false;
    }
    function hidePanel() {
        el('themeOverlay').hidden = true;
        el('themePanel').hidden = true;
    }

    // ---------- quick cycle (appbar long-press or click) ----------
    var presetIndex = 0;
    function cycleColor() {
        presetIndex = (presetIndex + 1) % PRESETS.length;
        prefs.color = PRESETS[presetIndex].id;
        applyColor(prefs.color);
        save();
        updateActive(el('themeSwatches'), 'color', prefs.color);
    }

    // ---------- bind events ----------
    function bind() {
        var toggle = el('btnThemeToggle');
        if (!toggle) return;

        toggle.addEventListener('click', function () { showPanel(); });

        el('themeClose').addEventListener('click', hidePanel);
        el('themeOverlay').addEventListener('click', hidePanel);

        el('themeSwatches').addEventListener('click', function (e) {
            var btn = e.target.closest('[data-color]');
            if (!btn) return;
            prefs.color = btn.getAttribute('data-color');
            applyColor(prefs.color);
            save();
            updateActive(el('themeSwatches'), 'color', prefs.color);
            presetIndex = PRESETS.map(function (p) { return p.id; }).indexOf(prefs.color);
        });

        el('themeFields').addEventListener('click', function (e) {
            var opt = e.target.closest('[data-field]');
            if (!opt) return;
            prefs.field = opt.getAttribute('data-field');
            applyField(prefs.field);
            save();
            updateActive(el('themeFields'), 'field', prefs.field);
        });

        el('themeDensity').addEventListener('click', function (e) {
            var opt = e.target.closest('[data-density]');
            if (!opt) return;
            prefs.density = opt.getAttribute('data-density');
            applyDensity(prefs.density);
            save();
            updateActive(el('themeDensity'), 'density', prefs.density);
        });

        el('themeReset').addEventListener('click', function () {
            prefs = { color: 'teal', field: 'rounded', density: 'comfortable' };
            applyAll();
            save();
            renderSwatches();
            renderFields();
            renderDensity();
            presetIndex = 0;
        });
    }

    // ---------- init ----------
    applyAll();
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', bind);
    } else {
        bind();
    }

    // Sync preset index
    for (var i = 0; i < PRESETS.length; i++) {
        if (PRESETS[i].id === prefs.color) { presetIndex = i; break; }
    }

    window.NsAppearance = { apply: applyAll, show: showPanel, hide: hidePanel, cycle: cycleColor };
})();
