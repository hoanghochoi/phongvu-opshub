import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);
const installerPath = path.join(
  repositoryRoot,
  "deploy",
  "staging",
  "install-cloudflare-api-tunnel.sh",
);
const source = readFileSync(installerPath, "utf8");
const bash =
  process.platform === "win32"
    ? path.join(process.env.ProgramFiles, "Git", "bin", "bash.exe")
    : "bash";

test("API-only tunnel installer has valid Bash syntax", () => {
  const result = spawnSync(bash, ["-n", installerPath], {
    encoding: "utf8",
  });

  assert.equal(result.status, 0, result.stderr);
});

test("API-only tunnel installer fails closed without both approvals", () => {
  const result = spawnSync(bash, [installerPath], {
    encoding: "utf8",
    env: {
      ...process.env,
      CLOUDFLARED_API_TUNNEL_APPROVAL: "",
      CLOUDFLARED_ROUTE_DNS: "",
    },
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /CLOUDFLARED_API_TUNNEL_APPROVAL must equal/);
});

test("API-only tunnel uses isolated deterministic identities", () => {
  assert.match(source, /SERVICE_NAME="cloudflared-opshub-staging-api"/);
  assert.match(source, /TUNNEL_NAME="opshub-staging-api"/);
  assert.match(
    source,
    /TUNNEL_HOSTNAME="api-opshub-staging\.hoanghochoi\.com"/,
  );
  assert.match(source, /METRICS_ADDRESS="127\.0\.0\.1:20243"/);
  assert.match(source, /tunnel must not reuse the protected current tunnel/);
});

test("API-only ingress allows only API paths and rejects the fallback", () => {
  assert.match(source, /path: "\^\/api\/\.\*\$"/);
  assert.match(source, /service: "http_status:404"/);
  assert.match(source, /httpHostHeader: "\$ORIGIN_HOST_HEADER"/);
  assert.match(source, /ORIGIN_HOST_HEADER="opshub-staging\.hoanghochoi\.com"/);
  assert.match(source, /tunnel --config "\$config_tmp" ingress validate/);
});

test("credentials and local configuration remain root-only", () => {
  assert.match(
    source,
    /install -m 0600 -o root -g root "\$source_credential" "\$CREDENTIAL_FILE"/,
  );
  assert.match(
    source,
    /install -m 0600 -o root -g root "\$config_tmp" "\$CONFIG_FILE"/,
  );
  assert.doesNotMatch(source, /cat .*credentials\.json/);
  assert.doesNotMatch(source, /tunnel token/);
});

test("DNS publication happens only after local validation and service start", () => {
  const localValidation = source.indexOf(
    'tunnel --config "$config_tmp" ingress validate',
  );
  const serviceStart = source.indexOf('systemctl restart "$SERVICE_NAME"');
  const dnsPublication = source.indexOf("tunnel route dns");

  assert.ok(localValidation >= 0);
  assert.ok(serviceStart > localValidation);
  assert.ok(dnsPublication > serviceStart);
});
