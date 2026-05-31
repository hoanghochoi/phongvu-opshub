-- Track one active authenticated device session per user/platform.
CREATE TABLE "UserPlatformSession" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "platform" TEXT NOT NULL,
    "sessionVersion" INTEGER NOT NULL DEFAULT 1,
    "deviceIdHash" TEXT NOT NULL,
    "deviceLabel" TEXT,
    "appVersion" TEXT,
    "buildNumber" TEXT,
    "lastLoginAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "revokedAt" TIMESTAMP(3),
    "revokedReason" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "UserPlatformSession_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "UserPlatformSession_userId_platform_key" ON "UserPlatformSession"("userId", "platform");
CREATE INDEX "UserPlatformSession_userId_idx" ON "UserPlatformSession"("userId");
CREATE INDEX "UserPlatformSession_platform_idx" ON "UserPlatformSession"("platform");
CREATE INDEX "UserPlatformSession_expiresAt_idx" ON "UserPlatformSession"("expiresAt");
CREATE INDEX "UserPlatformSession_revokedAt_idx" ON "UserPlatformSession"("revokedAt");

ALTER TABLE "UserPlatformSession" ADD CONSTRAINT "UserPlatformSession_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
