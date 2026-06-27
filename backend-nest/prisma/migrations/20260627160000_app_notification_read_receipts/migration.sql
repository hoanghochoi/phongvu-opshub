CREATE TABLE "AppNotificationReadReceipt" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "source" TEXT NOT NULL,
  "notificationId" TEXT NOT NULL,
  "readAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "AppNotificationReadReceipt_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "AppNotificationReadReceipt_userId_source_notificationId_key"
  ON "AppNotificationReadReceipt"("userId", "source", "notificationId");

CREATE INDEX "AppNotificationReadReceipt_source_notificationId_idx"
  ON "AppNotificationReadReceipt"("source", "notificationId");

CREATE INDEX "AppNotificationReadReceipt_userId_readAt_idx"
  ON "AppNotificationReadReceipt"("userId", "readAt");

ALTER TABLE "AppNotificationReadReceipt"
  ADD CONSTRAINT "AppNotificationReadReceipt_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
