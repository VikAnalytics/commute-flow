export type LatLng = {
  lat: number;
  lng: number;
};

export type BackendProperty = {
  kind: "apartment" | "hotel" | "airbnb";
  name: string;
  latitude: number;
  longitude: number;
  monthlyRentRange: string | null;
  nightlyRateRange: string | null;
  commuteTimeMinutes: number;
  walkingMinutes: number;
  commuteBreakdown: string;
  websiteURL: string;
  rating: number | null;
  ratingReviewCount: number | null;
  listingSource: "verified" | "generated";
  touristConnectivityScore: number | null;
  polylineCoordinates: LatLng[];
  journeySegments: string[];
};
