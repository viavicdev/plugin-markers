/**
 * RENDER – Multicam Markers
 * host.jsx
 *
 * Funksjoner:
 *   getMulticamClips()              → alle multicam-klipp i prosjektet
 *   addMarkersToClip(clipId, json)  → skriv markers på valgt klipp
 *   clearMarkersOnClip(clipId)      → fjern alle markers fra klipp
 */

// ─── JSON POLYFILL (Premiere 26+ ExtendScript mangler innebygd JSON) ──────────
// Enkel implementasjon, character-by-character. ES3-kompatibel.
if (typeof JSON !== "object") { JSON = {}; }
(function () {
    var meta = {
        "\b": "\\b", "\t": "\\t", "\n": "\\n", "\f": "\\f", "\r": "\\r",
        "\"": "\\\"", "\\": "\\\\"
    };
    function quote(s) {
        var r = "\"";
        for (var i = 0; i < s.length; i++) {
            var ch = s.charAt(i);
            var code = s.charCodeAt(i);
            if (meta[ch]) { r += meta[ch]; }
            else if (code < 0x20) {
                var hex = code.toString(16);
                r += "\\u" + "0000".substr(0, 4 - hex.length) + hex;
            } else { r += ch; }
        }
        return r + "\"";
    }
    function stringifyValue(v) {
        if (v === null || v === undefined) return "null";
        var t = typeof v;
        if (t === "string")  return quote(v);
        if (t === "number")  return isFinite(v) ? String(v) : "null";
        if (t === "boolean") return String(v);
        if (t === "object") {
            if (Object.prototype.toString.apply(v) === "[object Array]") {
                var parts = [];
                for (var i = 0; i < v.length; i++) { parts.push(stringifyValue(v[i])); }
                return "[" + parts.join(",") + "]";
            }
            var pairs = [];
            for (var k in v) {
                if (Object.prototype.hasOwnProperty.call(v, k)) {
                    pairs.push(quote(k) + ":" + stringifyValue(v[k]));
                }
            }
            return "{" + pairs.join(",") + "}";
        }
        return "null";
    }
    if (typeof JSON.stringify !== "function") {
        JSON.stringify = function (value) { return stringifyValue(value); };
    }
    if (typeof JSON.parse !== "function") {
        JSON.parse = function (text) { return eval("(" + text + ")"); };
    }
}());

// ─── TEST-FUNKSJONER (diagnostikk) ────────────────────────────────────────────

function helloTest() {
    return "hello world";
}

function helloTestJSON() {
    return JSON.stringify({ hello: "world" });
}

function listItemNamesFlat() {
    try {
        var n = app.project.rootItem.children.numItems;
        var names = [];
        for (var i = 0; i < n; i++) {
            try {
                var item = app.project.rootItem.children[i];
                names.push(String(item.name) + " (type=" + item.type + ")");
            } catch (e) {
                names.push("ITEM-" + i + "-ERR: " + String(e));
            }
        }
        return JSON.stringify(names);
    } catch (e) {
        return JSON.stringify({ fail: String(e) });
    }
}

// ─── HENT ALLE MULTICAM-KLIPP ─────────────────────────────────────────────────

function getMulticamClips() {
    var debug = [];
    try {
        var project = app.project;
        if (!project) return JSON.stringify({ ok: false, error: "Ingen prosjekt åpent" });
        if (!project.rootItem) return JSON.stringify({ ok: false, error: "Ingen rootItem" });

        var clips = [];
        debug.push("start scan");
        scanBin(project.rootItem, clips, debug, 0);
        debug.push("scan done, found " + clips.length + " clips");

        return JSON.stringify({ ok: true, clips: clips, debug: debug });
    } catch (e) {
        var msg = "?";
        try { msg = String(e); } catch (ignore) {}
        return JSON.stringify({ ok: false, error: msg, debug: debug });
    }
}

/**
 * Rekursivt scan av alle bins. Defensiv: hver item-tilgang i egen try/catch
 * så én korrupt item ikke krasjer hele scanningen. Premiere 26+ har strengere
 * type-håndtering enn eldre versjoner.
 */
