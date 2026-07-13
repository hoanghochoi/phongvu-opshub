package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/redis/go-redis/v9"
)

const realtimeTicketAudience = "opshub-realtime"

type ClientAuth struct {
	UserID                  string
	Role                    string
	StoreID                 string
	StoreCode               string
	DepartmentCode          string
	OrganizationNodeID      string
	OrganizationAccessCodes []string
	FeatureCodes            []string
	SessionID               string
	Platform                string
	SessionVersion          int
	TokenVersion            int
	SelectedStore           string
	Method                  string
}

type webSocketAuthenticator struct {
	jwtSecret      string
	allowLegacyJWT bool
	tickets        ticketConsumer
	now            func() time.Time
}

type ticketConsumer interface {
	Consume(context.Context, string) ([]byte, error)
}

type redisTicketStore struct {
	client *redis.Client
	prefix string
}

type ticketClaims struct {
	Version                 int             `json:"version"`
	Audience                string          `json:"audience"`
	UserID                  string          `json:"userId"`
	Email                   string          `json:"email"`
	Role                    string          `json:"role"`
	StoreID                 string          `json:"storeId"`
	StoreCode               string          `json:"storeCode"`
	DepartmentCode          string          `json:"departmentCode"`
	OrganizationNodeID      string          `json:"organizationNodeId"`
	OrganizationAccessCodes []string        `json:"organizationAccessCodes"`
	FeatureCodes            []string        `json:"featureCodes"`
	SessionID               string          `json:"sessionId"`
	Platform                string          `json:"platform"`
	SessionVersion          *int            `json:"sessionVersion"`
	TokenVersion            *int            `json:"tokenVersion"`
	IssuedAt                json.RawMessage `json:"issuedAt"`
	ExpiresAt               json.RawMessage `json:"expiresAt"`
}

func newWebSocketAuthenticator(config serviceConfig, tickets ticketConsumer) *webSocketAuthenticator {
	return &webSocketAuthenticator{
		jwtSecret:      config.jwtSecret,
		allowLegacyJWT: config.allowLegacyJWT,
		tickets:        tickets,
		now:            time.Now,
	}
}

func newRedisTicketStore(client *redis.Client, prefix string) *redisTicketStore {
	return &redisTicketStore{client: client, prefix: prefix}
}

func (store *redisTicketStore) Consume(ctx context.Context, digest string) ([]byte, error) {
	value, err := store.client.GetDel(ctx, store.prefix+digest).Bytes()
	if errors.Is(err, redis.Nil) {
		return nil, errors.New("websocket ticket is invalid or already consumed")
	}
	if err != nil {
		return nil, fmt.Errorf("websocket ticket store unavailable: %w", err)
	}
	return value, nil
}

func (authenticator *webSocketAuthenticator) Authenticate(r *http.Request) (*ClientAuth, error) {
	if rawTicket := strings.TrimSpace(r.URL.Query().Get("ticket")); rawTicket != "" {
		return authenticator.authenticateTicket(r.Context(), r, rawTicket)
	}
	if !authenticator.allowLegacyJWT {
		return nil, errors.New("websocket ticket is required")
	}
	return authenticator.authenticateLegacyJWT(r)
}

