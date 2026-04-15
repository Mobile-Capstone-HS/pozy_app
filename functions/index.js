const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");

const NAVER_DIRECTIONS_API_KEY_ID = defineSecret("NAVER_DIRECTIONS_API_KEY_ID");
const NAVER_DIRECTIONS_API_KEY = defineSecret("NAVER_DIRECTIONS_API_KEY");

const DIRECTIONS_API_URL =
  "https://maps.apigw.ntruss.com/map-direction/v1/driving";

exports.getDrivingRoute = onCall(
  {
    region: "asia-northeast3",
    timeoutSeconds: 20,
    memory: "256MiB",
    secrets: [NAVER_DIRECTIONS_API_KEY_ID, NAVER_DIRECTIONS_API_KEY],
  },
  async (request) => {
    try {
      if (!request.auth) {
        throw new HttpsError(
          "unauthenticated",
          "Driving route requests require an authenticated user.",
        );
      }

      const startLat = toFiniteNumber(request.data?.startLat);
      const startLng = toFiniteNumber(request.data?.startLng);
      const goalLat = toFiniteNumber(request.data?.goalLat);
      const goalLng = toFiniteNumber(request.data?.goalLng);
      const option = sanitizeOption(request.data?.option);

      if ([startLat, startLng, goalLat, goalLng].some((value) => value === null)) {
        throw new HttpsError(
          "invalid-argument",
          "Start and goal coordinates must be valid numbers.",
        );
      }

      console.log("getDrivingRoute request", {
        uid: request.auth.uid,
        option,
        startLat,
        startLng,
        goalLat,
        goalLng,
        endpoint: DIRECTIONS_API_URL,
      });

      const url = new URL(DIRECTIONS_API_URL);
      url.searchParams.set("start", `${startLng},${startLat}`);
      url.searchParams.set("goal", `${goalLng},${goalLat}`);
      url.searchParams.set("option", option);
      url.searchParams.set("cartype", "1");
      url.searchParams.set("fueltype", "gasoline");
      url.searchParams.set("lang", "ko");

      const response = await fetch(url, {
        headers: {
          "x-ncp-apigw-api-key-id": NAVER_DIRECTIONS_API_KEY_ID.value(),
          "x-ncp-apigw-api-key": NAVER_DIRECTIONS_API_KEY.value(),
        },
      });

      const rawText = await response.text();
      console.log("Naver directions response status", response.status);
      console.log("Naver directions response body", rawText.slice(0, 1200));

      let parsedJson = null;
      try {
        parsedJson = JSON.parse(rawText);
      } catch (_) {}

      if (!response.ok) {
        const apiErrorCode = parsedJson?.error?.errorCode ?? null;
        const apiErrorDetails = parsedJson?.error?.details ?? null;

        if (response.status === 401 && apiErrorCode === "210") {
          throw new HttpsError(
            "failed-precondition",
            "NAVER rejected this key for Directions 5. The application looks registered, but the key still does not have usable Directions 5 permission.",
            {
              responseStatus: response.status,
              apiErrorCode,
              apiErrorDetails,
              endpoint: DIRECTIONS_API_URL,
            },
          );
        }

        throw new HttpsError(
          "internal",
          `NAVER Directions API request failed. (${response.status})`,
          {
            responseStatus: response.status,
            apiErrorCode,
            apiErrorDetails,
            endpoint: DIRECTIONS_API_URL,
          },
        );
      }

      const json = parsedJson ?? JSON.parse(rawText);
      if (json.code !== 0) {
        throw new HttpsError(
          "failed-precondition",
          json.message || "NAVER Directions returned an unsuccessful result.",
          { code: json.code, apiResponse: json, endpoint: DIRECTIONS_API_URL },
        );
      }

      const routes = json.route?.[option];
      const primaryRoute = Array.isArray(routes) ? routes[0] : null;
      if (!primaryRoute?.summary || !Array.isArray(primaryRoute.path)) {
        console.error("No route found in Naver response", {
          option,
          routeKeys: Object.keys(json.route ?? {}),
        });
        throw new HttpsError(
          "not-found",
          "No driving route was returned for this destination.",
        );
      }

      return {
        option,
        distanceMeters: primaryRoute.summary.distance ?? 0,
        durationMs: primaryRoute.summary.duration ?? 0,
        tollFare: primaryRoute.summary.tollFare ?? 0,
        taxiFare: primaryRoute.summary.taxiFare ?? 0,
        fuelPrice: primaryRoute.summary.fuelPrice ?? 0,
        departureTime: primaryRoute.summary.departureTime ?? null,
        bounds: normalizeBounds(primaryRoute.summary.bbox),
        path: primaryRoute.path.map(normalizePathPoint).filter(Boolean),
        guide: Array.isArray(primaryRoute.guide)
          ? primaryRoute.guide.map(normalizeGuide).filter(Boolean).slice(0, 12)
          : [],
      };
    } catch (error) {
      console.error("getDrivingRoute failed", serializeError(error));
      throw error;
    }
  },
);

function toFiniteNumber(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function sanitizeOption(value) {
  const allowed = new Set([
    "trafast",
    "tracomfort",
    "traoptimal",
    "traavoidtoll",
    "traavoidcaronly",
  ]);
  return allowed.has(value) ? value : "traoptimal";
}

function normalizePathPoint(point) {
  if (!Array.isArray(point) || point.length < 2) return null;
  const lng = toFiniteNumber(point[0]);
  const lat = toFiniteNumber(point[1]);
  if (lat === null || lng === null) return null;
  return { lat, lng };
}

function normalizeBounds(bbox) {
  if (!Array.isArray(bbox) || bbox.length < 2) return null;
  const southWest = normalizePathPoint(bbox[0]);
  const northEast = normalizePathPoint(bbox[1]);
  if (!southWest || !northEast) return null;
  return { southWest, northEast };
}

function normalizeGuide(guide) {
  if (!guide || typeof guide !== "object") return null;
  return {
    pointIndex: Number.isFinite(guide.pointIndex) ? guide.pointIndex : null,
    type: Number.isFinite(guide.type) ? guide.type : null,
    instructions:
      typeof guide.instructions === "string" ? guide.instructions : "",
    distance: Number.isFinite(guide.distance) ? guide.distance : 0,
    duration: Number.isFinite(guide.duration) ? guide.duration : 0,
  };
}

function serializeError(error) {
  if (error instanceof HttpsError) {
    return {
      type: "HttpsError",
      code: error.code,
      message: error.message,
      details: error.details ?? null,
    };
  }

  if (error instanceof Error) {
    return {
      type: error.name,
      message: error.message,
      stack: error.stack,
    };
  }

  return { type: typeof error, value: error };
}
