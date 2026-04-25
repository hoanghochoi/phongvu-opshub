package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"github.com/redis/go-redis/v9"
)

var ctx = context.Background()

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true // Allow all for MVP, restrict in production
	},
}

// Hub manages WebSocket clients
type Hub struct {
	clients    map[*websocket.Conn]bool
	broadcast  chan []byte
	register   chan *websocket.Conn
	unregister chan *websocket.Conn
}

func newHub() *Hub {
	return &Hub{
		broadcast:  make(chan []byte),
		register:   make(chan *websocket.Conn),
		unregister: make(chan *websocket.Conn),
		clients:    make(map[*websocket.Conn]bool),
	}
}

func (h *Hub) run() {
	for {
		select {
		case client := <-h.register:
			h.clients[client] = true
			log.Println("New client connected. Total:", len(h.clients))
		case client := <-h.unregister:
			if _, ok := h.clients[client]; ok {
				delete(h.clients, client)
				client.Close()
				log.Println("Client disconnected. Total:", len(h.clients))
			}
		case message := <-h.broadcast:
			for client := range h.clients {
				err := client.WriteMessage(websocket.TextMessage, message)
				if err != nil {
					log.Printf("error: %v", err)
					client.Close()
					delete(h.clients, client)
				}
			}
		}
	}
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

	pubsub := rdb.Subscribe(ctx, "WARRANTY_STATUS_UPDATED")
	defer pubsub.Close()
	log.Println("Listening to Redis channel: WARRANTY_STATUS_UPDATED...")

	ch := pubsub.Channel()

	for msg := range ch {
		log.Println("Received event from Redis:", msg.Payload)
		// Transform message if needed, or just broadcast raw JSON
		type BroadcastMsg struct {
			Type    string          `json:"type"`
			Payload json.RawMessage `json:"payload"`
		}

		formattedMsg, _ := json.Marshal(BroadcastMsg{
			Type:    "WARRANTY_EVENT",
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

	r.GET("/ws", func(c *gin.Context) {
		conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
		if err != nil {
			log.Println("upgrade error:", err)
			return
		}
		hub.register <- conn

		// Listen for incoming websocket messages (e.g for chat)
		go func(c *websocket.Conn) {
			defer func() {
				hub.unregister <- c
			}()
			for {
				_, message, err := c.ReadMessage()
				if err != nil {
					if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
						log.Printf("error: %v", err)
					}
					break
				}
				log.Printf("Received message: %s", message)

				// Echo back for now. In real chat, save to GORM here.
				hub.broadcast <- message
			}
		}(conn)
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Println("Golang Realtime Service starting on port", port)
	r.Run(":" + port)
}
