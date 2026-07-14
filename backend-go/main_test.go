package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/gorilla/websocket"
)

func TestHealthAndReadinessEndpoints(t *testing.T) {
	gin.SetMode(gin.TestMode)
	dependencies := testDependencies(t)
	dependencies.readiness = staticReadiness{}
	router := newRouter(dependencies)

	health := performRequest(router, "/health")
	if health.Code != http.StatusOK || health.Body.String() != `{"service":"backend-go","status":"ok"}` {
		t.Fatalf("unexpected health response status=%d body=%s", health.Code, health.Body.String())
	}
	ready := performRequest(router, "/ready")
	if ready.Code != http.StatusOK || ready.Body.String() != `{"service":"backend-go","status":"ready"}` {
		t.Fatalf("unexpected readiness response status=%d body=%s", ready.Code, ready.Body.String())
	}

	dependencies.readiness = staticReadiness{err: errors.New("redis unavailable")}
	notReady := performRequest(newRouter(dependencies), "/ready")
	if notReady.Code != http.StatusServiceUnavailable ||
		notReady.Body.String() != `{"service":"backend-go","status":"not_ready"}` {
		t.Fatalf("unexpected unavailable response status=%d body=%s", notReady.Code, notReady.Body.String())
	}
}

func TestAccessAndRecoveryLogsNeverIncludeQueryCredentials(t *testing.T) {
	gin.SetMode(gin.TestMode)
	var output bytes.Buffer
	logger := log.New(&output, "", 0)
	router := gin.New()
	router.Use(accessLogger(logger), safeRecovery(logger))
	router.GET("/ok", func(c *gin.Context) { c.Status(http.StatusNoContent) })
	router.GET("/panic", func(*gin.Context) { panic("panic-secret-must-not-be-logged") })

	secretQuery := "access_token=jwt-super-secret&ticket=ticket-super-secret"
	request := httptest.NewRequest(http.MethodGet, "/ok?"+secretQuery, nil)
	request.RemoteAddr = "203.0.113.9:12345"
	request.Header.Set("Authorization", "Bearer header-super-secret")
	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, request)
	panicRecorder := httptest.NewRecorder()
	router.ServeHTTP(panicRecorder, httptest.NewRequest(http.MethodGet, "/panic?"+secretQuery, nil))

	logs := output.String()
	for _, forbidden := range []string{
		"jwt-super-secret",
		"ticket-super-secret",
		"header-super-secret",
		"panic-secret-must-not-be-logged",
		"access_token=",
		"ticket=",
	} {
		if strings.Contains(logs, forbidden) {
			t.Fatalf("logs leaked %q: %s", forbidden, logs)
		}
	}
	if !strings.Contains(logs, "path=/ok") || !strings.Contains(logs, "path=/panic") {
		t.Fatalf("expected redacted path-only access logs, got %s", logs)
	}
	if panicRecorder.Code != http.StatusInternalServerError {
		t.Fatalf("expected panic recovery status 500, got %d", panicRecorder.Code)
	}
}

func TestClientIPLogIDIsStableAndNeverContainsRawAddress(t *testing.T) {
	raw := "203.0.113.9"
	first := clientIPLogID(raw)
	second := clientIPLogID(raw)
	if first != second || len(first) != 12 {
		t.Fatalf("expected stable 12-character client IP log ID, got %q and %q", first, second)
	}
	if strings.Contains(first, raw) {
		t.Fatalf("client IP log ID leaked raw address: %q", first)
	}
}

func TestAccessLoggerUsesRouteTemplateForUnmatchedUserPath(t *testing.T) {
	gin.SetMode(gin.TestMode)
	var output bytes.Buffer
	router := gin.New()
	router.Use(accessLogger(log.New(&output, "", 0)))
	router.GET("/known/:id", func(c *gin.Context) { c.Status(http.StatusNoContent) })

	request := httptest.NewRequest(http.MethodGet, "/unknown%0Aforged-log-line", nil)
	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, request)

	logs := output.String()
	if !strings.Contains(logs, "path=<unmatched>") {
		t.Fatalf("expected unmatched route marker, got %s", logs)
	}
	if strings.Contains(logs, "forged-log-line") {
		t.Fatalf("access log included user-controlled path: %s", logs)
	}
}

