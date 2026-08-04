#!/usr/bin/env node
/* ==========================================================================
   Round-trip guard for the compose editor's markdown serializer.

   The editor may only ever hand the server back what it was given. Every
   fixture below is parsed into blocks and serialized again; the output has to
   match the input byte for byte. The realistic set is a copy of every trip
   report in the development database, and the boundary set pins down which
   constructs fall outside the rich-text subset and must survive as raw blocks.

   Run: node spec/js/editor_round_trip.js
   ========================================================================== */

"use strict";

var assert = require("assert");
var path = require("path");
var editor = require(path.join(__dirname, "..", "..", "public", "scripts", "editor.js"));
var io = editor.markdownIO;

var failures = 0;
var checks = 0;

function check(label, body) {
  checks += 1;
  try {
    body();
  } catch (error) {
    failures += 1;
    process.stdout.write("FAIL  " + label + "\n      " + error.message.split("\n")[0] + "\n");
  }
}

function blockTypes(source, photoIds) {
  var known = photoIds
    ? function (id) {
      return photoIds.indexOf(id) >= 0;
    }
    : null;

  return io.parseDocument(source, known).blocks.map(function (block) {
    return block.type;
  });
}

function roundTrips(label, source, photoIds) {
  check(label, function () {
    assert.strictEqual(io.roundTrip(source, photoIds), source);
  });
}

/* -- Real trip reports, copied out of the development database ------------- */

var REAL_TRIPS = [
  {slug: "coyote-wall", markdown: "Last Alpenhounds hike, bittersweet. ..."},
  {slug: "angel-s-rest", markdown: "Lucky Day- my son agreed to go on a hike with me! ..."},
  {slug: "sedona", markdown: "Trip to the Arizona desert. Day 1- visited Perry Mesa in the Agua Fria National Monument. This plateau has pueblo ruins, petroglyphs, and big red-rock views."},
  {slug: "devils-wahkeena", markdown: "Alpenhounds hike."},
  {slug: "lower-greenleaf", markdown: "Explored some of the new trails being built in the area. Lower Greenleaf Falls has had some big washouts since the last visit."},
  {slug: "broughton", markdown: "Goofing around at Broughton Bluff. Walked the Phone Home Boulders trail and examined some of the crags."},
  {slug: "the-pinnacles", markdown: "Alpenhounds."},
  {slug: "hardy-ridge", markdown: "Alpenhounds!"},
  {slug: "mack-s-canyon", markdown: "This was supposed to be a ski trip to the Tilly Jane Cabin. Thin cover and rain pushed us toward the Deschutes instead."},
  {slug: "multnomah-wahkeena-loop", markdown: "Chilly with a few icy spots."},
  {slug: "msh", markdown: "Beautiful sunny day. Lower mountain snow did not refreeze overnight, and the bootpack was total mashed potatoes."},
  {slug: "cedar-falls", markdown: "A rainy short hike from Bonneville Hot Springs to the Cedar Falls overlook."},
  {slug: "dog-mountain", markdown: "A bright spring hike with wildflowers along the ridge."},
  {slug: "qa-pin-smoke", markdown: "Map pin smoke test."},
  {slug: "ui-audit-test-hike", markdown: "{{ photo:29 }}\r\n\r\n# UI Audit Test Hike\r\n\r\nCreated by the UI audit. **Bold** text, a [link](https://example.com), and a list:\r\n\r\n- one\r\n- two\r\n"}
];

REAL_TRIPS.forEach(function (trip) {
  roundTrips("real trip: " + trip.slug, trip.markdown, [29]);
});

/* -- Subset boundaries ------------------------------------------------------ */

