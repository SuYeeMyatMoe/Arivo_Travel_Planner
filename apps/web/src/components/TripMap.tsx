import { useEffect, useRef, useState } from "react";
import { Expand, Layers, Minus, Plus, RotateCcw, MapPin } from "lucide-react";
import type {
  Map as MapInstance,
  Marker as MapMarker,
  GeoJSONSource,
} from "maplibre-gl";
import type { Stop } from "../lib/model";
import { routeCoordinates } from "../lib/model";
import "maplibre-gl/dist/maplibre-gl.css";
import "mapbox-gl/dist/mapbox-gl.css";
import workerUrl from "maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url";

export default function TripMap({
  items,
  selected,
  onSelect,
  motion = true,
}: {
  items: Stop[];
  selected: string | null;
  onSelect: (id: string) => void;
  motion?: boolean;
}) {
  const container = useRef<HTMLDivElement>(null),
    map = useRef<MapInstance | null>(null),
    markers = useRef<MapMarker[]>([]);
  const [loaded, setLoaded] = useState(false),
    [error, setError] = useState(""),
    [threeD, setThreeD] = useState(true),
    [fallback, setFallback] = useState(false),
    [attempt, setAttempt] = useState(0);
  const token = import.meta.env.VITE_MAPBOX_TOKEN as string | undefined;
  const useMapbox = Boolean(token?.startsWith("pk.")) && !fallback;
  const latest = useRef({ items, onSelect });
  latest.current = { items, onSelect };
  const engine = useRef<typeof import("maplibre-gl") | null>(null);
  function fit() {
    const coordinates = routeCoordinates(latest.current.items);
    if (!map.current || !coordinates.length) return;
    const xs = coordinates.map((c) => c[0]),
      ys = coordinates.map((c) => c[1]);
    map.current.fitBounds(
      [
        [Math.min(...xs), Math.min(...ys)],
        [Math.max(...xs), Math.max(...ys)],
      ],
      { padding: 70, maxZoom: 14.8, duration: motion ? 1100 : 0 },
    );
  }
  useEffect(() => {
    let disposed = false,
      timeout: ReturnType<typeof setTimeout> | undefined;
    setLoaded(false);
    setError("");
    async function init() {
      try {
        const lib = useMapbox
          ? await import("mapbox-gl")
          : await import("maplibre-gl");
        if (disposed) return;
        const sdk = ("default" in lib
          ? lib.default
          : lib) as unknown as typeof import("maplibre-gl");
        engine.current = sdk;
        if (!useMapbox) {
          sdk.setWorkerUrl(workerUrl);
          sdk.setWorkerCount(2);
        }
        const points = routeCoordinates(latest.current.items);
        const options = {
          container: container.current!,
          style: useMapbox
            ? "mapbox://styles/mapbox/standard"
            : "https://tiles.openfreemap.org/styles/dark",
          center: points[0] ?? [139.7967, 35.7148],
          zoom: 13.7,
          pitch: 55,
          bearing: -20,
          attributionControl: true,
          ...(useMapbox
            ? {
                accessToken: token,
                config: { basemap: { lightPreset: "dusk" } },
              }
            : {}),
        };
        const instance = new sdk.Map(
          options as ConstructorParameters<typeof sdk.Map>[0],
        );
        map.current = instance;
        instance.scrollZoom.disable();
        instance.on("error", () => {
          if (!disposed && !instance.isStyleLoaded())
            setError(
              "The map could not connect. Your itinerary is still available.",
            );
        });
        instance.on("load", () => {
          if (disposed) return;
          clearTimeout(timeout);
          if (!useMapbox) {
            const layers = instance.getStyle().layers ?? [];
            const building = layers.find(
              (l) => "source-layer" in l && l["source-layer"] === "building",
            );
            if (
              building &&
              "source" in building &&
              !layers.some((l) => l.type === "fill-extrusion")
            ) {
              instance.addLayer({
                id: "arivo-buildings",
                type: "fill-extrusion",
                source: building.source as string,
                "source-layer": "building",
                minzoom: 13,
                paint: {
                  "fill-extrusion-color": "#436676",
                  "fill-extrusion-height": [
                    "coalesce",
                    ["get", "render_height"],
                    8,
                  ],
                  "fill-extrusion-base": [
                    "coalesce",
                    ["get", "render_min_height"],
                    0,
                  ],
                  "fill-extrusion-opacity": 0.8,
                },
              });
            }
          }
          instance.addSource("trip-route", {
            type: "geojson",
            data: {
              type: "Feature",
              properties: {},
              geometry: { type: "LineString", coordinates: [] },
            },
          });
          instance.addLayer({
            id: "route-glow",
            type: "line",
            source: "trip-route",
            paint: {
              "line-color": "#bfe986",
              "line-width": 12,
              "line-blur": 7,
              "line-opacity": 0.25,
            },
          });
          instance.addLayer({
            id: "route-line",
            type: "line",
            source: "trip-route",
            layout: { "line-cap": "round", "line-join": "round" },
            paint: {
              "line-color": "#d9f99b",
              "line-width": 3,
              "line-dasharray": [2, 1],
            },
          });
          setError("");
          setLoaded(true);
          fit();
        });
        timeout = setTimeout(() => {
          if (!disposed && !instance.isStyleLoaded())
            setError(
              "The map is taking longer to connect. Check your connection or try again.",
            );
        }, 18000);
      } catch {
        if (!disposed)
          setError(
            "3D maps are unavailable on this device. You can still explore every stop in the itinerary.",
          );
      }
    }
    void init();
    const resize = new ResizeObserver(() => map.current?.resize());
    if (container.current) resize.observe(container.current);
    return () => {
      disposed = true;
      clearTimeout(timeout);
      resize.disconnect();
      markers.current.forEach((m) => m.remove());
      markers.current = [];
      map.current?.remove();
      map.current = null;
    };
  }, [useMapbox, token, attempt]);
  useEffect(() => {
    if (!loaded || !map.current || !engine.current) return;
    const instance = map.current;
    markers.current.forEach((m) => m.remove());
    const coordinates = routeCoordinates(items);
    (instance.getSource("trip-route") as GeoJSONSource)?.setData({
      type: "Feature",
      properties: {},
      geometry: {
        type: "LineString",
        coordinates: coordinates.length > 1 ? coordinates : [],
      },
    });
    markers.current = items
      .filter((i) => routeCoordinates([i]).length)
      .map((stop, index) => {
        const el = document.createElement("button");
        el.className = "map-stop";
        el.textContent = String(index + 1);
        el.dataset.stop = stop.id;
        el.setAttribute("aria-label", `Explore ${stop.name}`);
        el.title = stop.name;
        el.addEventListener("click", () => latest.current.onSelect(stop.id));
        return new engine.current!.Marker({ element: el })
          .setLngLat([stop.lon, stop.lat])
          .addTo(instance);
      });
    fit();
  }, [items, loaded]);
  useEffect(() => {
    markers.current.forEach((m) =>
      m
        .getElement()
        .classList.toggle("selected", m.getElement().dataset.stop === selected),
    );
    const stop = items.find((i) => i.id === selected);
    if (stop && loaded)
      map.current?.flyTo({
        center: [stop.lon, stop.lat],
        zoom: 15.2,
        duration: motion ? 1300 : 0,
        essential: false,
      });
  }, [selected, loaded, items, motion]);
  return (
    <div className="map-shell">
      <div
        className="map-canvas"
        ref={container}
        aria-label="Interactive trip map"
      />
      {!loaded && !error && (
        <div className="map-loading">
          <MapPin />
          <span>Finding your perspective…</span>
        </div>
      )}
      {error && (
        <div className="map-error glass">
          <MapPin />
          <p>{error}</p>
          {useMapbox && (
            <button
              className="button secondary"
              onClick={() => setFallback(true)}
            >
              Use free map
            </button>
          )}
          <button
            className="button secondary"
            onClick={() => setAttempt((a) => a + 1)}
          >
            Retry map
          </button>
        </div>
      )}
      <span className="map-label glass">
        <span className="live-dot" />
        {useMapbox ? "Mapbox" : "OpenFreeMap"}
        <span className="muted"> / {threeD ? "3D" : "2D"} explorer</span>
      </span>
      <div className="map-controls glass">
        <button aria-label="Zoom in" onClick={() => map.current?.zoomIn()}>
          <Plus size={18} />
        </button>
        <button aria-label="Zoom out" onClick={() => map.current?.zoomOut()}>
          <Minus size={18} />
        </button>
        <span />
        <button
          aria-label={threeD ? "Switch to 2D map" : "Switch to 3D map"}
          aria-pressed={threeD}
          onClick={() => {
            map.current?.easeTo({
              pitch: threeD ? 0 : 60,
              bearing: threeD ? 0 : -20,
              duration: motion ? 900 : 0,
            });
            setThreeD(!threeD);
          }}
        >
          <Layers size={18} />
          <small>{threeD ? "3D" : "2D"}</small>
        </button>
        <button aria-label="Fit all trip stops" onClick={fit}>
          <Expand size={18} />
        </button>
        <button
          aria-label="Reset map bearing"
          onClick={() =>
            map.current?.resetNorth({ duration: motion ? 700 : 0 })
          }
        >
          <RotateCcw size={17} />
        </button>
      </div>
      <div className="map-caption glass">
        Drag to explore · right-drag to orbit{" "}
        <span>Dashed lines connect stops, not walking directions</span>
      </div>
    </div>
  );
}