func TestAccessLoggerUsesAllowlistedHTTPMethod(t *testing.T) {
	gin.SetMode(gin.TestMode)
	var output bytes.Buffer
	router := gin.New()
	router.Use(accessLogger(log.New(&output, "", 0)))
	router.Any("/known", func(c *gin.Context) { c.Status(http.StatusNoContent) })

	request := httptest.NewRequest(http.MethodGet, "/known", nil)
	request.Method = "CUSTOM\nforged-log-line"
	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, request)

	logs := output.String()
	if !strings.Contains(logs, "method=<other>") {
		t.Fatalf("expected sanitized method marker, got %s", logs)
	}
	if strings.Contains(logs, "forged-log-line") {
		t.Fatalf("access log included user-controlled method: %s", logs)
	}
}

func TestOriginCheckUsesExactConfiguredOrigin(t *testing.T) {
	t.Setenv("ALLOWED_ORIGINS", "https://ops.example.com,https://admin.example.com")
	allowed := httptest.NewRequest(http.MethodGet, "/ws", nil)
	allowed.Header.Set("Origin", "https://ops.example.com")
	if !isOriginAllowed(allowed) {
		t.Fatal("expected configured origin to be allowed")
	}
	rejected := httptest.NewRequest(http.MethodGet, "/ws", nil)
	rejected.Header.Set("Origin", "https://evil.example.com")
	if isOriginAllowed(rejected) {
		t.Fatal("expected unconfigured origin to be rejected")
	}
}

func TestOriginCheckLocalhostFallbackDoesNotAllowLookalikeHost(t *testing.T) {
	t.Setenv("ALLOWED_ORIGINS", "")
	localhost := httptest.NewRequest(http.MethodGet, "/ws", nil)
	localhost.Header.Set("Origin", "http://localhost:8080")
	if !isOriginAllowed(localhost) {
		t.Fatal("expected localhost origin to be allowed in development")
	}
	lookalike := httptest.NewRequest(http.MethodGet, "/ws", nil)
	lookalike.Header.Set("Origin", "http://localhost.evil.example:8080")
	if isOriginAllowed(lookalike) {
		t.Fatal("expected localhost lookalike origin to be rejected")
	}
}

func TestLegacyJWTRequiresExplicitCompatibilityFlag(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/ws?access_token="+signTestToken(t, "user-1"), nil)
	disabled := newWebSocketAuthenticator(serviceConfig{jwtSecret: "test-secret"}, nil)
	if _, err := disabled.Authenticate(request); err == nil {
		t.Fatal("expected legacy JWT to be disabled by default")
	}
	enabled := newWebSocketAuthenticator(serviceConfig{
		jwtSecret:      "test-secret",
		allowLegacyJWT: true,
	}, nil)
	auth, err := enabled.Authenticate(request)
	if err != nil {
		t.Fatalf("expected explicit legacy JWT compatibility to work: %v", err)
	}
	if auth.UserID != "user-1" || auth.Method != "legacy_jwt" {
		t.Fatalf("unexpected legacy JWT auth: %+v", auth)
	}
}

func TestLegacyJWTRejectsWrongSecretAndMissingExpiry(t *testing.T) {
	authenticator := newWebSocketAuthenticator(serviceConfig{
		jwtSecret:      "test-secret",
		allowLegacyJWT: true,
	}, nil)
	wrongSecret := httptest.NewRequest(http.MethodGet, "/ws", nil)
	wrongSecret.Header.Set("Authorization", "Bearer "+signTokenWithSecret(t, "user-1", "wrong-secret", true))
	if _, err := authenticator.Authenticate(wrongSecret); err == nil {
		t.Fatal("expected wrong JWT secret to be rejected")
	}
	missingExpiry := httptest.NewRequest(http.MethodGet, "/ws", nil)
	missingExpiry.Header.Set("Authorization", "Bearer "+signTokenWithSecret(t, "user-1", "test-secret", false))
	if _, err := authenticator.Authenticate(missingExpiry); err == nil {
		t.Fatal("expected JWT without expiry to be rejected")
	}
}

