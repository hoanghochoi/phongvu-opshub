import assert from "node:assert/strict";
import { test } from "node:test";

import {
  buildPlan,
  loadTopologyContract,
  renderCaddyConfig,
  validatePlan,
} from "./blue-green-topology.mjs";

const SHA = "a".repeat(64);
const SHA_B = "b".repeat(64);

test("topology contract is opt-in and has isolated candidate services", async () => {
  const { topology } = await loadTopologyContract();
  assert.match(topology, /profiles: \[bluegreen-candidate\]/);
  assert.match(topology, /opshub_bluegreen_shared:/);
  assert.match(topology, /external: true/);
  assert.match(topology, /api_blue:/);
  assert.match(topology, /api_green:/);
  assert.match(topology, /realtime_blue:/);
  assert.match(topology, /realtime_green:/);
  assert.doesNotMatch(topology, /^\s{2}caddy:/m);
  assert.doesNotMatch(topology, /^\s{4}ports:/m);
});

test("plan is fail-closed and never authorizes traffic or migration", () => {
  const plan = buildPlan({
    activeColor: "blue",
    candidateColor: "green",
    activeRelease: "release-100",
    candidateRelease: "release-101",
    topologySha256: SHA,
    caddyTemplateSha256: SHA_B,
  });
  assert.equal(plan.mode, "plan-only");
  assert.equal(plan.trafficSwitch.allowed, false);
  assert.equal(plan.trafficSwitch.performed, false);
  assert.equal(plan.migration.allowed, false);
  assert.equal(plan.migration.performed, false);
  assert.equal(plan.rollback.targetRelease, "release-100");
  assert.doesNotThrow(() => validatePlan(plan));
});

test("same color, release, or malformed digest is rejected", () => {
  const base = {
    activeColor: "blue",
    candidateColor: "green",
    activeRelease: "release-100",
    candidateRelease: "release-101",
    topologySha256: SHA,
    caddyTemplateSha256: SHA_B,
  };
  assert.throws(() => buildPlan({ ...base, candidateColor: "blue" }));
  assert.throws(() => buildPlan({ ...base, candidateRelease: "release-100" }));
  assert.throws(() => buildPlan({ ...base, candidateRelease: "" }));
  assert.throws(() => buildPlan({ ...base, topologySha256: "bad" }));
});

test("rendered Caddy config selects exactly one color without loopback", async () => {
  const { caddyTemplate } = await loadTopologyContract();
  const rendered = renderCaddyConfig(caddyTemplate, "green");
  assert.match(rendered, /reverse_proxy api-green:3000/);
  assert.match(rendered, /reverse_proxy realtime-green:8080/);
  assert.doesNotMatch(rendered, /\{\{[A-Z_]+\}\}/);
  assert.doesNotMatch(rendered, /localhost|127\.0\.0\.1/);
});

test("validation rejects mutation claims and a changed rollback target", () => {
  const plan = buildPlan({
    activeColor: "green",
    candidateColor: "blue",
    activeRelease: "release-200",
    candidateRelease: "release-201",
    topologySha256: SHA,
    caddyTemplateSha256: SHA_B,
  });
  assert.throws(() =>
    validatePlan({
      ...plan,
      trafficSwitch: { ...plan.trafficSwitch, performed: true },
    }),
  );
  assert.throws(() =>
    validatePlan({
      ...plan,
      rollback: { ...plan.rollback, targetRelease: "release-201" },
    }),
  );
});
