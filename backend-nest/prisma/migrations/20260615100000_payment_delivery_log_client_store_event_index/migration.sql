-- Improve payment speaker ready-claim lookups by client, store, and event.
CREATE INDEX "PaymentDeliveryLog_client_store_event_createdAt_idx"
ON "PaymentNotificationDeliveryLog"("clientId", "storeCode", "event", "createdAt");