func TestTicketIsHashedConsumedOnceAndValidatesSessionClaims(t *testing.T) {
	rawTicket := strings.Repeat("A", 43)
	consumer := &memoryTicketConsumer{values: make(map[string][]byte)}
	digest := sha256.Sum256([]byte(rawTicket))
	digestText := hex.EncodeToString(digest[:])
	consumer.values[digestText] = ticketPayload(t, time.Now().Add(45*time.Second), nil)
	authenticator := newWebSocketAuthenticator(serviceConfig{}, consumer)
	authenticator.now = time.Now

	request := httptest.NewRequest(http.MethodGet, "/ws?ticket="+rawTicket+"&store_id=CP01", nil)
	auth, err := authenticator.Authenticate(request)
	if err != nil {
		t.Fatalf("expected valid one-time ticket to authenticate: %v", err)
	}
	if auth.UserID != "user-1" || auth.SessionID != "session-1" || auth.Method != "ticket" {
		t.Fatalf("unexpected ticket identity: %+v", auth)
	}
	if auth.SelectedStore != "CP01" {
		t.Fatalf("expected selected store CP01, got %q", auth.SelectedStore)
	}
	if _, err := authenticator.Authenticate(request); err == nil {
		t.Fatal("expected consumed ticket reuse to be rejected")
	}
	if len(consumer.keys) != 2 || consumer.keys[0] != digestText {
		t.Fatalf("expected only the ticket SHA-256 digest at store boundary, got %v", consumer.keys)
	}
	for _, key := range consumer.keys {
		if strings.Contains(key, rawTicket) {
			t.Fatal("raw ticket reached the ticket-store key")
		}
	}
}

func TestTicketRejectsExpiryWrongAudienceAndStoreScopeElevation(t *testing.T) {
	rawTicket := strings.Repeat("B", 43)
	digest := sha256.Sum256([]byte(rawTicket))
	digestText := hex.EncodeToString(digest[:])
	tests := []struct {
		name     string
		expires  time.Time
		override map[string]any
		url      string
	}{
		{name: "expired", expires: time.Now().Add(-time.Second), url: "/ws?ticket=" + rawTicket},
		{name: "wrong audience", expires: time.Now().Add(45 * time.Second), override: map[string]any{"audience": "another-service"}, url: "/ws?ticket=" + rawTicket},
		{name: "outside store", expires: time.Now().Add(45 * time.Second), url: "/ws?ticket=" + rawTicket + "&store_id=CP99"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			consumer := &memoryTicketConsumer{values: map[string][]byte{
				digestText: ticketPayload(t, test.expires, test.override),
			}}
			authenticator := newWebSocketAuthenticator(serviceConfig{}, consumer)
			if _, err := authenticator.Authenticate(httptest.NewRequest(http.MethodGet, test.url, nil)); err == nil {
				t.Fatal("expected invalid ticket to be rejected")
			}
		})
	}
}

func TestPublicAppUpdateWebSocketReceivesOnlyPublicUpdate(t *testing.T) {
	gin.SetMode(gin.TestMode)
	dependencies := testDependencies(t)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go dependencies.hub.run(ctx)
	server := httptest.NewServer(newRouter(dependencies))
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/ws/app-updates"
	connection, response, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		status := 0
		if response != nil {
			status = response.StatusCode
		}
		t.Fatalf("expected public app-update websocket status=%d error=%v", status, err)
	}
	defer connection.Close()
	waitForClientCount(t, dependencies.hub, 1)

	dependencies.hub.broadcast <- RoutedEvent{
		Type:     paymentEventType,
		Message:  []byte(`{"type":"PAYMENT_NOTIFICATION","payload":{"storeCode":"CP01"}}`),
		Audience: EventAudience{StoreCodes: []string{"CP01"}},
	}
	expected := `{"type":"APP_UPDATE","payload":{"schemaVersion":1}}`
	dependencies.hub.broadcast <- RoutedEvent{Type: appUpdateEventType, Message: []byte(expected), Public: true}
	if err := connection.SetReadDeadline(time.Now().Add(2 * time.Second)); err != nil {
		t.Fatal(err)
	}
	_, message, err := connection.ReadMessage()
	if err != nil {
		t.Fatalf("expected public update message: %v", err)
	}
	if string(message) != expected {
		t.Fatalf("expected %s, got %s", expected, string(message))
	}
}

