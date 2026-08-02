/* ==========================================================================
   Went Hiking — compose editor

   The story canvas is a block editor whose serialization target is the same
   `report_markdown` the public page has always rendered, with photos referenced
   by `{{ photo:ID }}` handles on their own line. Nothing about the server model
   changes, which means the editor's first duty is to never lose a byte of
   somebody's trip report.

   The rule that buys that guarantee: every block round-trips through text by
   construction. A paragraph is only parsed into rich text when re-serializing
   the parsed nodes reproduces the source chunk exactly; anything else — tables,
   lists, code, blockquotes, HTML, footnotes, inline handles — becomes a "raw"
   block that is edited as plain text and written back verbatim. Separators
   between blocks are remembered too, so a document nobody reordered comes back
   out with its original spacing.
   ========================================================================== */

(function () {
  "use strict";

  /* ------------------------------------------------------------------------
     Markdown IO. This half is deliberately DOM-free so it can be exercised by
     a plain Node harness (spec/js/editor_round_trip.js) as well as the browser.
     ------------------------------------------------------------------------ */

  var DEFAULT_SEPARATOR = "\n\n";
  var HANDLE_LINE = /^\{\{\s*photo:\s*(\d+)\s*\}\}$/;
  var HEADING_LINE = /^(#{1,6}[ \t]+)(.*)$/;
  var LINK_PATTERN = /^\[([^[\]]*)\]\(([^()\s]*)\)/;
  var WORD_CHARACTER = /[A-Za-z0-9]/;

  // Constructs the editor refuses to interpret. Anything matching here keeps
  // its chunk in a raw block, where the source text is the source of truth.
  var OUTSIDE_INLINE_SUBSET = /[`~|<>\\]|!\[|\[\^|\{\{|\}\}|&[A-Za-z#]/;

  var blockSequence = 0;

  function nextBlockId() {
    blockSequence += 1;
    return "b" + blockSequence;
  }

  function outsideBlockSubset(line) {
    if (/^[ \t]/.test(line)) return true; // indented code, or a lazy continuation
    if (/^>/.test(line)) return true; // blockquote
    if (/^(```|~~~)/.test(line)) return true; // fenced code
    if (/^[-*+][ \t]+/.test(line)) return true; // bullet list
    if (/^\d+[.)][ \t]+/.test(line)) return true; // ordered list
    if (/^([-*_][ \t]*){3,}$/.test(line)) return true; // thematic break
    if (/^(=+|-+)$/.test(line)) return true; // setext underline
    return false;
  }

  function canOpenEmphasis(text, index, marker) {
    var before = index === 0 ? "" : text.charAt(index - 1);
    var after = text.charAt(index + marker.length);
    if (after === "" || /\s/.test(after)) return false;
    // Redcarpet runs with no_intra_emphasis, so a marker glued to the end of a
    // word (snake_case_names) is literal text.
    return !WORD_CHARACTER.test(before);
  }

  function canCloseEmphasis(text, index, marker) {
    var before = text.charAt(index - 1);
    var after = text.charAt(index + marker.length);
    if (before === "" || /\s/.test(before)) return false;
    return after === "" || !WORD_CHARACTER.test(after);
  }

  function findEmphasisClose(text, from, marker) {
    var character = marker.charAt(0);
    var index = from;

    while (index < text.length) {
      if (text.charAt(index) === character) {
        if (marker.length === 2) {
          if (text.charAt(index + 1) === character) return index;
        } else if (text.charAt(index + 1) !== character) {
          return index;
        }
      }
      index += 1;
    }

    return -1;
  }

  function parseInline(text) {
    var nodes = [];
    var buffer = "";
    var index = 0;

    function flush() {
      if (buffer) {
        nodes.push({t: "text", v: buffer});
        buffer = "";
      }
    }

    while (index < text.length) {
      var character = text.charAt(index);

      if (character === "*" || character === "_") {
        var marker = text.charAt(index + 1) === character ? character + character : character;
        var close = findEmphasisClose(text, index + marker.length, marker);

        if (close > index + marker.length && canOpenEmphasis(text, index, marker) && canCloseEmphasis(text, close, marker)) {
          flush();
          nodes.push({
            t: marker.length === 2 ? "strong" : "em",
            m: marker,
            c: parseInline(text.slice(index + marker.length, close))
          });
          index = close + marker.length;
          continue;
        }
      } else if (character === "[") {
        var link = LINK_PATTERN.exec(text.slice(index));
        if (link && link[2]) {
          flush();
          nodes.push({t: "link", href: link[2], c: parseInline(link[1])});
          index += link[0].length;
          continue;
        }
      }

      buffer += character;
      index += 1;
    }

    flush();
    return nodes;
  }

  function serializeInline(nodes) {
    var out = "";

    for (var index = 0; index < nodes.length; index += 1) {
      var node = nodes[index];

      if (node.t === "text") {
        out += node.v;
      } else if (node.t === "link") {
        out += "[" + serializeInline(node.c) + "](" + node.href + ")";
      } else {
        var inner = serializeInline(node.c);
        if (!inner) continue; // an emptied <strong> would otherwise emit bare markers
        out += node.m + inner + node.m;
      }
    }

    return out;
  }

  function classifyChunk(text, knownPhoto) {
    var lines = text.split("\n");
    var index;

    if (lines.length === 1) {
      var handle = HANDLE_LINE.exec(text);
      if (handle) {
        var photoId = Number(handle[1]);
        if (!knownPhoto || knownPhoto(photoId)) {
          return {type: "figure", photoId: photoId, raw: text};
        }
        // A handle whose photo is gone renders as literal text on the public
        // page; keeping it raw keeps it visible and untouched.
        return {type: "raw", text: text};
      }
    }

    var headingCandidate = false;
    for (index = 0; index < lines.length; index += 1) {
      if (outsideBlockSubset(lines[index])) return {type: "raw", text: text};
      if (OUTSIDE_INLINE_SUBSET.test(lines[index])) return {type: "raw", text: text};
      if (HEADING_LINE.test(lines[index])) headingCandidate = true;
    }

    if (headingCandidate) {
      var heading = lines.length === 1 ? HEADING_LINE.exec(text) : null;
      if (!heading) return {type: "raw", text: text};

      var headingNodes = parseInline(heading[2]);
      if (serializeInline(headingNodes) !== heading[2]) return {type: "raw", text: text};

      return {
        type: "heading",
        level: heading[1].replace(/[^#]/g, "").length,
        prefix: heading[1],
        nodes: headingNodes
      };
    }

    var nodes = parseInline(text);
    if (serializeInline(nodes) !== text) return {type: "raw", text: text};

    return {type: "paragraph", nodes: nodes};
  }

  function groupLines(text) {
    var lines = text.split("\n");
    var groups = [];
    var current = null;

    for (var index = 0; index < lines.length; index += 1) {
      var line = lines[index];
      var blank = line.trim() === "";

      if (!current || current.blank !== blank) {
        current = {blank: blank, lines: []};
        groups.push(current);
      }

      current.lines.push(line);
    }

    return groups;
  }

  // source -> {blocks, leading, trailing, eol}. Separators are captured exactly
  // so untouched documents serialize back byte for byte.
  function parseDocument(source, knownPhoto) {
    var raw = source == null ? "" : String(source);
    // Reports saved through an HTML form arrive with CRLF endings, so the
    // parser works in LF and puts them back on the way out. That swap is only
    // safe when every line agrees: a document with mixed endings is left
    // exactly as it came in, carriage returns and all.
    var stripped = raw.indexOf("\r\n") >= 0 ? raw.replace(/\r\n/g, "") : raw;
    var uniformCrlf = raw.indexOf("\r\n") >= 0 && stripped.indexOf("\r") < 0 && stripped.indexOf("\n") < 0;
    var eol = uniformCrlf ? "\r\n" : "\n";
    var text = uniformCrlf ? raw.replace(/\r\n/g, "\n") : raw;
    var groups = groupLines(text);
    var doc = {eol: eol, leading: "", trailing: "", blank: "", blocks: []};
    var previous = null;
    var index;

    for (index = 0; index < groups.length; index += 1) {
      var group = groups[index];
      var body = group.lines.join("\n");

      if (group.blank) {
        if (index === 0) {
          doc.leading = body + "\n";
        } else if (index === groups.length - 1) {
          doc.trailing = "\n" + body;
        } else if (previous) {
          previous.sepAfter = "\n" + body + "\n";
        }
        continue;
      }

      var block = classifyChunk(body, knownPhoto);
      block.id = nextBlockId();
      block.sepAfter = DEFAULT_SEPARATOR;
      doc.blocks.push(block);
      previous = block;
    }

    for (index = 0; index < doc.blocks.length; index += 1) {
      doc.blocks[index].origNextId = doc.blocks[index + 1] ? doc.blocks[index + 1].id : null;
    }

    if (doc.blocks.length === 0) {
      doc.leading = "";
      doc.trailing = "";
      doc.blank = raw;
    }

    return doc;
  }

  function blockText(block) {
    if (block.type === "figure") return block.raw || "{{ photo:" + block.photoId + " }}";
    if (block.type === "raw") return block.text || "";
    if (block.type === "heading") return (block.prefix || "## ") + serializeInline(block.nodes || []);
    return serializeInline(block.nodes || []);
  }

  function serializeDocument(doc, blocks) {
    var source = blocks || (doc && doc.blocks) || [];
    var list = [];
    var index;

    for (index = 0; index < source.length; index += 1) {
      if (blockText(source[index]) !== "") list.push(source[index]);
    }

    if (list.length === 0) return (doc && doc.blank) || "";

    var out = (doc && doc.leading) || "";

    for (index = 0; index < list.length; index += 1) {
      out += blockText(list[index]);

      if (index < list.length - 1) {
        var block = list[index];
        var adjacent = block.origNextId && block.origNextId === list[index + 1].id;
        out += adjacent && block.sepAfter ? block.sepAfter : DEFAULT_SEPARATOR;
      }
    }

    out += (doc && doc.trailing) || "";

    return doc && doc.eol === "\r\n" ? out.replace(/\n/g, "\r\n") : out;
  }

  var markdownIO = {
    parseDocument: parseDocument,
    serializeDocument: serializeDocument,
    parseInline: parseInline,
    serializeInline: serializeInline,
    blockText: blockText,
    // Text -> blocks -> text with nothing touched in between.
    roundTrip: function (source, photoIds) {
      var known = photoIds ? function (id) { return photoIds.indexOf(id) >= 0; } : null;
      var doc = parseDocument(source, known);
      return serializeDocument(doc, doc.blocks);
    }
  };

  /* ------------------------------------------------------------------------
     Dating a hike from its photos. Also DOM-free for the Node harness.

     The min taken-on day becomes the hike date and the span to the max
     becomes the nights out. Photos only get to speak when their dates are
     believable: a camera with a reset clock stamps the distant past, a
     mis-set one stamps the future, and a spread wider than a long carry
     means the photos are not all from one trip.
     ------------------------------------------------------------------------ */

  var ISO_DAY = /^(\d{4}-\d{2}-\d{2})/;
  var EARLIEST_BELIEVABLE_DAY = "1990-01-01";
  var LONGEST_BELIEVABLE_TRIP_NIGHTS = 60;

  function utcDay(day) {
    var parts = day.split("-");
    return Date.UTC(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
  }

  function tripDatesFromPhotos(takenDays, today) {
    var days = [];

    for (var index = 0; index < (takenDays || []).length; index += 1) {
      var match = ISO_DAY.exec(String(takenDays[index] == null ? "" : takenDays[index]));
      if (!match) continue;

      var day = match[1];
      if (day < EARLIEST_BELIEVABLE_DAY) continue;
      if (today && day > today) continue;
      days.push(day);
    }

    if (!days.length) return null;

    days.sort();
    var nights = Math.round((utcDay(days[days.length - 1]) - utcDay(days[0])) / 86400000);
    if (nights > LONGEST_BELIEVABLE_TRIP_NIGHTS) return null;

    return {hikedAt: days[0], nights: nights};
  }

  var api = {markdownIO: markdownIO, tripDatesFromPhotos: tripDatesFromPhotos};

  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (typeof window !== "undefined") window.WentHikingEditor = api;
  if (typeof document === "undefined") return;

  /* ------------------------------------------------------------------------
     Small shared helpers.
     ------------------------------------------------------------------------ */

  function element(tag, className, attributes) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    // The whole compose page lives inside one form, so an untyped button would
    // publish the hike the first time anybody clicked it.
    if (tag === "button") node.type = "button";
    if (attributes) {
      Object.keys(attributes).forEach(function (key) {
        if (attributes[key] === null || attributes[key] === undefined) return;
        node.setAttribute(key, attributes[key]);
      });
    }
    return node;
  }

  function csrfToken() {
    var meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.getAttribute("content") : "";
  }

  // Same-origin POSTs carry the token in a header. The storage upload deliberately
  // does not: it may target S3, whose presigned POST rejects extra headers.
  function postHeaders(extra) {
    var headers = {"X-CSRF-Token": csrfToken()};
    if (extra) {
      Object.keys(extra).forEach(function (key) {
        headers[key] = extra[key];
      });
    }
    return headers;
  }

  function jsonPayload(response) {
    return response.text().then(function (text) {
      try {
        return text ? JSON.parse(text) : {};
      } catch (error) {
        return {};
      }
    });
  }

  function postJson(url, params) {
    return fetch(url, {
      method: "POST",
      headers: postHeaders({"Content-Type": "application/x-www-form-urlencoded"}),
      body: new URLSearchParams(params || {})
    }).then(function (response) {
      return jsonPayload(response).then(function (body) {
        if (!response.ok) throw body;
        return body;
      });
    });
  }

  function uploadWithProgress(upload, file, onProgress) {
    return new Promise(function (resolve, reject) {
      var body = new FormData();
      Object.keys(upload.fields || {}).forEach(function (key) {
        body.append(key, upload.fields[key]);
      });
      body.append("file", file);

      var request = new XMLHttpRequest();
      request.open("POST", upload.url);
      request.timeout = 180000;
      request.upload.addEventListener("progress", function (event) {
        if (event.lengthComputable) onProgress(event.loaded / event.total);
      });
      request.addEventListener("load", function () {
        if (request.status >= 200 && request.status < 300) resolve();
        else reject(new Error("Photo storage rejected the upload."));
      });
      request.addEventListener("error", function () {
        reject(new Error("Photo storage could not be reached."));
      });
      request.addEventListener("timeout", function () {
        reject(new Error("The upload timed out. Try again."));
      });
      request.send(body);
    });
  }

  // A saturated connection drops an upload now and then; the presigned ticket
  // is still good, so one quiet retry beats surfacing the hiccup.
  function uploadToStorage(upload, file, onProgress) {
    return uploadWithProgress(upload, file, onProgress).catch(function () {
      return uploadWithProgress(upload, file, onProgress);
    });
  }

  function errorMessages(error) {
    if (error && Array.isArray(error.errors)) return error.errors;
    if (error && error.errors && typeof error.errors === "object") {
      return Object.keys(error.errors).map(function (key) {
        return error.errors[key];
      });
    }
    if (error && error.message) return [error.message];
    return [];
  }

  function formatCoordinate(value) {
    return Number(value).toFixed(5).replace(/0+$/, "").replace(/\.$/, "");
  }

  function isImageFile(file) {
    return file && file.type && file.type.indexOf("image/") === 0;
  }

  /* ------------------------------------------------------------------------
     Blocks <-> DOM.
     ------------------------------------------------------------------------ */

  function nodesToHtml(nodes) {
    var out = "";

    for (var index = 0; index < nodes.length; index += 1) {
      var node = nodes[index];

      if (node.t === "text") {
        out += escapeHtml(node.v).replace(/\n/g, "<br>");
      } else if (node.t === "link") {
        out += '<a href="' + escapeHtml(node.href) + '">' + nodesToHtml(node.c) + "</a>";
      } else if (node.t === "strong") {
        out += '<strong data-md="' + escapeHtml(node.m) + '">' + nodesToHtml(node.c) + "</strong>";
      } else {
        out += '<em data-md="' + escapeHtml(node.m) + '">' + nodesToHtml(node.c) + "</em>";
      }
    }

    return out;
  }

  function escapeHtml(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function pushText(nodes, value) {
    if (!value) return;
    var last = nodes[nodes.length - 1];
    if (last && last.t === "text") last.v += value;
    else nodes.push({t: "text", v: value});
  }

  // Reads a contenteditable element back into inline nodes. Unknown wrappers
  // (spans from a paste, execCommand leftovers) are transparent.
  function nodesFromDom(root) {
    var nodes = [];
    var children = root.childNodes;

    for (var index = 0; index < children.length; index += 1) {
      var child = children[index];

      if (child.nodeType === 3) {
        pushText(nodes, child.nodeValue);
        continue;
      }

      if (child.nodeType !== 1) continue;

      var tag = child.tagName.toLowerCase();

      if (tag === "br") {
        // Browsers park a trailing <br> in an empty editable line; it is not content.
        if (index === children.length - 1 && root.getAttribute("data-block")) continue;
        pushText(nodes, "\n");
      } else if (tag === "strong" || tag === "b") {
        nodes.push({t: "strong", m: child.getAttribute("data-md") || "**", c: nodesFromDom(child)});
      } else if (tag === "em" || tag === "i") {
        nodes.push({t: "em", m: child.getAttribute("data-md") || "*", c: nodesFromDom(child)});
      } else if (tag === "a") {
        nodes.push({t: "link", href: child.getAttribute("href") || "", c: nodesFromDom(child)});
      } else {
        var inner = nodesFromDom(child);
        for (var inner_index = 0; inner_index < inner.length; inner_index += 1) {
          if (inner[inner_index].t === "text") pushText(nodes, inner[inner_index].v);
          else nodes.push(inner[inner_index]);
        }
      }
    }

    return nodes;
  }

  /* ------------------------------------------------------------------------
     Editor state.
     ------------------------------------------------------------------------ */

  var state = {
    root: null,
    form: null,
    canvas: null,
    source: null,
    title: null,
    tray: null,
    trayGrid: null,
    fileInput: null,
    statusNode: null,
    mode: "new",
    tripId: null,
    urls: {},
    doc: null,
    photos: {},
    photoOrder: [],
    canvasDirty: false,
    dirty: false,
    submitting: false,
    draftPromise: null,
    autosaveTimer: null,
    captionTimers: {},
    fileTarget: null,
    dragBlock: null,
    pendingSequence: 0,
    toolbar: null,
    savedRange: null,
    maxUploadBytes: 0,
    uploadQueue: [],
    activeUploads: 0,
    cancelledPending: {},
    autoDate: {active: false, nightsActive: true, applied: false, appliedNights: false, previous: null, note: null}
  };

  function hasPhoto(id) {
    return Object.prototype.hasOwnProperty.call(state.photos, String(id));
  }

  function isPendingId(id) {
    return String(id).indexOf("pending-") === 0;
  }

  function photoItem(id) {
    return state.photos[String(id)];
  }

  function registerPhoto(item) {
    var key = String(item.id);
    if (!hasPhoto(key)) state.photoOrder.push(key);
    state.photos[key] = item;
  }

  function forgetPhoto(id) {
    var key = String(id);
    delete state.photos[key];
    state.photoOrder = state.photoOrder.filter(function (value) {
      return value !== key;
    });
  }

  /* ------------------------------------------------------------------------
     Blocks in the DOM.
     ------------------------------------------------------------------------ */

  function blockMeta(node) {
    return node && node._block;
  }

  function isTextBlock(node) {
    var meta = blockMeta(node);
    return !!meta && (meta.type === "paragraph" || meta.type === "heading");
  }

  function newBlockMeta(type, extra) {
    var meta = {id: nextBlockId(), type: type, sepAfter: DEFAULT_SEPARATOR, origNextId: null};
    if (extra) {
      Object.keys(extra).forEach(function (key) {
        meta[key] = extra[key];
      });
    }
    return meta;
  }

  function createTextBlock(block) {
    var tag = block.type === "heading" ? "h" + Math.min(Math.max(block.level || 2, 1), 6) : "p";
    var node = element(tag, "compose-block compose-block-text", {
      "data-block": block.type,
      contenteditable: "true"
    });
    node.innerHTML = nodesToHtml(block.nodes || []);
    node._block = {
      id: block.id || nextBlockId(),
      type: block.type,
      level: block.level,
      prefix: block.prefix || (block.type === "heading" ? "## " : null),
      sepAfter: block.sepAfter || DEFAULT_SEPARATOR,
      origNextId: block.origNextId || null
    };
    return node;
  }

  function createRawBlock(block) {
    var node = element("div", "compose-block compose-block-raw", {"data-block": "raw"});
    var label = element("span", "compose-raw-tag", {"aria-hidden": "true"});
    label.textContent = "markdown";
    var area = element("textarea", "compose-raw-input", {
      spellcheck: "false",
      "aria-label": "Markdown this editor keeps as written"
    });
    area.value = block.text || "";
    node.appendChild(label);
    node.appendChild(area);
    node._block = {
      id: block.id || nextBlockId(),
      type: "raw",
      sepAfter: block.sepAfter || DEFAULT_SEPARATOR,
      origNextId: block.origNextId || null
    };
    return node;
  }

  function figureMenuButton(action, label) {
    var button = element("button", "compose-figure-menu-item", {"data-figure-action": action});
    button.textContent = label;
    return button;
  }

  function createFigureBlock(block) {
    var item = photoItem(block.photoId) || {};
    var node = element("figure", "compose-block compose-figure", {
      "data-block": "figure",
      "data-photo-id": block.photoId,
      contenteditable: "false",
      draggable: "true",
      tabindex: "0"
    });

    var media = element("div", "compose-figure-media");
    var image = element("img", "compose-figure-image", {alt: ""});
    if (item.thumb_url) image.src = item.thumb_url;
    media.appendChild(image);

    var progress = element("div", "compose-figure-progress", {hidden: "hidden"});
    progress.appendChild(element("span", "compose-figure-progress-bar"));
    media.appendChild(progress);

    var tools = element("div", "compose-figure-tools");
    var toggle = element("button", "compose-figure-toggle", {
      "aria-label": "Photo actions",
      "aria-haspopup": "true",
      "aria-expanded": "false",
      "data-figure-toggle": ""
    });
    toggle.innerHTML = '<span aria-hidden="true">&hellip;</span>';
    var menu = element("div", "compose-figure-menu", {hidden: "hidden", "data-figure-menu": ""});
    menu.appendChild(figureMenuButton("up", "Move up"));
    menu.appendChild(figureMenuButton("down", "Move down"));
    menu.appendChild(figureMenuButton("tray", "Send to gallery"));
    menu.appendChild(figureMenuButton("delete", "Delete photo"));
    tools.appendChild(toggle);
    tools.appendChild(menu);
    media.appendChild(tools);

    var caption = element("figcaption", "compose-figure-caption");
    var input = element("input", "compose-caption-input", {
      type: "text",
      placeholder: "Add a caption",
      "aria-label": "Photo caption",
      "data-compose-caption": ""
    });
    input.value = item.caption || "";
    caption.appendChild(input);

    node.appendChild(media);
    node.appendChild(caption);
    node._block = {
      id: block.id || nextBlockId(),
      type: "figure",
      photoId: block.photoId,
      raw: block.raw || null,
      sepAfter: block.sepAfter || DEFAULT_SEPARATOR,
      origNextId: block.origNextId || null
    };
    return node;
  }

  function createBlockElement(block) {
    if (block.type === "figure") return createFigureBlock(block);
    if (block.type === "raw") return createRawBlock(block);
    return createTextBlock(block);
  }

  function readBlock(node) {
    var meta = blockMeta(node);
    if (!meta) return null;

    var base = {id: meta.id, sepAfter: meta.sepAfter, origNextId: meta.origNextId};

    if (meta.type === "figure") {
      // A photo that has not finished uploading has no real id yet, and a
      // placeholder id must never reach report_markdown.
      if (isPendingId(meta.photoId)) return null;
      base.type = "figure";
      base.photoId = meta.photoId;
      base.raw = meta.raw;
      return base;
    }

    if (meta.type === "raw") {
      var area = node.querySelector("textarea");
      base.type = "raw";
      base.text = area ? area.value : "";
      return base;
    }

    base.type = meta.type;
    base.nodes = nodesFromDom(node);
    if (meta.type === "heading") {
      base.level = meta.level;
      base.prefix = meta.prefix || "## ";
    }
    return base;
  }

  function canvasBlocks() {
    var blocks = [];
    var children = state.canvas.children;

    for (var index = 0; index < children.length; index += 1) {
      var block = readBlock(children[index]);
      if (block) blocks.push(block);
    }

    return blocks;
  }

  function serializeCanvas() {
    return serializeDocument(state.doc, canvasBlocks());
  }

  // The pristine server value is only overwritten once the writer has actually
  // touched the story, so an untouched report is posted back exactly as it came.
  function syncSource() {
    if (!state.canvasDirty) return state.source.value;
    state.source.value = serializeCanvas();
    return state.source.value;
  }

  function renderCanvas() {
    state.doc = parseDocument(state.source.value, hasPhoto);
    state.canvas.innerHTML = "";

    state.doc.blocks.forEach(function (block) {
      state.canvas.appendChild(createBlockElement(block));
    });

    if (!state.canvas.firstChild) {
      state.canvas.appendChild(createTextBlock({type: "paragraph", nodes: []}));
    }

    // A textarea has no scrollHeight until it is in the document, so raw blocks
    // are sized after the canvas is assembled rather than as they are built.
    var raws = state.canvas.querySelectorAll(".compose-raw-input");
    for (var index = 0; index < raws.length; index += 1) autoGrow(raws[index]);

    refreshPlaceholders();
    syncTray();
  }

  function refreshPlaceholders() {
    var children = state.canvas.children;

    for (var index = 0; index < children.length; index += 1) {
      var node = children[index];
      if (!isTextBlock(node)) continue;
      var empty = node.textContent.trim() === "";
      node.classList.toggle("is-empty", empty);
      node.classList.toggle("is-lead", empty && index === 0 && children.length === 1);
    }
  }

  /* ------------------------------------------------------------------------
     Caret helpers.
     ------------------------------------------------------------------------ */

  function applyRange(range) {
    var selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
  }

  function focusBlock(node, position) {
    if (!node) return;

    if (blockMeta(node) && blockMeta(node).type === "raw") {
      var area = node.querySelector("textarea");
      if (area) {
        area.focus();
        var caret = position === "start" ? 0 : area.value.length;
        area.setSelectionRange(caret, caret);
      }
      return;
    }

    if (blockMeta(node) && blockMeta(node).type === "figure") {
      node.focus();
      return;
    }

    node.focus();
    var range = document.createRange();
    range.selectNodeContents(node);
    range.collapse(position === "start");
    applyRange(range);
  }

  function currentRange() {
    var selection = window.getSelection();
    if (!selection || !selection.rangeCount) return null;
    return selection.getRangeAt(0);
  }

  function caretAtEdge(node, edge) {
    var range = currentRange();
    if (!range || !range.collapsed) return false;

    var probe = range.cloneRange();
    probe.selectNodeContents(node);

    if (edge === "start") {
      probe.setEnd(range.startContainer, range.startOffset);
    } else {
      probe.setStart(range.endContainer, range.endOffset);
    }

    return probe.toString() === "";
  }

  function blockFromNode(node) {
    while (node && node !== state.canvas) {
      if (node.nodeType === 1 && node.parentNode === state.canvas) return node;
      node = node.parentNode;
    }
    return null;
  }

  function activeTextBlock() {
    var range = currentRange();
    if (!range) return null;
    var node = blockFromNode(range.startContainer);
    return isTextBlock(node) ? node : null;
  }

  /* ------------------------------------------------------------------------
     Canvas editing.
     ------------------------------------------------------------------------ */

  function markCanvasDirty() {
    state.canvasDirty = true;
    markDirty();
  }

  function insertBlockAt(node, reference) {
    state.canvas.insertBefore(node, reference || null);
    markCanvasDirty();
    refreshPlaceholders();
    syncTray();
    return node;
  }

  function splitTextBlock(node) {
    var range = currentRange();
    if (!range) return;

    var tail = range.cloneRange();
    tail.selectNodeContents(node);
    tail.setStart(range.endContainer, range.endOffset);

    var fragment = tail.extractContents();
    var next = createTextBlock({type: "paragraph", nodes: []});
    next.appendChild(fragment);
    stripTrailingBreak(node);
    state.canvas.insertBefore(next, node.nextSibling);
    markCanvasDirty();
    refreshPlaceholders();
    focusBlock(next, "start");
  }

  function stripTrailingBreak(node) {
    while (node.lastChild && node.lastChild.nodeType === 1 && node.lastChild.tagName.toLowerCase() === "br") {
      node.removeChild(node.lastChild);
    }
  }

  function convertToParagraph(node) {
    var paragraph = createTextBlock({type: "paragraph", nodes: []});
    var meta = blockMeta(node);
    paragraph._block.id = meta.id;
    paragraph._block.sepAfter = meta.sepAfter;
    paragraph._block.origNextId = meta.origNextId;

    while (node.firstChild) paragraph.appendChild(node.firstChild);
    state.canvas.replaceChild(paragraph, node);
    markCanvasDirty();
    refreshPlaceholders();
    focusBlock(paragraph, "start");
    return paragraph;
  }

  function mergeBackward(node) {
    var previous = node.previousElementSibling;
    if (!previous) return;

    var meta = blockMeta(previous);

    if (meta.type === "figure" || meta.type === "raw") {
      if (node.textContent === "") {
        state.canvas.removeChild(node);
        markCanvasDirty();
        refreshPlaceholders();
      }
      focusBlock(previous, "end");
      return;
    }

    stripTrailingBreak(previous);

    var range = document.createRange();
    if (previous.lastChild) range.setStartAfter(previous.lastChild);
    else range.setStart(previous, 0);
    range.collapse(true);

    while (node.firstChild) previous.appendChild(node.firstChild);
    state.canvas.removeChild(node);
    previous.focus();
    applyRange(range);
    markCanvasDirty();
    refreshPlaceholders();
  }

  function applyHeadingShortcut(node) {
    if (blockMeta(node).type !== "paragraph") return false;

    var first = node.firstChild;
    if (!first || first.nodeType !== 3) return false;

    var match = /^(#{1,6})[ \t]/.exec(first.nodeValue);
    if (!match) return false;

    // The trip's title is the page's only h1, so "# " here has to land at h2
    // rather than giving the page a second one — and the prefix has to be
    // clamped alongside the level, because the prefix is what gets written back
    // out as markdown. Anything past h3 flattens too: a trip report has no use
    // for six levels. Headings already in the source keep their own prefix and
    // round-trip untouched; only what is typed here is decided here.
    var level = Math.min(Math.max(match[1].length, 2), 3);
    var meta = blockMeta(node);
    var heading = createTextBlock({type: "heading", level: level, prefix: (level === 2 ? "## " : "### "), nodes: []});
    heading._block.id = meta.id;
    heading._block.sepAfter = meta.sepAfter;
    heading._block.origNextId = meta.origNextId;

    first.nodeValue = first.nodeValue.slice(match[0].length);
    while (node.firstChild) heading.appendChild(node.firstChild);
    state.canvas.replaceChild(heading, node);
    focusBlock(heading, "end");
    markCanvasDirty();
    refreshPlaceholders();
    return true;
  }

  function handleCanvasKeydown(event) {
    var node = blockFromNode(event.target);
    if (!node) return;

    if (blockMeta(node) && blockMeta(node).type === "raw") {
      if (event.key === "Backspace" && event.target.value === "") {
        event.preventDefault();
        var before = node.previousElementSibling;
        state.canvas.removeChild(node);
        markCanvasDirty();
        focusBlock(before, "end");
      }
      return;
    }

    if (!isTextBlock(node)) return;

    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      splitTextBlock(node);
      return;
    }

    if (event.key === "Backspace" && caretAtEdge(node, "start") && !currentRangeHasSelection()) {
      if (blockMeta(node).type === "heading") {
        event.preventDefault();
        convertToParagraph(node);
        return;
      }

      if (node.previousElementSibling) {
        event.preventDefault();
        mergeBackward(node);
      }
      return;
    }

    if (event.key === "ArrowUp" && caretAtEdge(node, "start")) {
      var above = node.previousElementSibling;
      if (above) {
        event.preventDefault();
        focusBlock(above, "end");
      }
      return;
    }

    if (event.key === "ArrowDown" && caretAtEdge(node, "end")) {
      var below = node.nextElementSibling;
      if (below) {
        event.preventDefault();
        focusBlock(below, "start");
      }
    }
  }

  function currentRangeHasSelection() {
    var range = currentRange();
    return !!range && !range.collapsed;
  }

  function handleCanvasInput(event) {
    var caption = event.target.closest ? event.target.closest("[data-compose-caption]") : null;
    if (caption) {
      saveCaption(caption);
      return;
    }

    var node = blockFromNode(event.target);
    if (!node) return;

    if (blockMeta(node) && blockMeta(node).type === "raw") {
      autoGrow(event.target);
      markCanvasDirty();
      scheduleAutosave();
      return;
    }

    if (isTextBlock(node)) applyHeadingShortcut(node);

    markCanvasDirty();
    refreshPlaceholders();
    scheduleAutosave();
  }

  function handleCanvasPaste(event) {
    var node = blockFromNode(event.target);
    if (!node || !isTextBlock(node)) return;

    var data = event.clipboardData;
    if (!data) return;

    var files = [];
    for (var index = 0; index < (data.files || []).length; index += 1) {
      if (isImageFile(data.files[index])) files.push(data.files[index]);
    }

    if (files.length) {
      event.preventDefault();
      queueUploads(files, {kind: "canvas", before: node.nextElementSibling});
      return;
    }

    var text = data.getData("text/plain");
    if (!text) return;

    event.preventDefault();
    var chunks = text.replace(/\r\n/g, "\n").split(/\n{2,}/);
    document.execCommand("insertText", false, chunks[0]);

    var reference = node.nextElementSibling;
    for (var chunk = 1; chunk < chunks.length; chunk += 1) {
      var block = createTextBlock({type: "paragraph", nodes: [{t: "text", v: chunks[chunk]}]});
      state.canvas.insertBefore(block, reference);
      if (chunk === chunks.length - 1) focusBlock(block, "end");
    }

    markCanvasDirty();
    refreshPlaceholders();
    scheduleAutosave();
  }

  /* ------------------------------------------------------------------------
     Selection toolbar.
     ------------------------------------------------------------------------ */

  function buildToolbar() {
    var bar = element("div", "compose-toolbar", {hidden: "hidden", role: "toolbar", "aria-label": "Text formatting"});

    var bold = element("button", "compose-toolbar-button", {"data-command": "bold", "aria-label": "Bold"});
    bold.innerHTML = "<strong>B</strong>";
    var italic = element("button", "compose-toolbar-button", {"data-command": "italic", "aria-label": "Italic"});
    italic.innerHTML = "<em>I</em>";
    var link = element("button", "compose-toolbar-button", {"data-command": "link", "aria-label": "Add link"});
    link.textContent = "Link";

    var row = element("span", "compose-toolbar-link", {hidden: "hidden"});
    var input = element("input", "compose-toolbar-input", {
      type: "url",
      placeholder: "https://",
      "aria-label": "Link address"
    });
    var apply = element("button", "compose-toolbar-apply");
    apply.textContent = "Apply";
    var remove = element("button", "compose-toolbar-remove");
    remove.textContent = "Remove";
    row.appendChild(input);
    row.appendChild(apply);
    row.appendChild(remove);

    bar.appendChild(bold);
    bar.appendChild(italic);
    bar.appendChild(link);
    bar.appendChild(row);
    document.body.appendChild(bar);

    // Keeping the selection alive means never letting the toolbar take focus.
    bar.addEventListener("mousedown", function (event) {
      if (event.target === input) return;
      event.preventDefault();
    });

    bar.addEventListener("click", function (event) {
      var button = event.target.closest("button");
      if (!button) return;
      event.preventDefault();

      if (button === apply) {
        applyLink(input.value.trim());
        return;
      }

      if (button === remove) {
        restoreRange();
        document.execCommand("unlink");
        row.hidden = true;
        markCanvasDirty();
        scheduleAutosave();
        return;
      }

      var command = button.getAttribute("data-command");
      if (command === "link") {
        state.savedRange = currentRange() ? currentRange().cloneRange() : null;
        row.hidden = false;
        input.value = enclosingLinkHref() || "";
        input.focus();
        return;
      }

      document.execCommand(command);
      markCanvasDirty();
      scheduleAutosave();
    });

    input.addEventListener("keydown", function (event) {
      if (event.key === "Enter") {
        event.preventDefault();
        applyLink(input.value.trim());
      } else if (event.key === "Escape") {
        event.preventDefault();
        row.hidden = true;
        hideToolbar();
      }
    });

    state.toolbar = {node: bar, row: row, input: input};
    return state.toolbar;
  }

  function enclosingLinkHref() {
    var range = state.savedRange || currentRange();
    if (!range) return "";
    var node = range.startContainer;
    while (node && node !== state.canvas) {
      if (node.nodeType === 1 && node.tagName.toLowerCase() === "a") return node.getAttribute("href");
      node = node.parentNode;
    }
    return "";
  }

  function restoreRange() {
    if (state.savedRange) applyRange(state.savedRange);
  }

  function applyLink(url) {
    if (!url) return;
    restoreRange();
    document.execCommand("createLink", false, url);
    state.toolbar.row.hidden = true;
    hideToolbar();
    markCanvasDirty();
    scheduleAutosave();
  }

  function hideToolbar() {
    if (!state.toolbar) return;
    state.toolbar.node.hidden = true;
    state.toolbar.row.hidden = true;
  }

  function positionToolbar() {
    if (!state.toolbar || document.activeElement === state.toolbar.input) return;

    var range = currentRange();
    var node = activeTextBlock();

    if (!range || range.collapsed || !node) {
      hideToolbar();
      return;
    }

    var rect = range.getBoundingClientRect();
    if (!rect.width && !rect.height) {
      hideToolbar();
      return;
    }

    var bar = state.toolbar.node;
    bar.hidden = false;

    var width = bar.offsetWidth;
    var left = rect.left + window.pageXOffset + rect.width / 2 - width / 2;
    left = Math.max(8, Math.min(left, window.innerWidth - width - 8));
    bar.style.left = left + "px";

    // Above the selection normally, below it when the sticky bar or the byline
    // is in the way — the toolbar must never cover the metadata it sits near.
    var composeBar = state.root.querySelector(".compose-bar");
    var ceiling = composeBar ? composeBar.getBoundingClientRect().bottom : 0;
    var byline = state.root.querySelector("[data-compose-byline]");
    if (byline) ceiling = Math.max(ceiling, byline.getBoundingClientRect().bottom);

    var above = rect.top - bar.offsetHeight - 10;
    var top = above < ceiling + 4 ? rect.bottom + 10 : above;
    bar.style.top = top + window.pageYOffset + "px";
  }

  /* ------------------------------------------------------------------------
     Photos: uploads, figures, gallery tray.
     ------------------------------------------------------------------------ */

  function trayCardFor(id) {
    return state.trayGrid.querySelector('[data-photo-id="' + String(id).replace(/"/g, '\\"') + '"]');
  }

  function figureFor(id) {
    return state.canvas.querySelector('[data-block="figure"][data-photo-id="' + String(id).replace(/"/g, '\\"') + '"]');
  }

  function createTrayCard(id) {
    var item = photoItem(id) || {};
    var card = element("article", "compose-tray-card", {"data-photo-id": id, draggable: "true"});

    var media = element("div", "compose-tray-media");
    var image = element("img", "compose-tray-image", {alt: ""});
    if (item.thumb_url) image.src = item.thumb_url;
    media.appendChild(image);
    var progress = element("div", "compose-tray-progress", {hidden: "hidden"});
    progress.appendChild(element("span", "compose-tray-progress-bar"));
    media.appendChild(progress);

    var caption = element("input", "compose-caption-input", {
      type: "text",
      placeholder: "Caption",
      "aria-label": "Photo caption",
      "data-compose-caption": ""
    });
    caption.value = item.caption || "";

    var actions = element("div", "compose-tray-actions");
    var insert = element("button", "compose-tray-insert", {"data-tray-action": "insert"});
    insert.textContent = "Add to story";
    var remove = element("button", "compose-tray-delete", {"data-tray-action": "delete", "aria-label": "Delete photo"});
    remove.textContent = "Delete";
    actions.appendChild(insert);
    actions.appendChild(remove);

    card.appendChild(media);
    card.appendChild(caption);
    card.appendChild(actions);
    return card;
  }

  // The tray holds whatever the story does not: attach a photo and it lands
  // here, place it in the story and it leaves.
  function syncTray() {
    if (!state.trayGrid) return;

    var used = {};
    var figures = state.canvas.querySelectorAll('[data-block="figure"]');

    for (var index = 0; index < figures.length; index += 1) {
      used[String(figures[index].getAttribute("data-photo-id"))] = true;
    }

    state.photoOrder.forEach(function (id) {
      var card = trayCardFor(id);

      if (used[id]) {
        if (card) card.remove();
        return;
      }

      if (!card) state.trayGrid.appendChild(createTrayCard(id));
    });

    var cards = state.trayGrid.children;
    for (var cardIndex = cards.length - 1; cardIndex >= 0; cardIndex -= 1) {
      var photoId = cards[cardIndex].getAttribute("data-photo-id");
      if (photoId && !isPendingId(photoId) && !hasPhoto(photoId)) cards[cardIndex].remove();
    }

    var count = state.trayGrid.children.length;
    state.tray.classList.toggle("is-empty", count === 0);
  }

  function insertFigure(photoId, reference) {
    var figure = createFigureBlock({type: "figure", photoId: photoId});
    insertBlockAt(figure, reference);
    scheduleAutosave();
    return figure;
  }

  function setProgress(container, amount) {
    if (!container) return;
    var progress = container.querySelector(".compose-figure-progress, .compose-tray-progress");
    if (!progress) return;
    var bar = progress.firstElementChild;
    progress.hidden = false;
    if (bar) bar.style.width = Math.max(4, Math.round(amount * 100)) + "%";
  }

  function clearProgress(container) {
    if (!container) return;
    var progress = container.querySelector(".compose-figure-progress, .compose-tray-progress");
    if (progress) progress.hidden = true;
  }

  function markUploadFailed(container, message) {
    if (!container) return;
    container.classList.add("is-failed");
    container.classList.remove("is-uploading");
    clearProgress(container);
    var note = container.querySelector(".compose-upload-error");
    if (!note) {
      note = element("p", "compose-upload-error");
      container.appendChild(note);
    }
    note.textContent = message || "Upload failed. Try again.";
  }

  function queueUploads(files, target) {
    var list = Array.prototype.slice.call(files || []).filter(isImageFile);
    if (!list.length) return;

    var reference = target && target.kind === "canvas" ? target.before : null;

    list.forEach(function (file) {
      uploadPhoto(file, target && target.kind === "canvas" ? {kind: "canvas", before: reference} : {kind: "tray"});
    });
  }

  // Dropping a dozen photos at once used to start a dozen simultaneous
  // uploads, and a saturated uplink starves every one of them — including the
  // small fetches this page needs to stay alive. Two at a time finishes each
  // photo quickly and keeps its progress bar honest; the rest wait their turn
  // with the spinner showing.
  var MAX_PARALLEL_UPLOADS = 2;

  function drainUploadQueue() {
    while (state.activeUploads < MAX_PARALLEL_UPLOADS && state.uploadQueue.length) {
      var run = state.uploadQueue.shift();
      state.activeUploads += 1;
      var settle = function () {
        state.activeUploads -= 1;
        drainUploadQueue();
      };
      run().then(settle, settle);
    }
  }

  function uploadPhoto(file, target) {
    state.pendingSequence += 1;
    var pendingId = "pending-" + state.pendingSequence;
    var previewUrl = URL.createObjectURL(file);
    var container;

    state.photos[pendingId] = {id: pendingId, caption: "", thumb_url: previewUrl};
    state.photoOrder.push(pendingId);

    if (target && target.kind === "canvas") {
      container = createFigureBlock({type: "figure", photoId: pendingId});
      state.canvas.insertBefore(container, target.before || null);
      markCanvasDirty();
      refreshPlaceholders();
    } else {
      container = createTrayCard(pendingId);
      state.trayGrid.appendChild(container);
      state.tray.classList.remove("is-empty");
    }

    container.classList.add("is-uploading");
    setProgress(container, 0.04);

    // The server would refuse this at ticket time anyway; saying so before
    // any bytes move keeps the oversize file from blocking the queue.
    if (state.maxUploadBytes && file.size > state.maxUploadBytes) {
      markUploadFailed(container, "Image file must be " + Math.round(state.maxUploadBytes / (1024 * 1024)) + " MB or smaller.");
      return Promise.resolve();
    }

    state.uploadQueue.push(function () {
      return runUploadFlow(file, container, pendingId, previewUrl);
    });
    drainUploadQueue();
  }

  function runUploadFlow(file, container, pendingId, previewUrl) {
    return ensureTrip()
      .then(function () {
        return postJson(state.urls.upload, {
          filename: file.name,
          content_type: file.type || "application/octet-stream",
          file_size: String(file.size),
          caption: ""
        });
      })
      .then(function (body) {
        return uploadToStorage(body.upload, file, function (amount) {
          setProgress(container, Math.max(0.05, amount * 0.9));
        }).then(function () {
          return body;
        });
      })
      .then(function (body) {
        setProgress(container, 0.97);
        return postJson(body.finalize_url, {});
      })
      .then(function (item) {
        // Deleted from the tray while the bytes were still moving: the upload
        // finished anyway, so quietly remove the orphan it produced.
        if (state.cancelledPending[pendingId]) {
          delete state.cancelledPending[pendingId];
          forgetPhoto(pendingId);
          if (state.urls.photo) postJson(state.urls.photo + "/" + item.id + "/delete", {});
          URL.revokeObjectURL(previewUrl);
          return item;
        }
        forgetPhoto(pendingId);
        registerPhoto(item);
        container.classList.remove("is-uploading");
        container.setAttribute("data-photo-id", item.id);
        if (blockMeta(container)) {
          blockMeta(container).photoId = item.id;
          blockMeta(container).raw = null;
        }
        var image = container.querySelector("img");
        if (image && item.thumb_url) image.src = item.thumb_url;
        clearProgress(container);
        URL.revokeObjectURL(previewUrl);
        markCanvasDirty();
        syncTray();
        applyPhotoDates();
        scheduleAutosave();
        return item;
      })
      .catch(function (error) {
        if (state.cancelledPending[pendingId]) {
          delete state.cancelledPending[pendingId];
          return;
        }
        var messages = errorMessages(error);
        markUploadFailed(container, messages[0]);
      });
  }

  function saveCaption(input) {
    var container = input.closest("[data-photo-id]");
    if (!container) return;

    var id = container.getAttribute("data-photo-id");
    var item = photoItem(id);
    if (!item || !item.caption_url) return;

    item.caption = input.value;
    window.clearTimeout(state.captionTimers[id]);
    state.captionTimers[id] = window.setTimeout(function () {
      postJson(item.caption_url, {caption: input.value})
        .then(function (payload) {
          registerPhoto(payload);
          // Captions save on their own even for a published hike, so the bar
          // must not claim the hike itself is saved when it is not.
          if (state.mode === "published" && state.dirty) setStatus("dirty");
          else setStatus("saved");
        })
        .catch(function () {
          setStatus("dirty", "Caption not saved");
        });
    }, 600);
  }

  function removePhotoLocally(id) {
    var figure = figureFor(id);
    if (figure) {
      figure.remove();
      markCanvasDirty();
    }
    var card = trayCardFor(id);
    if (card) card.remove();
    forgetPhoto(id);
    refreshPlaceholders();
    syncTray();
    applyPhotoDates();
    scheduleAutosave();
  }

  function deletePhoto(id) {
    // A pending card is a local preview — an upload still moving, or one that
    // failed. There is nothing on the server yet, so removal is immediate; if
    // bytes are still in flight, the flag tells the finish line to clean up.
    if (isPendingId(id)) {
      state.cancelledPending[id] = true;
      removePhotoLocally(id);
      return Promise.resolve();
    }

    var item = photoItem(id);
    var url = state.urls.photo ? state.urls.photo + "/" + id + "/delete" : null;
    if (!item || !url) return Promise.resolve();

    return postJson(url, {}).then(function () {
      removePhotoLocally(id);
    });
  }

  /* ------------------------------------------------------------------------
     Drag and drop.
     ------------------------------------------------------------------------ */

  function insertionReference(y) {
    var children = state.canvas.children;

    for (var index = 0; index < children.length; index += 1) {
      var rect = children[index].getBoundingClientRect();
      if (y < rect.top + rect.height / 2) return children[index];
    }

    return null;
  }

  function showDropMarker(reference) {
    var marker = state.dropMarker;
    if (!marker) {
      marker = element("div", "compose-drop-marker");
      state.dropMarker = marker;
    }
    state.canvas.insertBefore(marker, reference || null);
  }

  function hideDropMarker() {
    if (state.dropMarker && state.dropMarker.parentNode) state.dropMarker.remove();
  }

  function dragCarriesFiles(event) {
    var types = event.dataTransfer && event.dataTransfer.types;
    if (!types) return false;
    return Array.prototype.indexOf.call(types, "Files") >= 0;
  }

  function dragCarriesPhoto(event) {
    var types = event.dataTransfer && event.dataTransfer.types;
    if (!types) return false;
    return Array.prototype.indexOf.call(types, "application/x-wenthiking-photo") >= 0;
  }

  function overCanvas(event) {
    var rect = state.canvas.getBoundingClientRect();
    return event.clientY >= rect.top - 24 && event.clientY <= rect.bottom + 24;
  }

  function bindDragAndDrop() {
    state.root.addEventListener("dragover", function (event) {
      var files = dragCarriesFiles(event);
      var photo = dragCarriesPhoto(event) || state.dragBlock;
      if (!files && !photo) return;

      event.preventDefault();
      event.dataTransfer.dropEffect = files ? "copy" : "move";

      if (overCanvas(event)) {
        state.tray.classList.remove("is-drop-target");
        showDropMarker(insertionReference(event.clientY));
      } else {
        hideDropMarker();
        if (files) state.tray.classList.add("is-drop-target");
      }
    });

    state.root.addEventListener("dragleave", function (event) {
      if (event.target !== state.root && state.root.contains(event.relatedTarget)) return;
      hideDropMarker();
      state.tray.classList.remove("is-drop-target");
    });

    state.root.addEventListener("drop", function (event) {
      var files = dragCarriesFiles(event);
      var photoId = event.dataTransfer ? event.dataTransfer.getData("application/x-wenthiking-photo") : "";
      if (!files && !photoId && !state.dragBlock) return;

      event.preventDefault();
      var reference = state.dropMarker && state.dropMarker.parentNode ? state.dropMarker.nextElementSibling : null;
      var insideCanvas = state.dropMarker && state.dropMarker.parentNode;
      hideDropMarker();
      state.tray.classList.remove("is-drop-target");

      if (files) {
        queueUploads(event.dataTransfer.files, insideCanvas ? {kind: "canvas", before: reference} : {kind: "tray"});
        return;
      }

      if (state.dragBlock) {
        var moving = state.dragBlock;
        state.dragBlock = null;
        if (insideCanvas && reference !== moving) {
          state.canvas.insertBefore(moving, reference);
          markCanvasDirty();
          scheduleAutosave();
        } else if (!insideCanvas) {
          moving.remove();
          markCanvasDirty();
          syncTray();
          scheduleAutosave();
        }
        return;
      }

      if (photoId && insideCanvas) insertFigure(photoId, reference);
    });
  }

  /* ------------------------------------------------------------------------
     Byline chips.
     ------------------------------------------------------------------------ */

  function fieldNode(name) {
    return state.form.querySelector('[data-compose-field="' + name + '"]');
  }

  function fieldValue(name) {
    var node = fieldNode(name);
    return node ? node.value.trim() : "";
  }

  function autoSizeChip(input) {
    if (input.type === "date") return;

    var filled = input.value.trim() !== "";
    var content = input.value || input.getAttribute("placeholder") || "";
    var length = Math.max(String(content).length, 3);
    input.size = Math.min(length + 1, input.classList.contains("compose-chip-url") ? 32 : 12);
    input.classList.toggle("is-set", filled);

    var chip = input.closest("[data-compose-chip]");
    if (chip) chip.classList.toggle("is-set", filled);

    var unit = input.getAttribute("data-compose-unit");
    var label = chip && chip.querySelector("[data-compose-unit-label]");
    if (!unit || !label) return;

    // "1 nights" reads like a bug report, so the unit agrees with the number.
    var full = Number(input.value) === 1 ? unit.replace(/^(night|mile)s/, "$1") : unit;
    var abbreviation = input.getAttribute("data-compose-unit-short");

    if (abbreviation) {
      // Both spellings ship and CSS picks one, which keeps a full byline inside
      // two lines on a phone without listening for resizes.
      label.innerHTML =
        '<span class="compose-chip-wide">' + escapeHtml(full) + "</span>" +
        '<span class="compose-chip-narrow">' + escapeHtml(abbreviation) + "</span>";
    } else {
      label.textContent = full;
    }
  }

  function refreshChips() {
    var inputs = state.form.querySelectorAll(".compose-chip-input");
    for (var index = 0; index < inputs.length; index += 1) autoSizeChip(inputs[index]);
    refreshLocationChip();
  }

  function refreshLocationChip() {
    var toggle = state.root.querySelector("[data-compose-location-toggle]");
    if (!toggle) return;

    var lat = fieldValue("lat");
    var lng = fieldValue("lng");
    var label = lat && lng ? formatCoordinate(lat) + ", " + formatCoordinate(lng) : "";

    // Rewriting the toggle's contents detaches everything inside it, including
    // the span a click is still travelling up through — which is how clicking
    // "Pin set" used to open the popover and close it again in the same gesture.
    // So only touch the DOM when the pin has actually moved.
    if (toggle.getAttribute("data-location-label") === label) return;
    toggle.setAttribute("data-location-label", label);

    if (label) {
      // Coordinates on a wide byline, a mark on a narrow one: CSS picks, so the
      // label reflows with the viewport instead of on a resize listener.
      toggle.innerHTML =
        '<span class="compose-chip-wide">' + escapeHtml(label) + "</span>" +
        '<span class="compose-chip-narrow">Pin set &check;</span>';
      toggle.classList.add("is-set");
    } else {
      toggle.textContent = "+ drop a pin";
      toggle.classList.remove("is-set");
    }
  }

  function buildLocationChip() {
    var chip = state.root.querySelector("[data-compose-location]");
    if (!chip) return;

    var toggle = chip.querySelector("[data-compose-location-toggle]");
    var panel = chip.querySelector("[data-compose-location-panel]");
    var mapNode = chip.querySelector("[data-compose-map]");
    var latInput = chip.querySelector("[data-compose-lat]");
    var lngInput = chip.querySelector("[data-compose-lng]");
    var summary = chip.querySelector("[data-compose-location-summary]");
    var clear = chip.querySelector("[data-compose-location-clear]");
    var done = chip.querySelector("[data-compose-popover-close]");
    var map = null;
    var marker = null;

    function setSummary() {
      var lat = fieldValue("lat");
      var lng = fieldValue("lng");
      summary.textContent = lat && lng ? "Pin set at " + formatCoordinate(lat) + ", " + formatCoordinate(lng) + "." : "Click the map to drop a pin.";
    }

    // Purely the map's business. Showing an existing pin is not an edit, so
    // opening the popover on a hike that already has one must not travel any
    // further than this.
    function placeMarker(lat, lng, options) {
      if (!map) return;

      if (!marker) {
        marker = L.marker([lat, lng], {icon: pinIcon(), draggable: true}).addTo(map);
        marker.on("dragend", function () {
          var position = marker.getLatLng();
          setPin(position.lat, position.lng);
        });
      } else {
        marker.setLatLng([lat, lng]);
      }

      if (options && options.pan) map.panTo([lat, lng]);
    }

    // Latitude and longitude are set and cleared together, so the old
    // half-filled-coordinate error has nowhere to come from.
    function setPin(lat, lng, options) {
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;

      fieldNode("lat").value = formatCoordinate(lat);
      fieldNode("lng").value = formatCoordinate(lng);
      latInput.value = formatCoordinate(lat);
      lngInput.value = formatCoordinate(lng);

      placeMarker(lat, lng, options);
      setSummary();
      refreshLocationChip();
      clearFieldError("location");
      markDirty();
      scheduleAutosave();
    }

    function clearPin() {
      fieldNode("lat").value = "";
      fieldNode("lng").value = "";
      latInput.value = "";
      lngInput.value = "";
      if (marker) {
        marker.remove();
        marker = null;
      }
      setSummary();
      refreshLocationChip();
      markDirty();
      scheduleAutosave();
    }

    function pinIcon() {
      return L.icon({
        iconUrl: "/images/marker.png",
        shadowUrl: "/images/marker-shadow.png",
        iconSize: [16, 37],
        iconAnchor: [8, 37],
        shadowSize: [27, 18],
        shadowAnchor: [3, 18]
      });
    }

    function buildMap() {
      if (map || typeof L === "undefined") return;

      var lat = Number(fieldValue("lat"));
      var lng = Number(fieldValue("lng"));
      var hasPin = Number.isFinite(lat) && Number.isFinite(lng) && fieldValue("lat") !== "";

      map = L.map(mapNode).setView(
        hasPin ? [lat, lng] : [Number(mapNode.dataset.defaultLat), Number(mapNode.dataset.defaultLng)],
        hasPin ? 11 : Number(mapNode.dataset.defaultZoom)
      );
      L.tileLayer(mapNode.dataset.tileUrl, {
        attribution: "Tiles courtesy of the U.S. Geological Survey",
        maxZoom: 16
      }).addTo(map);
      map.on("click", function (event) {
        setPin(event.latlng.lat, event.latlng.lng);
      });
      if (hasPin) placeMarker(lat, lng);
      window.setTimeout(function () {
        map.invalidateSize({pan: false});
      }, 60);
    }

    function open() {
      panel.hidden = false;
      toggle.setAttribute("aria-expanded", "true");
      document.body.classList.add("compose-location-open");
      // Clicking into the map does not collapse a text selection, so the
      // formatting toolbar would otherwise hang around underneath the popover.
      hideToolbar();
      buildMap();
      if (map) {
        window.setTimeout(function () {
          map.invalidateSize({pan: false});
        }, 40);
      }
    }

    // Dismissing by keyboard has to hand focus back to the control that opened
    // the popover; dismissing by clicking elsewhere must not steal it.
    function close(options) {
      var wasOpen = !panel.hidden;

      panel.hidden = true;
      toggle.setAttribute("aria-expanded", "false");
      document.body.classList.remove("compose-location-open");
      if (wasOpen && options && options.restoreFocus) toggle.focus();
      return wasOpen;
    }

    toggle.addEventListener("click", function () {
      if (panel.hidden) open();
      else close();
    });

    clear.addEventListener("click", clearPin);
    done.addEventListener("click", function () {
      close({restoreFocus: true});
    });

    function syncManual() {
      var lat = Number(latInput.value);
      var lng = Number(lngInput.value);

      if (latInput.value.trim() === "" && lngInput.value.trim() === "") {
        clearPin();
        return;
      }

      if (Number.isFinite(lat) && Number.isFinite(lng) && latInput.value.trim() && lngInput.value.trim()) {
        setPin(lat, lng, {pan: true});
      } else {
        summary.textContent = "Both numbers are needed to set a pin.";
      }
    }

    latInput.addEventListener("change", syncManual);
    lngInput.addEventListener("change", syncManual);

    // The scrim is the modal's own "outside": a click that both starts and
    // ends there dismisses, while a map pan that strays off the dialog and
    // releases over the scrim must not.
    var scrimPress = false;

    panel.addEventListener("mousedown", function (event) {
      scrimPress = event.target === panel;
    });

    panel.addEventListener("click", function (event) {
      if (scrimPress && event.target === panel) close();
      scrimPress = false;
    });

    state.closeLocation = close;
    setSummary();
  }

  /* ------------------------------------------------------------------------
     The hike date follows the photos.

     Until the writer picks a date themselves, the byline is filled in from
     the photos' EXIF days: the earliest becomes the hike date, the span to
     the latest becomes the nights out. Every automatic change announces
     itself in place — a quiet line under the byline with the undo — and the
     writer touching either chip ends the automation for good.
     ------------------------------------------------------------------------ */

  function todayIso() {
    var now = new Date();
    var month = String(now.getMonth() + 1);
    var day = String(now.getDate());
    if (month.length < 2) month = "0" + month;
    if (day.length < 2) day = "0" + day;
    return now.getFullYear() + "-" + month + "-" + day;
  }

  function photoTakenDays() {
    var days = [];
    state.photoOrder.forEach(function (id) {
      var item = photoItem(id);
      if (item && item.taken_on) days.push(item.taken_on);
    });
    return days;
  }

  // Undoing puts the date back to the draft default — the very value the
  // server reads as "never touched" — so a reload would let the photos have
  // another go at a date the writer just rejected. The rejection is
  // remembered per draft for the rest of the browser session.
  function dateClaimKey() {
    return state.tripId ? "went-hiking-date-claimed-" + state.tripId : null;
  }

  function rememberDateClaimed() {
    try {
      var key = dateClaimKey();
      if (key) window.sessionStorage.setItem(key, "1");
    } catch (error) {
      /* storage can be denied; the in-page flag still holds until reload */
    }
  }

  function dateClaimedEarlier() {
    try {
      var key = dateClaimKey();
      return !!key && window.sessionStorage.getItem(key) === "1";
    } catch (error) {
      return false;
    }
  }

  function dateNote() {
    var auto = state.autoDate;
    if (auto.note) return auto.note;

    var note = element("p", "compose-photo-date-note", {"data-compose-date-note": "", role: "status", hidden: "hidden"});
    var text = element("span");
    var undo = element("button", "compose-photo-date-undo", {"data-compose-date-undo": ""});
    undo.textContent = "Undo";
    note.appendChild(text);
    note.appendChild(undo);

    undo.addEventListener("click", function () {
      undoPhotoDates();
    });

    var byline = state.root.querySelector("[data-compose-byline]");
    if (byline && byline.parentNode) byline.parentNode.insertBefore(note, byline.nextSibling);

    auto.note = note;
    return note;
  }

  function showDateNote(nightsToo) {
    var note = dateNote();
    note.firstChild.textContent = nightsToo
      ? "The days of your hike were set by your photos."
      : "The day of your hike was set by your photos.";
    note.hidden = false;
  }

  function hideDateNote() {
    if (state.autoDate.note) state.autoDate.note.hidden = true;
  }

  // Runs whenever the set of photos changes. The date is only ever written
  // over a value the writer has not claimed, and the first automatic write
  // remembers what it replaced so the undo can put it back.
  function applyPhotoDates() {
    var auto = state.autoDate;
    if (!auto.active || state.mode === "published") return;

    var dateField = fieldNode("hiked_at");
    var nightsField = fieldNode("nights");
    if (!dateField) return;

    var computed = tripDatesFromPhotos(photoTakenDays(), todayIso());

    if (!computed) {
      // The dated photos are gone again; hand back what the writer had, but
      // keep listening in case the next upload can speak.
      if (auto.applied) undoPhotoDates({keepWatching: true});
      return;
    }

    var settingNights = auto.nightsActive && !!nightsField && (computed.nights > 0 || auto.appliedNights);
    var nightsValue = computed.nights > 0 ? String(computed.nights) : "";
    var dateChanged = dateField.value !== computed.hikedAt;
    var nightsChanged = settingNights && nightsField.value !== nightsValue;
    if (!dateChanged && !nightsChanged) return;

    if (!auto.applied) {
      auto.previous = {hikedAt: dateField.value, nights: nightsField ? nightsField.value : ""};
    }
    auto.applied = true;

    if (dateChanged) {
      dateField.value = computed.hikedAt;
      clearFieldError("hiked_at");
    }

    if (nightsChanged) {
      nightsField.value = nightsValue;
      auto.appliedNights = true;
      clearFieldError("nights");
    }

    refreshChips();
    // The note describes what the photos hold right now: nights may have been
    // written earlier and rolled back to blank by a deletion since.
    showDateNote(auto.appliedNights && nightsField.value !== "");
    markDirty();
    scheduleAutosave();
  }

  function undoPhotoDates(options) {
    var auto = state.autoDate;
    var keepWatching = options && options.keepWatching;

    if (auto.applied && auto.previous) {
      var dateField = fieldNode("hiked_at");
      var nightsField = fieldNode("nights");
      if (dateField) dateField.value = auto.previous.hikedAt;
      if (nightsField && auto.appliedNights) nightsField.value = auto.previous.nights;
      refreshChips();
      markDirty();
      scheduleAutosave();
    }

    auto.applied = false;
    auto.appliedNights = false;
    auto.previous = null;

    if (!keepWatching) {
      auto.active = false;
      auto.nightsActive = false;
      rememberDateClaimed();
    }

    hideDateNote();
  }

  function bindAutoDate() {
    state.autoDate.active = state.root.getAttribute("data-date-untouched") === "true" &&
      state.mode !== "published" &&
      !dateClaimedEarlier();

    var dateField = fieldNode("hiked_at");
    var nightsField = fieldNode("nights");

    // A programmatic value never fires these, so anything heard here is the
    // writer taking the chip over.
    var claimDate = function () {
      state.autoDate.active = false;
      rememberDateClaimed();
      hideDateNote();
    };

    if (dateField) {
      dateField.addEventListener("input", claimDate);
      dateField.addEventListener("change", claimDate);
    }

    if (nightsField) {
      nightsField.addEventListener("input", function () {
        state.autoDate.nightsActive = false;
      });
    }
  }

  /* ------------------------------------------------------------------------
     Status, persistence, publishing.
     ------------------------------------------------------------------------ */

  function setStatus(kind, text) {
    if (!state.statusNode) return;

    var label = text;
    if (!label) {
      if (kind === "saving") label = "Saving…";
      else if (kind === "saved") label = "Saved ✓";
      else if (kind === "dirty") label = "Unsaved changes";
      else if (kind === "published") label = "Published";
      else if (kind === "publishing") label = "Publishing…";
      else label = "Draft";
    }

    state.statusNode.textContent = label;
    state.statusNode.setAttribute("data-state", kind);
  }

  function markDirty() {
    state.dirty = true;
    if (state.mode === "published") setStatus("dirty");
  }

  function collectFields() {
    var fields = {
      name: state.title.value.trim(),
      hiked_at: fieldValue("hiked_at"),
      nights: fieldValue("nights"),
      mileage: fieldValue("mileage"),
      elevation: fieldValue("elevation"),
      source_url: fieldValue("source_url"),
      lat: fieldValue("lat"),
      lng: fieldValue("lng"),
      report_markdown: syncSource()
    };

    // The condition flags come off the DOM rather than a list here, so the
    // vocabulary lives in one place (HikeFlags) and the markup carries it.
    // Every group is sent, cleared ones as "", which is what clears the column.
    var flags = state.root.querySelectorAll("[data-compose-conditions] input[type=radio]");
    for (var index = 0; index < flags.length; index += 1) {
      if (!(flags[index].name in fields)) fields[flags[index].name] = "";
      if (flags[index].checked) fields[flags[index].name] = flags[index].value;
    }

    return fields;
  }

  function applyDraft(payload) {
    state.tripId = payload.trip_id;
    state.mode = "draft";
    state.urls.save = payload.save_url;
    state.urls.upload = payload.upload_url;
    state.urls.edit = payload.edit_url;
    state.urls.autosave = payload.save_url + "/autosave";
    state.urls.photo = payload.save_url + "/photos";
    state.form.setAttribute("action", payload.save_url);

    var deleteForm = document.getElementById("compose-delete");
    if (deleteForm) {
      deleteForm.setAttribute("action", payload.save_url + "/delete");
      deleteForm.hidden = false;
    }

    var menu = state.root.querySelector("[data-compose-menu]");
    if (menu) menu.hidden = false;

    // Reloading mid-compose has to land back on this draft rather than opening
    // a second empty one.
    try {
      window.history.replaceState({}, "", payload.edit_url);
    } catch (error) {
      /* history is a nicety, not a requirement */
    }
  }

  // Nothing is written to the database until the writer means it: the draft row
  // appears on the first real keystroke, photo, or chip.
  function ensureTrip() {
    if (state.tripId) return Promise.resolve();
    if (state.draftPromise) return state.draftPromise;

    state.draftPromise = postJson(state.urls.draft, {}).then(function (payload) {
      applyDraft(payload);
      return payload;
    });

    return state.draftPromise;
  }

  function fieldErrorNode(key) {
    return state.form.querySelector('[data-compose-error="' + key + '"]');
  }

  function showFieldError(key, message) {
    var node = fieldErrorNode(key);

    if (!node) {
      node = element("span", "compose-error", {"data-compose-error": key});
      var anchor = key === "name" ? state.root.querySelector(".compose-title-field") : state.root.querySelector("[data-compose-byline]");
      if (anchor && anchor.parentNode) anchor.parentNode.insertBefore(node, anchor.nextSibling);
    }

    node.textContent = message;
    node.hidden = false;
  }

  function clearFieldError(key) {
    var node = fieldErrorNode(key);
    if (node) node.hidden = true;
  }

  function clearFieldErrors() {
    var nodes = state.form.querySelectorAll("[data-compose-error]");
    for (var index = 0; index < nodes.length; index += 1) nodes[index].hidden = true;
  }

  function scheduleAutosave() {
    markDirty();
    if (state.mode === "published") return;

    window.clearTimeout(state.autosaveTimer);
    state.autosaveTimer = window.setTimeout(runAutosave, 1500);
  }

  function runAutosave() {
    if (state.mode === "published" || state.submitting) return;

    setStatus("saving");

    ensureTrip()
      .then(function () {
        return postJson(state.urls.autosave, collectFields());
      })
      .then(function () {
        state.dirty = false;
        clearFieldErrors();
        setStatus("saved");
      })
      .catch(function (error) {
        if (error && error.errors && typeof error.errors === "object") {
          Object.keys(error.errors).forEach(function (key) {
            showFieldError(key, error.errors[key]);
          });
          setStatus("saved", "Saved, with notes");
        } else {
          setStatus("dirty", "Not saved");
        }
      });
  }

  function flushAutosave() {
    if (state.mode === "published" || !state.dirty || !state.tripId || state.submitting) return;

    try {
      var body = new FormData();
      var fields = collectFields();
      Object.keys(fields).forEach(function (key) {
        body.append(key, fields[key]);
      });
      body.append("_csrf", csrfToken());
      navigator.sendBeacon(state.urls.autosave, body);
    } catch (error) {
      /* a best-effort flush; the debounce already covers the normal case */
    }
  }

  function validateForPublish() {
    var problems = [];
    clearFieldErrors();

    if (!state.title.value.trim()) problems.push(["name", "This hike needs a name before it goes live."]);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(fieldValue("hiked_at"))) problems.push(["hiked_at", "Pick the date you hiked."]);

    [["nights", /^\d*$/, "Nights has to be a whole number."],
      ["mileage", /^\d*\.?\d*$/, "Miles has to be a number."],
      ["elevation", /^\d*$/, "Feet gained has to be a whole number."]].forEach(function (rule) {
      var value = fieldValue(rule[0]);
      if (value && !rule[1].test(value)) problems.push([rule[0], rule[2]]);
    });

    return problems;
  }

  function bindSubmit() {
    state.form.addEventListener("submit", function (event) {
      syncSource();

      var problems = validateForPublish();

      if (problems.length) {
        event.preventDefault();
        problems.forEach(function (problem) {
          showFieldError(problem[0], problem[1]);
        });
        var first = problems[0][0];
        var node = first === "name" ? state.title : fieldNode(first);
        if (node && node.focus) node.focus();
        return;
      }

      state.submitting = true;
      window.clearTimeout(state.autosaveTimer);
      setStatus(state.mode === "published" ? "saving" : "publishing");
    });
  }

  /* ------------------------------------------------------------------------
     Wiring.
     ------------------------------------------------------------------------ */

  function autoGrow(node) {
    node.style.height = "auto";
    node.style.height = node.scrollHeight + "px";
  }

  function bindTitle() {
    autoGrow(state.title);

    state.title.addEventListener("input", function () {
      autoGrow(state.title);
      clearFieldError("name");
      scheduleAutosave();
    });

    state.title.addEventListener("keydown", function (event) {
      if (event.key !== "Enter") return;
      event.preventDefault();
      var first = state.canvas.firstElementChild;
      focusBlock(first, "end");
    });
  }

  function bindChips() {
    var inputs = state.form.querySelectorAll(".compose-chip-input");

    for (var index = 0; index < inputs.length; index += 1) {
      inputs[index].addEventListener("input", function (event) {
        autoSizeChip(event.target);
        clearFieldError(event.target.getAttribute("data-compose-field"));
        scheduleAutosave();
      });

      inputs[index].addEventListener("change", function () {
        scheduleAutosave();
      });
    }

    refreshChips();
  }

  function bindConditions() {
    var block = state.root.querySelector("[data-compose-conditions]");
    if (!block) return;

    var radios = block.querySelectorAll('input[type="radio"]');

    function remember() {
      for (var index = 0; index < radios.length; index += 1) {
        radios[index].__wasChecked = radios[index].checked;
      }
    }

    for (var index = 0; index < radios.length; index += 1) {
      // Tapping the word that is already set takes it back; radios cannot say
      // that on their own. Click fires on the taps change misses (a re-tap
      // leaves the value alone), change fires on the keyboard moves click
      // misses; both funnel into the same debounced autosave.
      radios[index].addEventListener("click", function () {
        if (this.__wasChecked) this.checked = false;
        remember();
        scheduleAutosave();
      });

      radios[index].addEventListener("change", function () {
        remember();
        scheduleAutosave();
      });
    }

    remember();
  }

  function bindCanvas() {
    state.canvas.addEventListener("keydown", handleCanvasKeydown);
    state.canvas.addEventListener("input", handleCanvasInput);
    state.canvas.addEventListener("paste", handleCanvasPaste);

    state.canvas.addEventListener("dragstart", function (event) {
      var figure = event.target.closest('[data-block="figure"]');
      if (!figure) return;
      state.dragBlock = figure;
      event.dataTransfer.effectAllowed = "move";
      event.dataTransfer.setData("text/plain", "");
      figure.classList.add("is-dragging");
    });

    state.canvas.addEventListener("dragend", function () {
      var dragging = state.canvas.querySelector(".is-dragging");
      if (dragging) dragging.classList.remove("is-dragging");
      state.dragBlock = null;
      hideDropMarker();
    });

    state.canvas.addEventListener("click", function (event) {
      var toggle = event.target.closest("[data-figure-toggle]");
      if (toggle) {
        var menu = toggle.parentNode.querySelector("[data-figure-menu]");
        var openNow = menu.hidden;
        closeFigureMenus();
        menu.hidden = !openNow;
        toggle.setAttribute("aria-expanded", openNow ? "true" : "false");
        return;
      }

      var action = event.target.closest("[data-figure-action]");
      if (action) {
        runFigureAction(action.closest('[data-block="figure"]'), action.getAttribute("data-figure-action"));
        return;
      }

      if (event.target === state.canvas) {
        var last = state.canvas.lastElementChild;
        if (isTextBlock(last)) focusBlock(last, "end");
        else focusBlock(insertBlockAt(createTextBlock({type: "paragraph", nodes: []}), null), "end");
      }
    });

  }

  // Hiding the panel is only half of closing it: the toggle that opened it is
  // still telling a screen reader it is expanded, and on the keyboard path the
  // focus has to go back to that toggle rather than fall to the body. Returns
  // whether anything was actually open, so Escape can tell which panel it just
  // dismissed and hand the focus to that one.
  function closeFigureMenus(options) {
    var menus = state.canvas.querySelectorAll("[data-figure-menu]");
    var restoreFocus = options && options.restoreFocus;
    var wasOpen = false;

    for (var index = 0; index < menus.length; index += 1) {
      var menu = menus[index];
      if (menu.hidden) continue;

      var toggle = menu.parentNode.querySelector("[data-figure-toggle]");
      menu.hidden = true;
      if (toggle) toggle.setAttribute("aria-expanded", "false");
      if (toggle && restoreFocus && !wasOpen) toggle.focus();
      wasOpen = true;
    }

    return wasOpen;
  }

  function runFigureAction(figure, action) {
    if (!figure) return;
    closeFigureMenus();

    var photoId = figure.getAttribute("data-photo-id");

    if (action === "up") {
      var previous = figure.previousElementSibling;
      if (previous) {
        state.canvas.insertBefore(figure, previous);
        markCanvasDirty();
        scheduleAutosave();
      }
      figure.focus();
      return;
    }

    if (action === "down") {
      var next = figure.nextElementSibling;
      if (next) {
        state.canvas.insertBefore(next, figure);
        markCanvasDirty();
        scheduleAutosave();
      }
      figure.focus();
      return;
    }

    if (action === "tray") {
      figure.remove();
      markCanvasDirty();
      refreshPlaceholders();
      syncTray();
      scheduleAutosave();
      return;
    }

    if (action === "delete") {
      deletePhoto(photoId);
    }
  }

  function bindTray() {
    state.trayGrid.addEventListener("click", function (event) {
      var button = event.target.closest("[data-tray-action]");
      if (!button) return;

      var card = button.closest("[data-photo-id]");
      var photoId = card.getAttribute("data-photo-id");

      if (button.getAttribute("data-tray-action") === "insert") {
        var reference = null;
        var focused = activeTextBlock();
        if (focused) reference = focused.nextElementSibling;
        insertFigure(photoId, reference);
        return;
      }

      deletePhoto(photoId);
    });

    state.trayGrid.addEventListener("input", function (event) {
      var caption = event.target.closest("[data-compose-caption]");
      if (caption) saveCaption(caption);
    });

    state.trayGrid.addEventListener("dragstart", function (event) {
      var card = event.target.closest("[data-photo-id]");
      if (!card) return;
      event.dataTransfer.effectAllowed = "move";
      event.dataTransfer.setData("application/x-wenthiking-photo", card.getAttribute("data-photo-id"));
      card.classList.add("is-dragging");
    });

    state.trayGrid.addEventListener("dragend", function (event) {
      var card = event.target.closest("[data-photo-id]");
      if (card) card.classList.remove("is-dragging");
    });

    var drop = state.root.querySelector("[data-compose-tray-drop]");
    if (drop) {
      drop.addEventListener("click", function () {
        state.fileTarget = {kind: "tray"};
        state.fileInput.click();
      });
    }

    state.fileInput.addEventListener("change", function () {
      queueUploads(state.fileInput.files, state.fileTarget || {kind: "tray"});
      state.fileInput.value = "";
      state.fileTarget = null;
    });
  }

  function bindMenu() {
    var menu = state.root.querySelector("[data-compose-menu]");
    if (!menu) return;

    var toggle = menu.querySelector("[data-compose-menu-toggle]");
    var panel = menu.querySelector("[data-compose-menu-panel]");

    var setOpen = function (open) {
      panel.hidden = !open;
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
    };

    // Same shape as the site nav's menu: the aria state travels with the panel,
    // and a keyboard dismissal puts the focus back on the toggle. Clicking
    // elsewhere is already a choice about where focus goes, so that path leaves
    // it alone.
    var close = function (options) {
      if (panel.hidden) return false;
      setOpen(false);
      if (options && options.restoreFocus) toggle.focus();
      return true;
    };

    toggle.addEventListener("click", function () {
      setOpen(panel.hidden);
    });

    document.addEventListener("click", function (event) {
      if (menu.contains(event.target)) return;
      close();
    });

    state.closeMenu = close;

    var remove = menu.querySelector("[data-compose-delete]");
    if (remove) {
      remove.addEventListener("click", function (event) {
        if (!window.confirm(remove.getAttribute("data-confirm"))) {
          event.preventDefault();
          return;
        }
        state.submitting = true;
      });
    }
  }

  function bindGlobalKeys() {
    // Escape closes every compose panel, but only one of them can have been the
    // one the keyboard came from, so the first that was actually open takes the
    // focus back and the rest simply close. Leaving focus on the body — which is
    // what hiding the panels alone did — strands a keyboard user at the top of
    // the document with no way back to the control they just used.
    var dismissPanels = function () {
      var closers = [closeFigureMenus, state.closeLocation, state.closeMenu];
      var claimed = false;

      for (var index = 0; index < closers.length; index += 1) {
        if (!closers[index]) continue;
        if (closers[index]({restoreFocus: !claimed})) claimed = true;
      }

      return claimed;
    };

    document.addEventListener("keydown", function (event) {
      if (event.key !== "Escape") return;

      if (dismissPanels()) event.preventDefault();
      hideToolbar();
    });

    // A stray Enter in a chip should not fire off a half-written hike.
    state.form.addEventListener("keydown", function (event) {
      if (event.key !== "Enter") return;
      var target = event.target;
      if (target.tagName === "INPUT" && target.type !== "submit") {
        event.preventDefault();
        target.blur();
      }
    });

    document.addEventListener("selectionchange", function () {
      if (!state.toolbar) return;
      window.setTimeout(positionToolbar, 0);
    });

    window.addEventListener("beforeunload", flushAutosave);
  }

  function loadPhotos() {
    var script = document.querySelector("[data-compose-photos]");
    if (!script) return;

    var items = [];
    try {
      items = JSON.parse(script.textContent || "[]");
    } catch (error) {
      items = [];
    }

    items.forEach(registerPhoto);
  }

  function init() {
    var root = document.querySelector("[data-compose]");
    if (!root) return;

    state.root = root;
    state.form = root.querySelector("[data-compose-form]");
    state.canvas = root.querySelector("[data-compose-canvas]");
    state.source = root.querySelector("[data-compose-source]");
    state.title = root.querySelector("[data-compose-title]");
    state.tray = root.querySelector("[data-compose-tray]");
    state.trayGrid = root.querySelector("[data-compose-tray-grid]");
    state.fileInput = root.querySelector("[data-compose-file]");
    state.statusNode = root.querySelector("[data-compose-state]");
    state.mode = root.getAttribute("data-mode");
    state.tripId = root.getAttribute("data-trip-id") || null;
    state.urls = {
      draft: root.getAttribute("data-draft-url"),
      save: root.getAttribute("data-save-url"),
      autosave: root.getAttribute("data-autosave-url"),
      upload: root.getAttribute("data-upload-url"),
      photo: root.getAttribute("data-photo-url"),
      edit: root.getAttribute("data-edit-url")
    };
    state.maxUploadBytes = Number(root.getAttribute("data-max-upload-bytes")) || 0;

    if (!state.form || !state.canvas || !state.source) return;

    // execCommand is the only no-build way to get reliable inline formatting;
    // tags rather than inline styles keep the markdown mapping honest.
    try {
      document.execCommand("styleWithCSS", false, false);
    } catch (error) {
      /* not supported everywhere, and not fatal */
    }

    loadPhotos();
    state.canvas.hidden = false;
    state.source.hidden = true;
    root.classList.add("is-live");

    renderCanvas();
    buildToolbar();
    bindTitle();
    bindChips();
    bindAutoDate();
    bindConditions();
    bindCanvas();
    bindTray();
    bindMenu();
    bindLocationChipSafely();
    bindDragAndDrop();
    bindSubmit();
    bindGlobalKeys();

    // Photos that arrived while this page was closed — the phone upload link —
    // get their say as soon as the editor opens.
    applyPhotoDates();

    setStatus(state.mode === "published" ? "published" : "draft");

    if (state.mode !== "published" && !state.title.value.trim()) state.title.focus();
  }

  function bindLocationChipSafely() {
    try {
      buildLocationChip();
    } catch (error) {
      /* the map is an enhancement; the manual coordinate inputs still work */
    }
  }

  api.__dom = {nodesToHtml: nodesToHtml, nodesFromDom: nodesFromDom};
  api.__test = {
    state: state,
    renderCanvas: function () {
      renderCanvas();
    },
    serializeCanvas: serializeCanvas,
    // Load markdown into the real canvas and read it back out through the DOM.
    roundTripThroughDom: function (source) {
      var previous = state.source.value;
      state.source.value = source;
      renderCanvas();
      var out = serializeCanvas();
      state.source.value = previous;
      renderCanvas();
      return out;
    }
  };

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
