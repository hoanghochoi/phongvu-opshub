import assert from "node:assert/strict";
import test from "node:test";

import {
  homeResponsePairMatchesContract,
  legacyHomeBodyMatchesContract,
} from "./opshub-home-phase1-contract.mjs";

const route = {
  days: 2,
  startDate: "2026-07-04",
  endDate: "2026-07-05",
};
const legacy = {
  totalRevenue: 30,
  totalOrders: 3,
  reportedOrders: 2,
  totalReports: 4,
};
const daily = {
  ...legacy,
  dailySeries: [
    {
      date: "2026-07-04",
      totalRevenue: 10,
      totalOrders: 1,
      reportedOrders: 1,
      totalReports: 1,
    },
    {
      date: "2026-07-05",
      totalRevenue: 20,
      totalOrders: 2,
      reportedOrders: 1,
      totalReports: 3,
    },
  ],
};

test("accepts matched legacy and opted-in aggregate responses", () => {
  assert.equal(homeResponsePairMatchesContract(legacy, daily, route), true);
});

test("rejects opted-in aggregate drift even when its daily sum is internally consistent", () => {
  const driftedDaily = {
    ...daily,
    totalRevenue: 40,
    dailySeries: [
      daily.dailySeries[0],
      { ...daily.dailySeries[1], totalRevenue: 30 },
    ],
  };

  assert.equal(
    homeResponsePairMatchesContract(legacy, driftedDaily, route),
    false,
  );
});

test("rejects a legacy response that unexpectedly exposes the optional series", () => {
  assert.equal(
    legacyHomeBodyMatchesContract({ ...legacy, dailySeries: [] }),
    false,
  );
});
