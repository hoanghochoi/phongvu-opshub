package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/gorilla/websocket"
)

func TestHealthEndpoint(t *testing.T) {
	gin.SetMode(gin.TestMode)

	router := gin.New()
	registerRoutes(router, newHub())

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()

	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rec.Code)
	}

	expected := `{"service":"backend-go","status":"ok"}`
	if rec.Body.String() != expected {
		t.Fatalf("expected body %s, got %s", expected, rec.Body.String())
	}
}

func TestOriginCheckAllowsConfiguredOrigins(t *testing.T) {
	t.Setenv("ALLOWED_ORIGINS", "https://ops.example.com,https://admin.example.com")

	req := httptest.NewRequest(http.MethodGet, "/ws", nil)
	req.Header.Set("Origin", "https://ops.example.com")

	if !isOriginAllowed(req) {
		t.Fatal("expected configured origin to be allowed")
	}
}

func TestOriginCheckRejectsUnconfiguredOrigins(t *testing.T) {
	t.Setenv("ALLOWED_ORIGINS", "https://ops.example.com")

	req := httptest.NewRequest(http.MethodGet, "/ws", nil)
	req.Header.Set("Origin", "https://evil.example.com")

	if isOriginAllowed(req) {
		t.Fatal("expected unconfigured origin to be rejected")
	}
}

func TestWebSocketAuthAllowsValidBearerToken(t *testing.T) {
	t.Setenv("JWT_SECRET", "test-secret")

	req := httptest.NewRequest(http.MethodGet, "/ws", nil)
	req.Header.Set("Authorization", "Bearer "+signTestToken(t, "user-1"))

	if _, err := authenticateWebSocket(req); err != nil {
		t.Fatalf("expected valid token to be accepted, got %v", err)
	}
}

func TestWebSocketAuthRejectsMissingToken(t *testing.T) {
	t.Setenv("JWT_SECRET", "test-secret")

	req := httptest.NewRequest(http.MethodGet, "/ws", nil)

	if _, err := authenticateWebSocket(req); err == nil {
		t.Fatal("expected missing token to be rejected")
	}
}

func TestWebSocketAuthRejectsWrongSecret(t *testing.T) {
	t.Setenv("JWT_SECRET", "test-secret")

	req := httptest.NewRequest(http.MethodGet, "/ws", nil)
	req.Header.Set("Authorization", "Bearer "+signTokenWithSecret(t, "user-1", "wrong-secret"))

	if _, err := authenticateWebSocket(req); err == nil {
		t.Fatal("expected token signed with another secret to be rejected")
	}
}

func TestPublicAppUpdateWebSocketDoesNotRequireAuth(t *testing.T) {
	gin.SetMode(gin.TestMode)
	hub := newHub()
	go hub.run()
	router := gin.New()
	registerRoutes(router, hub)
	server := httptest.NewServer(router)
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/ws/app-updates"
	connection, response, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		status := 0
		if response != nil {
			status = response.StatusCode
		}
		t.Fatalf("expected public app-update websocket connection, status=%d error=%v", status, err)
	}
	defer connection.Close()
}

func TestPaymentEventFilteringByStore(t *testing.T) {
	client := &Client{auth: &ClientAuth{Role: "MANAGER", StoreCode: "CP01"}}
	message := []byte(`{"type":"PAYMENT_NOTIFICATION","payload":{"storeCode":"CP01"}}`)
	if !client.canReceive(message) {
		t.Fatal("expected client to receive own store payment event")
	}

	otherMessage := []byte(`{"type":"PAYMENT_NOTIFICATION","payload":{"storeCode":"CP02"}}`)
	if client.canReceive(otherMessage) {
		t.Fatal("expected client not to receive another store payment event")
	}
}

func TestSuperAdminRequiresSelectedStoreForPaymentEvents(t *testing.T) {
	client := &Client{auth: &ClientAuth{Role: "SUPER_ADMIN", SelectedStore: "CP02"}}
	message := []byte(`{"type":"PAYMENT_NOTIFICATION","payload":{"storeCode":"CP02"}}`)
	if !client.canReceive(message) {
		t.Fatal("expected super admin to receive selected store payment event")
	}

	missingSelection := &Client{auth: &ClientAuth{Role: "SUPER_ADMIN"}}
	if missingSelection.canReceive(message) {
		t.Fatal("expected super admin without selected store not to receive payment event")
	}
}

