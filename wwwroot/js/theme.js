/* =====================================================================
   Nurse Station — theme from the installation's suite stylesheets.

   Every legacy module takes its colours from the shared suite CSS the
   installation serves (CSS_serverpath: Master.css, stylesheet.css,
   ButtonStyles.css). This file loads those same files in a hidden frame
   (so they cannot clash with the tablet layout), reads the colours of the
   suite's own classes, and maps them to the tablet's CSS variables.

     #menu background            -> header bar          (--brand, --brand-2)
     .gridcolumnheader background-> accent              (--accent, --accent-soft)
     .buttonstandard background  -> primary buttons     (--btn)
     .divSearchHeader background -> soft tint           (--accent-soft)
     body background             -> page background     (--bg)
     .headerred colour           -> danger              (--danger)

   Theme:Colors in appsettings.json overrides individual colours by friendly
   name (header, accent, button, tint, background, danger). The result is cached so the next load paints
   with the right colours immediately.
   ===================================================================== */
(function () {
    'use strict';

    var CACHE_KEY = 'ns.theme.v1';

    // ---------- colour helpers ----------
    function parse(c) {
        if (!c) return null;
        var m = /rgba?\(\s*([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)(?:[,\s/]+([\d.]+))?/.exec(c);
        if (m) {
            var a = m[4] === undefined ? 1 : Number(m[4]);
            return a < 0.5 ? null : [Number(m[1]), Number(m[2]), Number(m[3])];
        }
        m = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(String(c).trim());
        if (!m) return null;
        var h = m[1].length === 3 ? m[1].replace(/(.)/g, '$1$1') : m[1];
        return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
    }
    function hex(rgb) {
        return '#' + rgb.map(function (v) { return ('0' + Math.round(Math.max(0, Math.min(255, v))).toString(16)).slice(-2); }).join('');
    }
    function mix(a, b, t) { return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]; }
    var WHITE = [255, 255, 255], BLACK = [0, 0, 0];
    function luminance(rgb) {
        var c = rgb.map(function (v) { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); });
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
    }
    function onColor(rgb) { return luminance(rgb) > 0.45 ? '#1e293b' : '#ffffff'; }
    function isGrey(rgb) { return Math.max.apply(null, rgb) - Math.min.apply(null, rgb) < 12; }

    // ---------- build CSS variables from the measured suite colours ----------
    function tokens(src) {
        var t = {};
        var menu = parse(src.menu), grid = parse(src.grid), btn = parse(src.button),
            tint = parse(src.searchHeader), body = parse(src.body), danger = parse(src.danger);

        if (menu) {
            t['--brand-2'] = hex(menu);
            t['--brand'] = hex(mix(menu, BLACK, 0.22));
            t['--on-brand'] = onColor(menu);
        }
        var accent = grid || btn;
        if (accent) {
            t['--accent'] = hex(accent);
            t['--accent-strong'] = hex(mix(accent, BLACK, 0.18));
            t['--on-accent'] = onColor(accent);
            t['--accent-soft'] = tint && luminance(tint) > 0.75 && !isGrey(tint) ? hex(tint) : hex(mix(accent, WHITE, 0.88));
            t['--focus-ring'] = 'rgba(' + accent.map(Math.round).join(',') + ',.18)';
        }
        if (btn) {
            t['--btn'] = hex(btn);
            t['--btn-strong'] = hex(mix(btn, BLACK, 0.18));
            t['--on-btn'] = onColor(btn);
        }
        if (body) t['--bg'] = hex(mix(body, WHITE, 0.55));      // softened: legacy page grey behind white cards
        if (danger) t['--danger'] = hex(danger);
        return t;
    }

    function apply(vars) {
        var root = document.documentElement.style;
        Object.keys(vars || {}).forEach(function (k) { root.setProperty(k, vars[k]); });
        if (vars && vars['--brand']) {
            var meta = document.querySelector('meta[name="theme-color"]');
            if (meta) meta.setAttribute('content', vars['--brand']);
        }
    }

    // Theme:Colors overrides (appsettings.json). Friendly names; each derives its matching shades
    // the same way the measured suite colours do.
    //   header     -> header bar, ward labels, bed badges   (replaces #menu colour)
    //   accent     -> counts, focus, active states           (replaces .gridcolumnheader colour)
    //   button     -> primary buttons                        (replaces .buttonstandard colour)
    //   tint       -> soft accent backgrounds                (replaces .divSearchHeader colour)
    //   background -> page background                        (replaces body colour)
    //   danger     -> Exit / warnings                        (replaces .headerred colour)
    var ALIASES = { header: 'menu', brand: 'menu', menu: 'menu', accent: 'grid', grid: 'grid', button: 'button', btn: 'button',
                    tint: 'searchHeader', background: 'body', bg: 'body', danger: 'danger' };

    function overrides(colors) {
        var src = {};
        Object.keys(colors || {}).forEach(function (k) {
            var key = ALIASES[k.toLowerCase()];
            if (key && parse(colors[k])) src[key] = colors[k];
        });
        var t = tokens(src);
        // tokens() softens "body" for the page; an explicit background is used exactly as given.
        if (src.body) t['--bg'] = hex(parse(src.body));
        if (src.searchHeader && !t['--accent-soft']) t['--accent-soft'] = hex(parse(src.searchHeader));
        return t;
    }

    // ---------- read the suite stylesheets in an isolated frame ----------
    function measure(cssPath) {
        return new Promise(function (resolve) {
            var frame = document.createElement('iframe');
            frame.setAttribute('aria-hidden', 'true');
            frame.tabIndex = -1;
            frame.style.cssText = 'position:absolute;width:1px;height:1px;left:-9999px;top:-9999px;border:0;visibility:hidden';
            document.body.appendChild(frame);

            var doc = frame.contentDocument;
            var base = new URL(cssPath.replace(/\/+$/, '') + '/', location.href).href.replace(/\/+$/, '');
            doc.open();
            doc.write('<!DOCTYPE html><html><head>' +
                ['Master.css', 'stylesheet.css', 'ButtonStyles.css'].map(function (f) {
                    return '<link rel="stylesheet" href="' + base + '/' + f + '">';
                }).join('') +
                '</head><body>' +
                '<div id="main_container"><div id="header"><div id="menu"></div></div></div>' +
                '<div class="gridcolumnheader"></div><input type="button" class="buttonstandard">' +
                '<div class="divSearchHeader"></div><span class="headerred"></span>' +
                '</body></html>');
            doc.close();

            var links = Array.prototype.slice.call(doc.querySelectorAll('link'));
            var pending = links.length, done = false;

            function finish() {
                if (done) return;
                done = true;
                var w = frame.contentWindow, d = frame.contentDocument, out = null;
                try {
                    var bg = function (sel) { var e = d.querySelector(sel); return e ? w.getComputedStyle(e).backgroundColor : null; };
                    out = {
                        menu: bg('#menu'),
                        grid: bg('.gridcolumnheader'),
                        button: bg('.buttonstandard'),
                        searchHeader: bg('.divSearchHeader'),
                        body: w.getComputedStyle(d.body).backgroundColor,
                        danger: w.getComputedStyle(d.querySelector('.headerred')).color,
                    };
                } catch (e) { out = null; }
                frame.parentNode && frame.parentNode.removeChild(frame);
                resolve(out);
            }

            links.forEach(function (l) {
                l.addEventListener('load', function () { if (--pending <= 0) finish(); });
                l.addEventListener('error', function () { if (--pending <= 0) finish(); });
            });
            setTimeout(finish, 5000);   // never block the page on a slow stylesheet server
        });
    }

    var NsTheme = {
        /** Paint immediately with the last theme this device saw for this installation. */
        applyCached: function () {
            try { var c = JSON.parse(localStorage.getItem(CACHE_KEY)); if (c && c.vars) apply(c.vars); } catch (e) { }
        },

        /** Read the installation's suite colours, apply them and cache them. */
        load: function (theme) {
            theme = theme || {};
            var cssPath = theme.cssPath || 'CSS';
            var forced = overrides(theme.colors);
            apply(forced);
            return measure(cssPath).then(function (src) {
                var vars = Object.assign({}, src ? tokens(src) : {}, forced);
                apply(vars);
                try { localStorage.setItem(CACHE_KEY, JSON.stringify({ cssPath: cssPath, vars: vars, at: Date.now() })); } catch (e) { }
                return vars;
            });
        },

        _tokens: tokens,
    };

    window.NsTheme = NsTheme;
    NsTheme.applyCached();
})();
