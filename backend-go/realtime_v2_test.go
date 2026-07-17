package main

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"github.com/redis/go-redis/v9"
)

func TestAuthenticatedRedisChannelsProduceStrictV2Envelopes(t *testing.T) {
	tests := []struct {
		name        string
		channel     string
		payload     string
		kind        string
		topic       string
		dataField   string
		dataValue   string
		expectedID  string
		expectedTS  string
		matching    *ClientAuth
		nonMatching *ClientAuth
	}{
		{
			name:        "access changed",
			channel:     accessChangedRedisChannel,
			payload:     versionedTestEvent(accessChangedEventType, `{"recipientUserIds":["user-1"]}`, `{"reason":"feature-assignment-updated"}`),
			kind:        accessChangedEventType,
			topic:       accessChangedTopic,
			dataField:   "reason",
			dataValue:   "feature-assignment-updated",
			expectedID:  "event-1",
			expectedTS:  "2026-07-15T01:02:03Z",
			matching:    &ClientAuth{UserID: "user-1"},
			nonMatching: &ClientAuth{UserID: "user-2"},
		},
		{
			name:       "warranty versioned",
			channel:    warrantyRedisChannel,
			payload:    versionedTestEvent(warrantyEventType, `{"storeCodes":["CP01"],"featureCodes":["WARRANTY"]}`, `{"warrantyId":"w-1","newStatus":"DONE"}`),
			kind:       warrantyEventType,
			topic:      warrantyTopic,
			dataField:  "warrantyId",
			dataValue:  "w-1",
			expectedID: "event-1",
			expectedTS: "2026-07-15T01:02:03Z",
			matching:   &ClientAuth{StoreCode: "CP01", FeatureCodes: []string{"WARRANTY"}},
			nonMatching: &ClientAuth{
				StoreCode:    "CP02",
				FeatureCodes: []string{"WARRANTY"},
			},
		},
		{
			name:        "payment transaction",
			channel:     paymentRedisChannel,
			payload:     `{"storeCode":"CP01","notificationId":"payment-1","createdAt":"2026-07-15T01:02:03Z"}`,
			kind:        paymentEventType,
			topic:       paymentTopic,
			dataField:   "notificationId",
			dataValue:   "payment-1",
			matching:    &ClientAuth{StoreCode: "CP01"},
			nonMatching: &ClientAuth{StoreCode: "CP02"},
		},
		{
			name:        "payment speaker",
			channel:     paymentStreamRedisChannel,
			payload:     `{"storeCode":"CP01","notificationId":"speaker-1","createdAt":"2026-07-15T01:02:03Z"}`,
			kind:        paymentStreamEventType,
			topic:       paymentStreamTopic,
			dataField:   "notificationId",
			dataValue:   "speaker-1",
			matching:    &ClientAuth{StoreCode: "CP01"},
			nonMatching: &ClientAuth{StoreCode: "CP02"},
		},
		{
			name:        "payment delivery metrics",
			channel:     paymentDeliveryMetricsRedisChannel,
			payload:     versionedTestEvent(paymentDeliveryMetricsEventType, `{"roles":["SUPER_ADMIN"]}`, `{"version":172101,"reason":"delivery-state-changed"}`),
			kind:        paymentDeliveryMetricsEventType,
			topic:       paymentDeliveryMetricsTopic,
			dataField:   "reason",
			dataValue:   "delivery-state-changed",
			expectedID:  "event-1",
			expectedTS:  "2026-07-15T01:02:03Z",
			matching:    &ClientAuth{Role: "SUPER_ADMIN"},
			nonMatching: &ClientAuth{Role: "MANAGER"},
		},
		{
			name:        "statement transfer",
			channel:     statementOrderTransferRedisChannel,
			payload:     `{"storeCode":"CP01","requestId":"request-1","createdAt":"2026-07-15T01:02:03Z"}`,
			kind:        statementOrderTransferEventType,
			topic:       statementOrderTransferTopic,
			dataField:   "requestId",
			dataValue:   "request-1",
			matching:    &ClientAuth{StoreCode: "CP01"},
			nonMatching: &ClientAuth{StoreCode: "CP02"},
		},
		{
			name:        "offset adjustment",
			channel:     offsetAdjustmentRedisChannel,
			payload:     `{"storeCode":"CP01","adjustmentId":"offset-1","updatedAt":"2026-07-15T01:02:03Z"}`,
			kind:        offsetAdjustmentEventType,
			topic:       offsetAdjustmentTopic,
			dataField:   "adjustmentId",
			dataValue:   "offset-1",
			matching:    &ClientAuth{DepartmentCode: "FIN_ACC"},
			nonMatching: &ClientAuth{StoreCode: "CP02"},
		},
		{
			name:        "sales report orders",
			channel:     salesReportOrdersRedisChannel,
			payload:     `{"storeCodes":["CP01"],"recipientUserIds":["user-1"],"source":"ERP"}`,
			kind:        salesReportOrdersEventType,
			topic:       salesReportOrdersTopic,
			dataField:   "source",
			dataValue:   "ERP",
			matching:    &ClientAuth{UserID: "user-1"},
			nonMatching: &ClientAuth{StoreCode: "CP02"},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			events, ok := formatRedisEvents(test.channel, test.payload)
			if !ok || len(events) != 2 {
				t.Fatalf("expected legacy and v2 routes, ok=%t count=%d", ok, len(events))
			}
			legacy, v2 := events[0], events[1]
			if legacy.ProtocolVersion != webSocketProtocolV1 || v2.ProtocolVersion != webSocketProtocolV2 {
				t.Fatalf("unexpected protocol routes legacy=%d v2=%d", legacy.ProtocolVersion, v2.ProtocolVersion)
			}
			if !(&Client{auth: test.matching, protocolVersion: webSocketProtocolV1}).canReceive(legacy) {
				t.Fatal("matching legacy client was rejected")
			}
			if (&Client{auth: test.matching, protocolVersion: webSocketProtocolV1}).canReceive(v2) {
				t.Fatal("legacy client received v2 event")
			}
			if !(&Client{auth: test.matching, protocolVersion: webSocketProtocolV2}).canReceive(v2) {
				t.Fatal("matching v2 client was rejected")
			}
			if (&Client{auth: test.nonMatching, protocolVersion: webSocketProtocolV2}).canReceive(v2) {
				t.Fatal("non-matching v2 client received sensitive event")
			}

			var envelope struct {
				Version int            `json:"v"`
				Kind    string         `json:"kind"`
				ID      string         `json:"id"`
				Topic   string         `json:"topic"`
				Seq     int64          `json:"seq"`
				TS      string         `json:"ts"`
				Data    map[string]any `json:"data"`
			}
			if err := json.Unmarshal(v2.Message, &envelope); err != nil {
				t.Fatal(err)
			}
			if envelope.Version != webSocketProtocolV2 || envelope.Kind != test.kind || envelope.Topic != test.topic {
				t.Fatalf("unexpected v2 contract: %s", v2.Message)
			}
			if envelope.ID == "" || len(envelope.ID) > 128 || envelope.Seq <= 0 {
				t.Fatalf("missing stable v2 identity: %s", v2.Message)
			}
			if _, err := time.Parse(time.RFC3339Nano, envelope.TS); err != nil {
				t.Fatalf("invalid v2 timestamp %q: %v", envelope.TS, err)
			}
			if test.expectedID != "" && envelope.ID != test.expectedID {
				t.Fatalf("expected id %q, got %q", test.expectedID, envelope.ID)
			}
			if test.expectedTS != "" && envelope.TS != test.expectedTS {
				t.Fatalf("expected timestamp %q, got %q", test.expectedTS, envelope.TS)
			}
			if envelope.Data[test.dataField] != test.dataValue {
				t.Fatalf("sanitized payload was not preserved: %s", v2.Message)
			}
			var clientObject map[string]json.RawMessage
			if err := json.Unmarshal(v2.Message, &clientObject); err != nil {
				t.Fatal(err)
			}
			if _, exposed := clientObject["audience"]; exposed {
				t.Fatalf("audience leaked to client: %s", v2.Message)
			}
		})
	}
}

