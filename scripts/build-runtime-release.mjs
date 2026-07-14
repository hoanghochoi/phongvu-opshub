import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { copyFile, mkdir, rm, stat, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import path from "node:path";
import process from "node:process";

const rootDir = process.cwd();
const outputDir = path.resolve(rootDir, "dist", "runtime-release");
const expectedOutputDir = path.join(
  path.resolve(rootDir, "dist"),
  "runtime-release",
);
const includeReviewedUntracked = process.argv.includes(
  "--include-untracked-reviewed",
);

// These tracked files are mounted read-only at /app/data for backend runtime
// lookups. Client-only assets and manual import sources stay outside the
// server artifact allowlist.
const RUNTIME_DATA_FILES = [
  "data/categories.csv",
  "data/email_domain.txt",
];

const REQUIRED_FILES = [
  "backend-nest/Dockerfile",
  "backend-nest/package.json",
  "backend-nest/package-lock.json",
  "backend-nest/prisma/schema.prisma",
  "backend-nest/src/main.ts",
  "backend-nest/src/auth/realtime-ticket.service.ts",
  "backend-nest/src/upload/private-media.service.ts",
  "backend-nest/prisma/migrations/20260712010000_add_private_media_objects/migration.sql",
  "backend-nest/scripts/migrate-private-media.mjs",
  "backend-nest/scripts/audit-legacy-upload-access.mjs",
  "backend-go/Dockerfile",
  "backend-go/go.mod",
  "backend-go/main.go",
  "backend-go/auth.go",
  "backend-go/audience.go",
  "backend-go/server.go",
  "deploy/home-server/Caddyfile",
  "deploy/home-server/docker-compose.home.yml",
  "docs/help/navigation.json",
  ...RUNTIME_DATA_FILES,
  "assets/icon/source/app_icon_master.png",
  "assets/icon/acare_logo.png",
  "fonts/SF-Pro-Display-Regular.otf",
  "fonts/SF-Pro-Display-Semibold.otf",
  "fonts/SF-Pro-Display-Bold.otf",
];

const EXACT_FILES = new Set([
  "backend-nest/Dockerfile",
  "backend-nest/package.json",
  "backend-nest/package-lock.json",
  "backend-nest/prisma.config.ts",
  "backend-nest/prisma/schema.prisma",
  "backend-nest/tsconfig.json",
  "backend-nest/tsconfig.build.json",
  "backend-nest/nest-cli.json",
  "backend-go/Dockerfile",
  "backend-go/go.mod",
  "backend-go/go.sum",
  "deploy/home-server/Caddyfile",
  "deploy/home-server/docker-compose.home.yml",
  "deploy/home-server/download.html",
  "deploy/home-server/backup.sh",
  ...RUNTIME_DATA_FILES,
  "assets/icon/source/app_icon_master.png",
  "assets/icon/acare_logo.png",
  "fonts/SF-Pro-Display-Regular.otf",
  "fonts/SF-Pro-Display-Semibold.otf",
  "fonts/SF-Pro-Display-Bold.otf",
]);

function isAllowed(file) {
  if (EXACT_FILES.has(file)) return true;
  if (file.startsWith("backend-nest/src/")) return !file.endsWith(".spec.ts");
  if (file.startsWith("backend-nest/prisma/migrations/")) {
    return file.endsWith("/migration.sql");
  }
  if (file.startsWith("backend-nest/scripts/")) return file.endsWith(".mjs");
  if (file.startsWith("backend-go/") && file.endsWith(".go")) {
    return !file.endsWith("_test.go");
  }
  return file.startsWith("docs/help/");
}

function assertSafeFile(file) {
  const lower = file.toLowerCase();
  const base = path.posix.basename(lower);
  if (
    base === ".env" ||
    base.startsWith(".env.") ||
    /\.(?:pem|key|pfx|p12|jks|keystore|xlsx|xls)$/i.test(base) ||
    /(?:service-account|credentials)(?:\.|$)/i.test(base)
  ) {
    throw new Error(`Refusing to package sensitive-looking file: ${file}`);
  }
}

async function sha256(filePath) {
  const { createReadStream } = await import("node:fs");
  return new Promise((resolve, reject) => {
    const hash = createHash("sha256");
    createReadStream(filePath)
      .on("error", reject)
      .on("data", (chunk) => hash.update(chunk))
      .on("end", () => resolve(hash.digest("hex")));
  });
}

async function main() {
  if (outputDir !== expectedOutputDir) {
    throw new Error(`Unexpected runtime release output path: ${outputDir}`);
  }

  const trackedFiles = execFileSync("git", ["ls-files", "-z"], {
    cwd: rootDir,
    encoding: "utf8",
  })
    .split("\0")
    .filter(Boolean)
    .map((file) => file.replaceAll("\\", "/"));
  const untrackedRuntimeFiles = execFileSync(
    "git",
    ["ls-files", "-z", "--others", "--exclude-standard"],
    { cwd: rootDir, encoding: "utf8" },
  )
    .split("\0")
    .filter(Boolean)
    .map((file) => file.replaceAll("\\", "/"))
    .filter(isAllowed)
    .filter((file) => existsSync(path.resolve(rootDir, ...file.split("/"))))
    .sort();
  if (untrackedRuntimeFiles.length > 0 && !includeReviewedUntracked) {
    throw new Error(
      `Refusing to build an incomplete release: ${untrackedRuntimeFiles.length} untracked runtime file(s) exist. Review and track them before CI, or use --include-untracked-reviewed only for an intentional local preview.`,
    );
  }

  const releaseFiles = [
    ...trackedFiles,
    ...(includeReviewedUntracked ? untrackedRuntimeFiles : []),
  ]
    .filter(isAllowed)
    .filter((file) => existsSync(path.resolve(rootDir, ...file.split("/"))))
    .filter((file, index, all) => all.indexOf(file) === index)
    .sort();
  const releaseFileSet = new Set(releaseFiles);

  for (const required of REQUIRED_FILES) {
    if (!releaseFileSet.has(required)) {
      throw new Error(
        `Runtime release is missing required tracked file: ${required}`,
      );
    }
  }

  await rm(outputDir, { recursive: true, force: true });
  const manifest = [];
  for (const file of releaseFiles) {
    assertSafeFile(file);
    const source = path.resolve(rootDir, ...file.split("/"));
    const destination = path.resolve(outputDir, ...file.split("/"));
    if (!destination.startsWith(`${outputDir}${path.sep}`)) {
      throw new Error(`Release path escaped the output directory: ${file}`);
    }
    const sourceStat = await stat(source);
    if (!sourceStat.isFile()) {
      throw new Error(`Runtime release entry is not a regular file: ${file}`);
    }
    await mkdir(path.dirname(destination), { recursive: true });
    await copyFile(source, destination);
    await (
      await import("node:fs/promises")
    ).chmod(destination, sourceStat.mode & 0o777);
    manifest.push({
      path: file,
      bytes: sourceStat.size,
      sha256: await sha256(source),
    });
  }

  const manifestPath = path.join(outputDir, "release-manifest.json");
  await writeFile(
    manifestPath,
    `${JSON.stringify(
      {
        schemaVersion: 1,
        includesReviewedUntracked: includeReviewedUntracked,
        sourceCommit: execFileSync("git", ["rev-parse", "HEAD"], {
          cwd: rootDir,
          encoding: "utf8",
        }).trim(),
        files: manifest,
      },
      null,
      2,
    )}\n`,
    { encoding: "utf8", mode: 0o644 },
  );

  const totalBytes = manifest.reduce((sum, item) => sum + item.bytes, 0);
  console.log(
    `Built reviewed runtime release: ${manifest.length} files, ${totalBytes} bytes`,
  );
}

await main();
