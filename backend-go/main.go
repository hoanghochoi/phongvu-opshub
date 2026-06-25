package main

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/gorilla/websocket"
	"github.com/redis/go-redis/v9"
)

var ctx = context.Background()

const (
	warrantyRedisChannel               = "WARRANTY_STATUS_UPDATED"
	paymentRedisChannel                = "PAYMENT_NOTIFICATION_READY"
	appVersionRedisChannel             = "APP_VERSION_UPDATED"
	statementOrderTransferRedisChannel = "STATEMENT_ORDER_TRANSFER_REQUESTED"
	offsetAdjustmentRedisChannel       = "OFFSET_ADJUSTMENT_UPDATED"
	warrantyEventType                  = "WARRANTY_EVENT"
	paymentEventType                   = "PAYMENT_NOTIFICATION"
	appUpdateEventType                 = "APP_UPDATE"
	statementOrderTransferEventType    = "STATEMENT_ORDER_TRANSFER_REQUEST"
	offsetAdjustmentEventType          = "OFFSET_ADJUSTMENT_NOTIFICATION"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return isOriginAllowed(r)
	},
}

func isOriginAllowed(r *http.Request) bool {
	origin := r.Header.Get("Origin")
	if origin == "" {
		return true
	}

	allowedOrigins := strings.TrimSpace(os.Getenv("ALLOWED_ORIGINS"))
	if allowedOrigins == "*" {
		return true
	}

	if allowedOrigins == "" {
		parsedOrigin, err := url.Parse(origin)
		if err != nil {
			return false
		}
		host := parsedOrigin.Hostname()
		return host == "localhost" || host == "127.0.0.1" || host == "::1"
	}

	for _, allowedOrigin := range strings.Split(allowedOrigins, ",") {
		if strings.TrimSpace(allowedOrigin) == origin {
			return true
		}
	}
	return false
}

type ClientAuth struct {
	UserID                  string
	Role                    string
	StoreCode               string
	DepartmentCode          string
	OrganizationAccessCodes []string
	SelectedStore           string
}

func authenticateWebSocket(r *http.Request) (*ClientAuth, error) {
	jwtSecret := strings.TrimSpace(os.Getenv("JWT_SECRET"))
	if jwtSecret == "" {
		return nil, errors.New("JWT_SECRET is not configured")
	}

	tokenValue := extractBearerToken(r)
	if tokenValue == "" {
		tokenValue = strings.TrimSpace(r.URL.Query().Get("access_token"))
	}
	if tokenValue == "" {
		return nil, errors.New("missing websocket access token")
	}

	claims := jwt.MapClaims{}
	token, err := jwt.ParseWithClaims(tokenValue, claims, func(token *jwt.Token) (any, error) {
		if token.Method.Alg() != jwt.SigningMethodHS256.Alg() {
			return nil, errors.New("unexpected JWT signing method")
		}
		return []byte(jwtSecret), nil
	})
	if err != nil || !token.Valid {
		return nil, errors.New("invalid websocket access token")
	}

	subject, err := claims.GetSubject()
	if err != nil {
		return nil, errors.New("missing JWT subject")
	}
	auth := &ClientAuth{
		UserID:         subject,
		Role:           strings.ToUpper(strings.TrimSpace(readClaimString(claims, "role"))),
		StoreCode:      strings.ToUpper(strings.TrimSpace(readClaimString(claims, "storeCode"))),
		DepartmentCode: strings.ToUpper(strings.TrimSpace(readClaimString(claims, "departmentCode"))),
		OrganizationAccessCodes: normalizeAccessCodes(
			readClaimStringList(claims, "organizationAccessCodes"),
		),
	}
	selectedStore := strings.ToUpper(strings.TrimSpace(r.URL.Query().Get("store_id")))
	if auth.Role == "SUPER_ADMIN" {
		auth.SelectedStore = selectedStore
	} else if selectedStore != "" && selectedStore != auth.StoreCode {
		return nil, errors.New("store subscription is outside token scope")
	}
	return auth, nil
}

