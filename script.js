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

    var measureCtx = null;

    function textWidth(text, px, bold) {
        if (!measureCtx) {
            measureCtx = document.createElement("canvas").getContext("2d");
        }
        measureCtx.font = (bold ? "bold " : "") + px + "px Arial, sans-serif";
        return measureCtx.measureText(String(text)).width;
    }

    /* The "no shortcuts" note is real DOM text: it cannot be clipped by the
       canvas edge and screen readers / printing see it too. */
    function setEmptyNote(section, show) {
        var canvas = section.querySelector("canvas");
        var note = section.querySelector("p.empty");
        if (show) {
            if (!note) {
                note = document.createElement("p");
                note.className = "empty";
                note.textContent = "no keyboard shortcuts in this mode";
                section.insertBefore(note, canvas);
            }
            canvas.hidden = true;
            /* the author stylesheet sets `display:block`, which beats the
               UA `[hidden]` rule, so hide it explicitly as well */
            canvas.style.display = "none";
        } else {
            if (note && note.parentNode) note.parentNode.removeChild(note);
            canvas.hidden = false;
            canvas.style.display = "";
        }
    }

    function drawSection(section, skip) {
        var canvas = section.querySelector("canvas");
        var table = section.querySelector("table");
        if (!canvas || !table) return;

        var freq = keyFrequency(table, skip);
        var max = 0;
        var total = 0;
        Object.keys(freq).forEach(function (name) {
            if (!mapsToKey(name)) return;
            max = Math.max(max, freq[name]);
            total += freq[name];
        });

        if (max === 0) {
            setEmptyNote(section, true);
            return;
        }
        setEmptyNote(section, false);

        var maxX = 0;
        var maxY = 0;
        LAYOUT.forEach(function (k) {
            maxX = Math.max(maxX, k.x + k.width);
            maxY = Math.max(maxY, k.y + k.height);
        });

        var u = 32;                                 /* one key unit, CSS px */
        var labelSize = Math.round(u * 0.34);
        var labelX = (maxX + 1.5) * u;
        var labels = [String(max), "0", total.toLocaleString() + " presses"];
        /* size the canvas from the widest label, so nothing is ever clipped */
        var labelW = labels.reduce(function (w, t) {
            return Math.max(w, textWidth(t, labelSize));
        }, 0);
        var cssW = Math.ceil(labelX + labelW + 6);
        var cssH = Math.ceil((maxY + 0.4) * u);

        var dpr = window.devicePixelRatio || 1;
        canvas.width = Math.round(cssW * dpr);      /* device pixels */
        canvas.height = Math.round(cssH * dpr);
        canvas.style.width = cssW + "px";
        canvas.style.height = cssH + "px";

        var ctx = canvas.getContext("2d");
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);     /* draw in CSS pixels */
        ctx.clearRect(0, 0, cssW, cssH);
        ctx.textBaseline = "middle";
        ctx.font = (u * 0.28).toFixed(1) + "px Arial, sans-serif";

        LAYOUT.forEach(function (key) {
            var x = key.x * u;
            var y = key.y * u;
            var w = key.width * u;
            var h = key.height * u;
            var value = 0;
            key.name.forEach(function (n) { value += freq[n] || 0; });

            ctx.fillStyle = "#DDDDDD";
            ctx.fillRect(x, y, w, h);
            ctx.fillStyle = "#FFFFFF";
            ctx.fillRect(x + 0.15 * u, y + 0.1 * u, w - 0.3 * u, h - 0.3 * u);

            if (value > 0) {
                var t = value / max;
                ctx.fillStyle = heatColor(t, 0.75);
                ctx.fillRect(x, y, w, h);
                ctx.fillStyle = t > 0.55 ? "#fff" : "#111";   /* readable label */
            } else {
                ctx.fillStyle = "#111";
            }
            ctx.fillText(key.name[0], x + 0.25 * u, y + h / 2);
        });

        /* colour scale plus its three labels */
        var barX = (maxX + 0.6) * u;
        var barW = u * 0.7;
        var barTop = u * 0.5;
        var barH = maxY * u - u;
        for (var i = 0; i < 128; i++) {
            ctx.fillStyle = heatColor(1 - i / 128, 1);
            ctx.fillRect(barX, barTop + (i * barH) / 128, barW, barH / 128 + 1);
        }

        ctx.font = labelSize + "px Arial, sans-serif";
        ctx.fillStyle = "#111";
        ctx.fillText(labels[0], labelX, barTop);
        ctx.fillText(labels[1], labelX, barTop + barH);
        ctx.fillText(labels[2], labelX, barTop + labelSize + 6);
    }

    function sections() {
        return document.querySelectorAll("section[data-mode]");
    }

    function redraw(skip) {
        var all = sections();
        for (var i = 0; i < all.length; i++) {
            drawSection(all[i], skip);
        }
    }

    /* "[&quot;C&quot;,&quot;S&quot;]" -> ["C","S"]; never eval(). */
    function parseSkip(text) {
        var trimmed = String(text || "").trim();
        if (!trimmed) return [];
        var value = JSON.parse(trimmed);          // throws on bad input
        if (!Array.isArray(value)) throw new Error("expected an array");
        return value.map(String);
    }

    function boot() {
        document.body.insertAdjacentHTML(
            "afterbegin",
            '<div class="skipbar">' +
            '<label for="skipkeys">Skip keys</label>' +
            '<input id="skipkeys" type="text" spellcheck="false" ' +
            'placeholder=\'["C", "S", "M"]\'>' +
            '<button id="skipgo" type="button">Redraw</button>' +
            '<span id="skiperror" role="status" aria-live="polite"></span>' +
            "</div>");

        var input = document.getElementById("skipkeys");
        var error = document.getElementById("skiperror");

        function apply() {
            try {
                var skip = parseSkip(input.value);
                error.textContent = "";
                input.setAttribute("aria-invalid", "false");
                redraw(skip);
            } catch (e) {
                error.textContent = "not a valid list (" + e.message +
                    ') - try ["C", "S"]';
                input.setAttribute("aria-invalid", "true");
            }
        }

        document.getElementById("skipgo").addEventListener("click", apply);
        input.addEventListener("keydown", function (e) {
            if (e.key === "Enter") { e.preventDefault(); apply(); }
        });

        redraw(parseSkip(""));
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", boot);
    } else {
        boot();
    }
}());
