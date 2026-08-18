#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import process from "node:process";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const TOPOLOGY_RELATIVE = "deploy/home-server/docker-compose.blue-green.yml";
const CADDY_TEMPLATE_RELATIVE =
  "deploy/home-server/Caddyfile.bluegreen.template";
const COLORS = new Set(["blue", "green"]);
const SAFE_IDENTIFIER = /^[a-z0-9][a-z0-9._-]{0,63}$/;

function fail(message) {
  throw new Error(message);
}

function assertColor(value, label) {
  if (!COLORS.has(value)) fail(`${label} must be blue or green.`);
  return value;
}

function assertIdentifier(value, label) {
  if (typeof value !== "string" || !SAFE_IDENTIFIER.test(value)) {
    fail(`${label} must be a lowercase release identifier.`);
  }
  return value;
}

function oppositeColor(color) {
  return color === "blue" ? "green" : "blue";
}

async function readRepoFile(relativePath) {
  const absolute = path.resolve(ROOT, ...relativePath.split("/"));
  return readFile(absolute, "utf8");
}

function sha256(content) {
  return createHash("sha256").update(content).digest("hex");
}

function assertTopologyContract(topology) {
  if (!topology.includes("profiles: [bluegreen-candidate]")) {
    fail("Topology overlay must be opt-in through bluegreen-candidate profile.");
  }
  if (!topology.includes("opshub_bluegreen_shared:")) {
    fail("Topology overlay must declare the shared external network.");
  }
  if (!topology.includes("external: true")) {
    fail("Shared blue-green network must be external and pre-created.");
  }
  for (const color of COLORS) {
    for (const service of [`api_${color}:`, `realtime_${color}:`]) {
      if (!topology.includes(`  ${service}`)) {
        fail(`Topology overlay is missing ${service}.`);
      }
    }
  }
  if (/^\s{2}caddy:/m.test(topology)) {
    fail("Topology overlay must not define or restart a second Caddy edge.");
  }

  // Candidate services must never publish a host port. Keep this deliberately
  // structural so the check remains deterministic without Docker or YAML deps.
  for (const color of COLORS) {
    const start = topology.indexOf(`  api_${color}:`);
    const end = topology.indexOf(`  realtime_${color}:`, start);
    const section = topology.slice(start, end < 0 ? topology.length : end);
    if (/^\s{4}ports:/m.test(section)) {
      fail(`api_${color} must not publish a host port.`);
    }
    const realtimeStart = topology.indexOf(`  realtime_${color}:`);
    const nextNetwork = topology.indexOf("\nnetworks:", realtimeStart);
    const realtimeSection = topology.slice(
      realtimeStart,
      nextNetwork < 0 ? topology.length : nextNetwork,
    );
    if (/^\s{4}ports:/m.test(realtimeSection)) {
      fail(`realtime_${color} must not publish a host port.`);
    }
  }
}

export async function loadTopologyContract() {
  const topology = await readRepoFile(TOPOLOGY_RELATIVE);
  const caddyTemplate = await readRepoFile(CADDY_TEMPLATE_RELATIVE);
  assertTopologyContract(topology);
  if (!caddyTemplate.includes("{{API_UPSTREAM}}")) {
    fail("Caddy template is missing the API upstream placeholder.");
  }
  if (!caddyTemplate.includes("{{WS_UPSTREAM}}")) {
    fail("Caddy template is missing the WebSocket upstream placeholder.");
  }
  return { topology, caddyTemplate };
}

export function buildPlan({
  activeColor,
  candidateColor,
  activeRelease,
  candidateRelease,
  topologySha256,
  caddyTemplateSha256,
}) {
  assertColor(activeColor, "activeColor");
  assertColor(candidateColor, "candidateColor");
  assertIdentifier(activeRelease, "activeRelease");
  assertIdentifier(candidateRelease, "candidateRelease");
  if (activeColor === candidateColor) {
    fail("Candidate color must be different from the active color.");
  }
  if (activeRelease === candidateRelease) {
    fail("Candidate release must differ from the active release.");
  }
  if (!/^[a-f0-9]{64}$/.test(topologySha256)) {
    fail("topologySha256 must be a SHA-256 digest.");
  }
  if (!/^[a-f0-9]{64}$/.test(caddyTemplateSha256)) {
    fail("caddyTemplateSha256 must be a SHA-256 digest.");
  }

  return {
    formatVersion: 1,
    mode: "plan-only",
    activeColor,
    candidateColor,
    activeRelease,
    candidateRelease,
    source: {
      topology: TOPOLOGY_RELATIVE,
      topologySha256,
      caddyTemplate: CADDY_TEMPLATE_RELATIVE,
      caddyTemplateSha256,
    },
    networks: {
      shared: "opshub-bluegreen-shared",
      candidate: `opshub-bluegreen-${candidateColor}`,
    },
    trafficSwitch: {
      allowed: false,
      performed: false,
      selectedColor: null,
    },
    migration: {
      allowed: false,
      performed: false,
      compatibilityProof: "required-by-later-slice",
    },
    rollback: {
      targetColor: activeColor,
      targetRelease: activeRelease,
      automatic: false,
    },
    candidateGates: [
      "compose-config",
      "candidate-health",
      "direct-origin-health",
      "authenticated-bootstrap-and-me",
      "home-parity-1-7-30-90",
      "app-version-identity",
    ],
  };
}

