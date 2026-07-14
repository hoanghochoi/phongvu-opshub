package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"log"
	"net"
	"net/http"
	"net/url"
	"runtime/debug"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	HandshakeTimeout: 10 * time.Second,
	CheckOrigin: func(r *http.Request) bool {
		return isOriginAllowed(r)
	},
}

type serverDependencies struct {
	hub           *Hub
	authenticator *webSocketAuthenticator
	readiness     readinessChecker
	limiter       *connectionLimiter
	logger        *log.Logger
	socket        socketConfig
}

type connectionLimiter struct {
	mu             sync.Mutex
	config         connectionLimitConfig
	total          int
	byIP           map[string]int
	byUser         map[string]int
	handshakeByIP  map[string]handshakeWindow
	lastWindowTrim time.Time
}

type handshakeWindow struct {
	count   int
	resetAt time.Time
}

const maxTrackedHandshakeIPs = 10_000

func newConnectionLimiter(config connectionLimitConfig) *connectionLimiter {
	return &connectionLimiter{
		config:         config,
		byIP:           make(map[string]int),
		byUser:         make(map[string]int),
		handshakeByIP:  make(map[string]handshakeWindow),
		lastWindowTrim: time.Now(),
	}
}

func newRouter(dependencies serverDependencies) *gin.Engine {
	router := gin.New()
	router.Use(accessLogger(dependencies.logger), safeRecovery(dependencies.logger))
	registerRoutes(router, dependencies)
	return router
}

func registerRoutes(router *gin.Engine, dependencies serverDependencies) {
	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"service": "backend-go", "status": "ok"})
	})
	router.GET("/ready", func(c *gin.Context) {
		if dependencies.readiness == nil || dependencies.readiness.Ready(c.Request.Context()) != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"service": "backend-go", "status": "not_ready"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"service": "backend-go", "status": "ready"})
	})

	router.GET("/ws", func(c *gin.Context) {
		clientIP := requestClientIP(c.Request)
		if !dependencies.limiter.allowHandshake(clientIP, time.Now()) {
			c.AbortWithStatus(http.StatusTooManyRequests)
			return
		}
		auth, err := dependencies.authenticator.Authenticate(c.Request)
		if err != nil {
			dependencies.logger.Printf("Realtime authentication rejected clientIpHash=%s", clientIPLogID(clientIP))
			c.AbortWithStatus(http.StatusUnauthorized)
			return
		}
		serveWebSocket(c, dependencies, auth, false, clientIP, webSocketProtocolV1)
	})

	router.GET("/ws/v2", func(c *gin.Context) {
		clientIP := requestClientIP(c.Request)
		if !dependencies.limiter.allowHandshake(clientIP, time.Now()) {
			c.AbortWithStatus(http.StatusTooManyRequests)
			return
		}
		if dependencies.readiness == nil || dependencies.readiness.Ready(c.Request.Context()) != nil {
			dependencies.logger.Printf("Realtime v2 rejected because Redis subscription is unavailable clientIpHash=%s", clientIPLogID(clientIP))
			c.AbortWithStatus(http.StatusServiceUnavailable)
			return
		}
		auth, err := dependencies.authenticator.Authenticate(c.Request)
		if err != nil {
			dependencies.logger.Printf("Realtime v2 authentication rejected clientIpHash=%s", clientIPLogID(clientIP))
			c.AbortWithStatus(http.StatusUnauthorized)
			return
		}
		serveWebSocket(c, dependencies, auth, false, clientIP, webSocketProtocolV2)
	})

	router.GET("/ws/app-updates", func(c *gin.Context) {
		clientIP := requestClientIP(c.Request)
		if !dependencies.limiter.allowHandshake(clientIP, time.Now()) {
			c.AbortWithStatus(http.StatusTooManyRequests)
			return
		}
		serveWebSocket(c, dependencies, nil, true, clientIP, webSocketProtocolV1)
	})
}

func serveWebSocket(
	c *gin.Context,
	dependencies serverDependencies,
	auth *ClientAuth,
	updatesOnly bool,
	clientIP string,
	protocolVersion int,
) {
	userID := ""
	if auth != nil {
		userID = auth.UserID
	}
	release, allowed := dependencies.limiter.acquire(clientIP, userID)
	if !allowed {
		c.AbortWithStatus(http.StatusTooManyRequests)
		return
	}

	connection, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		release()
		dependencies.logger.Printf("Realtime websocket upgrade failed clientIpHash=%s", clientIPLogID(clientIP))
		return
	}
	client := &Client{
		conn:            connection,
		auth:            auth,
		updatesOnly:     updatesOnly,
		protocolVersion: protocolVersion,
		send:            make(chan []byte, dependencies.hub.sendQueueSize),
		socket:          dependencies.socket,
		logger:          dependencies.logger,
		release:         release,
	}
	dependencies.hub.register <- client
	go client.writePump()
	go client.readPump(dependencies.hub)
}