func TestAuthenticatedWebSocketUsesOneTimeTicket(t *testing.T) {
	gin.SetMode(gin.TestMode)
	rawTicket := strings.Repeat("C", 43)
	digest := sha256.Sum256([]byte(rawTicket))
	consumer := &memoryTicketConsumer{values: map[string][]byte{
		hex.EncodeToString(digest[:]): ticketPayload(t, time.Now().Add(45*time.Second), nil),
	}}
	dependencies := testDependencies(t)
	dependencies.authenticator = newWebSocketAuthenticator(serviceConfig{}, consumer)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go dependencies.hub.run(ctx)
	server := httptest.NewServer(newRouter(dependencies))
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/ws?ticket=" + rawTicket
	connection, response, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		status := 0
		if response != nil {
			status = response.StatusCode
		}
		t.Fatalf("expected valid one-time ticket websocket status=%d error=%v", status, err)
	}
	connection.Close()
	_, secondResponse, secondErr := websocket.DefaultDialer.Dial(wsURL, nil)
	if secondErr == nil {
		t.Fatal("expected reused ticket websocket to be rejected")
	}
	if secondResponse == nil || secondResponse.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expected reused ticket status 401, got %+v", secondResponse)
	}
}

func TestIdleWebSocketIsDisconnectedAfterPongTimeout(t *testing.T) {
	gin.SetMode(gin.TestMode)
	dependencies := testDependencies(t)
	dependencies.socket = socketConfig{
		writeWait:  50 * time.Millisecond,
		pongWait:   150 * time.Millisecond,
		pingPeriod: 50 * time.Millisecond,
		readLimit:  4096,
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go dependencies.hub.run(ctx)
	server := httptest.NewServer(newRouter(dependencies))
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/ws/app-updates"
	connection, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close()
	waitForClientCount(t, dependencies.hub, 1)
	waitForClientCount(t, dependencies.hub, 0)
}

func TestSensitiveEventsAreRoutedByServerSideAudience(t *testing.T) {
	event := RoutedEvent{
		Type:    warrantyEventType,
		Message: []byte(`{"type":"WARRANTY_EVENT","payload":{"warrantyId":"w-1"}}`),
		Audience: EventAudience{
			StoreCodes:   []string{"CP01"},
			FeatureCodes: []string{"WARRANTY"},
		},
	}
	allowed := &Client{auth: &ClientAuth{StoreCode: "CP01", FeatureCodes: []string{"WARRANTY"}}}
	if !allowed.canReceive(event) {
		t.Fatal("expected matching store and feature to receive event")
	}
	wrongStore := &Client{auth: &ClientAuth{StoreCode: "CP02", FeatureCodes: []string{"WARRANTY"}}}
	if wrongStore.canReceive(event) {
		t.Fatal("expected different store to be rejected")
	}
	wrongFeature := &Client{auth: &ClientAuth{StoreCode: "CP01", FeatureCodes: []string{"PAYMENT_MONITOR"}}}
	if wrongFeature.canReceive(event) {
		t.Fatal("expected missing feature entitlement to be rejected")
	}
	unauthenticated := &Client{}
	if unauthenticated.canReceive(event) {
		t.Fatal("expected unauthenticated client to be rejected")
	}
}

func TestLegacyAudienceCompatibilityIsFailClosed(t *testing.T) {
	payment, ok := formatRedisEvent(paymentRedisChannel, `{"storeCode":"CP01","notificationId":"n-1"}`)
	if !ok {
		t.Fatal("expected scoped legacy payment event to remain compatible")
	}
	if !(&Client{auth: &ClientAuth{StoreCode: "CP01"}}).canReceive(payment) {
		t.Fatal("expected own-store payment event")
	}
	if (&Client{auth: &ClientAuth{StoreCode: "CP02"}}).canReceive(payment) {
		t.Fatal("expected cross-store payment event to be rejected")
	}

	if _, ok := formatRedisEvent(warrantyRedisChannel, `{"warrantyId":"w-1","newStatus":"DONE"}`); ok {
		t.Fatal("expected historical warranty event without audience to fail closed")
	}
	if _, ok := formatRedisEvent(salesReportOrdersRedisChannel, `{"storeCodes":[],"recipientUserIds":[]}`); ok {
		t.Fatal("expected empty sales-report audience to fail closed")
	}
}

func TestVersionedEnvelopeRequiresCompleteAudienceMetadata(t *testing.T) {
	valid := `{
		"schemaVersion":1,
		"type":"WARRANTY_EVENT",
		"eventId":"event-1",
		"occurredAt":"2026-07-12T00:00:00Z",
		"audience":{"storeCodes":["CP01"],"featureCodes":["WARRANTY"]},
		"payload":{"warrantyId":"w-1","newStatus":"DONE"}
	}`
	event, ok := formatRedisEvent(warrantyRedisChannel, valid)
	if !ok {
		t.Fatal("expected valid versioned event envelope")
	}
	expected := `{"type":"WARRANTY_EVENT","payload":{"warrantyId":"w-1","newStatus":"DONE"}}`
	if string(event.Message) != expected {
		t.Fatalf("expected audience metadata not to be exposed to client; got %s", event.Message)
	}
	missingAudience := `{"schemaVersion":1,"eventId":"event-1","occurredAt":"2026-07-12T00:00:00Z","payload":{"warrantyId":"w-1"}}`
	if _, ok := formatRedisEvent(warrantyRedisChannel, missingAudience); ok {
		t.Fatal("expected versioned sensitive event without audience to fail closed")
	}
}

func TestSalesReportAndOffsetLegacyRoutingRemainsServerSide(t *testing.T) {
	sales, ok := formatRedisEvent(
		salesReportOrdersRedisChannel,
		`{"storeCodes":["CP01"],"recipientUserIds":["user-1"]}`,
	)
	if !ok {
		t.Fatal("expected sales report event with legacy scope")
	}
	if !(&Client{auth: &ClientAuth{UserID: "user-1"}}).canReceive(sales) {
		t.Fatal("expected explicit sales report recipient")
	}
	if !(&Client{auth: &ClientAuth{OrganizationAccessCodes: []string{"CP01"}}}).canReceive(sales) {
		t.Fatal("expected assigned store access to match sales report store")
	}
	if (&Client{auth: &ClientAuth{StoreCode: "CP02"}}).canReceive(sales) {
		t.Fatal("expected unrelated store not to receive sales report event")
	}
	if !(&Client{auth: &ClientAuth{Role: "SUPER_ADMIN"}}).canReceive(sales) {
		t.Fatal("expected unfiltered super admin sales report compatibility")
	}
	if (&Client{auth: &ClientAuth{Role: "SUPER_ADMIN", SelectedStore: "CP02"}}).canReceive(sales) {
		t.Fatal("expected selected-store super admin not to widen scope")
	}

	offset, ok := formatRedisEvent(offsetAdjustmentRedisChannel, `{"storeCode":"CP02"}`)
	if !ok {
		t.Fatal("expected offset event with legacy scope")
	}
	if !(&Client{auth: &ClientAuth{DepartmentCode: "FIN_ACC"}}).canReceive(offset) {
		t.Fatal("expected finance reviewer to receive offset event")
	}
	if (&Client{auth: &ClientAuth{StoreCode: "CP01"}}).canReceive(offset) {
		t.Fatal("expected unrelated store not to receive offset event")
	}
}

func TestRedisEventFormattingAndPublicClassification(t *testing.T) {
	tests := []struct {
		channel string
		payload string
		typeID  string
		public  bool
	}{
		{statementOrderTransferRedisChannel, `{"storeCode":"CP01"}`, statementOrderTransferEventType, false},
		{offsetAdjustmentRedisChannel, `{"storeCode":"CP01"}`, offsetAdjustmentEventType, false},
		{paymentStreamRedisChannel, `{"storeCode":"CP01"}`, paymentStreamEventType, false},
		{salesReportOrdersRedisChannel, `{"storeCodes":["CP01"]}`, salesReportOrdersEventType, false},
		{appVersionRedisChannel, `{"schemaVersion":1}`, appUpdateEventType, true},
	}
	for _, test := range tests {
		event, ok := formatRedisEvent(test.channel, test.payload)
		if !ok {
			t.Fatalf("expected channel %s to format", test.channel)
		}
		if event.Type != test.typeID || event.Public != test.public {
			t.Fatalf("unexpected event metadata: %+v", event)
		}
	}
	if _, ok := formatRedisEvent("UNKNOWN", `{}`); ok {
		t.Fatal("expected unknown channel to be rejected")
	}
	if _, ok := formatRedisEvent(appVersionRedisChannel, `{invalid`); ok {
		t.Fatal("expected invalid JSON to be rejected")
	}
}

func TestHomeSummaryV2EnvelopeIsValidatedAndProtocolScoped(t *testing.T) {
	payload := `{
		"schemaVersion":2,
		"type":"HOME_SUMMARY_UPDATED",
		"eventId":"event-home-42",
		"occurredAt":"2026-07-14T10:30:05Z",
		"audience":{"kind":"AUTHENTICATED"},
		"payload":{"affectedDates":["2026-07-14"],"projectionVersion":42}
	}`
	event, ok := formatRedisEvent(homeSummaryRedisChannel, payload)
	if !ok {
		t.Fatal("expected valid Home Summary v2 event")
	}
	expected := `{"v":2,"kind":"HOME_SUMMARY_UPDATED","id":"event-home-42","topic":"home.summary","seq":42,"ts":"2026-07-14T10:30:05Z","data":{"affectedDates":["2026-07-14"],"projectionVersion":42}}`
	if string(event.Message) != expected {
		t.Fatalf("unexpected Home Summary client envelope: %s", event.Message)
	}
	if event.ProtocolVersion != webSocketProtocolV2 || !event.AuthenticatedOnly {
		t.Fatalf("unexpected Home Summary route metadata: %+v", event)
	}
	if (&Client{auth: &ClientAuth{UserID: "user-1"}, protocolVersion: webSocketProtocolV1}).canReceive(event) {
		t.Fatal("legacy socket must not receive v2 Home Summary events")
	}
	if !(&Client{auth: &ClientAuth{UserID: "user-1"}, protocolVersion: webSocketProtocolV2}).canReceive(event) {
		t.Fatal("authenticated v2 socket should receive Home Summary events")
	}
	if (&Client{protocolVersion: webSocketProtocolV2}).canReceive(event) {
		t.Fatal("unauthenticated v2 client must not receive Home Summary events")
	}

	invalidPayloads := []string{
		strings.Replace(payload, `"kind":"AUTHENTICATED"`, `"kind":"PUBLIC"`, 1),
		strings.Replace(payload, `"projectionVersion":42`, `"projectionVersion":0`, 1),
		strings.Replace(payload, `["2026-07-14"]`, `["2026-07-14","2026-07-14"]`, 1),
		strings.Replace(payload, `"2026-07-14"`, `"14-07-2026"`, 1),
	}
	for _, invalid := range invalidPayloads {
		if _, ok := formatRedisEvent(homeSummaryRedisChannel, invalid); ok {
			t.Fatalf("expected invalid Home Summary event to be rejected: %s", invalid)
		}
	}
}

func TestV2RouteFailsClosedWhenRedisIsUnavailable(t *testing.T) {
	gin.SetMode(gin.TestMode)
	dependencies := testDependencies(t)
	dependencies.readiness = staticReadiness{err: errors.New("redis unavailable")}
	notReady := performRequest(newRouter(dependencies), "/ws/v2")
	if notReady.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected v2 route to fail with 503, got %d", notReady.Code)
	}

	dependencies.readiness = staticReadiness{}
	unauthorized := performRequest(newRouter(dependencies), "/ws/v2")
	if unauthorized.Code != http.StatusUnauthorized {
		t.Fatalf("expected one-time ticket auth on v2 route, got %d", unauthorized.Code)
	}
}