func TestQuickActionLinkUpdatesAreScopedAndV2Only(t *testing.T) {
	payload := versionedTestEvent(
		quickActionLinksEventType,
		`{"storeCodes":["CP75"],"featureCodes":["QUICK_ACTIONS"]}`,
		`{"storeCode":"CP75","actionCodes":["APP_DOWNLOAD"],"configuredCount":1}`,
	)
	events, ok := formatRedisEvents(quickActionLinksRedisChannel, payload)
	if !ok || len(events) != 1 {
		t.Fatalf("expected one v2-only route, ok=%t count=%d", ok, len(events))
	}
	event := events[0]
	if event.ProtocolVersion != webSocketProtocolV2 || event.Type != quickActionLinksEventType {
		t.Fatalf("unexpected route metadata: %+v", event)
	}
	matching := &Client{auth: &ClientAuth{
		StoreCode:    "CP75",
		FeatureCodes: []string{"QUICK_ACTIONS"},
	}, protocolVersion: webSocketProtocolV2}
	if !matching.canReceive(event) {
		t.Fatal("matching Quick Actions client was rejected")
	}
	nonMatching := &Client{auth: &ClientAuth{
		StoreCode:    "CP01",
		FeatureCodes: []string{"QUICK_ACTIONS"},
	}, protocolVersion: webSocketProtocolV2}
	if nonMatching.canReceive(event) {
		t.Fatal("out-of-scope Quick Actions client received the event")
	}
	superAdmin := &Client{auth: &ClientAuth{
		Role:         "SUPER_ADMIN",
		FeatureCodes: []string{"QUICK_ACTIONS"},
	}, protocolVersion: webSocketProtocolV2}
	if !superAdmin.canReceive(event) {
		t.Fatal("Super Admin Quick Actions client was rejected")
	}
	missingFeature := &Client{auth: &ClientAuth{
		StoreCode: "CP75",
	}, protocolVersion: webSocketProtocolV2}
	if missingFeature.canReceive(event) {
		t.Fatal("client without QUICK_ACTIONS received the event")
	}
	if !strings.Contains(string(event.Message), `"topic":"quick-actions.links"`) ||
		!strings.Contains(string(event.Message), `"storeCode":"CP75"`) {
		t.Fatalf("unexpected Quick Actions v2 envelope: %s", event.Message)
	}
}

