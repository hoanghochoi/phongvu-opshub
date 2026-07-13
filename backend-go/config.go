package main

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
)

const defaultTicketKeyPrefix = "opshub:realtime:ticket:"

type serviceConfig struct {
	port             string
	redisAddress     string
	redisUsername    string
	redisPassword    string
	redisDB          int
	jwtSecret        string
	allowLegacyJWT   bool
	ticketKeyPrefix  string
	sendQueueSize    int
	socket           socketConfig
	connectionLimits connectionLimitConfig
}

type socketConfig struct {
	writeWait  time.Duration
	pongWait   time.Duration
	pingPeriod time.Duration
	readLimit  int64
}

type connectionLimitConfig struct {
	maxTotal              int
	maxPerIP              int
	maxPerUser            int
	maxHandshakesPerIPMin int
}

func loadConfig() (serviceConfig, error) {
	port := envOrDefault("PORT", "8080")
	redisHost := envOrDefault("REDIS_HOST", "localhost")
	redisPort := envOrDefault("REDIS_PORT", "6379")
	redisDB, err := positiveOrZeroEnv("REDIS_DB", 0)
	if err != nil {
		return serviceConfig{}, err
	}
	allowLegacyJWT, err := boolEnv("WS_ALLOW_LEGACY_JWT", false)
	if err != nil {
		return serviceConfig{}, err
	}
	jwtSecret := strings.TrimSpace(os.Getenv("JWT_SECRET"))
	if allowLegacyJWT && jwtSecret == "" {
		return serviceConfig{}, errors.New("JWT_SECRET is required when WS_ALLOW_LEGACY_JWT is enabled")
	}

	sendQueueSize, err := positiveIntEnv("WS_SEND_QUEUE_SIZE", 64)
	if err != nil {
		return serviceConfig{}, err
	}
	maxTotal, err := positiveIntEnv("WS_MAX_CONNECTIONS", 1000)
	if err != nil {
		return serviceConfig{}, err
	}
	maxPerIP, err := positiveIntEnv("WS_MAX_CONNECTIONS_PER_IP", 100)
	if err != nil {
		return serviceConfig{}, err
	}
	maxPerUser, err := positiveIntEnv("WS_MAX_CONNECTIONS_PER_USER", 5)
	if err != nil {
		return serviceConfig{}, err
	}
	maxHandshakes, err := positiveIntEnv("WS_MAX_HANDSHAKES_PER_IP_MINUTE", 60)
	if err != nil {
		return serviceConfig{}, err
	}

	pongSeconds, err := positiveIntEnv("WS_PONG_TIMEOUT_SECONDS", 60)
	if err != nil {
		return serviceConfig{}, err
	}
	writeSeconds, err := positiveIntEnv("WS_WRITE_TIMEOUT_SECONDS", 10)
	if err != nil {
		return serviceConfig{}, err
	}
	readLimit, err := positiveIntEnv("WS_READ_LIMIT_BYTES", 4096)
	if err != nil {
		return serviceConfig{}, err
	}
	pongWait := time.Duration(pongSeconds) * time.Second

	return serviceConfig{
		port:            port,
		redisAddress:    redisHost + ":" + redisPort,
		redisUsername:   strings.TrimSpace(os.Getenv("REDIS_USERNAME")),
		redisPassword:   os.Getenv("REDIS_PASSWORD"),
		redisDB:         redisDB,
		jwtSecret:       jwtSecret,
		allowLegacyJWT:  allowLegacyJWT,
		ticketKeyPrefix: envOrDefault("WS_TICKET_KEY_PREFIX", defaultTicketKeyPrefix),
		sendQueueSize:   sendQueueSize,
		socket: socketConfig{
			writeWait:  time.Duration(writeSeconds) * time.Second,
			pongWait:   pongWait,
			pingPeriod: pongWait * 9 / 10,
			readLimit:  int64(readLimit),
		},
		connectionLimits: connectionLimitConfig{
			maxTotal:              maxTotal,
			maxPerIP:              maxPerIP,
			maxPerUser:            maxPerUser,
			maxHandshakesPerIPMin: maxHandshakes,
		},
	}, nil
}

func newRedisClient(config serviceConfig) *redis.Client {
	return redis.NewClient(&redis.Options{
		Addr:     config.redisAddress,
		Username: config.redisUsername,
		Password: config.redisPassword,
		DB:       config.redisDB,
	})
}

func envOrDefault(key string, fallback string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	return value
}

func boolEnv(key string, fallback bool) (bool, error) {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return fallback, nil
	}
	value, err := strconv.ParseBool(raw)
	if err != nil {
		return false, fmt.Errorf("%s must be a boolean", key)
	}
	return value, nil
}

func positiveIntEnv(key string, fallback int) (int, error) {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return fallback, nil
	}
	value, err := strconv.Atoi(raw)
	if err != nil || value <= 0 {
		return 0, fmt.Errorf("%s must be a positive integer", key)
	}
	return value, nil
}

func positiveOrZeroEnv(key string, fallback int) (int, error) {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return fallback, nil
	}
	value, err := strconv.Atoi(raw)
	if err != nil || value < 0 {
		return 0, fmt.Errorf("%s must be zero or a positive integer", key)
	}
	return value, nil
}