func TestProtocolResyncDisconnectsOnlyV2Clients(t *testing.T) {
	hub := newHub(testLogger(), 2)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go hub.run(ctx)
	v1 := &Client{
		auth:            &ClientAuth{UserID: "legacy-user"},
		protocolVersion: webSocketProtocolV1,
		send:            make(chan []byte, 1),
	}
	v2 := &Client{
		auth:            &ClientAuth{UserID: "v2-user"},
		protocolVersion: webSocketProtocolV2,
		send:            make(chan []byte, 1),
	}
	hub.register <- v1
	hub.register <- v2
	waitForClientCount(t, hub, 2)
	hub.requestProtocolResync(webSocketProtocolV2, "redis_unavailable")
	waitForClientCount(t, hub, 1)
	if v2.closeCode != websocket.CloseServiceRestart || v2.closeReason != "resync_required" {
		t.Fatalf("unexpected v2 resync close metadata code=%d reason=%q", v2.closeCode, v2.closeReason)
	}
	if v1.closeCode != 0 {
		t.Fatalf("legacy socket was unexpectedly closed with code %d", v1.closeCode)
	}
}

func TestSlowClientQueueCannotBlockHubBroadcast(t *testing.T) {
	hub := newHub(testLogger(), 1)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go hub.run(ctx)

	slow := &Client{updatesOnly: true, send: make(chan []byte, 1)}
	slow.send <- []byte("queue already full")
	fast := &Client{updatesOnly: true, send: make(chan []byte, 1)}
	hub.register <- slow
	hub.register <- fast
	waitForClientCount(t, hub, 2)

	expected := []byte(`{"type":"APP_UPDATE","payload":{"schemaVersion":1}}`)
	hub.broadcast <- RoutedEvent{Type: appUpdateEventType, Message: expected, Public: true}
	select {
	case received := <-fast.send:
		if string(received) != string(expected) {
			t.Fatalf("unexpected fast client message %s", received)
		}
	case <-time.After(time.Second):
		t.Fatal("fast client was blocked by slow client")
	}
	waitForClientCount(t, hub, 1)
}