func TestStatementOrderTransferEventFilteringByStore(t *testing.T) {
	client := &Client{auth: &ClientAuth{Role: "MANAGER", StoreCode: "CP01"}}
	message := []byte(`{"type":"STATEMENT_ORDER_TRANSFER_REQUEST","payload":{"storeCode":"CP01"}}`)
	if !client.canReceive(message) {
		t.Fatal("expected client to receive own store statement transfer event")
	}

	otherMessage := []byte(`{"type":"STATEMENT_ORDER_TRANSFER_REQUEST","payload":{"storeCode":"CP02"}}`)
	if client.canReceive(otherMessage) {
		t.Fatal("expected client not to receive another store statement transfer event")
	}
}

func TestSuperAdminCanReceiveAllStatementOrderTransferEvents(t *testing.T) {
	message := []byte(`{"type":"STATEMENT_ORDER_TRANSFER_REQUEST","payload":{"storeCode":"CP02"}}`)

	allStores := &Client{auth: &ClientAuth{Role: "SUPER_ADMIN"}}
	if !allStores.canReceive(message) {
		t.Fatal("expected super admin without selected store to receive statement transfer event")
	}

	selectedStore := &Client{auth: &ClientAuth{Role: "SUPER_ADMIN", SelectedStore: "CP02"}}
	if !selectedStore.canReceive(message) {
		t.Fatal("expected super admin to receive selected store statement transfer event")
	}

	otherStore := &Client{auth: &ClientAuth{Role: "SUPER_ADMIN", SelectedStore: "CP01"}}
	if otherStore.canReceive(message) {
		t.Fatal("expected super admin not to receive another selected store statement transfer event")
	}
}

func TestPublicAppUpdateClientOnlyReceivesUpdateEvents(t *testing.T) {
	client := &Client{updatesOnly: true}
	appUpdate := []byte(`{"type":"APP_UPDATE","payload":{"schemaVersion":1}}`)
	if !client.canReceive(appUpdate) {
		t.Fatal("expected public app-update client to receive update event")
	}

	warranty := []byte(`{"type":"WARRANTY_EVENT","payload":{"warrantyId":"w-1"}}`)
	if client.canReceive(warranty) {
		t.Fatal("expected public app-update client not to receive warranty event")
	}

	payment := []byte(`{"type":"PAYMENT_NOTIFICATION","payload":{"storeCode":"CP01"}}`)
	if client.canReceive(payment) {
		t.Fatal("expected public app-update client not to receive payment event")
	}
}

func TestFormatsStatementOrderTransferRedisEvent(t *testing.T) {
	message, ok := formatRedisEvent(
		statementOrderTransferRedisChannel,
		`{"requestId":"request-1","transactionId":"tx-1","storeCode":"CP01"}`,
	)
	if !ok {
		t.Fatal("expected statement transfer Redis event to be formatted")
	}
	expected := `{"type":"STATEMENT_ORDER_TRANSFER_REQUEST","payload":{"requestId":"request-1","transactionId":"tx-1","storeCode":"CP01"}}`
	if string(message) != expected {
		t.Fatalf("expected %s, got %s", expected, string(message))
	}
}

func TestFormatsAppVersionRedisEvent(t *testing.T) {
	message, ok := formatRedisEvent(
		appVersionRedisChannel,
		`{"schemaVersion":1,"platforms":{"windows":{"latestBuild":42}}}`,
	)
	if !ok {
		t.Fatal("expected app version Redis event to be formatted")
	}
	expected := `{"type":"APP_UPDATE","payload":{"schemaVersion":1,"platforms":{"windows":{"latestBuild":42}}}}`
	if string(message) != expected {
		t.Fatalf("expected %s, got %s", expected, string(message))
	}
}

func TestRejectsInvalidRedisEventPayload(t *testing.T) {
	if _, ok := formatRedisEvent(appVersionRedisChannel, `{invalid`); ok {
		t.Fatal("expected invalid JSON payload to be rejected")
	}
}

func signTestToken(t *testing.T, subject string) string {
	t.Helper()
	return signTokenWithSecret(t, subject, "test-secret")
}

func signTokenWithSecret(t *testing.T, subject string, secret string) string {
	t.Helper()
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub":       subject,
		"role":      "MANAGER",
		"storeCode": "CP01",
		"exp":       time.Now().Add(time.Hour).Unix(),
	})
	signed, err := token.SignedString([]byte(secret))
	if err != nil {
		t.Fatal(err)
	}
	return signed
}
