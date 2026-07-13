package main

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"strings"
	"sync/atomic"
	"time"

	"github.com/redis/go-redis/v9"
)

var redisChannels = []string{
	warrantyRedisChannel,
	paymentRedisChannel,
	paymentStreamRedisChannel,
	appVersionRedisChannel,
	statementOrderTransferRedisChannel,
	offsetAdjustmentRedisChannel,
	salesReportOrdersRedisChannel,
	authSessionRevokedRedisChannel,
}

const authSessionRevokedRedisChannel = "AUTH_SESSION_REVOKED"

type SessionRevocation struct {
	SchemaVersion int
	UserID        string
	SessionID     string
	Platform      string
	Reason        string
	OccurredAt    string
}

func parseSessionRevocation(payload string) (SessionRevocation, bool) {
	var revocation SessionRevocation
	decoder := json.NewDecoder(strings.NewReader(payload))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&revocation); err != nil {
		return SessionRevocation{}, false
	}
	revocation.UserID = strings.TrimSpace(revocation.UserID)
	revocation.SessionID = strings.TrimSpace(revocation.SessionID)
	revocation.Platform = strings.ToLower(strings.TrimSpace(revocation.Platform))
	revocation.Reason = strings.TrimSpace(revocation.Reason)
	revocation.OccurredAt = strings.TrimSpace(revocation.OccurredAt)
	if revocation.SchemaVersion != 1 ||
		revocation.UserID == "" ||
		revocation.Reason == "" ||
		revocation.OccurredAt == "" {
		return SessionRevocation{}, false
	}
	return revocation, true
}

type readinessChecker interface {
	Ready(context.Context) error
}

type redisReadiness struct {
	client            *redis.Client
	subscriptionReady atomic.Bool
}

func newRedisReadiness(client *redis.Client) *redisReadiness {
	return &redisReadiness{client: client}
}

func (state *redisReadiness) Ready(ctx context.Context) error {
	if !state.subscriptionReady.Load() {
		return errors.New("redis subscription is not ready")
	}
	pingContext, cancel := context.WithTimeout(ctx, 500*time.Millisecond)
	defer cancel()
	if err := state.client.Ping(pingContext).Err(); err != nil {
		return errors.New("redis is unavailable")
	}
	return nil
}

func listenToRedis(
	ctx context.Context,
	client *redis.Client,
	state *redisReadiness,
	hub *Hub,
	logger *log.Logger,
) {
	backoff := time.Second
	for ctx.Err() == nil {
		state.subscriptionReady.Store(false)
		pubsub := client.Subscribe(ctx, redisChannels...)
		if _, err := pubsub.Receive(ctx); err != nil {
			_ = pubsub.Close()
			if ctx.Err() != nil {
				return
			}
			logger.Printf("Redis subscription failed; retrying delay=%s error=%q", backoff, err)
			waitForRetry(ctx, backoff)
			backoff = min(backoff*2, 30*time.Second)
			continue
		}

		state.subscriptionReady.Store(true)
		backoff = time.Second
		logger.Printf("Redis subscription ready channelCount=%d", len(redisChannels))
		messages := pubsub.Channel()
		for {
			select {
			case <-ctx.Done():
				state.subscriptionReady.Store(false)
				_ = pubsub.Close()
				return
			case message, open := <-messages:
				if !open {
					state.subscriptionReady.Store(false)
					_ = pubsub.Close()
					logger.Print("Redis subscription closed; reconnecting")
					waitForRetry(ctx, backoff)
					backoff = min(backoff*2, 30*time.Second)
					goto reconnect
				}
				if message.Channel == authSessionRevokedRedisChannel {
					revocation, valid := parseSessionRevocation(message.Payload)
					if !valid {
						logger.Printf(
							"Redis session revocation rejected payloadBytes=%d",
							len(message.Payload),
						)
						continue
					}
					select {
					case hub.revoke <- revocation:
					case <-ctx.Done():
						state.subscriptionReady.Store(false)
						_ = pubsub.Close()
						return
					}
					continue
				}
				event, ok := formatRedisEvent(message.Channel, message.Payload)
				if !ok {
					logger.Printf(
						"Redis event rejected channel=%s reason=invalid_or_missing_audience payloadBytes=%d",
						message.Channel,
						len(message.Payload),
					)
					continue
				}
				select {
				case hub.broadcast <- event:
				case <-ctx.Done():
					state.subscriptionReady.Store(false)
					_ = pubsub.Close()
					return
				}
			}
		}
	reconnect:
	}
}

func waitForRetry(ctx context.Context, delay time.Duration) {
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
	case <-timer.C:
	}
}