func TestConnectionAndHandshakeLimits(t *testing.T) {
	limiter := newConnectionLimiter(connectionLimitConfig{
		maxTotal:              2,
		maxPerIP:              1,
		maxPerUser:            1,
		maxHandshakesPerIPMin: 2,
	})
	now := time.Now()
	if !limiter.allowHandshake("192.0.2.1", now) || !limiter.allowHandshake("192.0.2.1", now) {
		t.Fatal("expected first two handshakes within limit")
	}
	if limiter.allowHandshake("192.0.2.1", now) {
		t.Fatal("expected third handshake to be rate limited")
	}
	release, allowed := limiter.acquire("192.0.2.1", "user-1")
	if !allowed {
		t.Fatal("expected first connection to be allowed")
	}
	if _, allowed := limiter.acquire("192.0.2.1", "user-2"); allowed {
		t.Fatal("expected per-IP active connection cap")
	}
	release()
	if _, allowed := limiter.acquire("192.0.2.2", "user-1"); !allowed {
		t.Fatal("expected capacity to be released exactly once")
	}
}

func TestRequestClientIPTrustsForwardedHeaderOnlyFromPrivateProxy(t *testing.T) {
	proxied := httptest.NewRequest(http.MethodGet, "/ws", nil)
	proxied.RemoteAddr = "172.18.0.2:12345"
	proxied.Header.Set("CF-Connecting-IP", "203.0.113.9")
	if got := requestClientIP(proxied); got != "203.0.113.9" {
		t.Fatalf("expected edge client IP, got %q", got)
	}
	direct := httptest.NewRequest(http.MethodGet, "/ws", nil)
	direct.RemoteAddr = "198.51.100.10:12345"
	direct.Header.Set("CF-Connecting-IP", "203.0.113.9")
	if got := requestClientIP(direct); got != "198.51.100.10" {
		t.Fatalf("expected direct remote IP, got %q", got)
	}
}