var BOUNDARIES = [
  {label: "plain paragraph", source: "Just a walk in the woods.", types: ["paragraph"]},
  {label: "bold, italic and a link", source: "A **big** day, _slightly_ damp, see [the map](https://example.com/map).", types: ["paragraph"]},
  {label: "underscore bold and asterisk italic", source: "__Loud__ and *quiet*.", types: ["paragraph"]},
  {label: "nested emphasis", source: "**bold with *italic* inside**", types: ["paragraph"]},
  {label: "intra-word underscores stay literal", source: "The file snake_case_name is fine.", types: ["paragraph"]},
  {label: "unpaired asterisk", source: "5 * 3 stars", types: ["paragraph"]},
  {label: "h2 heading", source: "## Day two", types: ["heading"]},
  {label: "h3 heading", source: "### Getting there", types: ["heading"]},
  {label: "h1 heading", source: "# The whole trip", types: ["heading"]},
  {label: "heading with odd spacing", source: "##    Spaced out", types: ["heading"]},
  {label: "photo handle line", source: "{{ photo:12 }}", types: ["figure"], photos: [12]},
  {label: "photo handle for a missing photo", source: "{{ photo:99 }}", types: ["raw"], photos: [12]},
  {label: "handle inside a sentence", source: "See {{ photo:12 }} for the view.", types: ["raw"], photos: [12]},
  {label: "table", source: "| Day | Miles |\n| --- | --- |\n| 1 | 8.2 |", types: ["raw"]},
  {label: "code fence", source: "```\ngpx --clean\n```", types: ["raw"]},
  {label: "inline code", source: "Run `gpsbabel` on the track.", types: ["raw"]},
  {label: "blockquote", source: "> The mountain decides.", types: ["raw"]},
  {label: "bullet list", source: "- one\n- two", types: ["raw"]},
  {label: "ordered list", source: "1. pack\n2. drive", types: ["raw"]},
  {label: "image", source: "![a view](https://example.com/a.jpg)", types: ["raw"]},
  {label: "raw html", source: 'A <b>bold</b> claim.', types: ["raw"]},
  {label: "footnote", source: "Cold[^1] at the summit.", types: ["raw"]},
  {label: "strikethrough", source: "~~Not this trail~~", types: ["raw"]},
  {label: "thematic break", source: "---", types: ["raw"]},
  {label: "indented code", source: "    puts 'hi'", types: ["raw"]},
  {label: "escaped asterisk", source: "A literal \\* star.", types: ["raw"]},
  {label: "html entity", source: "Tea &amp; biscuits.", types: ["raw"]},
  {label: "wrapped paragraph keeps its line breaks", source: "One line here\nand its continuation.", types: ["paragraph"]},
  {label: "mixed document", source: "Opening line.\n\n## Day one\n\n{{ photo:12 }}\n\n- a list\n- of things\n\nClosing **line**.", types: ["paragraph", "heading", "figure", "raw", "paragraph"], photos: [12]},
  {label: "extra blank lines between blocks", source: "First.\n\n\n\nSecond.", types: ["paragraph", "paragraph"]},
  {label: "leading and trailing blank lines", source: "\n\nOnly paragraph.\n", types: ["paragraph"]},
  {label: "crlf document", source: "First line.\r\n\r\n## Heading\r\n\r\nLast line.\r\n", types: ["paragraph", "heading", "paragraph"]},
  {label: "mixed line endings are left alone", source: "First line.\r\n\r\nSecond line.\n\nThird line.\r\n", types: ["paragraph", "paragraph", "paragraph"]},
  {label: "empty document", source: "", types: []},
  {label: "whitespace-only document", source: "\n\n", types: []}
];

BOUNDARIES.forEach(function (fixture) {
  roundTrips("boundary: " + fixture.label, fixture.source, fixture.photos || []);
  check("boundary types: " + fixture.label, function () {
    assert.deepStrictEqual(blockTypes(fixture.source, fixture.photos || []), fixture.types);
  });
});

/* -- Structural edits still produce well-formed markdown -------------------- */

check("moving a figure rewrites only the separators it touches", function () {
  var doc = io.parseDocument("Opening.\n\n{{ photo:7 }}\n\nClosing.", function (id) {
    return id === 7;
  });
  var reordered = [doc.blocks[1], doc.blocks[0], doc.blocks[2]];
  assert.strictEqual(io.serializeDocument(doc, reordered), "{{ photo:7 }}\n\nOpening.\n\nClosing.");
});

check("dropping a block drops its separator too", function () {
  var doc = io.parseDocument("One.\n\nTwo.\n\nThree.");
  assert.strictEqual(io.serializeDocument(doc, [doc.blocks[0], doc.blocks[2]]), "One.\n\nThree.");
});

check("empty blocks never emit blank markdown", function () {
  var doc = io.parseDocument("One.\n\nTwo.");
  var empty = {type: "paragraph", nodes: [], id: "new", sepAfter: "\n\n", origNextId: null};
  assert.strictEqual(io.serializeDocument(doc, [doc.blocks[0], empty, doc.blocks[1]]), "One.\n\nTwo.");
});

check("a fresh document with no source serializes cleanly", function () {
  var doc = io.parseDocument("");
  var blocks = [
    {type: "paragraph", nodes: [{t: "text", v: "Short and sweet."}], id: "n1"},
    {type: "figure", photoId: 3, raw: "{{ photo:3 }}", id: "n2"}
  ];
  assert.strictEqual(io.serializeDocument(doc, blocks), "Short and sweet.\n\n{{ photo:3 }}");
});