func readClaimString(claims jwt.MapClaims, key string) string {
	value, ok := claims[key]
	if !ok || value == nil {
		return ""
	}
	switch typed := value.(type) {
	case string:
		return typed
	default:
		return ""
	}
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

func normalizeAccessCodes(values []string) []string {
	normalized := make([]string, 0, len(values))
	seen := make(map[string]bool, len(values))
	for _, value := range values {
		code := strings.ToUpper(strings.TrimSpace(value))
		if code == "" || seen[code] {
			continue
		}
		seen[code] = true
		normalized = append(normalized, code)
	}
	return normalized
}

func extractBearerToken(r *http.Request) string {
	const prefix = "Bearer "
	header := strings.TrimSpace(r.Header.Get("Authorization"))
	if !strings.HasPrefix(header, prefix) {
		return ""
	}
	return strings.TrimSpace(strings.TrimPrefix(header, prefix))
}

type Client struct {
	conn        *websocket.Conn
	auth        *ClientAuth
	updatesOnly bool
}

// Hub manages WebSocket clients
type Hub struct {
	clients    map[*Client]bool
	broadcast  chan []byte
	register   chan *Client
	unregister chan *Client
}

func newHub() *Hub {
	return &Hub{
		broadcast:  make(chan []byte),
		register:   make(chan *Client),
		unregister: make(chan *Client),
		clients:    make(map[*Client]bool),
	}
}

func (h *Hub) run() {
	pingTicker := time.NewTicker(30 * time.Second)
	defer pingTicker.Stop()
	for {
		select {
		case client := <-h.register:
			h.clients[client] = true
			if client.updatesOnly {
				log.Printf("New public app-update client connected total=%d", len(h.clients))
			} else {
				log.Printf("New client connected user=%s role=%s store=%s selectedStore=%s total=%d",
					client.auth.UserID, client.auth.Role, client.auth.StoreCode, client.auth.SelectedStore, len(h.clients))
			}
		case client := <-h.unregister:
			if _, ok := h.clients[client]; ok {
				delete(h.clients, client)
				client.conn.Close()
				if client.updatesOnly {
					log.Printf("Public app-update client disconnected total=%d", len(h.clients))
				} else {
					log.Printf("Client disconnected user=%s total=%d", client.auth.UserID, len(h.clients))
				}
			}
		case message := <-h.broadcast:
			for client := range h.clients {
				if !client.canReceive(message) {
					continue
				}
				err := client.conn.WriteMessage(websocket.TextMessage, message)
				if err != nil {
					log.Printf("error: %v", err)
					client.conn.Close()
					delete(h.clients, client)
				}
			}
		case <-pingTicker.C:
			for client := range h.clients {
				if err := client.conn.WriteControl(
					websocket.PingMessage,
					nil,
					time.Now().Add(5*time.Second),
				); err != nil {
					log.Printf("WebSocket heartbeat failed: %v", err)
					client.conn.Close()
					delete(h.clients, client)
				}
			}
		}
	}
}

func (c *Client) canReceive(message []byte) bool {
	var envelope struct {
		Type    string          `json:"type"`
		Payload json.RawMessage `json:"payload"`
	}
	if err := json.Unmarshal(message, &envelope); err != nil {
		return false
	}
	if c.updatesOnly {
		return envelope.Type == appUpdateEventType
	}
	if c.auth == nil {
		return false
	}
	if envelope.Type != paymentEventType && envelope.Type != statementOrderTransferEventType && envelope.Type != offsetAdjustmentEventType {
		return true
	}
	var payload struct {
		StoreCode string `json:"storeCode"`
	}
	if err := json.Unmarshal(envelope.Payload, &payload); err != nil {
		return false
	}
	storeCode := strings.ToUpper(strings.TrimSpace(payload.StoreCode))
	if envelope.Type == offsetAdjustmentEventType {
		if c.auth.canReviewOffsetAdjustments() {
			return c.auth.SelectedStore == "" || c.auth.SelectedStore == storeCode
		}
		return c.auth.StoreCode != "" && c.auth.StoreCode == storeCode
	}
	if c.auth.Role == "SUPER_ADMIN" && envelope.Type == statementOrderTransferEventType {
		return c.auth.SelectedStore == "" || c.auth.SelectedStore == storeCode
	}
	if c.auth.Role == "SUPER_ADMIN" {
		return c.auth.SelectedStore != "" && c.auth.SelectedStore == storeCode
	}
	return c.auth.StoreCode != "" && c.auth.StoreCode == storeCode
}

func (auth *ClientAuth) canReviewOffsetAdjustments() bool {
	if auth == nil {
		return false
	}
	if auth.Role == "SUPER_ADMIN" {
		return true
	}
	if auth.DepartmentCode == "ACC" || auth.DepartmentCode == "FIN_ACC" {
		return true
	}
	for _, code := range auth.OrganizationAccessCodes {
		if code == "ACC" || code == "FIN_ACC" {
			return true
		}
	}
	return false
}

// Subscribe to Redis events from NestJS
func (h *Hub) listenToRedis() {
	redisHost := os.Getenv("REDIS_HOST")
	if redisHost == "" {
		redisHost = "localhost"
	}
	redisPort := os.Getenv("REDIS_PORT")
	if redisPort == "" {
		redisPort = "6379"
	}

	rdb := redis.NewClient(&redis.Options{
		Addr: redisHost + ":" + redisPort,
	})

	pubsub := rdb.Subscribe(
		ctx,
		warrantyRedisChannel,
		paymentRedisChannel,
		appVersionRedisChannel,
		statementOrderTransferRedisChannel,
		offsetAdjustmentRedisChannel,
	)
	defer pubsub.Close()
	log.Println("Listening to Redis channels: WARRANTY_STATUS_UPDATED, PAYMENT_NOTIFICATION_READY, APP_VERSION_UPDATED, STATEMENT_ORDER_TRANSFER_REQUESTED, OFFSET_ADJUSTMENT_UPDATED...")

	ch := pubsub.Channel()

	for msg := range ch {
		log.Printf("Received event from Redis channel=%s payloadBytes=%d", msg.Channel, len(msg.Payload))
		formattedMsg, ok := formatRedisEvent(msg.Channel, msg.Payload)
		if !ok {
			log.Printf("Ignored unsupported or invalid Redis event channel=%s", msg.Channel)
			continue
		}
		h.broadcast <- formattedMsg
	}
}

func formatRedisEvent(channel string, payload string) ([]byte, bool) {
	eventType := ""
	switch channel {
	case warrantyRedisChannel:
		eventType = warrantyEventType
	case paymentRedisChannel:
		eventType = paymentEventType
	case appVersionRedisChannel:
		eventType = appUpdateEventType
	case statementOrderTransferRedisChannel:
		eventType = statementOrderTransferEventType
	case offsetAdjustmentRedisChannel:
		eventType = offsetAdjustmentEventType
	default:
		return nil, false
	}

	if !json.Valid([]byte(payload)) {
		return nil, false
	}
	formatted, err := json.Marshal(struct {
		Type    string          `json:"type"`
		Payload json.RawMessage `json:"payload"`
	}{
		Type:    eventType,
		Payload: json.RawMessage(payload),
	})
	return formatted, err == nil
}

func main() {
	hub := newHub()
	go hub.run()
	go hub.listenToRedis()

	r := gin.Default()
	registerRoutes(r, hub)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Println("Golang Realtime Service starting on port", port)
	r.Run(":" + port)
}

func registerRoutes(r *gin.Engine, hub *Hub) {
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "ok",
			"service": "backend-go",
		})
	})

	r.GET("/ws", func(c *gin.Context) {
		auth, err := authenticateWebSocket(c.Request)
		if err != nil {
			log.Println("websocket auth rejected:", err)
			c.AbortWithStatus(http.StatusUnauthorized)
			return
		}
		serveWebSocket(c, hub, auth, false)
	})

	r.GET("/ws/app-updates", func(c *gin.Context) {
		serveWebSocket(c, hub, nil, true)
	})
}

func serveWebSocket(c *gin.Context, hub *Hub, auth *ClientAuth, updatesOnly bool) {
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Println("upgrade error:", err)
		return
	}
	client := &Client{conn: conn, auth: auth, updatesOnly: updatesOnly}
	conn.SetReadLimit(4096)
	hub.register <- client

	go func(client *Client) {
		defer func() {
			hub.unregister <- client
		}()
		for {
			_, message, err := client.conn.ReadMessage()
			if err != nil {
				if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
					log.Printf("error: %v", err)
				}
				break
			}
			if client.updatesOnly {
				break
			}
			log.Printf("Received client message (%d bytes)", len(message))
		}
	}(client)
}
