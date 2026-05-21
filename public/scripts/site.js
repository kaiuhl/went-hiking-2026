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

  const fitMapToPoints = (map, points, options = {}) => {
    if (points.length === 0) {
      map.setView([45, -121], 5);
      return;
    }

    if (points.length === 1) {
      map.setView(points[0], options.singlePointZoom || 9);
      return;
    }

    map.fitBounds(points, {
      paddingTopLeft: options.paddingTopLeft || [36, 28],
      paddingBottomRight: options.paddingBottomRight || [36, 44],
      maxZoom: options.maxZoom || 10
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

  const buildYearSwitcher = (element) => {
    element.addEventListener("change", () => {
      if (element.form) element.form.submit();
    });
  };

  const buildMarkdownEditor = (element) => {
    const input = element.querySelector("[data-markdown-input]");
    const preview = element.querySelector("[data-markdown-preview]");
    const status = element.querySelector("[data-markdown-status]");
    let timeout;
    let controller;

    const render = () => {
      const body = input.value;

      if (!body.trim()) {
        preview.innerHTML = '<p class="empty">Start writing to preview the trip report.</p>';
        status.textContent = "Markdown";
        return;
      }

      if (controller) controller.abort();
      controller = new AbortController();
      status.textContent = "Rendering";

      fetch("/api/markdown-preview", {
        method: "POST",
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: new URLSearchParams({body}),
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

  const buildPhotoLightbox = () => {
    const galleries = document.querySelectorAll("[data-photo-lightbox-gallery]");
    if (galleries.length === 0) return;

    let items = [];
    let currentIndex = 0;
    let thumbnailButtons = [];
    let previousFocus = null;

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

    const caption = document.createElement("figcaption");
    caption.className = "photo-lightbox-caption";

    const captionText = document.createElement("p");
    captionText.className = "photo-lightbox-caption-text";

    const metadata = document.createElement("p");
    metadata.className = "photo-lightbox-metadata";

    caption.append(captionText, metadata);
    figure.append(image, caption);

    const nextButton = document.createElement("button");
    nextButton.type = "button";
    nextButton.className = "photo-lightbox-nav photo-lightbox-next";
    nextButton.setAttribute("aria-label", "Next photo");
    nextButton.innerHTML = icon('<path d="M9 18l6-6-6-6"></path>');

    stage.append(previousButton, figure, nextButton);

    const thumbnails = document.createElement("div");
    thumbnails.className = "photo-lightbox-thumbnails";
    thumbnails.setAttribute("role", "listbox");
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

    const updateNavigation = () => {
      const disabled = items.length < 2;
      previousButton.disabled = disabled;
      nextButton.disabled = disabled;

      thumbnailButtons.forEach((button, index) => {
        const selected = index === currentIndex;
        button.setAttribute("aria-selected", selected ? "true" : "false");
        button.tabIndex = selected ? 0 : -1;

        if (selected) {
          button.scrollIntoView({behavior: "smooth", block: "nearest", inline: "center"});
        }
      });
    };

    const showPhoto = (index) => {
      if (items.length === 0) return;

      currentIndex = (index + items.length) % items.length;
      const item = items[currentIndex];

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
        button.setAttribute("role", "option");
        button.setAttribute("aria-label", `View photo ${index + 1}`);

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

    const trapFocus = (event) => {
      const focusable = Array.from(lightbox.querySelectorAll("button:not([disabled])"));
      if (focusable.length === 0) return;

      const first = focusable[0];
      const last = focusable[focusable.length - 1];

      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };

    previousButton.addEventListener("click", () => move(-1));
    nextButton.addEventListener("click", () => move(1));
    closeButton.addEventListener("click", closeLightbox);

    lightbox.addEventListener("click", (event) => {
      if (event.target === lightbox) closeLightbox();
    });

    document.addEventListener("keydown", (event) => {
      if (lightbox.hidden) return;

      if (event.key === "ArrowLeft") {
        event.preventDefault();
        move(-1);
      } else if (event.key === "ArrowRight") {
        event.preventDefault();
        move(1);
      } else if (event.key === "Escape") {
        event.preventDefault();
        closeLightbox();
      } else if (event.key === "Tab") {
        trapFocus(event);
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
    document.querySelectorAll("[data-map]").forEach(buildMap);
    document.querySelectorAll("[data-map-collection]").forEach(buildCollectionMap);
    document.querySelectorAll("[data-static-map]").forEach(buildStaticMap);
    document.querySelectorAll("[data-year-switcher]").forEach(buildYearSwitcher);
    document.querySelectorAll("[data-markdown-editor]").forEach(buildMarkdownEditor);
    buildPhotoLightbox();
  });
})();