function scanBin(bin, result, debug, depth) {
    if (depth > 20) { debug.push("max depth"); return; }

    var numItems = 0;
    try { numItems = bin.children.numItems; }
    catch (e) { debug.push("kunne ikke lese numItems: " + String(e)); return; }

    for (var i = 0; i < numItems; i++) {
        try {
            var item;
            // Premiere 26+ foretrekker getItemAt(i), eldre bruker [i]
            try { item = bin.children.getItemAt ? bin.children.getItemAt(i) : bin.children[i]; }
            catch (eGet) { item = bin.children[i]; }
            if (!item) continue;

            var itemType = -1;
            try { itemType = item.type; } catch (eType) {}

            var isBin  = (typeof ProjectItemType !== "undefined") ? (itemType === ProjectItemType.BIN)  : (itemType === 2);
            var isClip = (typeof ProjectItemType !== "undefined") ? (itemType === ProjectItemType.CLIP) : (itemType === 1);
            var isFile = (typeof ProjectItemType !== "undefined") ? (itemType === ProjectItemType.FILE) : (itemType === 4);

            if (isBin) {
                scanBin(item, result, debug, depth + 1);
            } else if (isClip || isFile) {
                var entry = { type: itemType };
                try { entry.name = String(item.name); } catch (eN) { entry.name = "(uten navn)"; }
                try { entry.id   = String(item.nodeId); } catch (eId) { entry.id = "idx-" + result.length; }
                if (!entry.id || entry.id === "undefined") entry.id = "idx-" + result.length;
                result.push(entry);
            }
        } catch (eItem) {
            debug.push("item " + i + ": " + String(eItem));
        }
    }
}

// ─── LEGG TIL MARKERS PÅ KLIPP ────────────────────────────────────────────────

/**
 * clipId  — nodeId fra getMulticamClips()
 * markersJson — JSON-streng: [{timecode:"19:20:00:00", comment:"...", color:"yellow"}, ...]
 *
 * Timecode er kamera-TC (wall clock), f.eks. "19:20:00:00" ved 25fps
 */
function addMarkersToClip(clipId, markersJson, manualStartTC, manualFps) {
    try {
        var item = findItemById(app.project.rootItem, clipId);
        if (!item) return JSON.stringify({ ok: false, error: "Fant ikke klipp med id: " + clipId });

        var markers = JSON.parse(markersJson);
        if (!markers || markers.length === 0) {
            return JSON.stringify({ ok: false, error: "Ingen markers å legge til" });
        }

        // Bruk manuell fps hvis angitt, ellers prøv auto-detect, ellers 25
        var fps = parseFloat(manualFps);
        if (!fps || fps <= 0) fps = getClipFPS(item);
        if (!fps || fps <= 0) fps = 25;

        // Bruk manuell start-TC hvis angitt, ellers prøv auto-detect
        var startTC;
        if (manualStartTC && String(manualStartTC).length > 0) {
            startTC = tcToFrames(manualStartTC, fps);
            if (startTC < 0) startTC = 0;
        } else {
            startTC = getClipStartTC(item, fps);
        }

        var added   = 0;
        var skipped = [];
        var debug   = [];

        var markerCollection = item.getMarkers();
        var beforeCount = markerCollection.numMarkers;

        for (var i = 0; i < markers.length; i++) {
            var m = markers[i];

            var markerFrames = tcToFrames(m.timecode, fps);
            if (markerFrames < 0) {
                skipped.push(m.timecode + " (ugyldig format)");
                debug.push(m.timecode + " → INVALID FORMAT");
                continue;
            }

            // Offset: marker-TC minus klippets start-TC = posisjon i klippet
            var offsetFrames = markerFrames - startTC;
            if (offsetFrames < 0) {
                skipped.push(m.timecode + " (før klippstart)");
                debug.push(m.timecode + " → before clipStart (offset=" + offsetFrames + "f)");
                continue;
            }

            var seconds = offsetFrames / fps;

            try {
                var marker = markerCollection.createMarker(seconds);
                if (!marker) {
                    skipped.push(m.timecode + " (createMarker returnerte null)");
                    debug.push(m.timecode + " → createMarker(" + seconds + "s) returned NULL");
                    continue;
                }
                marker.name     = m.comment || "";
                marker.comments = m.comment || "";
                marker.type     = "Comment";

                var colorIdx = COLORS[m.color] !== undefined ? COLORS[m.color] : COLORS["yellow"];
                try { marker.setColorByIndex(colorIdx); } catch (ce) { /* ignore color errors */ }

                added++;
                debug.push(m.timecode + " → OK @ " + seconds.toFixed(2) + "s (offset=" + offsetFrames + "f)");
            } catch (me) {
                skipped.push(m.timecode + " (" + me.message + ")");
                debug.push(m.timecode + " → THREW: " + me.message + " @ " + seconds.toFixed(2) + "s");
            }
        }

        var afterCount = item.getMarkers().numMarkers;

        return JSON.stringify({
            ok:           true,
            added:        added,
            skipped:      skipped,
            clip:         item.name,
            fps:          fps,
            startTC:      framesToTC(startTC, fps),
            startTCticks: item.startTime,
            markersBefore: beforeCount,
            markersAfter:  afterCount,
            debug:         debug
        });

    } catch (e) {
        return JSON.stringify({ ok: false, error: e.toString() });
    }
}

