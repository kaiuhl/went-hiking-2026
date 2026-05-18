(() => {
  const tileOptions = {
    attribution: "Tiles courtesy of the U.S. Geological Survey",
    maxZoom: 16
  };

  const buildMap = (element) => {
    const lat = Number(element.dataset.lat);
    const lng = Number(element.dataset.lng);
    const map = L.map(element, {scrollWheelZoom: false}).setView([lat, lng], 11);
    L.tileLayer(element.dataset.tileUrl, tileOptions).addTo(map);
    L.marker([lat, lng]).addTo(map).bindPopup(element.dataset.title || "Trip");
  };

  const buildCollectionMap = (element) => {
    const points = JSON.parse(element.dataset.points || "[]");
    const map = L.map(element, {scrollWheelZoom: false});
    L.tileLayer(element.dataset.tileUrl, tileOptions).addTo(map);
    const bounds = [];

    points.forEach((point) => {
      const marker = L.marker([point.lat, point.lng]).addTo(map);
      marker.bindPopup(`<a href="${point.url}">${point.title}</a>`);
      bounds.push([point.lat, point.lng]);
    });

    if (bounds.length > 0) {
      map.fitBounds(bounds, {padding: [24, 24], maxZoom: 10});
    } else {
      map.setView([45, -121], 5);
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

  window.addEventListener("DOMContentLoaded", () => {
    document.querySelectorAll("[data-map]").forEach(buildMap);
    document.querySelectorAll("[data-map-collection]").forEach(buildCollectionMap);
    document.querySelectorAll("[data-markdown-editor]").forEach(buildMarkdownEditor);
  });
})();
