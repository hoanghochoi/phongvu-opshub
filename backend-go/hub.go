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
	conn            *websocket.Conn
	auth            *ClientAuth
	updatesOnly     bool
	protocolVersion int
	send            chan []byte
	socket          socketConfig
	logger          *log.Logger
	release         func()
	closeCode       int
	closeReason     string
}

type protocolResync struct {
	version int
	reason  string
}

type Hub struct {
	clients       map[*Client]struct{}
	broadcast     chan RoutedEvent
	revoke        chan SessionRevocation
	resync        chan protocolResync
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
		resync:        make(chan protocolResync, 1),
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
					"Realtime client connected user=%s role=%s authMethod=%s protocolVersion=%d total=%d",
					client.auth.UserID,
					client.auth.Role,
					client.auth.Method,
					client.effectiveProtocolVersion(),
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
					if event.Type == accessChangedEventType {
						// Access claims are captured when the one-time ticket is
						// consumed. Deliver the invalidation signal, then force this
						// recipient to reconnect so stale grants cannot authorize any
						// later realtime event even if a client ignores the signal.
						hub.removeWithClose(
							client,
							"access_changed",
							websocket.CloseServiceRestart,
							"resync_required",
						)
					}
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
		case resync := <-hub.resync:
			disconnected := 0
			for client := range hub.clients {
				if client.effectiveProtocolVersion() != resync.version {
					continue
				}
				hub.removeWithClose(
					client,
					resync.reason,
					websocket.CloseServiceRestart,
					"resync_required",
				)
				disconnected++
			}
			hub.logger.Printf(
				"Realtime protocol resync requested protocolVersion=%d reason=%s disconnected=%d",
				resync.version,
				resync.reason,
				disconnected,
			)
		}
	}
}

func (hub *Hub) remove(client *Client, reason string) {
	hub.removeWithClose(client, reason, 0, "")
}

func (hub *Hub) removeWithClose(client *Client, reason string, closeCode int, closeReason string) {
	if _, exists := hub.clients[client]; !exists {
		return
	}
	delete(hub.clients, client)
	client.closeCode = closeCode
	client.closeReason = closeReason
	close(client.send)
	if client.release != nil {
		client.release()
		client.release = nil
	}
	// Publish the lower count only after the client close state and limiter
	// release are complete. Observers that use clientCount as the completion
	// barrier must not see a half-removed client.
	hub.clientCount.Add(-1)
	if client.updatesOnly {
		hub.logger.Printf("Public app-update client disconnected reason=%s total=%d", reason, hub.clientCount.Load())
		return
	}
	hub.logger.Printf(
		"Realtime client disconnected user=%s protocolVersion=%d reason=%s total=%d",
		client.auth.UserID,
		client.effectiveProtocolVersion(),
		reason,
		hub.clientCount.Load(),
	)
}

func (hub *Hub) requestProtocolResync(version int, reason string) {
	select {
	case hub.resync <- protocolResync{version: version, reason: reason}:
	default:
		// Một yêu cầu đang chờ sẽ đóng toàn bộ client của protocol này; không
		// chặn Redis listener hoặc xếp thêm tín hiệu trùng lặp.
	}
}

func (client *Client) canReceive(event RoutedEvent) bool {
	if client.updatesOnly {
		return event.Public && event.Type == appUpdateEventType
	}
	if client.auth == nil {
		return false
	}
	// Public update signals have a dedicated unauthenticated socket. Keeping
	// them off authenticated protocols prevents the shared v2 stream (and the
	// legacy feature stream) from becoming a second app-update transport.
	if event.Public {
		return false
	}
	eventVersion := event.ProtocolVersion
	if eventVersion == 0 {
		eventVersion = webSocketProtocolV1
	}
	if client.effectiveProtocolVersion() != eventVersion {
		return false
	}
	if event.AuthenticatedOnly {
		return client.auth != nil
	}
	return event.Audience.matches(client.auth)
}

func (client *Client) effectiveProtocolVersion() int {
	if client.protocolVersion <= 0 {
		return webSocketProtocolV1
	}
	return client.protocolVersion
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
				if client.closeCode == 0 {
					_ = client.conn.WriteMessage(websocket.CloseMessage, []byte{})
					return
				}
				_ = client.conn.WriteControl(
					websocket.CloseMessage,
					websocket.FormatCloseMessage(client.closeCode, client.closeReason),
					time.Now().Add(client.socket.writeWait),
				)
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
