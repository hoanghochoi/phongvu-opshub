package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	logger := log.New(os.Stdout, "", log.LstdFlags|log.LUTC)
	config, err := loadConfig()
	if err != nil {
		logger.Fatal("Realtime configuration is invalid: ", err)
	}

	redisClient := newRedisClient(config)
	defer redisClient.Close()

	redisState := newRedisReadiness(redisClient)
	hub := newHub(logger, config.sendQueueSize)
	authenticator := newWebSocketAuthenticator(
		config,
		newRedisTicketStore(redisClient, config.ticketKeyPrefix),
	)
	limiter := newConnectionLimiter(config.connectionLimits)

	serviceContext, stopService := signal.NotifyContext(
		context.Background(),
		syscall.SIGINT,
		syscall.SIGTERM,
	)
	defer stopService()

	go hub.run(serviceContext)
	go listenToRedis(serviceContext, redisClient, redisState, hub, logger)

	router := newRouter(serverDependencies{
		hub:           hub,
		authenticator: authenticator,
		readiness:     redisState,
		limiter:       limiter,
		logger:        logger,
		socket:        config.socket,
	})
	server := &http.Server{
		Addr:              ":" + config.port,
		Handler:           router,
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       75 * time.Second,
		MaxHeaderBytes:    16 << 10,
	}

	serverErrors := make(chan error, 1)
	go func() {
		logger.Printf("Realtime service started port=%s legacyJwtEnabled=%t", config.port, config.allowLegacyJWT)
		serverErrors <- server.ListenAndServe()
	}()

	select {
	case <-serviceContext.Done():
	case serveErr := <-serverErrors:
		if serveErr != nil && !errors.Is(serveErr, http.ErrServerClosed) {
			logger.Fatal("Realtime service stopped unexpectedly: ", serveErr)
		}
	}

	shutdownContext, cancelShutdown := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancelShutdown()
	if err := server.Shutdown(shutdownContext); err != nil {
		logger.Printf("Realtime service shutdown failed error=%q", err)
	}
}
