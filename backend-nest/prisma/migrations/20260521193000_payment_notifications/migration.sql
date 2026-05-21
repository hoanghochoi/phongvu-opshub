CREATE TABLE "PaymentNotification" (
  "id" TEXT NOT NULL,
  "storeCode" TEXT NOT NULL,
  "transactionId" TEXT NOT NULL,
  "text" TEXT NOT NULL,
  "amount" INTEGER NOT NULL,
  "audioStatus" TEXT NOT NULL DEFAULT 'PENDING',
  "audioPath" TEXT,
  "audioMime" TEXT,
  "audioError" TEXT,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "PaymentNotification_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "PaymentNotificationDeliveryLog" (
  "id" TEXT NOT NULL,
  "notificationId" TEXT NOT NULL,
  "transactionId" TEXT,
  "storeCode" TEXT NOT NULL,
  "userId" TEXT,
  "clientId" TEXT,
  "event" TEXT NOT NULL,
  "error" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "PaymentNotificationDeliveryLog_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "AppLog" (
  "id" TEXT NOT NULL,
  "level" TEXT NOT NULL,
  "source" TEXT NOT NULL,
  "message" TEXT NOT NULL,
  "userId" TEXT,
  "clientId" TEXT,
  "storeCode" TEXT,
  "context" JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "AppLog_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "PaymentNotification_transactionId_key"
  ON "PaymentNotification"("transactionId");

CREATE INDEX "PaymentNotification_storeCode_createdAt_idx"
  ON "PaymentNotification"("storeCode", "createdAt");

CREATE INDEX "PaymentNotification_expiresAt_idx"
  ON "PaymentNotification"("expiresAt");

CREATE INDEX "PaymentNotificationDeliveryLog_notificationId_createdAt_idx"
  ON "PaymentNotificationDeliveryLog"("notificationId", "createdAt");

CREATE INDEX "PaymentNotificationDeliveryLog_storeCode_createdAt_idx"
  ON "PaymentNotificationDeliveryLog"("storeCode", "createdAt");

CREATE INDEX "PaymentNotificationDeliveryLog_createdAt_idx"
  ON "PaymentNotificationDeliveryLog"("createdAt");

CREATE INDEX "AppLog_createdAt_idx" ON "AppLog"("createdAt");

CREATE INDEX "AppLog_source_createdAt_idx" ON "AppLog"("source", "createdAt");

CREATE INDEX "AppLog_storeCode_createdAt_idx"
  ON "AppLog"("storeCode", "createdAt");
