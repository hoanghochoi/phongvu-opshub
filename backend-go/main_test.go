package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
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

	if err := authenticateWebSocket(req); err != nil {
		t.Fatalf("expected valid token to be accepted, got %v", err)
	}
}

func TestWebSocketAuthRejectsMissingToken(t *testing.T) {
	t.Setenv("JWT_SECRET", "test-secret")

	req := httptest.NewRequest(http.MethodGet, "/ws", nil)

	if err := authenticateWebSocket(req); err == nil {
		t.Fatal("expected missing token to be rejected")
	}
}

func TestWebSocketAuthRejectsWrongSecret(t *testing.T) {
	t.Setenv("JWT_SECRET", "test-secret")

	req := httptest.NewRequest(http.MethodGet, "/ws", nil)
	req.Header.Set("Authorization", "Bearer "+signTokenWithSecret(t, "user-1", "wrong-secret"))

	if err := authenticateWebSocket(req); err == nil {
		t.Fatal("expected token signed with another secret to be rejected")
	}
}

func signTestToken(t *testing.T, subject string) string {
	t.Helper()
	return signTokenWithSecret(t, subject, "test-secret")
}

func signTokenWithSecret(t *testing.T, subject string, secret string) string {
	t.Helper()
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub": subject,
		"exp": time.Now().Add(time.Hour).Unix(),
	})
	signed, err := token.SignedString([]byte(secret))
	if err != nil {
		t.Fatal(err)
	}
	return signed
}