func TestConfigSupportsRedisAuthenticationAndSecureJWTDefault(t *testing.T) {
	t.Setenv("REDIS_HOST", "redis.internal")
	t.Setenv("REDIS_PORT", "6380")
	t.Setenv("REDIS_USERNAME", "opshub")
	t.Setenv("REDIS_PASSWORD", "test-password")
	t.Setenv("REDIS_DB", "2")
	t.Setenv("WS_ALLOW_LEGACY_JWT", "false")
	config, err := loadConfig()
	if err != nil {
		t.Fatal(err)
	}
	if config.redisAddress != "redis.internal:6380" || config.redisUsername != "opshub" ||
		config.redisPassword != "test-password" || config.redisDB != 2 {
		t.Fatalf("unexpected Redis config: address=%s user=%s db=%d", config.redisAddress, config.redisUsername, config.redisDB)
	}
	if config.allowLegacyJWT {
		t.Fatal("expected secure ticket-only authentication default")
	}
}

func TestConfigDefaultsSupportCurrentFlutterRealtimeConsumers(t *testing.T) {
	t.Setenv("WS_MAX_CONNECTIONS_PER_USER", "")
	config, err := loadConfig()
	if err != nil {
		t.Fatal(err)
	}
	if config.connectionLimits.maxPerUser != 12 {
		t.Fatalf("expected 12 concurrent connections per user, got %d", config.connectionLimits.maxPerUser)
	}
}

