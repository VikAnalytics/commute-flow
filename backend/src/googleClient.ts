import axios, { AxiosInstance } from "axios";
import type { LatLng } from "./types.js";

type PlaceCandidate = {
  placeId: string;
  name: string;
  coordinate: LatLng;
  rating: number | null;
  ratingCount: number | null;
  googleURL: string;
};

type RouteSummary = {
  durationSeconds: number;
  walkingSeconds: number;
  breakdown: string;
  polylineCoordinates: LatLng[];
};

export class GoogleMapsClient {
  private readonly http: AxiosInstance;

  constructor(private readonly apiKey: string) {
    this.http = axios.create({
      timeout: 12_000
    });
  }

  async nearbyPlaces(
    location: LatLng,
    radiusMeters: number,
    keyword: string,
    type?: string
  ): Promise<PlaceCandidate[]> {
    const { data } = await this.http.get("https://maps.googleapis.com/maps/api/place/nearbysearch/json", {
      params: {
        key: this.apiKey,
        location: `${location.lat},${location.lng}`,
        radius: radiusMeters,
        keyword,
        type
      }
    });

    if (!["OK", "ZERO_RESULTS"].includes(data.status)) {
      throw new Error(`Google nearby error: ${data.status}`);
    }

    return (data.results ?? []).map((r: any) => ({
      placeId: r.place_id as string,
      name: r.name as string,
      coordinate: { lat: r.geometry.location.lat as number, lng: r.geometry.location.lng as number },
      rating: typeof r.rating === "number" ? r.rating : null,
      ratingCount: typeof r.user_ratings_total === "number" ? r.user_ratings_total : null,
      googleURL: `https://maps.google.com/?q=place_id:${r.place_id as string}`
    }));
  }

  async placeWebsiteURL(placeId: string, fallback: string): Promise<string> {
    const { data } = await this.http.get("https://maps.googleapis.com/maps/api/place/details/json", {
      params: {
        key: this.apiKey,
        place_id: placeId,
        fields: "website,url"
      }
    });

    if (data.status !== "OK") {
      return fallback;
    }

    return (data.result?.website as string | undefined) ?? (data.result?.url as string | undefined) ?? fallback;
  }

  async transitRoute(origin: LatLng, destination: LatLng): Promise<RouteSummary | null> {
    const { data } = await this.http.get("https://maps.googleapis.com/maps/api/directions/json", {
      params: {
        key: this.apiKey,
        origin: `${origin.lat},${origin.lng}`,
        destination: `${destination.lat},${destination.lng}`,
        mode: "transit"
      }
    });

    if (data.status !== "OK" || !data.routes?.[0]?.legs?.[0]) {
      return null;
    }

    const route = data.routes[0];
    const leg = route.legs[0];
    const steps = leg.steps ?? [];
    const walkingSeconds = steps
      .filter((s: any) => String(s.travel_mode).toUpperCase() === "WALKING")
      .reduce((sum: number, s: any) => sum + (s.duration?.value ?? 0), 0);

    const breakdown = steps
      .map((step: any) => {
        const mode = String(step.travel_mode).toUpperCase();
        if (mode === "WALKING") {
          return `${Math.max(1, Math.floor((step.duration?.value ?? 60) / 60))} min walk`;
        }
        if (mode === "TRANSIT") {
          return (
            (step.transit_details?.line?.short_name as string | undefined) ??
            (step.transit_details?.line?.name as string | undefined) ??
            "Transit"
          );
        }
        return mode;
      })
      .join(" -> ");

    const polyline = decodePolyline((route.overview_polyline?.points as string | undefined) ?? "");
    return {
      durationSeconds: leg.duration.value as number,
      walkingSeconds,
      breakdown: breakdown || "Transit route available",
      polylineCoordinates: polyline.length > 0 ? polyline : [origin, destination]
    };
  }
}

export function estimateRoute(origin: LatLng, destination: LatLng): RouteSummary {
  const distanceMeters = haversineMeters(origin, destination);
  const transitSeconds = Math.round(distanceMeters / 7.8);
  const walkingSeconds = Math.max(180, Math.round((distanceMeters * 0.18) / 1.35));
  return {
    durationSeconds: Math.max(300, transitSeconds + walkingSeconds),
    walkingSeconds,
    breakdown: "Transit estimate (backend fallback)",
    polylineCoordinates: [origin, destination]
  };
}

function haversineMeters(a: LatLng, b: LatLng): number {
  const toRad = (v: number) => (v * Math.PI) / 180;
  const r = 6371000;
  const dLat = toRad(b.lat - a.lat);
  const dLon = toRad(b.lng - a.lng);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const sinLat = Math.sin(dLat / 2);
  const sinLon = Math.sin(dLon / 2);
  const q = sinLat * sinLat + sinLon * sinLon * Math.cos(lat1) * Math.cos(lat2);
  return 2 * r * Math.atan2(Math.sqrt(q), Math.sqrt(1 - q));
}

function decodePolyline(encoded: string): LatLng[] {
  if (!encoded) return [];
  const bytes = Array.from(encoded).map((c) => c.charCodeAt(0));
  const points: LatLng[] = [];
  let index = 0;
  let lat = 0;
  let lng = 0;

  while (index < bytes.length) {
    let shift = 0;
    let result = 0;
    let byte: number;
    do {
      byte = bytes[index++] - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < bytes.length);
    lat += result & 1 ? ~(result >> 1) : result >> 1;

    shift = 0;
    result = 0;
    do {
      byte = bytes[index++] - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < bytes.length);
    lng += result & 1 ? ~(result >> 1) : result >> 1;

    points.push({ lat: lat / 1e5, lng: lng / 1e5 });
  }

  return points;
}
