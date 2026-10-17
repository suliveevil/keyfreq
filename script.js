/* Keyfreq heat-map renderer.
 *
 * The report is a self-contained HTML file: one <section data-mode="...">
 * per major mode, each holding a <canvas> and a <table>.  Shortcuts are
 * stored as <code data-count="N">C-n, &lt;down&gt;</code>, so the renderer
 * never has to build a CSS selector out of a mode name (mode names may
 * contain "/" or other characters that are not valid in a selector).
 */
(function () {
    "use strict";

    /* Apple keyboard layout, in key units.  Kept as a single constant so
       it is not rebuilt for every canvas. */
    var LAYOUT = [
        // Top row
        {name: ['ESC'], x: 0, y: 0, width: 1.04, height: 0.75},
        {name: ['F1'], x: 1.04, y: 0, width: 1.0357, height: 0.75},
        {name: ['F2'], x: 2.08, y: 0, width: 1.0357, height: 0.75},
        {name: ['F3'], x: 3.12, y: 0, width: 1.0357, height: 0.75},
        {name: ['F4'], x: 4.16, y: 0, width: 1.0357, height: 0.75},
        {name: ['F5'], x: 5.20, y: 0, width: 1.0357, height: 0.75},
        {name: ['F6'], x: 6.24, y: 0, width: 1.0357, height: 0.75},
        {name: ['F7'], x: 7.28, y: 0, width: 1.0357, height: 0.75},
        {name: ['F8'], x: 8.32, y: 0, width: 1.0357, height: 0.75},
        {name: ['F9'], x: 9.36, y: 0, width: 1.0357, height: 0.75},
        {name: ['F10'], x: 10.40, y: 0, width: 1.0357, height: 0.75},
        {name: ['F11'], x: 11.44, y: 0, width: 1.0357, height: 0.75},
        {name: ['F12'], x: 12.48, y: 0, width: 1.0357, height: 0.75},
        {name: ['⏏'], x: 13.52, y: 0, width: 1, height: 0.75},
        // First row
        {name: ['~', '`'], x: 0, y: 1.25, width: 1, height: 1},
        {name: ['!', '1'], x: 1, y: 1.25, width: 1, height: 1},
        {name: ['@', '2'], x: 2, y: 1.25, width: 1, height: 1},
        {name: ['#', '3'], x: 3, y: 1.25, width: 1, height: 1},
        {name: ['$', '4'], x: 4, y: 1.25, width: 1, height: 1},
        {name: ['%', '5'], x: 5, y: 1.25, width: 1, height: 1},
        {name: ['^', '6'], x: 6, y: 1.25, width: 1, height: 1},
        {name: ['&', '7'], x: 7, y: 1.25, width: 1, height: 1},
        {name: ['*', '8'], x: 8, y: 1.25, width: 1, height: 1},
        {name: ['(', '9'], x: 9, y: 1.25, width: 1, height: 1},
        {name: [')', '0'], x: 10, y: 1.25, width: 1, height: 1},
        {name: ['_', '-'], x: 11, y: 1.25, width: 1, height: 1},
        {name: ['+', '='], x: 12, y: 1.25, width: 1, height: 1},
        {name: ['backspace'], x: 13, y: 1.25, width: 1.5, height: 1},
        // Second row
        {name: ['TAB'], x: 0, y: 2.25, width: 1.5, height: 1},
        {name: ['q'], x: 1.5, y: 2.25, width: 1, height: 1},
        {name: ['w'], x: 2.5, y: 2.25, width: 1, height: 1},
        {name: ['e'], x: 3.5, y: 2.25, width: 1, height: 1},
        {name: ['r'], x: 4.5, y: 2.25, width: 1, height: 1},
        {name: ['t'], x: 5.5, y: 2.25, width: 1, height: 1},
        {name: ['y'], x: 6.5, y: 2.25, width: 1, height: 1},
        {name: ['u'], x: 7.5, y: 2.25, width: 1, height: 1},
        {name: ['i'], x: 8.5, y: 2.25, width: 1, height: 1},
        {name: ['o'], x: 9.5, y: 2.25, width: 1, height: 1},
        {name: ['p'], x: 10.5, y: 2.25, width: 1, height: 1},
        {name: ['{', '['], x: 11.5, y: 2.25, width: 1, height: 1},
        {name: ['}', ']'], x: 12.5, y: 2.25, width: 1, height: 1},
        {name: ['|', '\\'], x: 13.5, y: 2.25, width: 1, height: 1},
        // Third row
        {name: ['CAPSLOCK'], x: 0, y: 3.25, width: 1.75, height: 1},
        {name: ['a'], x: 1.75, y: 3.25, width: 1, height: 1},
        {name: ['s'], x: 2.75, y: 3.25, width: 1, height: 1},
        {name: ['d'], x: 3.75, y: 3.25, width: 1, height: 1},
        {name: ['f'], x: 4.75, y: 3.25, width: 1, height: 1},
        {name: ['g'], x: 5.75, y: 3.25, width: 1, height: 1},
        {name: ['h'], x: 6.75, y: 3.25, width: 1, height: 1},
        {name: ['j'], x: 7.75, y: 3.25, width: 1, height: 1},
        {name: ['k'], x: 8.75, y: 3.25, width: 1, height: 1},
        {name: ['l'], x: 9.75, y: 3.25, width: 1, height: 1},
        {name: [':', ';'], x: 10.75, y: 3.25, width: 1, height: 1},
        {name: ['"', "'"], x: 11.75, y: 3.25, width: 1, height: 1},
        {name: ['RET'], x: 12.75, y: 3.25, width: 1.75, height: 1},
        // Fourth row
        {name: ['S'], x: 0, y: 4.25, width: 2.25, height: 1},
        {name: ['z'], x: 2.25, y: 4.25, width: 1, height: 1},
        {name: ['x'], x: 3.25, y: 4.25, width: 1, height: 1},
        {name: ['c'], x: 4.25, y: 4.25, width: 1, height: 1},
        {name: ['v'], x: 5.25, y: 4.25, width: 1, height: 1},
        {name: ['b'], x: 6.25, y: 4.25, width: 1, height: 1},
        {name: ['n'], x: 7.25, y: 4.25, width: 1, height: 1},
        {name: ['m'], x: 8.25, y: 4.25, width: 1, height: 1},
        {name: ['<', ','], x: 9.25, y: 4.25, width: 1, height: 1},
        {name: ['>', '.'], x: 10.25, y: 4.25, width: 1, height: 1},
        {name: ['?', '/'], x: 11.25, y: 4.25, width: 1, height: 1},
        {name: ['RSHIFT'], x: 12.25, y: 4.25, width: 2.25, height: 1},
        // Fifth row
        {name: ['G'], x: 0, y: 5.25, width: 1, height: 1},
        {name: ['C'], x: 1, y: 5.25, width: 1, height: 1},
        {name: ['M'], x: 2, y: 5.25, width: 1, height: 1},
        {name: ['CMD'], x: 3, y: 5.25, width: 1.25, height: 1},
        {name: ['SPC'], x: 4.25, y: 5.25, width: 5, height: 1},
        {name: ['R_CMD'], x: 9.25, y: 5.25, width: 1.25, height: 1},
        {name: ['R_OPT'], x: 10.5, y: 5.25, width: 1, height: 1},
        {name: ['left'], x: 11.5, y: 5.75, width: 1, height: 0.5},
        {name: ['up'], x: 12.5, y: 5.25, width: 1, height: 0.5},
        {name: ['down'], x: 12.5, y: 5.75, width: 1, height: 0.5},
        {name: ['right'], x: 13.5, y: 5.75, width: 1, height: 0.5}
    ];

    var LEGEND_W = 2.5;                 // keys of horizontal room for the scale
    var MODIFIERS = ["C", "S", "M", "G", "s"];

    /* Blue -> cyan -> green -> yellow -> red, matching the old scale. */
    function heatColor(value, opacity) {
        var x = Math.max(0, Math.min(1, value)) * 255;
        var r, g, b;
        if (x < 64) {
            r = 0; g = x * 4; b = 255;
        } else if (x < 128) {
            r = 0; g = 255; b = 255 - (x - 64) * 4;
        } else if (x < 192) {
            r = (x - 128) * 4; g = 255; b = 0;
        } else {
            r = 255; g = 256 - (x - 191) * 4; b = 0;
        }
        return "rgba(" + Math.round(r) + "," + Math.round(g) + "," +
            Math.round(b) + "," + opacity + ")";
    }

    /* "C-x C-s", "<menu-bar> <file>" and the like. */
    function splitShortcut(text) {
        return String(text || "")
            .split(",")
            .map(function (s) { return s.trim(); })
            .filter(function (s) { return s.length > 0; });
    }

    /* menu-bar / tool-bar / mouse paths are not keystrokes. */
    var PSEUDO = /<[^>]*(menu-bar|tool-bar|tab-bar|mode-line|scroll-bar|divider|vertical-line)/i;

    function isPseudo(binding) {
        return PSEUDO.test(binding) || /mouse|wheel/i.test(binding);
    }

    /* keyfreq counts commands, not keys.  A command usually has several
       bindings (next-line is both C-n and <down>), so crediting every one
       of them would multiply the counts.  Only the first binding that is
       a real keystroke is taken as the representative one. */
    function firstBinding(text) {
        var parts = String(text || "").split(",");
        for (var i = 0; i < parts.length; i++) {
            var part = parts[i].trim();
            if (part && !isPseudo(part)) return part;
        }
        return null;
    }

    /* "C-x C-s" -> ["C","x","C","s"];  "<down-mouse-1>" is skipped. */
    function shortcutKeys(binding) {
        if (/mouse/i.test(binding)) return [];
        return binding
            .replace(/[<>]/g, " ")
            .split(/[\s]+/)
            .reduce(function (acc, chord) {
                return acc.concat(chord.split("-"));
            }, [])
            .map(function (s) { return s.trim(); })
            .filter(function (s) { return s.length > 0; });
    }

    function keyFrequency(table, skip) {
        var freq = Object.create(null);
        var cells = table.querySelectorAll("td[data-count]");
        for (var i = 0; i < cells.length; i++) {
            var count = parseInt(cells[i].getAttribute("data-count"), 10);
            if (!count) continue;
            var binding = firstBinding(cells[i].textContent);
            if (!binding) continue;
            var keys = shortcutKeys(binding);
            var counted = Object.create(null);
            for (var k = 0; k < keys.length; k++) {
                var key = keys[k];
                if (skip.indexOf(key) >= 0) continue;
                if (counted[key]) continue;       // once per command
                counted[key] = true;
                freq[key] = (freq[key] || 0) + count;
            }
        }
        return freq;
    }

    function mapsToKey(name) {
        for (var i = 0; i < LAYOUT.length; i++) {
            if (LAYOUT[i].name.indexOf(name) >= 0) return true;
        }
        return false;
    }

    /* ---------- geometry and colour ---------- */

    var U = 34;                 /* one key unit, CSS px */
    var GAP = 2;                /* gap between key caps */
    var RADIUS = 6;

    function roundRect(ctx, x, y, w, h, r) {
        var radius = Math.min(r, w / 2, h / 2);
        ctx.beginPath();
        ctx.moveTo(x + radius, y);
        ctx.arcTo(x + w, y, x + w, y + h, radius);
        ctx.arcTo(x + w, y + h, x, y + h, radius);
        ctx.arcTo(x, y + h, x, y, radius);
        ctx.arcTo(x, y, x + w, y, radius);
        ctx.closePath();
    }

    /* One accent ramp instead of a rainbow: a neutral key cap reddens as it
       gets hotter.  A rainbow (jet) ramp invents boundaries that are not in
       the data; this reads the way a heat map should. */
    function heatRGB(t) {
        t = Math.max(0, Math.min(1, t));
        return [Math.round(236 + (203 - 236) * t),
                Math.round(236 + (0 - 236) * t),
                Math.round(239 + (0 - 239) * t)];
    }

    function applyScale(value, max, mode) {
        if (!max) return 0;
        if (mode === "log") return Math.log1p(value) / Math.log1p(max);
        if (mode === "sqrt") return Math.sqrt(value / max);
        return value / max;
    }

    /* ---------- data ---------- */

    function readTable(section) {
        var cells = section.querySelectorAll("td[data-count]");
        var items = [];
        for (var i = 0; i < cells.length; i++) {
            items.push({
                count: parseInt(cells[i].getAttribute("data-count"), 10) || 0,
                text: cells[i].textContent
            });
        }
        return items;
    }

    function keyBag(items, skip) {
        var bag = Object.create(null);
        for (var i = 0; i < items.length; i++) {
            var item = items[i];
            if (!item.count) continue;
            var binding = firstBinding(item.text);
            if (!binding) continue;
            var keys = shortcutKeys(binding);
            var seen = Object.create(null);
            for (var k = 0; k < keys.length; k++) {
                var key = keys[k];
                if (seen[key] || skip.indexOf(key) >= 0) continue;
                if (!mapsToKey(key)) continue;
                seen[key] = true;
                bag[key] = (bag[key] || 0) + item.count;
            }
        }
        return bag;
    }

    /* ---------- drawing ---------- */

    var keyBoxes = [];          /* hit-test rectangles of the last draw */

    function draw(canvas, bag, scaleMode) {
        var dpr = window.devicePixelRatio || 1;
        var maxX = 0, maxY = 0;
        LAYOUT.forEach(function (k) {
            maxX = Math.max(maxX, k.x + k.width);
            maxY = Math.max(maxY, k.y + k.height);
        });

        var max = 0, total = 0;
        Object.keys(bag).forEach(function (name) {
            max = Math.max(max, bag[name]);
            total += bag[name];
        });

        var legendX = (maxX + 0.8) * U;
        var labelSize = Math.round(U * 0.32);
        var cssW = Math.round(legendX + U * 3.4);
        var cssH = Math.round((maxY + 0.6) * U);

        canvas.width = Math.round(cssW * dpr);
        canvas.height = Math.round(cssH * dpr);
        canvas.style.width = cssW + "px";
        canvas.style.height = cssH + "px";

        var ctx = canvas.getContext("2d");
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        ctx.clearRect(0, 0, cssW, cssH);

        var dark = window.matchMedia &&
            window.matchMedia("(prefers-color-scheme: dark)").matches;
        var surface = dark ? "#26262a" : "#eceef1";
        var ink = dark ? "#e8e8ea" : "#1d1d1f";
        var muted = dark ? "#9a9aa0" : "#6b6b70";
        var edge = dark ? "rgba(255,255,255,.10)" : "rgba(0,0,0,.10)";

        keyBoxes = [];
        ctx.textBaseline = "middle";
        ctx.font = (U * 0.26).toFixed(1) + "px -apple-system, Arial, sans-serif";

        LAYOUT.forEach(function (key) {
            var x = key.x * U + GAP / 2;
            var y = key.y * U + GAP / 2;
            var w = key.width * U - GAP;
            var h = key.height * U - GAP;
            var value = 0;
            key.name.forEach(function (n) { value += bag[n] || 0; });
            var t = applyScale(value, max, scaleMode);
            var rgb = heatRGB(t);
            var hot = t > 0.02;

            /* key cap: soft shadow, rounded, subtle border */
            ctx.save();
            ctx.shadowColor = dark ? "rgba(0,0,0,.55)" : "rgba(0,0,0,.10)";
            ctx.shadowBlur = 3;
            ctx.shadowOffsetY = 1;
            ctx.fillStyle = hot
                ? "rgb(" + rgb[0] + "," + rgb[1] + "," + rgb[2] + ")"
                : surface;
            roundRect(ctx, x, y, w, h, RADIUS);
            ctx.fill();
            ctx.restore();

            ctx.strokeStyle = hot ? "rgba(0,0,0,.12)" : edge;
            ctx.lineWidth = 1;
            roundRect(ctx, x + 0.5, y + 0.5, w - 1, h - 1, RADIUS - 0.5);
            ctx.stroke();

            /* label: dark on light keys, white once the key is hot */
            ctx.fillStyle = hot && t > 0.55 ? "#fff" : ink;
            var label = key.name[0];
            var tw = ctx.measureText(label).width;
            ctx.fillText(label, x + (w - tw) / 2, y + h / 2 + 0.5);

            keyBoxes.push({
                x: x, y: y, w: w, h: h,
                names: key.name,
                value: value,
                share: total ? value / total : 0
            });
        });

        /* legend: vertical ramp plus three labels */
        if (!max) return { max: 0, total: 0 };

        var barW = U * 0.55;
        var barTop = U * 0.7;
        var barH = maxY * U - U * 1.4;
        for (var i = 0; i < 120; i++) {
            var rgb2 = heatRGB(1 - i / 120);
            ctx.fillStyle = "rgb(" + rgb2[0] + "," + rgb2[1] + "," + rgb2[2] + ")";
            ctx.fillRect(legendX, barTop + (i * barH) / 120, barW, barH / 120 + 1);
        }
        ctx.strokeStyle = edge;
        ctx.lineWidth = 1;
        ctx.strokeRect(legendX + 0.5, barTop + 0.5, barW - 1, barH - 1);

        ctx.font = labelSize + "px -apple-system, Arial, sans-serif";
        ctx.fillStyle = ink;
        ctx.fillText(max.toLocaleString(), legendX + barW + 8, barTop);
        ctx.fillStyle = muted;
        ctx.fillText("0", legendX + barW + 8, barTop + barH);
        ctx.fillText(total.toLocaleString(), legendX + barW + 8,
                     barTop + labelSize + 10);
        ctx.fillText("presses", legendX + barW + 8,
                     barTop + labelSize * 2 + 12);

        return { max: max, total: total };
    }

    /* ---------- wiring ---------- */

    function sections() {
        return Array.prototype.slice.call(
            document.querySelectorAll("section[data-mode]"));
    }

    function boot() {
        var canvas = document.getElementById("heatmap");
        var modeSelect = document.getElementById("mode-select");
        if (!canvas || !modeSelect) return;

        var scaleSelect = document.getElementById("scale-select");
        var summary = document.getElementById("scope-summary");
        var emptyNote = document.getElementById("empty-note");
        var tip = document.getElementById("key-tip");
        var wrap = canvas.parentNode;
        var all = sections();
        var byMode = Object.create(null);
        all.forEach(function (section) {
            byMode[section.getAttribute("data-mode")] = section;
        });

        function render() {
            var mode = modeSelect.value;
            var section = byMode[mode] || byMode.all;
            var items = readTable(section);
            var bag = keyBag(items, []);
            var stats = draw(canvas, bag, scaleSelect ? scaleSelect.value : "sqrt");

            canvas.hidden = stats.max === 0;
            emptyNote.hidden = stats.max !== 0;
            if (stats.max === 0) {
                emptyNote.textContent = mode === "all"
                    ? "no keyboard shortcuts recorded"
                    : "no keyboard shortcuts in " + mode;
            }
            if (summary) {
                summary.textContent = (mode === "all" ? "all modes" : mode) +
                    " \u00b7 " + stats.total.toLocaleString() + " presses";
            }
            tip.hidden = true;
        }

        /* hover detail */
        canvas.addEventListener("mousemove", function (event) {
            var rect = canvas.getBoundingClientRect();
            var dpr = window.devicePixelRatio || 1;
            /* the canvas may be scaled down by CSS max-width */
            var sx = canvas.width / dpr / rect.width;
            var sy = canvas.height / dpr / rect.height;
            var x = (event.clientX - rect.left) * sx;
            var y = (event.clientY - rect.top) * sy;

            var hit = null;
            for (var i = 0; i < keyBoxes.length; i++) {
                var b = keyBoxes[i];
                if (x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h) {
                    hit = b;
                    break;
                }
            }
            if (!hit) { tip.hidden = true; canvas.style.cursor = "default"; return; }
            canvas.style.cursor = "pointer";
            tip.hidden = false;
            tip.innerHTML = "<b>" + hit.names[0] + "</b> " +
                hit.value.toLocaleString() + " presses" +
                (hit.share ? " \u00b7 " + (hit.share * 100).toFixed(1) + "%" : "");
            var left = event.clientX - rect.left + 14;
            var top = event.clientY - rect.top + 14;
            if (left + tip.offsetWidth > rect.width) left = rect.width - tip.offsetWidth - 8;
            tip.style.left = left + "px";
            tip.style.top = top + "px";
        });
        canvas.addEventListener("mouseleave", function () { tip.hidden = true; });

        modeSelect.addEventListener("change", render);
        if (scaleSelect) scaleSelect.addEventListener("change", render);
        render();
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", boot);
    } else {
        boot();
    }
}());