func TestRedisBridgeBroadcastsLegacyAndV2Routes(t *testing.T) {
	hub := newHub(testLogger(), 2)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go hub.run(ctx)

	v1 := &Client{
		auth:            &ClientAuth{StoreCode: "CP01"},
		protocolVersion: webSocketProtocolV1,
		send:            make(chan []byte, 1),
	}
	v2 := &Client{
		auth:            &ClientAuth{StoreCode: "CP01"},
		protocolVersion: webSocketProtocolV2,
		send:            make(chan []byte, 1),
	}
	hub.register <- v1
	hub.register <- v2
	waitForClientCount(t, hub, 2)

	if !handleRedisMessage(
		ctx,
		&redisReadiness{},
		nil,
		hub,
		testLogger(),
		&redis.Message{
			Channel: paymentRedisChannel,
			Payload: `{"storeCode":"CP01","notificationId":"payment-1","createdAt":"2026-07-15T01:02:03Z"}`,
		},
	) {
		t.Fatal("expected Redis bridge to stay active")
	}

	select {
	case message := <-v1.send:
		if !strings.Contains(string(message), `"type":"PAYMENT_NOTIFICATION"`) {
			t.Fatalf("unexpected legacy message %s", message)
		}
	case <-time.After(time.Second):
		t.Fatal("legacy client did not receive event")
	}
	select {
	case message := <-v2.send:
		if !strings.Contains(string(message), `"topic":"payment.transactions"`) {
			t.Fatalf("unexpected v2 message %s", message)
		}
	case <-time.After(time.Second):
		t.Fatal("v2 client did not receive event")
	}
}

func TestV2SensitiveEventsRejectMissingOrInvalidAudience(t *testing.T) {
	tests := []struct {
		name    string
		channel string
		payload string
	}{
		{"missing versioned audience", warrantyRedisChannel, `{"schemaVersion":1,"type":"WARRANTY_EVENT","eventId":"event-1","occurredAt":"2026-07-15T01:02:03Z","payload":{"warrantyId":"w-1"}}`},
		{"empty versioned audience", warrantyRedisChannel, versionedTestEvent(warrantyEventType, `{}`, `{"warrantyId":"w-1"}`)},
		{"feature-only versioned audience", paymentRedisChannel, versionedTestEvent(paymentEventType, `{"featureCodes":["PAYMENT_MONITOR"]}`, `{"notificationId":"payment-1"}`)},
		{"invalid versioned timestamp", warrantyRedisChannel, strings.Replace(versionedTestEvent(warrantyEventType, `{"storeCodes":["CP01"]}`, `{"warrantyId":"w-1"}`), "2026-07-15T01:02:03Z", "invalid", 1)},
		{"wrong versioned kind", warrantyRedisChannel, versionedTestEvent(paymentEventType, `{"storeCodes":["CP01"]}`, `{"warrantyId":"w-1"}`)},
		{"unknown envelope field", warrantyRedisChannel, strings.Replace(versionedTestEvent(warrantyEventType, `{"storeCodes":["CP01"]}`, `{"warrantyId":"w-1"}`), `"payload":`, `"extra":true,"payload":`, 1)},
		{"legacy warranty no scope", warrantyRedisChannel, `{"warrantyId":"w-1"}`},
		{"legacy payment no scope", paymentRedisChannel, `{"notificationId":"payment-1"}`},
		{"legacy speaker no scope", paymentStreamRedisChannel, `{"notificationId":"speaker-1"}`},
		{"legacy delivery metrics no scope", paymentDeliveryMetricsRedisChannel, `{"version":172101}`},
		{"legacy statement no scope", statementOrderTransferRedisChannel, `{"requestId":"request-1"}`},
		{"legacy offset no scope", offsetAdjustmentRedisChannel, `{"adjustmentId":"offset-1"}`},
		{"legacy sales no scope", salesReportOrdersRedisChannel, `{"source":"ERP"}`},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if events, ok := formatRedisEvents(test.channel, test.payload); ok {
				t.Fatalf("expected sensitive event to fail closed, got %+v", events)
			}
		})
	}
}

