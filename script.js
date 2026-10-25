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
    /* What the key cap actually prints.  The names in LAYOUT stay the ones
       the data is keyed on; these are only what gets drawn. */
    var KEY_LABEL = {
        "ESC": "esc",
        "TAB": "\u21e5",
        "CAPSLOCK": "\u21ea",
        "backspace": "\u232b",
        "RET": "\u21a9",
        "S": "\u21e7",
        "RSHIFT": "\u21e7",
        "SPC": "space",
        "C": "\u2303",
        "M": "\u2325",
        "CMD": "\u2318",
        "R_CMD": "\u2318",
        "R_OPT": "\u2325",
        "G": "fn",
        "left": "\u2190",
        "up": "\u2191",
        "down": "\u2193",
        "right": "\u2192",
        "\u23cf": "\u23fb"
    };

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

    /* Emacs key descriptions put the modifiers first: C- M- S- s- H- A-.
       `s-' is Super -- the macOS Command key -- so the leading letter must
       not be mistaken for the letter key of the same name. */
    var MODIFIER_KEYCAP = {
        "C": "C",       /* Control */
        "M": "M",       /* Meta, the Option key */
        "S": "S",       /* Shift */
        "s": "CMD",     /* Super, the Command key */
        "A": "M",       /* Alt is the same physical key as Meta here */
        "H": null       /* Hyper has no key of its own */
    };

    /* "<return>" and friends mean a keycap that is not spelled that way. */
    var NAMED_KEYCAP = {
        "return": "RET", "ret": "RET", "newline": "RET", "linefeed": "RET",
        "space": "SPC", "tab": "TAB", "backtab": "TAB",
        "backspace": "backspace", "delete": "backspace",
        "deletechar": "backspace", "escape": "ESC", "esc": "ESC",
        "prior": null, "next": null, "home": null, "end": null
    };

    function parseChord(chord) {
        var modifiers = [];
        var rest = chord;
        var match = /^([CMSsHA])-/.exec(rest);
        while (match) {
            if (MODIFIER_KEYCAP[match[1]]) modifiers.push(MODIFIER_KEYCAP[match[1]]);
            rest = rest.slice(2);
            match = /^([CMSsHA])-/.exec(rest);
        }
        return { modifiers: modifiers, base: rest };
    }

    function keycapFor(base) {
        /* a modifier may prefix a named key, as in C-<left> */
        base = base.replace(/^</, "").replace(/>$/, "");
        var lower = base.toLowerCase();
        if (Object.prototype.hasOwnProperty.call(NAMED_KEYCAP, lower)) {
            return NAMED_KEYCAP[lower];
        }
        if (/^f([1-9]|1[0-2])$/.test(lower)) return "F" + lower.slice(1);
        return base;
    }

    /* "C-x C-s" -> ["C","x","C","s"];  "s-q" -> ["CMD","q"]. */
    function shortcutKeys(binding) {
        if (/mouse/i.test(binding)) return [];
        var out = [];
        String(binding).split(/\s+/).forEach(function (chord) {
            chord = chord.replace(/^</, "").replace(/>$/, "");
            if (!chord) return;
            var parsed = parseChord(chord);
            parsed.modifiers.forEach(function (name) { out.push(name); });
            var base = keycapFor(parsed.base);
            if (!base) return;
            /* an uppercase letter is shift plus that letter */
            if (/^[A-Z]$/.test(base)) {
                out.push("S");
                base = base.toLowerCase();
            }
            out.push(base);
        });
        return out;
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

    /* ---------- drawing ---------- */

    var keyBoxes = [];          /* hit-test rectangles of the last draw */

    var FAMILY = "-apple-system, BlinkMacSystemFont, Arial, sans-serif";

    function fitFont(ctx, text, maxWidth, size) {
        var px = size;
        while (px > 6) {
            ctx.font = px + "px " + FAMILY;
            if (ctx.measureText(text).width <= maxWidth) break;
            px -= 1;
        }
        return px;
    }

    /* A key with two legends (":" over ";") prints both, like the key cap
       does: the shifted symbol small in the upper left, the base symbol
       below it.  Everything else gets its printed name, centred. */
    function drawKeyLabel(ctx, key, x, y, w, h, unit) {
        var pad = Math.max(2, unit * 0.09);
        var room = w - pad * 2;
        if (key.name.length > 1) {
            ctx.textAlign = "left";
            ctx.textBaseline = "top";
            fitFont(ctx, key.name[0], room, Math.round(unit * 0.29));
            ctx.fillText(key.name[0], x + pad, y + pad);
            ctx.textBaseline = "bottom";
            fitFont(ctx, key.name[1], room, Math.round(unit * 0.40));
            ctx.fillText(key.name[1], x + pad, y + h - pad);
        } else {
            var name = key.name[0];
            var text = KEY_LABEL[name] ||
                (/^[a-z]$/.test(name) ? name.toUpperCase() : name);
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            fitFont(ctx, text, room, Math.round(unit * 0.30));
            ctx.fillText(text, x + w / 2, y + h / 2 + 1);
        }
        ctx.textAlign = "start";
        ctx.textBaseline = "alphabetic";
    }

    function draw(canvas, bag, scaleMode, focus, related) {
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
        /* a key that is out of focus: shape only, no heat */
        var mutedSurface = dark ? "#1e1e21" : "#f4f4f6";
        var mutedEdge = dark ? "rgba(255,255,255,.05)" : "rgba(0,0,0,.05)";
        var mutedInk = dark ? "#55555b" : "#c2c2c8";
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
            var isFocus = !!focus && key.name.indexOf(focus) >= 0;
            /* either legend of a two-symbol cap counts as related */
            var relatedHere = !!related && key.name.some(function (n) {
                return related[n];
            });
            /* a key that has nothing to do with the focused one keeps its
               shape but loses its heat, so the map stays readable */
            var muted = !!focus && !isFocus && !relatedHere;

            /* key cap: soft shadow, rounded, subtle border */
            ctx.save();
            if (!muted) {
                ctx.shadowColor = dark ? "rgba(0,0,0,.55)" : "rgba(0,0,0,.10)";
                ctx.shadowBlur = 3;
                ctx.shadowOffsetY = 1;
            }
            ctx.fillStyle = muted || !hot
                ? (muted ? mutedSurface : surface)
                : "rgb(" + rgb[0] + "," + rgb[1] + "," + rgb[2] + ")";
            roundRect(ctx, x, y, w, h, RADIUS);
            ctx.fill();
            ctx.restore();

            ctx.strokeStyle = isFocus ? "#cb0000"
                : (muted ? mutedEdge : (hot ? "rgba(0,0,0,.12)" : edge));
            ctx.lineWidth = isFocus ? 2 : 1;
            roundRect(ctx, x + 0.5, y + 0.5, w - 1, h - 1, RADIUS - 0.5);
            ctx.stroke();

            /* label: dark on light keys, white once the key is hot */
            ctx.fillStyle = muted ? mutedInk : (hot && t > 0.55 ? "#fff" : ink);
            drawKeyLabel(ctx, key, x, y, w, h, U);

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

        var labelSize = Math.round(U * 0.32);
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

    /* ---------- data tables ---------- */

    var catalog = Object.create(null);   /* mode -> {command: shortcut text} */
    var counts = Object.create(null);    /* mode -> {command: count} */
    var history = null;

    function readTables() {
        var all = Array.prototype.slice.call(
            document.querySelectorAll("section[data-mode]"));
        all.forEach(function (section) {
            var id = section.getAttribute("data-mode");
            var bag = Object.create(null);
            var texts = Object.create(null);
            var rows = section.querySelectorAll("tbody tr");
            for (var i = 0; i < rows.length; i++) {
                var cells = rows[i].children;
                if (cells.length < 4) continue;
                var command = cells[2].textContent.trim();
                bag[command] = parseInt(cells[0].textContent.replace(/[^0-9]/g, ""), 10) || 0;
                var cell = cells[3];
                texts[command] = {
                    text: cell.textContent,
                    /* keys recorded at press time beat any later guess */
                    keys: parseKeyAttr(cell.getAttribute("data-keys"))
                };
            }
            counts[id] = bag;
            catalog[id] = texts;
        });
        return all;
    }

    function parseKeyAttr(value) {
        if (!value) return null;
        var out = [];
        value.split("|").forEach(function (part) {
            var at = part.lastIndexOf(":");
            if (at <= 0) return;
            var count = parseInt(part.slice(at + 1), 10);
            if (!count) return;
            out.push([part.slice(0, at), count]);
        });
        return out.length ? out : null;
    }

    function bagFrom(pairs, resolve) {
        var bag = Object.create(null);
        for (var i = 0; i < pairs.length; i++) {
            var command = pairs[i][0];
            var n = pairs[i][1];
            var modeId = pairs[i][2];
            if (!n) continue;
            var info = resolve(command, modeId);
            if (!info) continue;

            if (info.keys) {
                /* The report carries the keys that were actually pressed.
                   They are all-time counts, so a period view uses their
                   proportions rather than their absolute values. */
                var total = 0;
                info.keys.forEach(function (pair) { total += pair[1]; });
                var scale = total ? n / total : 0;
                info.keys.forEach(function (pair) {
                    var keys = shortcutKeys(pair[0]);
                    var seen = Object.create(null);
                    keys.forEach(function (key) {
                        if (seen[key] || !mapsToKey(key)) return;
                        seen[key] = true;
                        bag[key] = (bag[key] || 0) + pair[1] * scale;
                    });
                });
                continue;
            }

            var binding = firstBinding(info.text);
            if (!binding) continue;
            var keys = shortcutKeys(binding);
            var seen = Object.create(null);
            for (var k = 0; k < keys.length; k++) {
                var key = keys[k];
                if (seen[key] || !mapsToKey(key)) continue;
                seen[key] = true;
                bag[key] = (bag[key] || 0) + n;
            }
        }
        return bag;
    }

    function bagFor(modeId, period) {
        if (period === "now") {
            var c = counts[modeId] || {};
            var t = catalog[modeId] || {};
            var pairs = Object.keys(c).map(function (command) {
                return [command, c[command], modeId];
            });
            return bagFrom(pairs, function (command) { return t[command]; });
        }
        if (!history) return Object.create(null);
        var p = history.periodIndex[period];
        if (p === undefined) return Object.create(null);
        var rows = history.rows;
        var names = history.names;
        var out = [];
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i];
            if (row[0] !== p) continue;
            var modeName = names[row[1]];
            if (modeId !== "all" && modeName !== modeId) continue;
            out.push([names[row[2]], row[3], modeName]);
        }
        return bagFrom(out, function (command, m) {
            return (catalog[m] || {})[command];
        });
    }

    function loadHistory() {
        var node = document.getElementById("keyfreq-data");
        if (!node) return null;
        try {
            var data = JSON.parse(node.textContent);
            var index = Object.create(null);
            data.periods.forEach(function (period, i) { index[period] = i; });
            data.periodIndex = index;
            return data;
        } catch (e) {
            return null;
        }
    }

    /* ---------- sorting ---------- */

    function escapeHTML(text) {
        return String(text)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;");
    }

    function sortValue(row, key) {
        switch (key) {
        case "count":
            return parseInt(row.children[3].getAttribute("data-count"), 10) || 0;
        case "percent":
            return parseFloat(row.children[1].textContent) || 0;
        case "shortcut":
            /* an unbound key is no binding, so it sorts to the bottom */
            var text = row.children[3].textContent.trim();
            return text.indexOf("unbound key") >= 0 ? "" : text;
        default:
            return row.children[2].textContent.trim();
        }
    }

    function compareValues(a, b) {
        if (typeof a === "number" && typeof b === "number") return a - b;
        return String(a).localeCompare(String(b), undefined,
                                       {numeric: true, sensitivity: "base"});
    }

    function sortRowsOf(table, key, direction) {
        var tbody = table.querySelector("tbody");
        if (!tbody) return;
        var rows = Array.prototype.slice.call(tbody.rows);
        rows.sort(function (a, b) {
            var x = sortValue(a, key);
            var y = sortValue(b, key);
            /* commands with no key binding stay at the bottom */
            if (key === "shortcut") {
                if (!x && y) return 1;
                if (x && !y) return -1;
            }
            return compareValues(x, y) * direction;
        });
        rows.forEach(function (row) { tbody.appendChild(row); });

        Array.prototype.forEach.call(table.querySelectorAll("th"),
                                     function (th) {
                                         th.removeAttribute("aria-sort");
                                     });
        var header = table.querySelector('button[data-sort="' + key + '"]');
        if (header) {
            header.parentNode.setAttribute(
                "aria-sort", direction > 0 ? "ascending" : "descending");
        }
        table.dataset.sortKey = key;
        table.dataset.sortDir = String(direction);
    }

    function makeSortable(table) {
        var buttons = table.querySelectorAll("th button.sort");
        Array.prototype.forEach.call(buttons, function (button) {
            button.addEventListener("click", function () {
                var key = button.getAttribute("data-sort");
                var direction = -1;
                if (key === table.dataset.sortKey) {
                    direction = -parseInt(table.dataset.sortDir || "-1", 10);
                } else if (key === "command" || key === "shortcut") {
                    direction = 1;      /* names read best A-to-Z */
                }
                sortRowsOf(table, key, direction);
            });
        });
    }

    /* ---------- mode statistics ---------- */

    function periodModeCounts(period) {
        /* mode -> {command: presses}; "now" uses the tables read at boot */
        if (period === "now") return counts;
        var out = Object.create(null);
        if (!history) return out;
        var p = history.periodIndex[period];
        if (p === undefined) return out;
        var rows = history.rows;
        var names = history.names;
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i];
            if (row[0] !== p) continue;
            var mode = names[row[1]];
            var command = names[row[2]];
            if (!out[mode]) out[mode] = Object.create(null);
            out[mode][command] = (out[mode][command] || 0) + row[3];
        }
        return out;
    }

    function realModes(data) {
        return Object.keys(data).filter(function (mode) { return mode !== "all"; });
    }

    function modeTotals(data) {
        var totals = Object.create(null);
        realModes(data).forEach(function (mode) {
            var sum = 0;
            var bag = data[mode];
            Object.keys(bag).forEach(function (command) { sum += bag[command]; });
            totals[mode] = sum;
        });
        return totals;
    }

    function number(n) {
        return n.toLocaleString();
    }

    function refreshModeStats(data) {
        var totals = modeTotals(data);
        var grand = 0;
        realModes(data).forEach(function (mode) { grand += totals[mode]; });

        /* the Mode menu of the heat map card is the only mode picker */
        var select = document.getElementById("mode-select");
        if (select) {
            var selected = select.value;
            var options = Array.prototype.slice.call(select.options);
            var all = options.shift();          /* All major modes stays first */
            all.textContent = "All major modes (" + number(grand) + ")";
            options.forEach(function (option) {
                option.textContent = option.value + " (" +
                    number(totals[option.value] || 0) + ")";
            });
            options.sort(function (a, b) {
                return (totals[b.value] || 0) - (totals[a.value] || 0);
            });
            options.forEach(function (option) { select.appendChild(option); });
            select.insertBefore(all, select.firstChild);
            select.value = selected;
        }

        var meta = document.getElementById("modes-meta");
        if (meta) {
            var live = realModes(data).filter(function (mode) {
                return totals[mode] > 0;
            }).length;
            meta.textContent = live + " of " + realModes(counts).length + " modes";
        }
    }

    var unionCache = { stamp: null, data: null };

    function unionOf(data) {
        if (unionCache.stamp === data) return unionCache.data;
        var union = Object.create(null);
        realModes(data).forEach(function (mode) {
            Object.keys(data[mode]).forEach(function (command) {
                union[command] = (union[command] || 0) + data[mode][command];
            });
        });
        unionCache = { stamp: data, data: union };
        return union;
    }

    function rebuildSection(section, data) {
        var table = section.querySelector("table");
        if (!table) return;
        var id = section.getAttribute("data-mode");
        var bag = id === "all" ? unionOf(data) : (data[id] || {});
        var rows = Object.keys(bag).map(function (command) {
            return [command, bag[command]];
        });
        var sum = 0;
        rows.forEach(function (row) { sum += row[1]; });
        rows.sort(function (a, b) { return b[1] - a[1]; });

        var html = rows.map(function (row) {
            var command = row[0];
            var count = row[1];
            var percent = sum ? (count * 100 / sum) : 0;
            var entry = (catalog[id] || {})[command];
            if (entry === undefined) entry = (catalog.all || {})[command];
            var text = entry ? entry.text : "";
            var attr = "";
            if (entry && entry.keys) {
                attr = " data-keys=\"" + escapeHTML(entry.keys.map(function (pair) {
                    return pair[0] + ":" + pair[1];
                }).join("|")) + "\"";
            }
            return "<tr><td>" + number(count) + "</td><td>" +
                percent.toFixed(2) + "%</td><td>" +
                escapeHTML(command) + "</td>" +
                "<td data-count=\"" + count + "\"" + attr + ">" +
                escapeHTML(text) + "</td></tr>";
        }).join("");

        table.querySelector("tbody").innerHTML = html ||
            "<tr><td colspan=\"4\" class=\"empty\">no presses in this period</td></tr>";
        sortRowsOf(table, table.dataset.sortKey || "count",
                   parseInt(table.dataset.sortDir || "-1", 10));
    }

    /* ---------- key focus ---------- */

    var focusKey = null;         /* primary name of the clicked cap, or null */
    var focusNames = null;       /* every name printed on that cap */
    var focusRelated = null;     /* {key: true} its neighbours */

    /* Every binding of a row, as lists of keycaps. */
    function rowKeyLists(cell) {
        var lists = [];
        var recorded = parseKeyAttr(cell.getAttribute("data-keys"));
        if (recorded) {
            recorded.forEach(function (pair) {
                var keys = shortcutKeys(pair[0]);
                if (keys.length) lists.push(keys);
            });
            return lists;
        }
        splitShortcut(cell.textContent).forEach(function (binding) {
            if (isPseudo(binding)) return;
            var keys = shortcutKeys(binding);
            if (keys.length) lists.push(keys);
        });
        return lists;
    }

    /* Two keys are related when they share a binding: a modifier with the
       key it modifies, or two keys of a multi-key sequence. */
    function buildKeyGraph(section) {
        var graph = Object.create(null);
        function link(a, b) {
            if (a === b) return;
            (graph[a] || (graph[a] = Object.create(null)))[b] = true;
            (graph[b] || (graph[b] = Object.create(null)))[a] = true;
        }
        var rows = section.querySelectorAll("tbody tr");
        for (var i = 0; i < rows.length; i++) {
            var cells = rows[i].children;
            if (cells.length < 4) continue;
            rowKeyLists(cells[3]).forEach(function (keys) {
                for (var a = 0; a < keys.length; a++) {
                    for (var b = a + 1; b < keys.length; b++) link(keys[a], keys[b]);
                }
            });
        }
        return graph;
    }

    function rowMatchesFocus(row) {
        if (!focusNames) return false;
        var cells = row.children;
        if (cells.length < 4) return false;
        return rowKeyLists(cells[3]).some(function (keys) {
            return keys.some(function (key) { return focusNames.indexOf(key) >= 0; });
        });
    }

    function applyFocusToTable(section) {
        var rows = section.querySelectorAll("tbody tr");
        for (var i = 0; i < rows.length; i++) {
            rows[i].hidden = focusKey ? !rowMatchesFocus(rows[i]) : false;
        }
    }

    /* ---------- wiring ---------- */

    function boot() {
        var canvas = document.getElementById("heatmap");
        var modeSelect = document.getElementById("mode-select");
        if (!canvas || !modeSelect) return;

        var scaleSelect = document.getElementById("scale-select");
        var periodSelect = document.getElementById("period-select");
        var summary = document.getElementById("scope-summary");
        var emptyNote = document.getElementById("empty-note");
        var tip = document.getElementById("key-tip");
        var lastPeriod = null;

        var allSections = [];
        var sectionsById = Object.create(null);
        var data = null;

        /* a chip showing the focused key, so it can be cleared by mouse */
        var chip = document.createElement("button");
        chip.type = "button";
        chip.className = "focus-chip";
        chip.id = "focus-chip";
        chip.hidden = true;
        chip.addEventListener("click", function () {
            focusKey = null;
            focusNames = null;
            render();
        });
        var statusLine = document.querySelector(".status");
        if (statusLine) statusLine.appendChild(chip);

        function updateChip() {
            chip.hidden = !focusKey;
            if (focusKey) {
                var related = focusRelated ? Object.keys(focusRelated).length : 0;
                chip.textContent = (focusNames || [focusKey]).join(" / ") + " \u00d7";
                chip.title = related + " related keys; click to clear";
            }
        }

        function canvasCapAt(event) {
            var rect = canvas.getBoundingClientRect();
            var dpr = window.devicePixelRatio || 1;
            var sx = canvas.width / dpr / rect.width;
            var sy = canvas.height / dpr / rect.height;
            var x = (event.clientX - rect.left) * sx;
            var y = (event.clientY - rect.top) * sy;
            for (var i = 0; i < keyBoxes.length; i++) {
                var b = keyBoxes[i];
                if (x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h) {
                    return b;
                }
            }
            return null;
        }

        canvas.addEventListener("click", function (event) {
            var cap = canvasCapAt(event);
            if (!cap) return;
            if (focusKey && focusNames && cap.names[0] === focusNames[0]) {
                focusKey = null;
                focusNames = null;
            } else {
                focusKey = cap.names[0];
                focusNames = cap.names.slice();
            }
            render();
        });

        document.addEventListener("keydown", function (event) {
            if (event.key === "Escape" && focusKey) {
                focusKey = null;
                focusNames = null;
                render();
            }
        });

        readTables();
        history = loadHistory();
        Array.prototype.forEach.call(document.querySelectorAll("section[data-mode]"),
                                     function (section) {
                                         allSections.push(section);
                                         sectionsById[section.getAttribute("data-mode")] =
                                             section;
                                         var table = section.querySelector("table");
                                         if (table) makeSortable(table);
                                     });


        function showSection(mode) {
            Array.prototype.forEach.call(allSections, function (section) {
                section.hidden = section.getAttribute("data-mode") !== mode;
            });
        }

        function render() {
            var mode = modeSelect.value;
            var period = periodSelect ? periodSelect.value : "now";

            if (period !== lastPeriod) {
                data = periodModeCounts(period);
                refreshModeStats(data);
                Array.prototype.forEach.call(allSections, function (section) {
                    section.dataset.built = "";
                });
                lastPeriod = period;
            }

            showSection(mode);
            var section = sectionsById[mode] || sectionsById.all;
            if (section && section.dataset.built !== "1") {
                rebuildSection(section, data);
                section.dataset.built = "1";
            }

            /* the focused key and the keys it is used with come from the
               rows that are on screen, so they follow the mode and period */
            focusRelated = null;
            if (focusKey) {
                if (!focusNames) focusNames = [focusKey];
                var graph = buildKeyGraph(section);
                var neighbours = null;
                focusNames.forEach(function (name) {
                    var links = graph[name];
                    if (!links) return;
                    neighbours = neighbours || Object.create(null);
                    Object.keys(links).forEach(function (other) {
                        neighbours[other] = true;
                    });
                });
                var rows = section.querySelectorAll("tbody tr");
                var matching = 0;
                for (var r = 0; r < rows.length; r++) {
                    if (rowMatchesFocus(rows[r])) matching++;
                }
                if (!matching) {
                    focusKey = null;          /* the key is not used here */
                    focusNames = null;
                } else {
                    focusRelated = neighbours || Object.create(null);
                }
            }
            applyFocusToTable(section);
            updateChip();

            var bag = bagFor(mode, period);
            var stats = draw(canvas, bag, scaleSelect ? scaleSelect.value : "sqrt",
                             focusKey, focusRelated);

            canvas.hidden = stats.max === 0;
            emptyNote.hidden = stats.max !== 0;
            if (stats.max === 0) {
                emptyNote.textContent = mode === "all"
                    ? "no keyboard shortcuts recorded"
                    : "no keyboard shortcuts in " + mode;
            }
            if (summary) {
                var label = (mode === "all" ? "all modes" : mode) +
                    (period === "now" ? "" : " \u00b7 " + period);
                if (focusKey) {
                    /* every number on this line is about the focused key */
                    var onKey = 0;
                    (focusNames || [focusKey]).forEach(function (name) {
                        onKey += bag[name] || 0;
                    });
                    var share = stats.total ? onKey * 100 / stats.total : 0;
                    summary.textContent = label + " \u00b7 " +
                        (focusNames || [focusKey]).join(" / ") + " \u00b7 " +
                        number(onKey) + " presses (" + share.toFixed(1) +
                        "% of " + number(stats.total) + ") \u00b7 " +
                        matching + (matching === 1 ? " command" : " commands");
                } else {
                    summary.textContent = label + " \u00b7 " +
                        stats.total.toLocaleString() + " presses";
                }
            }
            tip.hidden = true;
        }

        canvas.addEventListener("mousemove", function (event) {
            var rect = canvas.getBoundingClientRect();
            var dpr = window.devicePixelRatio || 1;
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
            tip.innerHTML = "<b>" + hit.names.join(" / ") + "</b> " +
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
        if (periodSelect) periodSelect.addEventListener("change", render);
        render();
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", boot);
    } else {
        boot();
    }
}());
