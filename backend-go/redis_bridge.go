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
	paymentDeliveryMetricsRedisChannel,
	appVersionRedisChannel,
	statementOrderTransferRedisChannel,
	offsetAdjustmentRedisChannel,
	salesReportOrdersRedisChannel,
	homeSummaryRedisChannel,
	accessChangedRedisChannel,
	quickActionLinksRedisChannel,
	authSessionRevokedRedisChannel,
}

const authSessionRevokedRedisChannel = "AUTH_SESSION_REVOKED"

const (
	redisSubscriptionHealthInterval = time.Second
	redisSubscriptionPingTimeout    = 500 * time.Millisecond
)

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
		messages := pubsub.ChannelWithSubscriptions(
			redis.WithChannelSize(256),
			redis.WithChannelHealthCheckInterval(redisSubscriptionHealthInterval),
		)
		healthTicker := time.NewTicker(redisSubscriptionHealthInterval)
		generationReady := false
		reconnecting := false
		for {
			select {
			case <-ctx.Done():
				healthTicker.Stop()
				state.subscriptionReady.Store(false)
				_ = pubsub.Close()
				return
			case rawMessage, open := <-messages:
				if !open {
					healthTicker.Stop()
					markRedisSubscriptionLost(state, hub, logger, "redis_subscription_closed")
					_ = pubsub.Close()
					logger.Print("Redis subscription closed; reconnecting")
					waitForRetry(ctx, backoff)
					backoff = min(backoff*2, 30*time.Second)
					goto reconnect
				}
				switch message := rawMessage.(type) {
				case *redis.Subscription:
					if strings.ToLower(strings.TrimSpace(message.Kind)) != "subscribe" {
						continue
					}
					if generationReady && !reconnecting {
						markRedisSubscriptionLost(state, hub, logger, "redis_subscription_reconnected")
						generationReady = false
						reconnecting = true
					}
					if message.Count >= len(redisChannels) {
						state.subscriptionReady.Store(true)
						generationReady = true
						reconnecting = false
						backoff = time.Second
						logger.Printf("Redis subscription ready channelCount=%d", len(redisChannels))
					}
				case *redis.Message:
					if !handleRedisMessage(ctx, state, pubsub, hub, logger, message) {
						healthTicker.Stop()
						return
					}
				}
			case <-healthTicker.C:
				pingContext, cancel := context.WithTimeout(ctx, redisSubscriptionPingTimeout)
				err := client.Ping(pingContext).Err()
				cancel()
				if err == nil {
					continue
				}
				healthTicker.Stop()
				markRedisSubscriptionLost(state, hub, logger, "redis_unavailable")
				_ = pubsub.Close()
				if ctx.Err() != nil {
					return
				}
				logger.Printf("Redis health check failed; retrying delay=%s error=%q", backoff, err)
				waitForRetry(ctx, backoff)
				backoff = min(backoff*2, 30*time.Second)
				goto reconnect
			}
		}
	reconnect:
	}
}

func handleRedisMessage(
	ctx context.Context,
	state *redisReadiness,
	pubsub *redis.PubSub,
	hub *Hub,
	logger *log.Logger,
	message *redis.Message,
) bool {
	if message.Channel == authSessionRevokedRedisChannel {
		revocation, valid := parseSessionRevocation(message.Payload)
		if !valid {
			logger.Printf(
				"Redis session revocation rejected payloadBytes=%d",
				len(message.Payload),
			)
			return true
		}
		select {
		case hub.revoke <- revocation:
			return true
		case <-ctx.Done():
			state.subscriptionReady.Store(false)
			_ = pubsub.Close()
			return false
		}
	}

	events, ok := formatRedisEvents(message.Channel, message.Payload)
	if !ok {
		logger.Printf(
			"Redis event rejected channel=%s reason=invalid_or_missing_audience payloadBytes=%d",
			message.Channel,
			len(message.Payload),
		)
		return true
	}
	for _, event := range events {
		select {
		case hub.broadcast <- event:
		case <-ctx.Done():
			state.subscriptionReady.Store(false)
			_ = pubsub.Close()
			return false
		}
	}
	return true
}

func markRedisSubscriptionLost(
	state *redisReadiness,
	hub *Hub,
	logger *log.Logger,
	reason string,
) {
	if !state.subscriptionReady.Swap(false) {
		return
	}
	hub.requestProtocolResync(webSocketProtocolV2, reason)
	logger.Printf("Redis subscription lost; realtime v2 resync required reason=%s", reason)
}

func waitForRetry(ctx context.Context, delay time.Duration) {
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
	case <-timer.C:
	}
}