// ─── FJERN MARKERS FRA KLIPP ──────────────────────────────────────────────────

function clearMarkersOnClip(clipId) {
    try {
        var item = findItemById(app.project.rootItem, clipId);
        if (!item) return JSON.stringify({ ok: false, error: "Fant ikke klipp" });

        var col   = item.getMarkers();
        var count = col.numMarkers;
        var m     = col.getFirstMarker();
        while (m) {
            var next = col.getNextMarker(m);
            col.deleteMarker(m);
            m = next;
        }
        return JSON.stringify({ ok: true, deleted: count, clip: item.name });
    } catch (e) {
        return JSON.stringify({ ok: false, error: e.toString() });
    }
}

// ─── UTILS ────────────────────────────────────────────────────────────────────

var COLORS = {
    "red":    0,
    "green":  1,
    "yellow": 2,
    "blue":   3,
    "cyan":   4,
    "purple": 5
};

function findItemById(bin, id) {
    for (var i = 0; i < bin.children.numItems; i++) {
        var item = bin.children[i];
        if (item.type === ProjectItemType.BIN) {
            var found = findItemById(item, id);
            if (found) return found;
        } else if (item.nodeId === id) {
            return item;
        }
    }
    return null;
}

function getClipFPS(item) {
    try {
        // footageInterpretation gir oss frameRate
        var interp = item.getFootageInterpretation();
        if (interp && interp.frameRate > 0) {
            return Math.round(interp.frameRate);
        }
    } catch (e) {}
    return 25; // NRK standard fallback
}

function getClipStartTC(item, fps) {
    try {
        // startTime er i ticks (254016000000 ticks per sekund)
        var ticks = parseFloat(item.startTime);
        if (ticks > 0) {
            var seconds = ticks / 254016000000;
            return Math.round(seconds * fps);
        }
    } catch (e) {}
    return 0;
}

/**
 * TC til frames.
 * Støtter: 19:20:00:00 / 19.20 / 19:20 / 19:20:30
 */
function tcToFrames(tc, fps) {
    tc = String(tc).replace(/\s/g, "");

    // HH:MM:SS:FF eller HH:MM:SS;FF
    var m = tc.match(/^(\d{1,2})[:\.](\d{2})[:\.](\d{2})[:;](\d{2})$/);
    if (m) {
        return ((parseInt(m[1]) * 3600 + parseInt(m[2]) * 60 + parseInt(m[3])) * fps) + parseInt(m[4]);
    }

    // HH:MM:SS
    m = tc.match(/^(\d{1,2}):(\d{2}):(\d{2})$/);
    if (m) {
        return (parseInt(m[1]) * 3600 + parseInt(m[2]) * 60 + parseInt(m[3])) * fps;
    }

    // HH.MM (f.eks. 19.20 fra Teams)
    m = tc.match(/^(\d{1,2})\.(\d{2})$/);
    if (m) {
        return (parseInt(m[1]) * 3600 + parseInt(m[2]) * 60) * fps;
    }

    // HH:MM
    m = tc.match(/^(\d{1,2}):(\d{2})$/);
    if (m) {
        return (parseInt(m[1]) * 3600 + parseInt(m[2]) * 60) * fps;
    }

    return -1;
}

function framesToTC(frames, fps) {
    var totalS = Math.floor(frames / fps);
    var f  = frames % fps;
    var h  = Math.floor(totalS / 3600);
    var mn = Math.floor((totalS % 3600) / 60);
    var s  = totalS % 60;
    return pad(h) + ":" + pad(mn) + ":" + pad(s) + ":" + pad(f);
}

function pad(n) {
    return n < 10 ? "0" + n : String(n);
}
