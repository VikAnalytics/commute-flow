import cors from "cors";
import express from "express";
import rateLimit from "express-rate-limit";
import helmet from "helmet";
import pino from "pino";
import pinoHttp from "pino-http";
import { ZodError } from "zod";
import { config } from "./config.js";
import { GoogleMapsClient, estimateRoute } from "./googleClient.js";
import { apartmentsSearchSchema, travelSearchSchema } from "./schemas.js";
import { centroid, estimateMonthlyRent, estimateNightlyRate, touristConnectivityScore } from "./scoring.js";
import type { BackendProperty, LatLng } from "./types.js";

const logger = pino({ level: process.env.LOG_LEVEL ?? "info" });
const app = express();
app.set("trust proxy", 1);

app.use(helmet());
app.use(express.json({ limit: "300kb" }));
app.use(
  cors({
    origin: config.ALLOWED_ORIGINS === "*" ? true : config.ALLOWED_ORIGINS.split(",").map((x) => x.trim())
  })
);
app.use(
  rateLimit({
    windowMs: 60_000,
    limit: 120,
    standardHeaders: true,
    legacyHeaders: false
  })
);
app.use(
  pinoHttp({
    logger,
    autoLogging: true
  })
);

const google = new GoogleMapsClient(config.GOOGLE_MAPS_API_KEY);

app.get("/healthz", (_req, res) => {
  res.status(200).json({ status: "ok", service: "commuteflow-backend", env: config.NODE_ENV });
});

app.post("/api/v1/apartments/search", async (req, res, next) => {
  try {
    const payload = apartmentsSearchSchema.parse(req.body);
    const workplace: LatLng = { lat: payload.workplaceLat, lng: payload.workplaceLng };
    const radiusMeters = Math.min(Math.round(payload.withinMiles * 1609.344), 50_000);

    const places = await google.nearbyPlaces(workplace, radiusMeters, "apartment");
    const properties: BackendProperty[] = [];

    for (const [index, place] of places.slice(0, 10).entries()) {
      const route = (await google.transitRoute(place.coordinate, workplace)) ?? estimateRoute(place.coordinate, workplace);
      const website = await google.placeWebsiteURL(place.placeId, place.googleURL);
      properties.push({
        kind: "apartment",
        name: place.name,
        latitude: place.coordinate.lat,
        longitude: place.coordinate.lng,
        monthlyRentRange: estimateMonthlyRent(index, place.rating),
        nightlyRateRange: null,
        commuteTimeMinutes: Math.max(1, Math.floor(route.durationSeconds / 60)),
        walkingMinutes: Math.max(0, Math.floor(route.walkingSeconds / 60)),
        commuteBreakdown: route.breakdown,
        websiteURL: website,
        rating: place.rating,
        ratingReviewCount: place.ratingCount,
        listingSource: "verified",
        touristConnectivityScore: null,
        polylineCoordinates: route.polylineCoordinates,
        journeySegments: route.segments
      });
    }

    res.status(200).json({
      workplaceName: payload.workplaceName,
      workplaceLat: payload.workplaceLat,
      workplaceLng: payload.workplaceLng,
      properties
    });
  } catch (error) {
    next(error);
  }
});

app.post("/api/v1/travel/stays", async (req, res, next) => {
  try {
    const payload = travelSearchSchema.parse(req.body);
    const hubCenter = centroid(payload.hubs.map((h) => ({ lat: h.lat, lng: h.lng })));
    const places = await google.nearbyPlaces(hubCenter, 12_000, "hotel", "lodging");
    const properties: BackendProperty[] = [];

    for (const place of places.slice(0, 10)) {
      const routes = await Promise.all(
        payload.hubs.map(async (hub) => (await google.transitRoute(place.coordinate, { lat: hub.lat, lng: hub.lng })) ?? estimateRoute(place.coordinate, { lat: hub.lat, lng: hub.lng }))
      );
      const avgDuration = Math.floor(routes.reduce((sum, r) => sum + r.durationSeconds, 0) / routes.length);
      const avgWalking = Math.floor(routes.reduce((sum, r) => sum + r.walkingSeconds, 0) / routes.length);
      const bestRoute = routes.reduce((best, current) => (current.durationSeconds < best.durationSeconds ? current : best), routes[0]);
      const journeySegments = payload.hubs.map((hub, index) => {
        const route = routes[index];
        return `To ${hub.name}: ${route.segments.join(" -> ")}`;
      });

      properties.push({
        kind: "hotel",
        name: place.name,
        latitude: place.coordinate.lat,
        longitude: place.coordinate.lng,
        monthlyRentRange: null,
        nightlyRateRange: estimateNightlyRate(place.rating),
        commuteTimeMinutes: Math.max(1, Math.floor(avgDuration / 60)),
        walkingMinutes: Math.max(0, Math.floor(avgWalking / 60)),
        commuteBreakdown: bestRoute.breakdown,
        websiteURL: await google.placeWebsiteURL(place.placeId, place.googleURL),
        rating: place.rating,
        ratingReviewCount: place.ratingCount,
        listingSource: "verified",
        touristConnectivityScore: touristConnectivityScore(avgDuration, avgWalking),
        polylineCoordinates: bestRoute.polylineCoordinates,
        journeySegments
      });
    }

    res.status(200).json({ properties });
  } catch (error) {
    next(error);
  }
});

app.use((error: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  if (error instanceof ZodError) {
    return res.status(400).json({
      error: "validation_error",
      details: error.issues.map((i) => ({ path: i.path.join("."), message: i.message }))
    });
  }

  logger.error({ err: error }, "Unhandled backend error");
  const detail = error instanceof Error ? error.message : "Unknown backend error";
  return res.status(502).json({
    error: "provider_error",
    message: "Upstream provider unavailable",
    ...(config.NODE_ENV === "development" ? { detail } : {})
  });
});

app.listen(config.PORT, () => {
  logger.info({ port: config.PORT }, "CommuteFlow backend listening");
});