func TestAccessChangedDeliversThenDisconnectsOnlyMatchingRecipient(t *testing.T) {
	hub := newHub(testLogger(), 2)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go hub.run(ctx)

	matching := &Client{
		auth:            &ClientAuth{UserID: "user-1", FeatureCodes: []string{"WARRANTY"}},
		protocolVersion: webSocketProtocolV2,
		send:            make(chan []byte, 2),
	}
	other := &Client{
		auth:            &ClientAuth{UserID: "user-2", FeatureCodes: []string{"WARRANTY"}},
		protocolVersion: webSocketProtocolV2,
		send:            make(chan []byte, 2),
	}
	hub.register <- matching
	hub.register <- other
	waitForClientCount(t, hub, 2)

	events, ok := formatRedisEvents(
		accessChangedRedisChannel,
		versionedTestEvent(
			accessChangedEventType,
			`{"recipientUserIds":["user-1"]}`,
			`{"reason":"feature-assignment-updated"}`,
		),
	)
	if !ok || len(events) != 2 {
		t.Fatalf("expected legacy and v2 access routes, ok=%t count=%d", ok, len(events))
	}
	hub.broadcast <- events[1]

	select {
	case message, open := <-matching.send:
		if !open || !strings.Contains(string(message), `"topic":"access.changed"`) {
			t.Fatalf("matching recipient did not receive access invalidation: %s", message)
		}
	case <-time.After(time.Second):
		t.Fatal("matching recipient did not receive access invalidation")
	}
	waitForClientCount(t, hub, 1)
	if matching.closeCode != websocket.CloseServiceRestart || matching.closeReason != "resync_required" {
		t.Fatalf("expected retryable entitlement resync close, code=%d reason=%q", matching.closeCode, matching.closeReason)
	}
	select {
	case _, open := <-matching.send:
		if open {
			t.Fatal("matching recipient channel remained open after access invalidation")
		}
	case <-time.After(time.Second):
		t.Fatal("matching recipient was not disconnected after access invalidation")
	}
	select {
	case message := <-other.send:
		t.Fatalf("unrelated recipient received access invalidation: %s", message)
	default:
	}
	if other.closeCode != 0 {
		t.Fatalf("unrelated recipient was disconnected with code=%d", other.closeCode)
	}

	hub.unregister <- other
	waitForClientCount(t, hub, 0)
}

func TestPublicAppUpdateIsIsolatedFromAuthenticatedV2(t *testing.T) {
	events, ok := formatRedisEvents(appVersionRedisChannel, `{"schemaVersion":1}`)
	if !ok || len(events) != 1 {
		t.Fatalf("expected one public legacy event, ok=%t count=%d", ok, len(events))
	}
	event := events[0]
	if !event.Public || event.ProtocolVersion != webSocketProtocolV1 {
		t.Fatalf("unexpected public event metadata %+v", event)
	}
	if !(&Client{updatesOnly: true}).canReceive(event) {
		t.Fatal("public app-update socket did not receive app update")
	}
	if (&Client{auth: &ClientAuth{UserID: "user-1"}, protocolVersion: webSocketProtocolV1}).canReceive(event) {
		t.Fatal("authenticated legacy socket received public app update")
	}
	if (&Client{auth: &ClientAuth{UserID: "user-1"}, protocolVersion: webSocketProtocolV2}).canReceive(event) {
		t.Fatal("authenticated v2 socket received public app update")
	}

	sensitive, ok := formatRedisEvents(paymentRedisChannel, `{"storeCode":"CP01","notificationId":"payment-1"}`)
	if !ok || len(sensitive) != 2 {
		t.Fatal("expected payment routes")
	}
	if (&Client{updatesOnly: true}).canReceive(sensitive[1]) {
		t.Fatal("public app-update socket received sensitive v2 event")
	}
}

func versionedTestEvent(eventType string, audience string, payload string) string {
	return `{"schemaVersion":1,"type":"` + eventType + `","eventId":"event-1","occurredAt":"2026-07-15T01:02:03Z","audience":` + audience + `,"payload":` + payload + `}`
}
