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

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/gorilla/websocket"
	"github.com/redis/go-redis/v9"
)

var ctx = context.Background()

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
	UserID        string
	Role          string
	StoreCode     string
	SelectedStore string
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
		UserID:    subject,
		Role:      strings.ToUpper(strings.TrimSpace(readClaimString(claims, "role"))),
		StoreCode: strings.ToUpper(strings.TrimSpace(readClaimString(claims, "storeCode"))),
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

func extractBearerToken(r *http.Request) string {
	const prefix = "Bearer "
	header := strings.TrimSpace(r.Header.Get("Authorization"))
	if !strings.HasPrefix(header, prefix) {
		return ""
	}
	return strings.TrimSpace(strings.TrimPrefix(header, prefix))
}

type Client struct {
	conn *websocket.Conn
	auth *ClientAuth
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
	for {
		select {
		case client := <-h.register:
			h.clients[client] = true
			log.Printf("New client connected user=%s role=%s store=%s selectedStore=%s total=%d",
				client.auth.UserID, client.auth.Role, client.auth.StoreCode, client.auth.SelectedStore, len(h.clients))
		case client := <-h.unregister:
			if _, ok := h.clients[client]; ok {
				delete(h.clients, client)
				client.conn.Close()
				log.Printf("Client disconnected user=%s total=%d", client.auth.UserID, len(h.clients))
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
	if envelope.Type != "PAYMENT_NOTIFICATION" {
		return true
	}
	var payload struct {
		StoreCode string `json:"storeCode"`
	}
	if err := json.Unmarshal(envelope.Payload, &payload); err != nil {
		return false
	}
	storeCode := strings.ToUpper(strings.TrimSpace(payload.StoreCode))
	if c.auth.Role == "SUPER_ADMIN" {
		return c.auth.SelectedStore != "" && c.auth.SelectedStore == storeCode
	}
	return c.auth.StoreCode != "" && c.auth.StoreCode == storeCode
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

	pubsub := rdb.Subscribe(ctx, "WARRANTY_STATUS_UPDATED", "PAYMENT_NOTIFICATION_READY")
	defer pubsub.Close()
	log.Println("Listening to Redis channels: WARRANTY_STATUS_UPDATED, PAYMENT_NOTIFICATION_READY...")

	ch := pubsub.Channel()

	for msg := range ch {
		log.Println("Received event from Redis:", msg.Payload)
		// Transform message if needed, or just broadcast raw JSON
		type BroadcastMsg struct {
			Type    string          `json:"type"`
			Payload json.RawMessage `json:"payload"`
		}

		eventType := "WARRANTY_EVENT"
		if msg.Channel == "PAYMENT_NOTIFICATION_READY" {
			eventType = "PAYMENT_NOTIFICATION"
		}
		formattedMsg, _ := json.Marshal(BroadcastMsg{
			Type:    eventType,
			Payload: json.RawMessage(msg.Payload),
		})

		h.broadcast <- formattedMsg
	}
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

		conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
		if err != nil {
			log.Println("upgrade error:", err)
			return
		}
		client := &Client{conn: conn, auth: auth}
		hub.register <- client

		// Listen for incoming websocket messages (e.g for chat)
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
				log.Printf("Received client message (%d bytes)", len(message))
			}
		}(client)
	})
}
