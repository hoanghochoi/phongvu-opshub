package main

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
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
