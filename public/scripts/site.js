(() => {
  const tileOptions = {
    attribution: "Tiles courtesy of the U.S. Geological Survey",
    maxZoom: 16
  };

  const tripIcon = () => L.icon({
    iconUrl: "/images/marker.png",
    shadowUrl: "/images/marker-shadow.png",
    iconSize: [16, 37],
    iconAnchor: [8, 37],
    popupAnchor: [0, -34],
    shadowSize: [27, 18],
    shadowAnchor: [3, 18]
  });

  const escapeHtml = (value) => String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");

  const afterLayout = (callback) => {
    if (typeof window.requestAnimationFrame !== "function") {
      window.setTimeout(callback, 0);
      return;
    }

    window.requestAnimationFrame(() => {
      window.requestAnimationFrame(callback);
    });
  };

  const mapResizeIcon = (expanded) => {
    const paths = expanded
      ? '<path d="M4 14h6v6"></path><path d="M10 14l-7 7"></path><path d="M20 10h-6V4"></path><path d="M14 10l7-7"></path>'
      : '<path d="M15 3h6v6"></path><path d="M21 3l-7 7"></path><path d="M9 21H3v-6"></path><path d="M3 21l7-7"></path>';

    return [
      '<svg class="map-size-icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">',
      paths,
      "</svg>"
    ].join("");
  };

  const refreshMapSize = (map) => {
    let ticks = 0;

    const refresh = () => {
      map.invalidateSize({pan: false});
      ticks += 1;
      if (ticks < 4) window.setTimeout(refresh, 55);
    };

    afterLayout(refresh);
  };

  // Leaflet is only loaded on pages that render a map, so every entry point
  // has to tolerate its absence.
  const leafletReady = () => typeof L !== "undefined";

  const fitMapToPoints = (map, points, options = {}) => {
    if (points.length === 0) {
      map.setView([45.4, -121.7], 7);
      return;
    }

    if (points.length === 1) {
      map.setView(points[0], options.singlePointZoom || 10);
      return;
    }

    // A higher zoom ceiling so the region fills the band instead of centring
    // on open ocean, with enough top padding to clear a marker's 37px pin
    // (it is anchored at the tip, so it hangs above its own coordinate).
    map.fitBounds(points, {
      paddingTopLeft: options.paddingTopLeft || [30, 48],
      paddingBottomRight: options.paddingBottomRight || [30, 22],
      maxZoom: options.maxZoom || 12
    });
  };

  const addMapResizeControl = (map, container) => {
    const ResizeControl = L.Control.extend({
      options: {
        position: "bottomright"
      },

      onAdd: () => {
        const control = L.DomUtil.create("div", "leaflet-bar map-size-control");
        const button = L.DomUtil.create("button", "map-size-button", control);

        button.type = "button";

        const setExpanded = (expanded) => {
          container.classList.toggle("map-expanded", expanded);
          button.innerHTML = mapResizeIcon(expanded);
          button.setAttribute("aria-label", expanded ? "Collapse map" : "Expand map");
          button.setAttribute("aria-pressed", expanded ? "true" : "false");
          button.title = expanded ? "Collapse map" : "Expand map";
          refreshMapSize(map);
        };

        setExpanded(false);

        L.DomEvent.disableClickPropagation(control);
        L.DomEvent.disableScrollPropagation(control);
        L.DomEvent.on(button, "click", (event) => {
          L.DomEvent.stop(event);
          setExpanded(!container.classList.contains("map-expanded"));
        });

        return control;
      }
    });

    new ResizeControl().addTo(map);
  };

  const buildMap = (element) => {
    const lat = Number(element.dataset.lat);
    const lng = Number(element.dataset.lng);
    const map = L.map(element, {scrollWheelZoom: false}).setView([lat, lng], 11);
    L.tileLayer(element.dataset.tileUrl, tileOptions).addTo(map);
    L.marker([lat, lng], {icon: tripIcon()}).addTo(map).bindPopup(escapeHtml(element.dataset.title || "Trip"));

    if (element.hasAttribute("data-map-expandable")) {
      addMapResizeControl(map, element);
    }
  };

  const buildCollectionMap = (element) => {
    const points = JSON.parse(element.dataset.points || "[]");
    const map = L.map(element, {scrollWheelZoom: false});
    L.tileLayer(element.dataset.tileUrl, tileOptions).addTo(map);
    const bounds = points.map((point) => [point.lat, point.lng]);

    points.forEach((point) => {
      const marker = L.marker([point.lat, point.lng], {icon: tripIcon()}).addTo(map);
      marker.bindPopup(`<a href="${escapeHtml(point.url)}">${escapeHtml(point.title)}</a>`);
    });

    fitMapToPoints(map, bounds);
    afterLayout(() => {
      map.invalidateSize({pan: false});
      fitMapToPoints(map, bounds);
    });

    if (element.hasAttribute("data-map-expandable")) {
      addMapResizeControl(map, element);
    }
  };

  const buildStaticMap = (element) => {
    const lat = Number(element.dataset.lat);
    const lng = Number(element.dataset.lng);
    const map = L.map(element, {
      attributionControl: false,
      boxZoom: false,
      doubleClickZoom: false,
      dragging: false,
      keyboard: false,
      scrollWheelZoom: false,
      tap: false,
      touchZoom: false,
      zoomControl: false
    }).setView([lat, lng], 9);

    L.tileLayer(element.dataset.tileUrl, {...tileOptions, attribution: ""}).addTo(map);
    L.marker([lat, lng], {icon: tripIcon(), interactive: false, keyboard: false}).addTo(map);
    element.removeAttribute("tabindex");
    refreshMapSize(map);
  };

  // Shared by every focus trap on the site. querySelectorAll order is DOM order,
  // which is the tab order here because nothing sets a positive tabindex; the
  // filters drop anything the browser would skip (hidden, disabled, roving -1).
  const FOCUSABLE_SELECTOR = "a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]";

  const focusableWithin = (root) => Array.from(root.querySelectorAll(FOCUSABLE_SELECTOR))
    .filter((element) => element.tabIndex >= 0 && element.offsetParent !== null);

  // Keeps Tab inside `root`. Anything focused outside the trap — or parked on a
  // roving tabindex="-1" element inside it — is pulled back to an edge.
  const containFocus = (event, root) => {
    const focusable = focusableWithin(root);
    if (focusable.length === 0) return;

    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    const index = focusable.indexOf(document.activeElement);

    if (index === -1) {
      event.preventDefault();
      (event.shiftKey ? last : first).focus();
    } else if (event.shiftKey && index === 0) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && index === focusable.length - 1) {
      event.preventDefault();
      first.focus();
    }
  };

  const groupedNumber = (value) => String(value).replace(/\B(?=(\d{3})+(?!\d))/g, ",");

  const heartTitle = (count) => `${groupedNumber(count)} ${(count === 1) ? "heart" : "hearts"}`;

  // Without JS this form posts and the server redirects back, which throws away
  // scroll position on a long index. Enhanced, the toggle lands immediately and
  // the POST goes out in the background; a failure puts the old state back.
  const buildHeartForm = (form) => {
    const button = form.querySelector("button[type='submit']");
    const count = form.querySelector("[data-heart-count]");
    if (!button || !count) return;

    let pending = false;

    const render = (hearted, total) => {
      button.classList.toggle("is-hearted", hearted);
      button.setAttribute("aria-pressed", hearted ? "true" : "false");
      button.setAttribute("aria-label", hearted ? form.dataset.heartLabelOn : form.dataset.heartLabelOff);
      button.title = heartTitle(total);
      count.textContent = groupedNumber(total);
      form.dataset.heartCountValue = String(total);
    };

    form.addEventListener("submit", (event) => {
      event.preventDefault();
      if (pending) return;

      const wasHearted = button.classList.contains("is-hearted");
      const previousTotal = Number.parseInt(form.dataset.heartCountValue, 10) || 0;
      const nextHearted = !wasHearted;
      const nextTotal = Math.max(0, previousTotal + (nextHearted ? 1 : -1));

      pending = true;
      render(nextHearted, nextTotal);

      button.classList.remove("is-hearting");
      void button.offsetWidth; // Restart the pop rather than letting it no-op.
      button.classList.toggle("is-hearting", nextHearted);

      window.fetch(form.action, {
        method: "POST",
        headers: postHeaders(),
        body: new FormData(form),
        credentials: "same-origin",
        redirect: "manual"
      })
        .then((response) => {
          // The route answers 302; with redirect: "manual" that arrives as an
          // opaque response with status 0, so only 4xx/5xx count as a failure.
          if (response.status >= 400) throw new Error(`Heart request failed: ${response.status}`);
        })
        .catch(() => render(wasHearted, previousTotal))
        .finally(() => {
          pending = false;
        });
    });
  };

  // Signed in there are five destinations and room for two, so everything but
  // Hikes and the add button folds into a disclosure. Desktop never sees it, and
  // neither does a browser without JS: the fold is gated on a class added here,
  // so the plain scrolling row stays the fallback rather than a dead button.
  const buildNavMenu = (menu) => {
    const button = menu.querySelector("[data-nav-menu-button]");
    const panel = menu.querySelector("[data-nav-menu-panel]");
    const nav = menu.closest(".site-nav");
    if (!button || !panel || !nav) return;

    nav.classList.add("site-nav-has-menu");

    const isOpen = () => button.getAttribute("aria-expanded") === "true";

    const setOpen = (open) => {
      button.setAttribute("aria-expanded", open ? "true" : "false");
      panel.hidden = !open;
      menu.classList.toggle("is-open", open);
    };

    const close = ({restoreFocus = false} = {}) => {
      if (!isOpen()) return;
      setOpen(false);
      if (restoreFocus) button.focus();
    };

    setOpen(false);

    button.addEventListener("click", () => setOpen(!isOpen()));

    menu.addEventListener("keydown", (event) => {
      if (event.key !== "Escape" || !isOpen()) return;
      event.preventDefault();
      close({restoreFocus: true});
    });

    // Tabbing or clicking past the menu dismisses it; relatedTarget is null when
    // focus leaves the document entirely, which should not close anything.
    menu.addEventListener("focusout", (event) => {
      if (event.relatedTarget && !menu.contains(event.relatedTarget)) close();
    });

    document.addEventListener("pointerdown", (event) => {
      if (!menu.contains(event.target)) close();
    });

    // The button is display:none above the mobile breakpoint, so a panel left
    // open through a rotate or resize would otherwise strand itself.
    window.addEventListener("resize", () => {
      if (button.offsetParent === null) close();
    });
  };

  const buildProfileFollowModal = (modal) => {
    const openers = document.querySelectorAll(`[data-profile-modal-open="${modal.id}"]`);
    const closers = modal.querySelectorAll("[data-profile-modal-close]");
    const panel = modal.querySelector(".profile-modal-panel");
    let previousFocus = null;

    const open = (trigger = null) => {
      previousFocus = trigger || document.activeElement;
      modal.classList.add("is-open");
      document.body.classList.add("profile-follow-modal-open");
      const emailInput = modal.querySelector("input[type='email']");
      afterLayout(() => (emailInput || panel).focus());
    };

    const close = () => {
      modal.classList.remove("is-open");
      document.body.classList.remove("profile-follow-modal-open");

      if (window.location.hash === `#${modal.id}` && window.history && window.history.replaceState) {
        window.history.replaceState(null, "", `${window.location.pathname}${window.location.search}`);
      }

      if (previousFocus && typeof previousFocus.focus === "function") {
        previousFocus.focus();
      }
    };

    openers.forEach((opener) => {
      opener.addEventListener("click", (event) => {
        event.preventDefault();
        open(opener);
      });
    });

    closers.forEach((closer) => {
      closer.addEventListener("click", (event) => {
        event.preventDefault();
        close();
      });
    });

    document.addEventListener("keydown", (event) => {
      if (!modal.classList.contains("is-open")) return;

      if (event.key === "Escape") {
        event.preventDefault();
        close();
      } else if (event.key === "Tab") {
        containFocus(event, modal);
      }
    });

    if (modal.classList.contains("is-open") || window.location.hash === `#${modal.id}`) {
      open();
    }
  };

  const buildMarkdownEditor = (element) => {
    const input = element.querySelector("[data-markdown-input]");
    const preview = element.querySelector("[data-markdown-preview]");
    const status = element.querySelector("[data-markdown-status]");
    let timeout;
    let controller;

    const render = () => {
      const body = input.value;
      const payload = new URLSearchParams({body});
      if (element.dataset.tripId) payload.set("trip_id", element.dataset.tripId);

      if (!body.trim() && !element.dataset.tripId) {
        preview.innerHTML = '<p class="empty">Start writing to preview the trip report.</p>';
        status.textContent = "Markdown";
        return;
      }

      if (controller) controller.abort();
      controller = new AbortController();
      status.textContent = "Rendering";

      fetch("/api/markdown-preview", {
        method: "POST",
        headers: postHeaders({"Content-Type": "application/x-www-form-urlencoded"}),
        body: payload,
        signal: controller.signal
      })
        .then((response) => response.ok ? response.json() : Promise.reject(new Error("preview failed")))
        .then((payload) => {
          preview.innerHTML = payload.html || '<p class="empty">Nothing to preview yet.</p>';
          status.textContent = "Preview";
        })
        .catch((error) => {
          if (error.name === "AbortError") return;
          status.textContent = "Preview unavailable";
        });
    };

    input.addEventListener("input", () => {
      window.clearTimeout(timeout);
      timeout = window.setTimeout(render, 250);
    });
  };

  const formatCoordinate = (value) => Number(value).toFixed(5).replace(/0+$/, "").replace(/\.$/, "");

  const buildTripLocationPicker = (element) => {
    const mapElement = element.querySelector("[data-location-map]");
    const latInput = element.querySelector("[data-location-lat]");
    const lngInput = element.querySelector("[data-location-lng]");
    const summary = element.querySelector("[data-location-summary]");
    const clearButton = element.querySelector("[data-location-clear]");
    if (!mapElement || !latInput || !lngInput || typeof L === "undefined") return;

    const defaultLat = Number(element.dataset.defaultLat || 45.52);
    const defaultLng = Number(element.dataset.defaultLng || -122.67);
    const defaultZoom = Number(element.dataset.defaultZoom || 6);
    const parseInputCoordinate = (input) => {
      if (!input.value.trim()) return null;
      const parsed = Number(input.value);
      return Number.isFinite(parsed) ? parsed : null;
    };
    const initialLat = parseInputCoordinate(latInput);
    const initialLng = parseInputCoordinate(lngInput);
    const hasInitialPin = initialLat !== null && initialLng !== null;
    const map = L.map(mapElement, {scrollWheelZoom: false}).setView(
      hasInitialPin ? [initialLat, initialLng] : [defaultLat, defaultLng],
      hasInitialPin ? 11 : defaultZoom
    );
    let marker = null;

    L.tileLayer(element.dataset.tileUrl, tileOptions).addTo(map);

    const updateSummary = (lat, lng) => {
      if (Number.isFinite(lat) && Number.isFinite(lng)) {
        summary.textContent = `Pin set at ${formatCoordinate(lat)}, ${formatCoordinate(lng)}.`;
        clearButton.hidden = false;
      } else if (latInput.value || lngInput.value) {
        summary.textContent = "Set both latitude and longitude, or clear the location.";
        clearButton.hidden = false;
      } else {
        summary.textContent = "Click the map to drop a pin.";
        clearButton.hidden = true;
      }
    };

    const setPin = (lat, lng, options = {}) => {
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
        updateSummary(lat, lng);
        return;
      }

      const point = [lat, lng];
      if (!marker) {
        marker = L.marker(point, {icon: tripIcon(), draggable: true}).addTo(map);
        marker.on("dragend", () => {
          const position = marker.getLatLng();
          setPin(position.lat, position.lng);
        });
      } else {
        marker.setLatLng(point);
      }

      latInput.value = formatCoordinate(lat);
      lngInput.value = formatCoordinate(lng);
      updateSummary(lat, lng);
      if (options.pan) map.panTo(point);
    };

    const clearPin = () => {
      if (marker) {
        marker.remove();
        marker = null;
      }
      latInput.value = "";
      lngInput.value = "";
      updateSummary();
    };

    map.on("click", (event) => setPin(event.latlng.lat, event.latlng.lng));
    clearButton.addEventListener("click", clearPin);

    const syncManualCoordinates = () => {
      if (!latInput.value && !lngInput.value) {
        clearPin();
        return;
      }

      const lat = parseInputCoordinate(latInput);
      const lng = parseInputCoordinate(lngInput);
      if (lat !== null && lng !== null) {
        setPin(lat, lng, {pan: true});
      } else {
        updateSummary(lat, lng);
      }
    };

    latInput.addEventListener("input", syncManualCoordinates);
    lngInput.addEventListener("input", syncManualCoordinates);

    if (hasInitialPin) setPin(initialLat, initialLng);
    refreshMapSize(map);
  };

  const formatFileSize = (bytes) => {
    if (!Number.isFinite(bytes)) return "";
    if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  };

  const csrfToken = () => {
    const meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.getAttribute("content") : "";
  };

  // Same-origin POST headers. The direct upload XHR deliberately skips these:
  // it may target S3, and its signed ticket is its own authorization.
  const postHeaders = (extra) => Object.assign({"X-CSRF-Token": csrfToken()}, extra || {});

  const jsonPayload = (response) => response.text().then((text) => {
    try {
      return text ? JSON.parse(text) : {};
    } catch (_error) {
      return {};
    }
  });

  const uploadWithProgress = (upload, file, progressCallback) => new Promise((resolve, reject) => {
    const body = new FormData();
    Object.entries(upload.fields || {}).forEach(([key, value]) => body.append(key, value));
    body.append("file", file);

    const xhr = new XMLHttpRequest();
    xhr.open("POST", upload.url);
    xhr.upload.addEventListener("progress", (event) => {
      if (event.lengthComputable) progressCallback(event.loaded / event.total);
    });
    xhr.addEventListener("load", () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        resolve();
      } else {
        reject(new Error("S3 upload failed"));
      }
    });
    xhr.addEventListener("error", () => reject(new Error("S3 upload failed")));
    xhr.send(body);
  });

  const buildPhotoUploadForm = (form) => {
    const input = form.querySelector('input[type="file"][name="image"]');
    const caption = form.querySelector("[name='caption']");
    const preview = form.querySelector("[data-photo-upload-preview]");
    const previewImage = form.querySelector("[data-photo-upload-preview-image]");
    const previewName = form.querySelector("[data-photo-upload-preview-name]");
    const previewSize = form.querySelector("[data-photo-upload-preview-size]");
    const progress = form.querySelector("[data-photo-upload-progress]");
    const progressBar = form.querySelector("[data-photo-upload-progress-bar]");
    const status = form.querySelector("[data-photo-upload-status]");
    const submit = form.querySelector("[data-photo-upload-submit]");
    const errors = document.querySelector("[data-photo-upload-errors]");
    let previewUrl = null;

    if (!input) return;

    const showErrors = (messages) => {
      if (!errors) return;
      const list = (messages.length ? messages : ["Photo upload failed. Please try again."])
        .map((message) => `<li>${escapeHtml(message)}</li>`)
        .join("");
      errors.innerHTML = `<p>A couple things need fixing before these can hit the gallery:</p><ul>${list}</ul>`;
      errors.hidden = false;
    };

    const setProgress = (message, amount = null) => {
      if (!progress || !progressBar || !status) return;
      progress.hidden = false;
      status.textContent = message;
      if (amount === null) {
        progressBar.removeAttribute("style");
      } else {
        progressBar.style.width = `${Math.max(2, Math.round(amount * 100))}%`;
      }
    };

    input.addEventListener("change", () => {
      const file = input.files && input.files[0];
      if (previewUrl) URL.revokeObjectURL(previewUrl);
      previewUrl = null;

      if (!file || !preview || !previewImage || !previewName || !previewSize) {
        if (preview) preview.hidden = true;
        return;
      }

      previewName.textContent = file.name;
      previewSize.textContent = formatFileSize(file.size);
      if (file.type && file.type.startsWith("image/")) {
        previewUrl = URL.createObjectURL(file);
        previewImage.src = previewUrl;
      } else {
        previewImage.removeAttribute("src");
      }
      preview.hidden = false;
    });

    if (!form.dataset.directUploadUrl) return;

    form.addEventListener("submit", (event) => {
      if (!form.checkValidity()) return;

      const file = input.files && input.files[0];
      if (!file) return;

      event.preventDefault();
      if (errors) errors.hidden = true;
      if (submit) submit.disabled = true;
      setProgress("Preparing direct upload", 0.02);

      const payload = new URLSearchParams({
        filename: file.name,
        content_type: file.type || "application/octet-stream",
        file_size: String(file.size),
        caption: caption ? caption.value : ""
      });

      fetch(form.dataset.directUploadUrl, {
        method: "POST",
        headers: postHeaders({"Content-Type": "application/x-www-form-urlencoded"}),
        body: payload
      })
        .then((response) => jsonPayload(response).then((body) => {
          if (!response.ok) throw body;
          return body;
        }))
        .then((body) => {
          setProgress("Uploading to media storage", 0.05);
          return uploadWithProgress(body.upload, file, (amount) => setProgress("Uploading to media storage", amount))
            .then(() => body);
        })
        .then((body) => {
          setProgress("Finishing photo", 1);
          return fetch(body.finalize_url, {method: "POST", headers: postHeaders()})
            .then((response) => jsonPayload(response).then((finalizeBody) => {
              if (!response.ok) throw finalizeBody;
              return {...body, ...finalizeBody};
            }));
        })
        .then((body) => {
          window.location.href = body.redirect_url || form.action;
        })
        .catch((error) => {
          const messages = Array.isArray(error && error.errors) ? error.errors : [error && error.message].filter(Boolean);
          showErrors(messages);
          setProgress("Upload stopped", 0);
          if (submit) submit.disabled = false;
        });
    });
  };

  const insertAtCursor = (input, text) => {
    const start = input.selectionStart || 0;
    const end = input.selectionEnd || start;
    const prefix = input.value.slice(0, start);
    const suffix = input.value.slice(end);
    const before = prefix && !prefix.endsWith("\n") ? "\n\n" : "";
    const after = suffix && !suffix.startsWith("\n") ? "\n\n" : "";
    const inserted = `${before}${text}${after}`;

    input.value = `${prefix}${inserted}${suffix}`;
    input.focus();
    input.setSelectionRange(start + inserted.length, start + inserted.length);
    input.dispatchEvent(new Event("input", {bubbles: true}));
  };

  const buildTripPhotoWorkbench = (workbench) => {
    const form = workbench.closest("[data-trip-editor]");
    const list = workbench.querySelector("[data-trip-photo-list]");
    const fileInput = workbench.querySelector("[data-trip-photo-input]");
    const dropzone = workbench.querySelector("[data-trip-photo-dropzone]");
    const markdownEditor = form && form.querySelector("[data-markdown-editor]");
    const markdownInput = form && form.querySelector("[data-markdown-input]");
    const count = workbench.querySelector(".trip-photo-workbench-heading .meta");
    const directUploadAvailable = workbench.dataset.directUploadAvailable === "true";
    const captionTimers = new WeakMap();
    const queue = [];
    let activeUploads = 0;
    let draftPromise = null;
    let uploadUrl = workbench.dataset.uploadUrl || "";

    if (!form || !list || !markdownInput) return;

    const refreshPreview = () => {
      markdownInput.dispatchEvent(new Event("input", {bubbles: true}));
    };

    const updateCount = () => {
      if (!count) return;
      const total = list.querySelectorAll("[data-trip-photo-card]").length;
      count.textContent = `${total.toLocaleString()} uploaded`;
    };

    const setPhotoStatus = (card, message) => {
      const status = card.querySelector("[data-photo-status]");
      if (status) status.textContent = message;
    };

    const applyTripDraft = (payload) => {
      form.dataset.tripId = String(payload.trip_id || "");
      if (markdownEditor) markdownEditor.dataset.tripId = String(payload.trip_id || "");
      if (payload.save_url) form.setAttribute("action", payload.save_url);
      uploadUrl = payload.upload_url || uploadUrl;
      workbench.dataset.uploadUrl = uploadUrl;
    };

    const ensureUploadUrl = () => {
      if (uploadUrl) return Promise.resolve();
      if (!workbench.dataset.draftUrl) return Promise.reject(new Error("Save this hike before uploading photos."));
      if (draftPromise) return draftPromise;

      draftPromise = fetch(workbench.dataset.draftUrl, {method: "POST", headers: postHeaders()})
        .then((response) => jsonPayload(response).then((body) => {
          if (!response.ok) throw body;
          applyTripDraft(body);
          return body;
        }))
        .finally(() => {
          draftPromise = null;
        });

      return draftPromise;
    };

    const cardTemplate = (file) => {
      const card = document.createElement("article");
      card.className = "trip-photo-card trip-photo-card-uploading";
      card.setAttribute("data-trip-photo-card", "");

      const image = document.createElement("img");
      image.setAttribute("data-trip-photo-thumb", "");
      image.alt = "";
      if (file && file.type && file.type.startsWith("image/")) {
        image.src = URL.createObjectURL(file);
      }

      const body = document.createElement("div");
      body.className = "trip-photo-card-body";
      body.innerHTML = [
        '<div class="trip-photo-card-tools">',
        '<code data-photo-handle>Preparing...</code>',
        '<button class="secondary-button" type="button" data-insert-photo disabled>Insert</button>',
        "</div>",
        "<label>Caption</label>",
        '<textarea rows="2" data-photo-caption disabled></textarea>',
        `<p class="meta" data-photo-status>${escapeHtml(file ? `${file.name} / ${formatFileSize(file.size)}` : "Queued")}</p>`
      ].join("");

      card.append(image, body);
      list.prepend(card);
      updateCount();
      return card;
    };

    const applyPhotoPayload = (card, payload) => {
      const id = payload.id || payload.photo_id;
      const handle = payload.handle || `{{ photo:${id} }}`;
      const image = card.querySelector("[data-trip-photo-thumb]");
      const code = card.querySelector("[data-photo-handle]");
      const insertButton = card.querySelector("[data-insert-photo]");
      const caption = card.querySelector("[data-photo-caption]");

      card.classList.remove("trip-photo-card-uploading");
      card.dataset.photoId = id;
      card.dataset.handle = handle;
      if (payload.caption_url) card.dataset.captionUrl = payload.caption_url;
      if (image && payload.thumb_url) image.src = payload.thumb_url;
      if (code) code.textContent = handle;
      if (insertButton) insertButton.disabled = false;
      if (caption) {
        caption.disabled = false;
        caption.name = `photo_captions[${id}]`;
        caption.value = payload.caption || caption.value || "";
      }
      setPhotoStatus(card, "Saved");
      refreshPreview();
    };

    const uploadOne = (file) => {
      const card = cardTemplate(file);
      setPhotoStatus(card, "Preparing upload");

      return ensureUploadUrl()
        .then(() => {
          const payload = new URLSearchParams({
            filename: file.name,
            content_type: file.type || "application/octet-stream",
            file_size: String(file.size),
            caption: ""
          });

          return fetch(uploadUrl, {
            method: "POST",
            headers: postHeaders({"Content-Type": "application/x-www-form-urlencoded"}),
            body: payload
          });
        })
        .then((response) => jsonPayload(response).then((body) => {
          if (!response.ok) throw body;
          setPhotoStatus(card, "Uploading");
          return uploadWithProgress(body.upload, file, (amount) => {
            setPhotoStatus(card, `Uploading ${Math.round(amount * 100)}%`);
          }).then(() => body);
        }))
        .then((body) => {
          setPhotoStatus(card, "Finishing");
          return fetch(body.finalize_url, {method: "POST", headers: postHeaders()})
            .then((response) => jsonPayload(response).then((finalizeBody) => {
              if (!response.ok) throw finalizeBody;
              return {...body, ...finalizeBody};
            }));
        })
        .then((body) => applyPhotoPayload(card, body))
        .catch((error) => {
          const messages = Array.isArray(error && error.errors) ? error.errors : [error && error.message].filter(Boolean);
          setPhotoStatus(card, messages[0] || "Upload failed");
          card.classList.add("trip-photo-card-error");
        });
    };

    const pumpQueue = () => {
      while (activeUploads < 3 && queue.length > 0) {
        const file = queue.shift();
        activeUploads += 1;
        uploadOne(file).finally(() => {
          activeUploads -= 1;
          pumpQueue();
        });
      }
    };

    const enqueueFiles = (files) => {
      if (!directUploadAvailable) return;
      queue.push(...Array.from(files || []));
      pumpQueue();
    };

    list.addEventListener("click", (event) => {
      const button = event.target.closest("[data-insert-photo]");
      if (!button || button.disabled) return;
      const card = button.closest("[data-trip-photo-card]");
      if (!card || !card.dataset.handle) return;
      insertAtCursor(markdownInput, card.dataset.handle);
    });

    list.addEventListener("input", (event) => {
      const caption = event.target.closest("[data-photo-caption]");
      if (!caption || caption.disabled) return;
      const card = caption.closest("[data-trip-photo-card]");
      if (!card || !card.dataset.captionUrl) return;

      window.clearTimeout(captionTimers.get(caption));
      setPhotoStatus(card, "Saving caption");
      captionTimers.set(caption, window.setTimeout(() => {
        fetch(card.dataset.captionUrl, {
          method: "POST",
          headers: postHeaders({"Content-Type": "application/x-www-form-urlencoded"}),
          body: new URLSearchParams({caption: caption.value})
        })
          .then((response) => jsonPayload(response).then((body) => {
            if (!response.ok) throw body;
            applyPhotoPayload(card, body);
          }))
          .catch(() => setPhotoStatus(card, "Caption not saved"));
      }, 450));
    });

    if (fileInput) {
      fileInput.addEventListener("change", () => {
        enqueueFiles(fileInput.files);
        fileInput.value = "";
      });
    }

    if (dropzone) {
      ["dragenter", "dragover"].forEach((eventName) => {
        dropzone.addEventListener(eventName, (event) => {
          event.preventDefault();
          dropzone.classList.add("is-dragging");
        });
      });

      ["dragleave", "drop"].forEach((eventName) => {
        dropzone.addEventListener(eventName, () => dropzone.classList.remove("is-dragging"));
      });

      dropzone.addEventListener("drop", (event) => {
        event.preventDefault();
        enqueueFiles(event.dataTransfer && event.dataTransfer.files);
      });
    }
  };

  const buildPhotoLightbox = () => {
    const galleries = document.querySelectorAll("[data-photo-lightbox-gallery]");
    if (galleries.length === 0) return;

    let items = [];
    let currentIndex = 0;
    let thumbnailButtons = [];
    let previousFocus = null;
    let swipePointerId = null;
    let swipeStartX = 0;
    let swipeStartY = 0;

    const icon = (path) => `
      <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
        ${path}
      </svg>
    `;

    const lightbox = document.createElement("div");
    lightbox.className = "photo-lightbox";
    lightbox.hidden = true;
    lightbox.tabIndex = -1;
    lightbox.setAttribute("role", "dialog");
    lightbox.setAttribute("aria-modal", "true");
    lightbox.setAttribute("aria-label", "Photo viewer");

    const closeButton = document.createElement("button");
    closeButton.type = "button";
    closeButton.className = "photo-lightbox-close";
    closeButton.setAttribute("aria-label", "Close photo viewer");
    closeButton.innerHTML = icon('<path d="M6 6l12 12"></path><path d="M18 6L6 18"></path>');

    const stage = document.createElement("div");
    stage.className = "photo-lightbox-stage";

    const previousButton = document.createElement("button");
    previousButton.type = "button";
    previousButton.className = "photo-lightbox-nav photo-lightbox-previous";
    previousButton.setAttribute("aria-label", "Previous photo");
    previousButton.innerHTML = icon('<path d="M15 18l-6-6 6-6"></path>');

    const figure = document.createElement("figure");
    figure.className = "photo-lightbox-figure";

    const image = document.createElement("img");
    image.className = "photo-lightbox-image";
    image.draggable = false;

    const caption = document.createElement("figcaption");
    caption.className = "photo-lightbox-caption";

    const captionText = document.createElement("p");
    captionText.className = "photo-lightbox-caption-text";

    const metadata = document.createElement("p");
    metadata.className = "photo-lightbox-metadata";

    // A photo that fails to load used to leave nothing but black, which reads as
    // a broken lightbox rather than a broken file.
    const failure = document.createElement("p");
    failure.className = "photo-lightbox-failure";
    failure.hidden = true;
    failure.innerHTML = [
      '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">',
      '<path d="M3 5h18v14H3z"></path><path d="M3 16l5-5 4 4 3-3 6 6"></path><circle cx="8.5" cy="9.5" r="1.5"></circle>',
      "</svg>",
      "<span>This photo could not be loaded.</span>"
    ].join("");

    caption.append(captionText, metadata);
    figure.append(image, failure, caption);

    const nextButton = document.createElement("button");
    nextButton.type = "button";
    nextButton.className = "photo-lightbox-nav photo-lightbox-next";
    nextButton.setAttribute("aria-label", "Next photo");
    nextButton.innerHTML = icon('<path d="M9 18l6-6-6-6"></path>');

    stage.append(previousButton, figure, nextButton);

    // A toolbar rather than a listbox: these are buttons, not selectable
    // options, and a toolbar is the role that expects the roving tabindex and
    // arrow-key movement the lightbox already implements.
    const thumbnails = document.createElement("div");
    thumbnails.className = "photo-lightbox-thumbnails";
    thumbnails.setAttribute("role", "toolbar");
    thumbnails.setAttribute("aria-orientation", "horizontal");
    thumbnails.setAttribute("aria-label", "Photo thumbnails");

    lightbox.append(closeButton, stage, thumbnails);
    document.body.append(lightbox);

    const parseItems = (gallery) => {
      try {
        const parsedItems = JSON.parse(gallery.dataset.photoLightboxItems || "[]");
        return Array.isArray(parsedItems) ? parsedItems.filter((item) => item && item.full && item.thumb) : [];
      } catch (_error) {
        return [];
      }
    };

    const preloadNeighbor = (offset) => {
      if (items.length < 2) return;
      const neighbor = items[(currentIndex + offset + items.length) % items.length];
      if (!neighbor) return;
      const preview = new Image();
      preview.src = neighbor.full;
    };

    const setFailed = (failed) => {
      figure.classList.toggle("is-failed", failed);
      failure.hidden = !failed;
    };

    image.addEventListener("error", () => {
      // Clearing the src on close is not a load failure, so ignore it.
      if (image.getAttribute("src")) setFailed(true);
    });

    image.addEventListener("load", () => setFailed(false));

    const updateNavigation = () => {
      const disabled = items.length < 2;
      previousButton.disabled = disabled;
      nextButton.disabled = disabled;

      thumbnailButtons.forEach((button, index) => {
        const selected = index === currentIndex;

        if (selected) {
          button.setAttribute("aria-current", "true");
          button.scrollIntoView({behavior: "smooth", block: "nearest", inline: "center"});
        } else {
          button.removeAttribute("aria-current");
        }

        button.tabIndex = selected ? 0 : -1;
      });
    };

    const showPhoto = (index) => {
      if (items.length === 0) return;

      currentIndex = (index + items.length) % items.length;
      const item = items[currentIndex];

      setFailed(false);
      image.src = item.full;
      image.alt = item.alt || "";
      captionText.textContent = item.caption || "";
      captionText.hidden = !item.caption;
      metadata.textContent = item.metadata || "";
      metadata.hidden = !item.metadata;
      caption.hidden = !item.caption && !item.metadata;

      updateNavigation();
      preloadNeighbor(-1);
      preloadNeighbor(1);
    };

    const renderThumbnails = () => {
      thumbnails.replaceChildren();
      thumbnailButtons = items.map((item, index) => {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "photo-lightbox-thumb";
        button.setAttribute("aria-label", `View photo ${index + 1} of ${items.length}`);

        const thumb = document.createElement("img");
        thumb.src = item.thumb;
        thumb.alt = "";

        button.append(thumb);
        button.addEventListener("click", () => showPhoto(index));
        thumbnails.append(button);

        return button;
      });
    };

    const openLightbox = (galleryItems, index, trigger) => {
      items = galleryItems;
      if (items.length === 0) return;

      previousFocus = trigger;
      renderThumbnails();
      lightbox.hidden = false;
      document.body.classList.add("photo-lightbox-open");
      showPhoto(index);
      closeButton.focus();
    };

    const closeLightbox = () => {
      lightbox.hidden = true;
      document.body.classList.remove("photo-lightbox-open");
      image.removeAttribute("src");

      if (previousFocus) {
        previousFocus.focus();
        previousFocus = null;
      }
    };

    const move = (offset) => showPhoto(currentIndex + offset);

    const resetSwipe = () => {
      swipePointerId = null;
      swipeStartX = 0;
      swipeStartY = 0;
    };

    const beginSwipe = (event) => {
      if (items.length < 2) return;
      if (event.pointerType === "mouse" && event.button !== 0) return;

      swipePointerId = event.pointerId;
      swipeStartX = event.clientX;
      swipeStartY = event.clientY;

      if (figure.setPointerCapture) {
        figure.setPointerCapture(event.pointerId);
      }
    };

    const finishSwipe = (event) => {
      if (swipePointerId !== event.pointerId) return;

      const deltaX = event.clientX - swipeStartX;
      const deltaY = event.clientY - swipeStartY;
      const horizontalSwipe = Math.abs(deltaX) > 48 && Math.abs(deltaX) > Math.abs(deltaY) * 1.25;

      if (figure.releasePointerCapture && figure.hasPointerCapture && figure.hasPointerCapture(event.pointerId)) {
        figure.releasePointerCapture(event.pointerId);
      }

      resetSwipe();
      if (horizontalSwipe) move(deltaX < 0 ? 1 : -1);
    };

    // Arrow keys are the toolbar's own navigation, so when focus is parked on a
    // thumbnail it should ride along to the new one instead of being stranded on
    // a button that just lost its place in the roving tabindex.
    const moveAndKeepFocus = (offset) => {
      const onThumbnail = thumbnails.contains(document.activeElement);
      move(offset);
      if (onThumbnail && thumbnailButtons[currentIndex]) thumbnailButtons[currentIndex].focus();
    };

    previousButton.addEventListener("click", () => move(-1));
    nextButton.addEventListener("click", () => move(1));
    closeButton.addEventListener("click", closeLightbox);
    figure.addEventListener("pointerdown", beginSwipe);
    figure.addEventListener("pointerup", finishSwipe);
    figure.addEventListener("pointercancel", resetSwipe);

    lightbox.addEventListener("click", (event) => {
      if (event.target === lightbox) closeLightbox();
    });

    document.addEventListener("keydown", (event) => {
      if (lightbox.hidden) return;

      if (event.key === "ArrowLeft") {
        event.preventDefault();
        moveAndKeepFocus(-1);
      } else if (event.key === "ArrowRight") {
        event.preventDefault();
        moveAndKeepFocus(1);
      } else if (event.key === "Escape") {
        event.preventDefault();
        closeLightbox();
      } else if (event.key === "Tab") {
        containFocus(event, lightbox);
      }
    });

    galleries.forEach((gallery) => {
      const galleryItems = parseItems(gallery);
      gallery.querySelectorAll("[data-photo-lightbox-trigger]").forEach((trigger, fallbackIndex) => {
        trigger.addEventListener("click", (event) => {
          if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;

          const requestedIndex = Number.parseInt(trigger.dataset.photoIndex, 10);
          const index = Number.isFinite(requestedIndex) ? requestedIndex : fallbackIndex;
          if (!galleryItems[index]) return;

          event.preventDefault();
          openLightbox(galleryItems, index, trigger);
        });
      });
    });
  };

  window.addEventListener("DOMContentLoaded", () => {
    if (leafletReady()) {
      document.querySelectorAll("[data-map]").forEach(buildMap);
      document.querySelectorAll("[data-map-collection]").forEach(buildCollectionMap);
      document.querySelectorAll("[data-static-map]").forEach(buildStaticMap);
    }

    document.querySelectorAll("[data-nav-menu]").forEach(buildNavMenu);
    document.querySelectorAll("[data-heart-form]").forEach(buildHeartForm);
    document.querySelectorAll("[data-profile-follow-modal]").forEach(buildProfileFollowModal);
    document.querySelectorAll("[data-markdown-editor]").forEach(buildMarkdownEditor);
    document.querySelectorAll("[data-trip-location-picker]").forEach(buildTripLocationPicker);
    document.querySelectorAll("[data-photo-upload-form]").forEach(buildPhotoUploadForm);
    document.querySelectorAll("[data-trip-photo-workbench]").forEach(buildTripPhotoWorkbench);
    buildPhotoLightbox();
  });
})();