export function renderCaddyConfig(template, color) {
  assertColor(color, "color");
  const rendered = template
    .replaceAll("{{API_UPSTREAM}}", `api-${color}:3000`)
    .replaceAll("{{WS_UPSTREAM}}", `realtime-${color}:8080`);
  if (rendered.includes("{{")) fail("Rendered Caddy config has placeholders.");
  if (rendered.includes("localhost") || rendered.includes("127.0.0.1")) {
    fail("Rendered Caddy config must use the color network, not loopback.");
  }
  return rendered;
}

export function validatePlan(manifest) {
  if (!manifest || manifest.formatVersion !== 1) {
    fail("Unsupported blue-green plan format.");
  }
  assertColor(manifest.activeColor, "activeColor");
  assertColor(manifest.candidateColor, "candidateColor");
  if (manifest.activeColor === manifest.candidateColor) {
    fail("Plan active and candidate colors must differ.");
  }
  for (const pathValue of [
    manifest.activeRelease,
    manifest.candidateRelease,
  ]) {
    assertIdentifier(pathValue, "release");
  }
  if (manifest.trafficSwitch?.allowed !== false) {
    fail("This slice must not allow a traffic switch.");
  }
  if (manifest.trafficSwitch?.performed !== false) {
    fail("This slice must not report a traffic switch.");
  }
  if (manifest.migration?.allowed !== false) {
    fail("This slice must not allow migrations.");
  }
  if (manifest.migration?.performed !== false) {
    fail("This slice must not report a migration.");
  }
  if (manifest.rollback?.targetRelease !== manifest.activeRelease) {
    fail("Rollback target must remain the active release.");
  }
  return manifest;
}

function parseArgs(argv) {
  const [command, ...rest] = argv;
  const options = { command };
  for (let index = 0; index < rest.length; index += 1) {
    const token = rest[index];
    if (!token.startsWith("--")) fail(`Unexpected argument: ${token}`);
    const name = token.slice(2);
    const value = rest[index + 1];
    if (!value || value.startsWith("--")) fail(`Missing value for --${name}.`);
    options[name] = value;
    index += 1;
  }
  return options;
}

async function writeJson(relativeOrAbsolutePath, value) {
  const destination = path.isAbsolute(relativeOrAbsolutePath)
    ? relativeOrAbsolutePath
    : path.resolve(process.cwd(), relativeOrAbsolutePath);
  await mkdir(path.dirname(destination), { recursive: true });
  await writeFile(destination, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (!options.command || !["plan", "render", "validate"].includes(options.command)) {
    fail("Usage: blue-green-topology.mjs plan|render|validate ...");
  }

  if (options.command === "plan") {
    const activeColor = assertColor(options["active-color"], "--active-color");
    const candidateColor = assertColor(
      options["candidate-color"],
      "--candidate-color",
    );
    const { topology, caddyTemplate } = await loadTopologyContract();
    const manifest = buildPlan({
      activeColor,
      candidateColor,
      activeRelease: options["active-release"],
      candidateRelease: options["candidate-release"],
      topologySha256: sha256(topology),
      caddyTemplateSha256: sha256(caddyTemplate),
    });
    if (options.output) await writeJson(options.output, manifest);
    process.stdout.write(
      `${JSON.stringify({
        status: "planned",
        activeColor,
        candidateColor,
        trafficSwitch: false,
        migration: false,
        output: options.output ?? null,
      })}\n`,
    );
    return;
  }

  if (options.command === "render") {
    if (!options.color || !options.output) {
      fail("render requires --color and --output.");
    }
    const { caddyTemplate } = await loadTopologyContract();
    const rendered = renderCaddyConfig(caddyTemplate, options.color);
    const destination = path.isAbsolute(options.output)
      ? options.output
      : path.resolve(process.cwd(), options.output);
    await mkdir(path.dirname(destination), { recursive: true });
    await writeFile(destination, rendered, "utf8");
    process.stdout.write(
      `${JSON.stringify({
        status: "rendered",
        color: options.color,
        sha256: sha256(rendered),
        trafficSwitch: false,
      })}\n`,
    );
    return;
  }

  if (!options.manifest) fail("validate requires --manifest.");
  const manifestPath = path.isAbsolute(options.manifest)
    ? options.manifest
    : path.resolve(process.cwd(), options.manifest);
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  validatePlan(manifest);
  process.stdout.write(
    `${JSON.stringify({
      status: "valid",
      activeColor: manifest.activeColor,
      candidateColor: manifest.candidateColor,
      trafficSwitch: false,
      migration: false,
    })}\n`,
  );
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 2;
  });
}