func (limiter *connectionLimiter) allowHandshake(ip string, now time.Time) bool {
	limiter.mu.Lock()
	defer limiter.mu.Unlock()
	if _, tracked := limiter.handshakeByIP[ip]; !tracked && len(limiter.handshakeByIP) >= maxTrackedHandshakeIPs {
		ip = "__overflow__"
	}
	window := limiter.handshakeByIP[ip]
	if window.resetAt.IsZero() || !now.Before(window.resetAt) {
		window = handshakeWindow{resetAt: now.Add(time.Minute)}
	}
	if window.count >= limiter.config.maxHandshakesPerIPMin {
		limiter.handshakeByIP[ip] = window
		return false
	}
	window.count++
	limiter.handshakeByIP[ip] = window
	if now.Sub(limiter.lastWindowTrim) >= time.Minute {
		for key, candidate := range limiter.handshakeByIP {
			if !now.Before(candidate.resetAt) {
				delete(limiter.handshakeByIP, key)
			}
		}
		limiter.lastWindowTrim = now
	}
	return true
}

func (limiter *connectionLimiter) acquire(ip string, userID string) (func(), bool) {
	limiter.mu.Lock()
	defer limiter.mu.Unlock()
	if limiter.total >= limiter.config.maxTotal || limiter.byIP[ip] >= limiter.config.maxPerIP {
		return nil, false
	}
	if userID != "" && limiter.byUser[userID] >= limiter.config.maxPerUser {
		return nil, false
	}
	limiter.total++
	limiter.byIP[ip]++
	if userID != "" {
		limiter.byUser[userID]++
	}

	var once sync.Once
	return func() {
		once.Do(func() {
			limiter.mu.Lock()
			defer limiter.mu.Unlock()
			limiter.total--
			decrementCount(limiter.byIP, ip)
			if userID != "" {
				decrementCount(limiter.byUser, userID)
			}
		})
	}, true
}

func decrementCount(counts map[string]int, key string) {
	if counts[key] <= 1 {
		delete(counts, key)
		return
	}
	counts[key]--
}

func requestClientIP(request *http.Request) string {
	remoteIP := request.RemoteAddr
	if host, _, err := net.SplitHostPort(request.RemoteAddr); err == nil {
		remoteIP = host
	}
	parsedRemote := net.ParseIP(strings.TrimSpace(remoteIP))
	if parsedRemote == nil || (!parsedRemote.IsPrivate() && !parsedRemote.IsLoopback()) {
		return remoteIP
	}
	for _, header := range []string{"CF-Connecting-IP", "X-Real-IP"} {
		candidate := strings.TrimSpace(request.Header.Get(header))
		if net.ParseIP(candidate) != nil {
			return candidate
		}
	}
	forwarded := strings.Split(request.Header.Get("X-Forwarded-For"), ",")
	if len(forwarded) > 0 {
		candidate := strings.TrimSpace(forwarded[0])
		if net.ParseIP(candidate) != nil {
			return candidate
		}
	}
	return remoteIP
}

func clientIPLogID(clientIP string) string {
	digest := sha256.Sum256([]byte(clientIP))
	return hex.EncodeToString(digest[:])[:12]
}

func isOriginAllowed(r *http.Request) bool {
	origin := r.Header.Get("Origin")
	if origin == "" {
		return true
	}
	allowedOrigins := strings.TrimSpace(envOrDefault("ALLOWED_ORIGINS", ""))
	if allowedOrigins == "*" {
		return true
	}
	if allowedOrigins == "" {
		parsedOrigin, err := url.Parse(origin)
		if err != nil || (parsedOrigin.Scheme != "http" && parsedOrigin.Scheme != "https") {
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

func accessLogger(logger *log.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		startedAt := time.Now()
		c.Next()
		route := c.FullPath()
		if route == "" {
			route = "<unmatched>"
		}
		logger.Printf(
			"HTTP request method=%s path=%s status=%d durationMs=%d",
			safeHTTPMethod(c.Request.Method),
			route,
			c.Writer.Status(),
			time.Since(startedAt).Milliseconds(),
		)
	}
}

func safeHTTPMethod(method string) string {
	switch method {
	case http.MethodGet:
		return "GET"
	case http.MethodHead:
		return "HEAD"
	case http.MethodPost:
		return "POST"
	case http.MethodPut:
		return "PUT"
	case http.MethodPatch:
		return "PATCH"
	case http.MethodDelete:
		return "DELETE"
	case http.MethodConnect:
		return "CONNECT"
	case http.MethodOptions:
		return "OPTIONS"
	case http.MethodTrace:
		return "TRACE"
	default:
		return "<other>"
	}
}

func safeRecovery(logger *log.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		defer func() {
			if recovered := recover(); recovered != nil {
				stack := bytes.ReplaceAll(debug.Stack(), []byte("\n"), []byte(" | "))
				logger.Printf("HTTP panic recovered errorType=%T stack=%s", recovered, stack)
				c.AbortWithStatus(http.StatusInternalServerError)
			}
		}()
		c.Next()
	}
}
