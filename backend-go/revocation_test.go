package main

import "testing"

func TestParseSessionRevocation(t *testing.T) {
	payload := `{"schemaVersion":1,"userId":"user-1","sessionId":"session-1","platform":"WINDOWS","reason":"LOGOUT","occurredAt":"2026-07-12T10:00:00Z"}`
	revocation, ok := parseSessionRevocation(payload)
	if !ok {
		t.Fatal("expected a valid revocation payload")
	}
	if revocation.UserID != "user-1" || revocation.Platform != "windows" {
		t.Fatalf("unexpected revocation: %#v", revocation)
	}
}

func TestParseSessionRevocationRejectsIncompletePayload(t *testing.T) {
	if _, ok := parseSessionRevocation(`{"schemaVersion":1,"userId":"user-1"}`); ok {
		t.Fatal("expected incomplete revocation to be rejected")
	}
}

func TestClientMatchesOnlyItsRevokedSession(t *testing.T) {
	client := &Client{auth: &ClientAuth{
		UserID:    "user-1",
		SessionID: "session-1",
		Platform:  "windows",
	}}
	if !client.matchesRevocation(SessionRevocation{
		UserID: "user-1", SessionID: "session-1", Platform: "windows",
	}) {
		t.Fatal("expected matching session to be revoked")
	}
	if client.matchesRevocation(SessionRevocation{
		UserID: "user-1", SessionID: "session-2", Platform: "windows",
	}) {
		t.Fatal("must not revoke a different session")
	}
	if client.matchesRevocation(SessionRevocation{
		UserID: "user-2",
	}) {
		t.Fatal("must not revoke a different user")
	}
}
