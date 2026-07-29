export const HOME_AGGREGATE_METRICS = Object.freeze([
  "totalRevenue",
  "totalOrders",
  "reportedOrders",
  "totalReports",
]);

function isRecord(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function hasFiniteAggregateMetrics(body) {
  return HOME_AGGREGATE_METRICS.every(
    (metric) =>
      typeof body[metric] === "number" && Number.isFinite(body[metric]),
  );
}

function dateAtOffset(startDate, offset) {
  const date = new Date(`${startDate}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + offset);
  return date.toISOString().slice(0, 10);
}

export function legacyHomeBodyMatchesContract(body) {
  return (
    isRecord(body) &&
    !Object.prototype.hasOwnProperty.call(body, "dailySeries") &&
    hasFiniteAggregateMetrics(body)
  );
}

export function dailyHomeBodyMatchesContract(body, route) {
  if (
    !isRecord(body) ||
    !hasFiniteAggregateMetrics(body) ||
    !Array.isArray(body.dailySeries) ||
    body.dailySeries.length !== route.days
  ) {
    return false;
  }
  const totals = {
    totalRevenue: 0,
    totalOrders: 0,
    reportedOrders: 0,
    totalReports: 0,
  };
  for (let index = 0; index < body.dailySeries.length; index += 1) {
    const point = body.dailySeries[index];
    if (
      !isRecord(point) ||
      point.date !== dateAtOffset(route.startDate, index)
    ) {
      return false;
    }
    for (const metric of HOME_AGGREGATE_METRICS) {
      if (
        typeof point[metric] !== "number" ||
        !Number.isFinite(point[metric])
      ) {
        return false;
      }
      totals[metric] += point[metric];
    }
  }
  return HOME_AGGREGATE_METRICS.every(
    (metric) => totals[metric] === body[metric],
  );
}

export function homeAggregateBodiesHaveParity(legacyBody, dailyBody) {
  if (
    !legacyHomeBodyMatchesContract(legacyBody) ||
    !isRecord(dailyBody) ||
    !hasFiniteAggregateMetrics(dailyBody)
  ) {
    return false;
  }
  return HOME_AGGREGATE_METRICS.every(
    (metric) => legacyBody[metric] === dailyBody[metric],
  );
}

export function homeResponsePairMatchesContract(legacyBody, dailyBody, route) {
  return (
    legacyHomeBodyMatchesContract(legacyBody) &&
    dailyHomeBodyMatchesContract(dailyBody, route) &&
    homeAggregateBodiesHaveParity(legacyBody, dailyBody)
  );
}
