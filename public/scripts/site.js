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

  window.addEventListener("DOMContentLoaded", () => {
    document.querySelectorAll("[data-map]").forEach(buildMap);
    document.querySelectorAll("[data-map-collection]").forEach(buildCollectionMap);
  });
})();
