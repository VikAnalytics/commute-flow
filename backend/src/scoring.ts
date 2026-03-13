export function estimateMonthlyRent(index: number, rating: number | null): string {
  const base = 1500 + index * 120;
  const boost = Math.round((rating ?? 4.0) * 60);
  const low = base + boost;
  return `$${low} - $${low + 550}`;
}

export function estimateNightlyRate(rating: number | null): string {
  const base = 120 + Math.round((rating ?? 4.0) * 20);
  return `$${base} - $${base + 90} / night`;
}

export function touristConnectivityScore(avgDurationSeconds: number, avgWalkingSeconds: number): number {
  const durationPenalty = (avgDurationSeconds / 60) * 1.8;
  const walkingPenalty = (avgWalkingSeconds / 60) * 1.2;
  const raw = 100 - durationPenalty - walkingPenalty;
  return Math.max(0, Math.min(100, Math.round(raw)));
}

export function centroid(values: Array<{ lat: number; lng: number }>): { lat: number; lng: number } {
  const sum = values.reduce(
    (acc, item) => ({ lat: acc.lat + item.lat, lng: acc.lng + item.lng }),
    { lat: 0, lng: 0 }
  );
  return { lat: sum.lat / values.length, lng: sum.lng / values.length };
}
