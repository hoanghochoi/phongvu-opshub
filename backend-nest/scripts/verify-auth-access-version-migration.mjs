import fs from 'node:fs';
import path from 'node:path';
import { Client } from 'pg';
import dotenv from 'dotenv';

dotenv.config();

const client = new Client({ connectionString: process.env.DATABASE_URL });
const schema = `opshub_auth_version_check_${Date.now()}`;
const query = (sql) => client.query(sql);

try {
  await client.connect();
  await query('BEGIN');
  await query(`CREATE SCHEMA "${schema}"`);
  await query(`SET LOCAL search_path TO "${schema}"`);
  await query(`
    CREATE TABLE "User" ("id" text PRIMARY KEY, "email" text, "firstName" text,
      "lastName" text, "avatarUrl" text, "status" text NOT NULL DEFAULT 'yes',
      "tokenVersion" int NOT NULL DEFAULT 0, "role" text, "storeId" text,
      "departmentCode" text, "jobRoleCode" text, "workScopeType" text,
      "regionCode" text, "areaCode" text, "organizationNodeId" text,
      "profileCompletedAt" timestamptz, "branchLockedAt" timestamptz);
    CREATE TABLE "OrganizationNode" ("id" text PRIMARY KEY, "parentId" text,
      "code" text, "displayName" text, "businessCode" text, "abbreviation" text,
      "type" text, "emailDomain" text, "loginAllowed" boolean,
      "sortOrder" int NOT NULL DEFAULT 0, "isActive" boolean NOT NULL DEFAULT true);
    CREATE TABLE "UserOrganizationAssignment" ("userId" text,
      "organizationNodeId" text, "isActive" boolean NOT NULL DEFAULT true);
    CREATE TABLE "UserFeatureAssignment" ("userId" text);
    CREATE TABLE "UserPlatformSession" ("userId" text, "sessionVersion" int,
      "revokedAt" timestamptz, "expiresAt" timestamptz);
    CREATE TABLE "FeatureDefinition" ("code" text, "parentCode" text,
      "isActive" boolean NOT NULL DEFAULT true);
    CREATE TABLE "FeatureAccessRule" ("id" text);
    CREATE TABLE "OrganizationNodeFeatureAssignment" ("scopeRootNodeId" text);
    CREATE TABLE "AdminPolicyDefinition" ("code" text, "defaultAllowed" boolean,
      "isActive" boolean NOT NULL DEFAULT true);
    CREATE TABLE "AdminPolicyRule" ("organizationNodeId" text);
    CREATE TABLE "Store" ("storeId" text, "storeName" text, "areaCode" text,
      "organizationNodeId" text);
    CREATE TABLE "DepartmentDefinition" ("code" text, "displayName" text,
      "organizationNodeId" text, "isActive" boolean NOT NULL DEFAULT true);
    CREATE TABLE "JobRoleDefinition" ("code" text, "displayName" text,
      "departmentCode" text, "organizationNodeId" text,
      "isActive" boolean NOT NULL DEFAULT true);
    CREATE TABLE "RegionDefinition" ("code" text, "displayName" text,
      "abbreviation" text, "organizationNodeId" text,
      "isActive" boolean NOT NULL DEFAULT true);
    CREATE TABLE "AreaDefinition" ("code" text, "displayName" text,
      "abbreviation" text, "regionCode" text, "organizationNodeId" text,
      "isActive" boolean NOT NULL DEFAULT true);
  `);

  const migrationPath = path.resolve(
    process.cwd(),
    'prisma/migrations/20260716170000_user_access_version/migration.sql',
  );
  await query(fs.readFileSync(migrationPath, 'utf8'));

  await query(`
    INSERT INTO "User" ("id", "email", "firstName")
      VALUES ('u1', 'u1@test', 'One'), ('u2', 'u2@test', 'Two');
    INSERT INTO "OrganizationNode" ("id", "code", "displayName", "type")
      VALUES ('root', 'ROOT', 'Root', 'ROOT'),
             ('child', 'CHILD', 'Child', 'STORE');
    UPDATE "OrganizationNode" SET "parentId" = 'root' WHERE "id" = 'child';
    INSERT INTO "UserOrganizationAssignment" ("userId", "organizationNodeId")
      VALUES ('u1', 'child'), ('u2', 'root');
    INSERT INTO "FeatureDefinition" ("code", "isActive") VALUES ('HOME', true);
    UPDATE "User" SET "accessVersion" = 0;
  `);

  await query(
    `INSERT INTO "AdminPolicyRule" ("organizationNodeId") VALUES ('root')`,
  );
  let rows = (
    await query(`SELECT "id", "accessVersion" FROM "User" ORDER BY "id"`)
  ).rows;
  if (rows.some((row) => row.accessVersion !== 1)) {
    throw new Error(`subtree trigger mismatch: ${JSON.stringify(rows)}`);
  }

  await query(
    `UPDATE "FeatureDefinition" SET "isActive" = true WHERE "code" = 'HOME'`,
  );
  rows = (await query(`SELECT "id", "accessVersion" FROM "User" ORDER BY "id"`))
    .rows;
  if (rows.some((row) => row.accessVersion !== 1)) {
    throw new Error(`no-op seed caused a bump: ${JSON.stringify(rows)}`);
  }

  await query(
    `UPDATE "FeatureDefinition" SET "isActive" = false WHERE "code" = 'HOME'`,
  );
  rows = (await query(`SELECT "id", "accessVersion" FROM "User" ORDER BY "id"`))
    .rows;
  if (rows.some((row) => row.accessVersion !== 2)) {
    throw new Error(`broad trigger mismatch: ${JSON.stringify(rows)}`);
  }

  await query(`
    INSERT INTO "UserPlatformSession" ("userId", "sessionVersion", "expiresAt")
      VALUES ('u1', 1, now() + interval '1 day')
  `);
  rows = (await query(`SELECT "id", "accessVersion" FROM "User" ORDER BY "id"`))
    .rows;
  if (rows[0].accessVersion !== 3 || rows[1].accessVersion !== 2) {
    throw new Error(`session trigger mismatch: ${JSON.stringify(rows)}`);
  }

  await query('SAVEPOINT rollback_check');
  await query(`UPDATE "User" SET "firstName" = 'Changed' WHERE "id" = 'u1'`);
  await query('ROLLBACK TO SAVEPOINT rollback_check');
  const rolledBack = await query(
    `SELECT "accessVersion" FROM "User" WHERE "id" = 'u1'`,
  );
  if (rolledBack.rows[0].accessVersion !== 3) {
    throw new Error('profile-trigger increment escaped the source rollback');
  }

  await query('ROLLBACK');
  console.log(
    JSON.stringify({
      migrationSql: 'ok',
      subtreeTrigger: 'ok',
      broadTrigger: 'ok',
      sessionTrigger: 'ok',
      noOpSeed: 'ok',
      rollback: 'ok',
    }),
  );
} catch (error) {
  try {
    await query('ROLLBACK');
  } catch {}
  console.error(error?.stack || String(error));
  process.exitCode = 1;
} finally {
  await client.end();
}
