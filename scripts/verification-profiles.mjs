import path from 'node:path';

/**
 * Repository verification profiles.
 *
 * Keep commands structured so the runner can report exactly what it executed
 * and can fingerprint the command contract before and after the proof.
 */
export const PROFILES = Object.freeze([
  {
    id: 'harness',
    pathPatterns: [
      /^AGENTS\.md$/,
      /^\.agents\//,
      /^\.harness\//,
      /^\.gitignore$/,
      /^docs\/(?:WORKFLOW|README|FEATURE_INTAKE|TEST_MATRIX)\.md$/,
      /^scripts\/README\.md$/,
      /^docs\/(?:contracts|decisions|migrations|plans|templates)\//,
      /^scripts\/(?:adapter|schema)\//,
      /^\.gitattributes$/,
      /^scripts\/bootstrap-harness\.(?:ps1|sh)$/,
      /^scripts\/bin\/harness(?:-cli)?\.exe\.sha256$/,
      /^tests\/(?:README\.md|(?:bootstrap|fixtures|workflow)\/)/,
      /^scripts\/(?:agent-harness-block|archive-harness|build-harness|collect-(?:harness|artifact-inventory|ops72-shadow-metrics)|harness(?:-|$)|install-harness|materialize-core-state|promote-harness|review-harness-disposition|task-lifecycle|test-task-lifecycle|verify-(?:artifact-inventory|core|harness|materialized|ops72-live-shadow-evidence|plan-disposition|revision)|validate-changeset-rebuild)/,
      /^tests\/(?:adapter|boundary|changesets|ci|coherence|core|protocol|snapshot|worktrees)\//,
      /^tests\/docs\/test-doc-contracts\.sh$/,
      /^tests\/migration\//,
      /^tests\/(?:installer|maintenance|migration|verification)\//,
      /^\.github\/workflows\/(?:post-merge-maintenance|release-guard-pr)/,
    ],
    consumers: [
      'repository-harness-adoption',
      'task-lifecycle-and-affected-consumer-proof',
    ],
    prerequisites: ['git repository', 'Node.js'],
    commands: [
      {
        id: 'git-diff-check',
        cwd: '.',
        executable: 'git',
        argv: ['diff', '--check'],
      },
    ],
  },
  {
    id: 'docs',
    pathPatterns: [
      /^README(?:-backend)?\.md$/,
      /^docs\//,
      /^app-.*\.md$/,
      /^ui-ux\.md$/,
    ],
    consumers: ['repository documentation', 'product and release authority'],
    prerequisites: ['Git', 'Node.js'],
    commands: [
      {
        id: 'docs-diff-check',
        cwd: '.',
        executable: 'git',
        argv: ['diff', '--check'],
      },
    ],
  },
  {
    id: 'verification-runner',
    pathPatterns: [/^scripts\/verify-task(?:-(?:canary|shadow))?\.mjs$/, /^scripts\/verification-profiles\.mjs$/, /^tests\/verification\//],
    consumers: ['generic-verification-runner', 'affected-consumer-orchestrator'],
    prerequisites: ['Node.js', 'Git'],
    commands: [
      {
        id: 'runner-syntax',
        cwd: '.',
        executable: process.execPath,
        argv: ['--check', 'scripts/verify-task.mjs'],
      },
    ],
  },
  {
    id: 'release',
    pathPatterns: [
      /^\.github\/workflows\//,
      /^docs\/runbooks\/git-release-playbook\.md$/,
      /^scripts\/(?:task-lifecycle|test-git-release-workflow|validate-premerge|validate-release|release-guard)/,
      /^tests\/release\//,
    ],
    consumers: ['task lifecycle', 'staging release gates', 'production promotion guards'],
    prerequisites: ['Git', 'Node.js'],
    commands: [
      {
        id: 'release-diff-check',
        cwd: '.',
        executable: 'git',
        argv: ['diff', '--check'],
      },
    ],
  },
  {
    id: 'flutter',
    pathPatterns: [
      /^lib\//,
      /^test\//,
      /^pubspec(?:\.yaml|\.lock)$/,
      /^(?:android|ios|linux|macos|web|windows)\//,
    ],
    consumers: ['Flutter app', 'Flutter widget/unit/integration tests'],
    prerequisites: ['Flutter SDK', 'pub dependencies'],
    commands: [
      {
        id: 'flutter-analyze',
        cwd: '.',
        executable: process.platform === 'win32' ? 'flutter.bat' : 'flutter',
        argv: ['analyze', '--no-pub'],
      },
    ],
  },
  {
    id: 'nestjs',
    pathPatterns: [/^backend-nest\//],
    consumers: ['NestJS API', 'Flutter API repositories'],
    prerequisites: ['Node.js', 'backend-nest dependencies'],
    commands: [
      {
        id: 'nestjs-build',
        cwd: 'backend-nest',
        executable: process.platform === 'win32' ? 'npm.cmd' : 'npm',
        argv: ['run', 'build'],
      },
    ],
  },
  {
    id: 'go-realtime',
    pathPatterns: [/^backend-go\//],
    consumers: ['Go realtime service', 'Flutter realtime clients'],
    prerequisites: ['Go toolchain'],
    commands: [
      {
        id: 'go-test',
        cwd: 'backend-go',
        executable: 'go',
        argv: ['test', './...'],
      },
    ],
  },
  {
    id: 'deployment',
    pathPatterns: [
      /^deploy\//,
      /^docker-compose\.yml$/,
      /^scripts\/(?:validate-ops39-caddy|verify-platform-security)\.mjs$/,
    ],
    consumers: ['deployment manifests', 'runtime configuration'],
    prerequisites: ['deployment tooling'],
    commands: [
      {
        id: 'deployment-whitespace',
        cwd: '.',
        executable: 'git',
        argv: ['diff', '--check'],
      },
      {
        id: 'ops39-caddy-contract',
        cwd: '.',
        executable: process.execPath,
        argv: ['scripts/validate-ops39-caddy.mjs'],
      },
      {
        id: 'platform-security-contract',
        cwd: '.',
        executable: process.execPath,
        argv: ['scripts/verify-platform-security.mjs'],
      },
    ],
  },
]);

export const FULL_PROFILE_ID = 'full';

export function profileById(id) {
  return PROFILES.find((profile) => profile.id === id) ?? null;
}

export function matchProfiles(changedPaths, requested = []) {
  const auto = PROFILES.filter((profile) =>
    changedPaths.some((changedPath) =>
      profile.pathPatterns.some((pattern) => pattern.test(changedPath)),
    ),
  );
  const explicit = requested.map((id) => {
    const profile = profileById(id);
    if (!profile) throw new Error(`Unknown verification profile: ${id}`);
    return profile;
  });
  const selected = new Map(auto.map((profile) => [profile.id, profile]));
  for (const profile of explicit) selected.set(profile.id, profile);
  return [...selected.values()];
}

export function allProfiles() {
  return [...PROFILES];
}

export function resolveCommandCwd(root, command) {
  return path.resolve(root, command.cwd || '.');
}