func (authenticator *webSocketAuthenticator) authenticateTicket(
	ctx context.Context,
	r *http.Request,
	rawTicket string,
) (*ClientAuth, error) {
	if !validTicketFormat(rawTicket) {
		return nil, errors.New("websocket ticket format is invalid")
	}
	if authenticator.tickets == nil {
		return nil, errors.New("websocket ticket store is unavailable")
	}
	digest := sha256.Sum256([]byte(rawTicket))
	encoded, err := authenticator.tickets.Consume(ctx, hex.EncodeToString(digest[:]))
	if err != nil {
		return nil, err
	}

	var claims ticketClaims
	decoder := json.NewDecoder(strings.NewReader(string(encoded)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&claims); err != nil {
		return nil, errors.New("websocket ticket payload is invalid")
	}
	issuedAt, err := parseTicketTime(claims.IssuedAt)
	if err != nil {
		return nil, errors.New("websocket ticket issue time is invalid")
	}
	expiresAt, err := parseTicketTime(claims.ExpiresAt)
	if err != nil {
		return nil, errors.New("websocket ticket expiry is invalid")
	}
	now := authenticator.now()
	if issuedAt.After(now.Add(10*time.Second)) || now.Sub(issuedAt) > 2*time.Minute ||
		!expiresAt.After(now) || expiresAt.After(now.Add(2*time.Minute)) ||
		expiresAt.Sub(issuedAt) > 2*time.Minute {
		return nil, errors.New("websocket ticket has expired or exceeds the allowed lifetime")
	}
	if claims.Version != 1 || claims.Audience != realtimeTicketAudience {
		return nil, errors.New("websocket ticket version or audience is invalid")
	}
	if strings.TrimSpace(claims.UserID) == "" || strings.TrimSpace(claims.SessionID) == "" {
		return nil, errors.New("websocket ticket identity is incomplete")
	}
	if claims.SessionVersion == nil || claims.TokenVersion == nil ||
		*claims.SessionVersion < 0 || *claims.TokenVersion < 0 {
		return nil, errors.New("websocket ticket session version is invalid")
	}

	auth := &ClientAuth{
		UserID:                  strings.TrimSpace(claims.UserID),
		Role:                    normalizeCode(claims.Role),
		StoreID:                 strings.TrimSpace(claims.StoreID),
		StoreCode:               normalizeCode(claims.StoreCode),
		DepartmentCode:          normalizeCode(claims.DepartmentCode),
		OrganizationNodeID:      strings.TrimSpace(claims.OrganizationNodeID),
		OrganizationAccessCodes: normalizeCodes(claims.OrganizationAccessCodes),
		FeatureCodes:            normalizeCodes(claims.FeatureCodes),
		SessionID:               strings.TrimSpace(claims.SessionID),
		Platform:                strings.ToLower(strings.TrimSpace(claims.Platform)),
		SessionVersion:          *claims.SessionVersion,
		TokenVersion:            *claims.TokenVersion,
		Method:                  "ticket",
	}
	if err := applySelectedStore(auth, r.URL); err != nil {
		return nil, err
	}
	return auth, nil
}

func (authenticator *webSocketAuthenticator) authenticateLegacyJWT(r *http.Request) (*ClientAuth, error) {
	if authenticator.jwtSecret == "" {
		return nil, errors.New("legacy websocket authentication is unavailable")
	}
	tokenValue := extractBearerToken(r)
	if tokenValue == "" {
		tokenValue = strings.TrimSpace(r.URL.Query().Get("access_token"))
	}
	if tokenValue == "" {
		return nil, errors.New("missing websocket credential")
	}

	claims := jwt.MapClaims{}
	token, err := jwt.ParseWithClaims(
		tokenValue,
		claims,
		func(_ *jwt.Token) (any, error) { return []byte(authenticator.jwtSecret), nil },
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithExpirationRequired(),
	)
	if err != nil || !token.Valid {
		return nil, errors.New("invalid websocket credential")
	}

	subject, err := claims.GetSubject()
	if err != nil || strings.TrimSpace(subject) == "" {
		return nil, errors.New("websocket identity is missing")
	}
	auth := &ClientAuth{
		UserID:                  strings.TrimSpace(subject),
		Role:                    normalizeCode(readClaimString(claims, "role")),
		StoreID:                 strings.TrimSpace(readClaimString(claims, "storeUuid")),
		StoreCode:               normalizeCode(readClaimString(claims, "storeCode")),
		DepartmentCode:          normalizeCode(readClaimString(claims, "departmentCode")),
		OrganizationNodeID:      strings.TrimSpace(readClaimString(claims, "organizationNodeId")),
		OrganizationAccessCodes: normalizeCodes(readClaimStringList(claims, "organizationAccessCodes")),
		FeatureCodes:            normalizeCodes(readClaimStringList(claims, "featureCodes")),
		SessionID:               strings.TrimSpace(readClaimString(claims, "sessionId")),
		Platform:                strings.ToLower(strings.TrimSpace(readClaimString(claims, "platform"))),
		SessionVersion:          readClaimInt(claims, "sessionVersion"),
		TokenVersion:            readClaimInt(claims, "tokenVersion"),
		Method:                  "legacy_jwt",
	}
	if err := applySelectedStore(auth, r.URL); err != nil {
		return nil, err
	}
	return auth, nil
}

func applySelectedStore(auth *ClientAuth, requestURL *url.URL) error {
	selectedStore := normalizeCode(requestURL.Query().Get("store_id"))
	if selectedStore == "" {
		return nil
	}
	if !auth.hasStoreAccess(selectedStore) {
		return errors.New("store subscription is outside authenticated scope")
	}
	auth.SelectedStore = selectedStore
	return nil
}

func validTicketFormat(value string) bool {
	if len(value) < 43 || len(value) > 128 {
		return false
	}
	for _, character := range value {
		if (character >= 'a' && character <= 'z') ||
			(character >= 'A' && character <= 'Z') ||
			(character >= '0' && character <= '9') ||
			character == '-' || character == '_' {
			continue
		}
		return false
	}
	return true
}

func parseTicketTime(raw json.RawMessage) (time.Time, error) {
	if len(raw) == 0 {
		return time.Time{}, errors.New("missing expiry")
	}
	var text string
	if err := json.Unmarshal(raw, &text); err == nil {
		return time.Parse(time.RFC3339Nano, text)
	}
	var numeric json.Number
	if err := json.Unmarshal(raw, &numeric); err != nil {
		return time.Time{}, err
	}
	value, err := strconv.ParseInt(numeric.String(), 10, 64)
	if err != nil {
		return time.Time{}, err
	}
	if value > 10_000_000_000 {
		return time.UnixMilli(value), nil
	}
	return time.Unix(value, 0), nil
}

func readClaimString(claims jwt.MapClaims, key string) string {
	value, ok := claims[key]
	if !ok || value == nil {
		return ""
	}
	text, _ := value.(string)
	return text
}

func readClaimStringList(claims jwt.MapClaims, key string) []string {
	value, ok := claims[key]
	if !ok || value == nil {
		return nil
	}
	switch typed := value.(type) {
	case []string:
		return typed
	case []any:
		values := make([]string, 0, len(typed))
		for _, item := range typed {
			if text, ok := item.(string); ok {
				values = append(values, text)
			}
		}
		return values
	default:
		return nil
	}
}

func readClaimInt(claims jwt.MapClaims, key string) int {
	value, ok := claims[key]
	if !ok || value == nil {
		return 0
	}
	switch typed := value.(type) {
	case float64:
		return int(typed)
	case int:
		return typed
	case json.Number:
		parsed, _ := strconv.Atoi(typed.String())
		return parsed
	default:
		return 0
	}
}

func extractBearerToken(r *http.Request) string {
	header := strings.TrimSpace(r.Header.Get("Authorization"))
	if len(header) < 7 || !strings.EqualFold(header[:7], "Bearer ") {
		return ""
	}
	return strings.TrimSpace(header[7:])
}

func normalizeCode(value string) string {
	return strings.ToUpper(strings.TrimSpace(value))
}

func normalizeCodes(values []string) []string {
	normalized := make([]string, 0, len(values))
	seen := make(map[string]struct{}, len(values))
	for _, value := range values {
		code := normalizeCode(value)
		if code == "" {
			continue
		}
		if _, exists := seen[code]; exists {
			continue
		}
		seen[code] = struct{}{}
		normalized = append(normalized, code)
	}
	return normalized
}
