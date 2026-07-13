package main

import (
	"context"
	"io"
	"log"
	"sync/atomic"
	"time"

	"github.com/gorilla/websocket"
)

type Client struct {
	conn        *websocket.Conn
	auth        *ClientAuth
	updatesOnly bool
	send        chan []byte
	socket      socketConfig
	logger      *log.Logger
	release     func()
}

type Hub struct {
	clients       map[*Client]struct{}
	broadcast     chan RoutedEvent
	revoke        chan SessionRevocation
	register      chan *Client
	unregister    chan *Client
	clientCount   atomic.Int64
	logger        *log.Logger
	sendQueueSize int
}

func newHub(logger *log.Logger, queueSizes ...int) *Hub {
	if logger == nil {
		logger = log.New(io.Discard, "", 0)
	}
	queueSize := 64
	if len(queueSizes) > 0 && queueSizes[0] > 0 {
		queueSize = queueSizes[0]
	}
	return &Hub{
		broadcast:     make(chan RoutedEvent),
		revoke:        make(chan SessionRevocation, 64),
		register:      make(chan *Client, 64),
		unregister:    make(chan *Client, 256),
		clients:       make(map[*Client]struct{}),
		logger:        logger,
		sendQueueSize: queueSize,
	}
}

func (hub *Hub) run(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			for client := range hub.clients {
				hub.remove(client, "service_shutdown")
			}
			return
		case client := <-hub.register:
			hub.clients[client] = struct{}{}
			hub.clientCount.Add(1)
			if client.updatesOnly {
				hub.logger.Printf("Public app-update client connected total=%d", hub.clientCount.Load())
			} else {
				hub.logger.Printf(
					"Realtime client connected user=%s role=%s authMethod=%s total=%d",
					client.auth.UserID,
					client.auth.Role,
					client.auth.Method,
					hub.clientCount.Load(),
				)
			}
		case client := <-hub.unregister:
			hub.remove(client, "client_closed")
		case event := <-hub.broadcast:
			for client := range hub.clients {
				if !client.canReceive(event) {
					continue
				}
				select {
				case client.send <- event.Message:
				default:
					hub.remove(client, "send_queue_full")
				}
			}
		case revocation := <-hub.revoke:
			for client := range hub.clients {
				if client.matchesRevocation(revocation) {
					hub.remove(client, "session_revoked")
				}
			}
		}
	}
}

func (hub *Hub) remove(client *Client, reason string) {
	if _, exists := hub.clients[client]; !exists {
		return
	}
	delete(hub.clients, client)
	hub.clientCount.Add(-1)
	close(client.send)
	if client.release != nil {
		client.release()
		client.release = nil
	}
	if client.updatesOnly {
		hub.logger.Printf("Public app-update client disconnected reason=%s total=%d", reason, hub.clientCount.Load())
		return
	}
	hub.logger.Printf(
		"Realtime client disconnected user=%s reason=%s total=%d",
		client.auth.UserID,
		reason,
		hub.clientCount.Load(),
	)
}

func (client *Client) canReceive(event RoutedEvent) bool {
	if client.updatesOnly {
		return event.Public && event.Type == appUpdateEventType
	}
	if client.auth == nil {
		return false
	}
	if event.Public {
		return event.Type == appUpdateEventType
	}
	return event.Audience.matches(client.auth)
}

func (client *Client) matchesRevocation(revocation SessionRevocation) bool {
	if client == nil || client.auth == nil || client.auth.UserID != revocation.UserID {
		return false
	}
	if revocation.SessionID != "" && client.auth.SessionID != revocation.SessionID {
		return false
	}
	if revocation.Platform != "" && client.auth.Platform != revocation.Platform {
		return false
	}
	return true
}

func (client *Client) readPump(hub *Hub) {
	defer func() {
		hub.unregister <- client
		client.conn.Close()
	}()
	client.conn.SetReadLimit(client.socket.readLimit)
	if err := client.conn.SetReadDeadline(time.Now().Add(client.socket.pongWait)); err != nil {
		return
	}
	client.conn.SetPongHandler(func(string) error {
		return client.conn.SetReadDeadline(time.Now().Add(client.socket.pongWait))
	})
	for {
		messageType, _, err := client.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseNormalClosure) {
				client.logger.Printf("Realtime client read failed error=%q", err)
			}
			return
		}
		if messageType == websocket.TextMessage || messageType == websocket.BinaryMessage {
			// This service is server-push only. Receiving application data is a
			// protocol violation and closes the connection without logging payload.
			return
		}
	}
}

func (client *Client) writePump() {
	ticker := time.NewTicker(client.socket.pingPeriod)
	defer func() {
		ticker.Stop()
		client.conn.Close()
	}()
	for {
		select {
		case message, ok := <-client.send:
			if err := client.conn.SetWriteDeadline(time.Now().Add(client.socket.writeWait)); err != nil {
				return
			}
			if !ok {
				_ = client.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := client.conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}
		case <-ticker.C:
			if err := client.conn.WriteControl(
				websocket.PingMessage,
				nil,
				time.Now().Add(client.socket.writeWait),
			); err != nil {
				return
			}
		}
	}
}