check("inline serialization is the exact inverse of parsing", function () {
  ["**a** _b_ [c](d)", "plain", "*a*b", "a*b*c", "[not a link] (x)", "**", "* *"].forEach(function (source) {
    assert.strictEqual(io.serializeInline(io.parseInline(source)), source, source);
  });
});

/* -- Dating a hike from its photos ------------------------------------------ */

var tripDates = editor.tripDatesFromPhotos;
var TODAY = "2026-08-02";

check("one day of photos dates the hike with no nights", function () {
  assert.deepStrictEqual(
    tripDates(["2026-07-14", "2026-07-14"], TODAY),
    {hikedAt: "2026-07-14", nights: 0}
  );
});

check("a spread of days starts at the earliest and counts the nights", function () {
  assert.deepStrictEqual(
    tripDates(["2026-07-16", "2026-07-14", "2026-07-15"], TODAY),
    {hikedAt: "2026-07-14", nights: 2}
  );
});

check("full timestamps are read as their calendar day", function () {
  assert.deepStrictEqual(
    tripDates(["2026-07-14T18:40:00", "2026-07-15T06:05:00"], TODAY),
    {hikedAt: "2026-07-14", nights: 1}
  );
});

check("photos without dates are ignored, not fatal", function () {
  assert.deepStrictEqual(
    tripDates([null, "", "2026-07-14", undefined], TODAY),
    {hikedAt: "2026-07-14", nights: 0}
  );
});

check("no dated photos means no opinion", function () {
  assert.strictEqual(tripDates([], TODAY), null);
  assert.strictEqual(tripDates([null, "not a date"], TODAY), null);
});

check("reset camera clocks and future stamps are not believed", function () {
  assert.deepStrictEqual(
    tripDates(["1970-01-01", "2026-07-14", "2027-01-01"], TODAY),
    {hikedAt: "2026-07-14", nights: 0}
  );
});

check("a spread wider than one trip is not believed at all", function () {
  assert.strictEqual(tripDates(["2025-05-01", "2026-07-14"], TODAY), null);
});

check("a month crossing counts its nights through the boundary", function () {
  assert.deepStrictEqual(
    tripDates(["2026-06-29", "2026-07-02"], TODAY),
    {hikedAt: "2026-06-29", nights: 3}
  );
});

/* --------------------------------------------------------------------------
   Naming a pin after a chosen place.
   -------------------------------------------------------------------------- */

var places = editor.placesIO;

check("distances come out in believable kilometers", function () {
  // Portland to Hood River is about 95 km as the crow flies.
  var km = places.distanceKm(45.5231, -122.6765, 45.7054, -121.5215);
  assert.ok(km > 85 && km < 105, "expected ~95, got " + km);
  assert.ok(places.distanceKm(45.5, -122.6, 45.5, -122.6) < 0.001);
});

check("a pin stays named near its place and lets go far away", function () {
  // A drag across the lake basin keeps the name.
  assert.strictEqual(places.pinNearPlace(45.3560, -121.7900, 45.3600, -121.7800), true);
  // A different mountain range does not.
  assert.strictEqual(places.pinNearPlace(45.3560, -121.7900, 46.8523, -121.7603), false);
});

var tripPin = editor.tripPinFromPhotos;

check("one located photo pins the hike", function () {
  assert.deepStrictEqual(tripPin([{lat: 45.36, lng: -121.79}]), {lat: 45.36, lng: -121.79});
});

check("a cluster pins at its median, ignoring one lying fix", function () {
  var pin = tripPin([
    {lat: 45.360, lng: -121.790},
    {lat: 45.362, lng: -121.792},
    {lat: 45.364, lng: -121.794},
    // A fix from another state cannot drag the pin there.
    {lat: 40.0, lng: -105.0}
  ]);
  assert.strictEqual(pin.lat, 45.362);
  assert.strictEqual(pin.lng, -121.792);
});

check("an even split between two mountains says nothing", function () {
  assert.strictEqual(tripPin([
    {lat: 45.36, lng: -121.79},
    {lat: 48.78, lng: -121.90}
  ]), null);
});

check("null island and junk coordinates are not believed", function () {
  assert.strictEqual(tripPin([{lat: 0, lng: 0}, {lat: null, lng: null}, {lat: 200, lng: -300}]), null);
  assert.strictEqual(tripPin([]), null);
  assert.strictEqual(tripPin(null), null);
});

process.stdout.write(
  (failures === 0 ? "OK" : "FAILED") + ": " + (checks - failures) + "/" + checks + " round-trip checks passed\n"
);
process.exit(failures === 0 ? 0 : 1);