func TestConfigAllowsExplicitPerUserConnectionLimit(t *testing.T) {
	t.Setenv("WS_MAX_CONNECTIONS_PER_USER", "18")
	config, err := loadConfig()
	if err != nil {
		t.Fatal(err)
	}
	if config.connectionLimits.maxPerUser != 18 {
		t.Fatalf("expected explicit per-user limit 18, got %d", config.connectionLimits.maxPerUser)
	}
}

type memoryTicketConsumer struct {
	mu     sync.Mutex
	values map[string][]byte
	keys   []string
}

type staticReadiness struct {
	err error
}

func (state staticReadiness) Ready(context.Context) error {
	return state.err
}

func (consumer *memoryTicketConsumer) Consume(_ context.Context, key string) ([]byte, error) {
	consumer.mu.Lock()
	defer consumer.mu.Unlock()
	consumer.keys = append(consumer.keys, key)
	value, ok := consumer.values[key]
	if !ok {
		return nil, errors.New("ticket missing")
	}
	delete(consumer.values, key)
	return value, nil
}

func ticketPayload(t *testing.T, expiresAt time.Time, override map[string]any) []byte {
	t.Helper()
	payload := map[string]any{
		"version":                 1,
		"audience":                realtimeTicketAudience,
		"userId":                  "user-1",
		"email":                   "user@example.com",
		"role":                    "MANAGER",
		"storeId":                 "store-uuid-1",
		"storeCode":               "CP01",
		"departmentCode":          "SALES",
		"organizationNodeId":      "node-1",
		"organizationAccessCodes": []string{"CP01"},
		"featureCodes":            []string{"WARRANTY", "PAYMENT_MONITOR"},
		"sessionId":               "session-1",
		"platform":                "web",
		"sessionVersion":          1,
		"tokenVersion":            2,
		"issuedAt":                time.Now().UTC().Format(time.RFC3339Nano),
		"expiresAt":               expiresAt.UTC().Format(time.RFC3339Nano),
	}
	for key, value := range override {
		payload[key] = value
	}
	encoded, err := json.Marshal(payload)
	if err != nil {
		t.Fatal(err)
	}
	return encoded
}

func testDependencies(t *testing.T) serverDependencies {
	t.Helper()
	config := serviceConfig{
		jwtSecret:      "test-secret",
		allowLegacyJWT: true,
		sendQueueSize:  8,
		socket: socketConfig{
			writeWait:  time.Second,
			pongWait:   2 * time.Second,
			pingPeriod: time.Second,
			readLimit:  4096,
		},
		connectionLimits: connectionLimitConfig{
			maxTotal:              100,
			maxPerIP:              100,
			maxPerUser:            5,
			maxHandshakesPerIPMin: 100,
		},
	}
	logger := testLogger()
	return serverDependencies{
		hub:           newHub(logger, config.sendQueueSize),
		authenticator: newWebSocketAuthenticator(config, nil),
		readiness:     staticReadiness{},
		limiter:       newConnectionLimiter(config.connectionLimits),
		logger:        logger,
		socket:        config.socket,
	}
}

func testLogger() *log.Logger {
	return log.New(io.Discard, "", 0)
}

func performRequest(handler http.Handler, path string) *httptest.ResponseRecorder {
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, path, nil))
	return recorder
}

func waitForClientCount(t *testing.T, hub *Hub, want int64) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if hub.clientCount.Load() == want {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("expected %d websocket clients, got %d", want, hub.clientCount.Load())
}

func signTestToken(t *testing.T, subject string) string {
	t.Helper()
	return signTokenWithSecret(t, subject, "test-secret", true)
}

func signTokenWithSecret(t *testing.T, subject string, secret string, includeExpiry bool) string {
	t.Helper()
	claims := jwt.MapClaims{
		"sub":                     subject,
		"role":                    "MANAGER",
		"storeCode":               "CP01",
		"organizationAccessCodes": []string{"CP01"},
		"sessionId":               "session-1",
		"sessionVersion":          1,
		"tokenVersion":            1,
	}
	if includeExpiry {
		claims["exp"] = time.Now().Add(time.Hour).Unix()
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString([]byte(secret))
	if err != nil {
		t.Fatal(err)
	}
	return signed
}
