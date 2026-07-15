package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

const (
	warrantyRedisChannel               = "WARRANTY_STATUS_UPDATED"
	paymentRedisChannel                = "PAYMENT_NOTIFICATION_READY"
	paymentStreamRedisChannel          = "PAYMENT_SPEAKER_STREAM"
	paymentDeliveryMetricsRedisChannel = "PAYMENT_DELIVERY_METRICS_UPDATED"
	appVersionRedisChannel             = "APP_VERSION_UPDATED"
	statementOrderTransferRedisChannel = "STATEMENT_ORDER_TRANSFER_REQUESTED"
	offsetAdjustmentRedisChannel       = "OFFSET_ADJUSTMENT_UPDATED"
	salesReportOrdersRedisChannel      = "SALES_REPORT_ORDERS_UPDATED"
	homeSummaryRedisChannel            = "HOME_SUMMARY_UPDATED"
	accessChangedRedisChannel          = "ACCESS_CHANGED"

	warrantyEventType               = "WARRANTY_EVENT"
	paymentEventType                = "PAYMENT_NOTIFICATION"
	paymentStreamEventType          = "PAYMENT_SPEAKER_STREAM"
	paymentDeliveryMetricsEventType = "PAYMENT_DELIVERY_METRICS_UPDATED"
	appUpdateEventType              = "APP_UPDATE"
	statementOrderTransferEventType = "STATEMENT_ORDER_TRANSFER_REQUEST"
	offsetAdjustmentEventType       = "OFFSET_ADJUSTMENT_NOTIFICATION"
	salesReportOrdersEventType      = "SALES_REPORT_ORDERS_UPDATED"
	homeSummaryEventType            = "HOME_SUMMARY_UPDATED"
	accessChangedEventType          = "ACCESS_CHANGED"
	warrantyTopic                   = "warranty"
	paymentTopic                    = "payment.transactions"
	paymentStreamTopic              = "payment.speaker"
	paymentDeliveryMetricsTopic     = "payment.delivery-metrics"
	statementOrderTransferTopic     = "notifications.statement-transfer"
	offsetAdjustmentTopic           = "notifications.offset-adjustment"
	salesReportOrdersTopic          = "sales-report.orders"
	homeSummaryTopic                = "home.summary"
	accessChangedTopic              = "access.changed"

	webSocketProtocolV1 = 1
	webSocketProtocolV2 = 2

	maxHomeSummaryAffectedDates = 366
)

type EventAudience struct {
	StoreCodes              []string `json:"storeCodes,omitempty"`
	RecipientUserIDs        []string `json:"recipientUserIds,omitempty"`
	Roles                   []string `json:"roles,omitempty"`
	DepartmentCodes         []string `json:"departmentCodes,omitempty"`
	OrganizationAccessCodes []string `json:"organizationAccessCodes,omitempty"`
	PolicyCodes             []string `json:"policyCodes,omitempty"`
	FeatureCodes            []string `json:"featureCodes,omitempty"`
}

type RoutedEvent struct {
	Type              string
	Message           []byte
	Audience          EventAudience
	Public            bool
	AuthenticatedOnly bool
	ProtocolVersion   int
}

type redisEventEnvelope struct {
	SchemaVersion int             `json:"schemaVersion"`
	Type          string          `json:"type"`
	EventID       string          `json:"eventId"`
	OccurredAt    string          `json:"occurredAt"`
	Audience      *EventAudience  `json:"audience"`
	Payload       json.RawMessage `json:"payload"`
}

type homeSummaryRedisEnvelope struct {
	SchemaVersion int                      `json:"schemaVersion"`
	Type          string                   `json:"type"`
	EventID       string                   `json:"eventId"`
	OccurredAt    string                   `json:"occurredAt"`
	Audience      homeSummaryEventAudience `json:"audience"`
	Payload       homeSummaryUpdatePayload `json:"payload"`
}

type homeSummaryEventAudience struct {
	Kind string `json:"kind"`
}

type homeSummaryUpdatePayload struct {
	AffectedDates     []string `json:"affectedDates"`
	ProjectionVersion int64    `json:"projectionVersion"`
}

type realtimeV2Envelope struct {
	Version int             `json:"v"`
	Kind    string          `json:"kind"`
	ID      string          `json:"id"`
	Topic   string          `json:"topic"`
	Seq     int64           `json:"seq"`
	TS      string          `json:"ts"`
	Data    json.RawMessage `json:"data"`
}

func formatRedisEvent(channel string, payload string) (RoutedEvent, bool) {
	events, ok := formatRedisEvents(channel, payload)
	if !ok || len(events) == 0 {
		return RoutedEvent{}, false
	}
	return events[0], true
}

func formatRedisEvents(channel string, payload string) ([]RoutedEvent, bool) {
	if channel == homeSummaryRedisChannel {
		event, ok := formatHomeSummaryEvent(payload)
		if !ok {
			return nil, false
		}
		return []RoutedEvent{event}, true
	}
	eventType, ok := eventTypeForChannel(channel)
	if !ok || !validJSONObject(json.RawMessage(payload)) {
		return nil, false
	}

	rawPayload := json.RawMessage(payload)
	if eventType == appUpdateEventType {
		message, ok := formatLegacyClientMessage(eventType, rawPayload)
		if !ok {
			return nil, false
		}
		return []RoutedEvent{{
			Type:            eventType,
			Message:         message,
			Public:          true,
			ProtocolVersion: webSocketProtocolV1,
		}}, true
	}

	topic, ok := topicForChannel(channel)
	if !ok {
		return nil, false
	}
	parsed, ok := parseAuthenticatedRedisEvent(channel, eventType, rawPayload)
	if !ok {
		return nil, false
	}

	legacyMessage, ok := formatLegacyClientMessage(eventType, parsed.payload)
	if !ok {
		return nil, false
	}
	v2Message, ok := formatRealtimeV2ClientMessage(
		eventType,
		topic,
		parsed.eventID,
		parsed.occurredAt,
		parsed.payload,
	)
	if !ok {
		return nil, false
	}

	return []RoutedEvent{
		{
			Type:            eventType,
			Message:         legacyMessage,
			Audience:        parsed.audience,
			ProtocolVersion: webSocketProtocolV1,
		},
		{
			Type:            eventType,
			Message:         v2Message,
			Audience:        parsed.audience,
			ProtocolVersion: webSocketProtocolV2,
		},
	}, true
}

type parsedAuthenticatedRedisEvent struct {
	eventID    string
	occurredAt string
	payload    json.RawMessage
	audience   EventAudience
}

func parseAuthenticatedRedisEvent(
	channel string,
	eventType string,
	rawPayload json.RawMessage,
) (parsedAuthenticatedRedisEvent, bool) {
	var probe map[string]json.RawMessage
	if err := json.Unmarshal(rawPayload, &probe); err != nil || probe == nil {
		return parsedAuthenticatedRedisEvent{}, false
	}
	_, hasSchemaVersion := probe["schemaVersion"]
	_, hasEventID := probe["eventId"]
	_, hasOccurredAt := probe["occurredAt"]
	_, hasAudience := probe["audience"]
	_, hasPayload := probe["payload"]
	looksVersioned := hasSchemaVersion || hasEventID || hasOccurredAt || hasAudience || hasPayload

	if looksVersioned {
		var envelope redisEventEnvelope
		decoder := json.NewDecoder(strings.NewReader(string(rawPayload)))
		decoder.DisallowUnknownFields()
		if err := decoder.Decode(&envelope); err != nil {
			return parsedAuthenticatedRedisEvent{}, false
		}
		eventID := strings.TrimSpace(envelope.EventID)
		occurredAt := strings.TrimSpace(envelope.OccurredAt)
		audience := EventAudience{}
		if envelope.Audience != nil {
			audience = normalizeAudience(*envelope.Audience)
		}
		if envelope.SchemaVersion != webSocketProtocolV1 ||
			envelope.Type != eventType ||
			eventID == "" || len(eventID) > 128 ||
			envelope.Audience == nil || !audience.valid() ||
			!validJSONObject(envelope.Payload) {
			return parsedAuthenticatedRedisEvent{}, false
		}
		if _, err := time.Parse(time.RFC3339Nano, occurredAt); err != nil {
			return parsedAuthenticatedRedisEvent{}, false
		}
		return parsedAuthenticatedRedisEvent{
			eventID:    eventID,
			occurredAt: occurredAt,
			payload:    envelope.Payload,
			audience:   audience,
		}, true
	}

	audience, ok := inferLegacyAudience(eventType, rawPayload)
	if !ok || !audience.valid() {
		return parsedAuthenticatedRedisEvent{}, false
	}
	return parsedAuthenticatedRedisEvent{
		eventID:    legacyEventID(channel, rawPayload),
		occurredAt: legacyOccurredAt(rawPayload),
		payload:    rawPayload,
		audience:   audience,
	}, true
}

func formatLegacyClientMessage(eventType string, payload json.RawMessage) ([]byte, bool) {
	message, err := json.Marshal(struct {
		Type    string          `json:"type"`
		Payload json.RawMessage `json:"payload"`
	}{
		Type:    eventType,
		Payload: payload,
	})
	return message, err == nil
}

func formatRealtimeV2ClientMessage(
	eventType string,
	topic string,
	eventID string,
	occurredAt string,
	payload json.RawMessage,
) ([]byte, bool) {
	parsedTime, err := time.Parse(time.RFC3339Nano, occurredAt)
	if err != nil || strings.TrimSpace(eventID) == "" || !validJSONObject(payload) {
		return nil, false
	}
	sequence := parsedTime.UnixMilli()
	if sequence <= 0 {
		sequence = 1
	}
	message, err := json.Marshal(realtimeV2Envelope{
		Version: webSocketProtocolV2,
		Kind:    eventType,
		ID:      eventID,
		Topic:   topic,
		Seq:     sequence,
		TS:      occurredAt,
		Data:    payload,
	})
	return message, err == nil
}

func legacyEventID(channel string, payload json.RawMessage) string {
	digest := sha256.Sum256(payload)
	return fmt.Sprintf("legacy:%s:%x", strings.ToLower(channel), digest[:16])
}

func legacyOccurredAt(payload json.RawMessage) string {
	var values map[string]json.RawMessage
	if err := json.Unmarshal(payload, &values); err == nil {
		for _, field := range []string{"timestamp", "updatedAt", "createdAt", "paidAt", "firstSeenAt"} {
			var candidate string
			if err := json.Unmarshal(values[field], &candidate); err != nil {
				continue
			}
			parsed, err := time.Parse(time.RFC3339Nano, strings.TrimSpace(candidate))
			if err == nil {
				return parsed.UTC().Format(time.RFC3339Nano)
			}
		}
	}
	return time.Now().UTC().Format(time.RFC3339Nano)
}

func validJSONObject(value json.RawMessage) bool {
	if !json.Valid(value) {
		return false
	}
	var object map[string]json.RawMessage
	return json.Unmarshal(value, &object) == nil && object != nil
}

func formatHomeSummaryEvent(payload string) (RoutedEvent, bool) {
	if !json.Valid([]byte(payload)) {
		return RoutedEvent{}, false
	}
	var envelope homeSummaryRedisEnvelope
	decoder := json.NewDecoder(strings.NewReader(payload))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&envelope); err != nil {
		return RoutedEvent{}, false
	}

	eventID := strings.TrimSpace(envelope.EventID)
	occurredAt := strings.TrimSpace(envelope.OccurredAt)
	if envelope.SchemaVersion != webSocketProtocolV2 ||
		envelope.Type != homeSummaryEventType ||
		eventID == "" || len(eventID) > 128 ||
		envelope.Audience.Kind != "AUTHENTICATED" ||
		envelope.Payload.ProjectionVersion <= 0 ||
		len(envelope.Payload.AffectedDates) == 0 ||
		len(envelope.Payload.AffectedDates) > maxHomeSummaryAffectedDates {
		return RoutedEvent{}, false
	}
	if _, err := time.Parse(time.RFC3339Nano, occurredAt); err != nil {
		return RoutedEvent{}, false
	}

	seenDates := make(map[string]struct{}, len(envelope.Payload.AffectedDates))
	for _, affectedDate := range envelope.Payload.AffectedDates {
		parsedDate, err := time.Parse("2006-01-02", affectedDate)
		if err != nil || parsedDate.Format("2006-01-02") != affectedDate {
			return RoutedEvent{}, false
		}
		if _, duplicated := seenDates[affectedDate]; duplicated {
			return RoutedEvent{}, false
		}
		seenDates[affectedDate] = struct{}{}
	}

	data, err := json.Marshal(envelope.Payload)
	if err != nil {
		return RoutedEvent{}, false
	}
	message, err := json.Marshal(realtimeV2Envelope{
		Version: webSocketProtocolV2,
		Kind:    homeSummaryEventType,
		ID:      eventID,
		Topic:   homeSummaryTopic,
		Seq:     envelope.Payload.ProjectionVersion,
		TS:      occurredAt,
		Data:    data,
	})
	if err != nil {
		return RoutedEvent{}, false
	}
	return RoutedEvent{
		Type:              homeSummaryEventType,
		Message:           message,
		AuthenticatedOnly: true,
		ProtocolVersion:   webSocketProtocolV2,
	}, true
}

func eventTypeForChannel(channel string) (string, bool) {
	switch channel {
	case warrantyRedisChannel:
		return warrantyEventType, true
	case paymentRedisChannel:
		return paymentEventType, true
	case paymentStreamRedisChannel:
		return paymentStreamEventType, true
	case paymentDeliveryMetricsRedisChannel:
		return paymentDeliveryMetricsEventType, true
	case appVersionRedisChannel:
		return appUpdateEventType, true
	case statementOrderTransferRedisChannel:
		return statementOrderTransferEventType, true
	case offsetAdjustmentRedisChannel:
		return offsetAdjustmentEventType, true
	case salesReportOrdersRedisChannel:
		return salesReportOrdersEventType, true
	case homeSummaryRedisChannel:
		return homeSummaryEventType, true
	case accessChangedRedisChannel:
		return accessChangedEventType, true
	default:
		return "", false
	}
}

func topicForChannel(channel string) (string, bool) {
	switch channel {
	case warrantyRedisChannel:
		return warrantyTopic, true
	case paymentRedisChannel:
		return paymentTopic, true
	case paymentStreamRedisChannel:
		return paymentStreamTopic, true
	case paymentDeliveryMetricsRedisChannel:
		return paymentDeliveryMetricsTopic, true
	case statementOrderTransferRedisChannel:
		return statementOrderTransferTopic, true
	case offsetAdjustmentRedisChannel:
		return offsetAdjustmentTopic, true
	case salesReportOrdersRedisChannel:
		return salesReportOrdersTopic, true
	case homeSummaryRedisChannel:
		return homeSummaryTopic, true
	case accessChangedRedisChannel:
		return accessChangedTopic, true
	default:
		return "", false
	}
}

func inferLegacyAudience(eventType string, payload json.RawMessage) (EventAudience, bool) {
	var legacy struct {
		StoreCode       string   `json:"storeCode"`
		StoreCodes      []string `json:"storeCodes"`
		RecipientUserID string   `json:"recipientUserId"`
		RecipientIDs    []string `json:"recipientUserIds"`
	}
	if err := json.Unmarshal(payload, &legacy); err != nil {
		return EventAudience{}, false
	}
	audience := EventAudience{
		StoreCodes:       append(legacy.StoreCodes, legacy.StoreCode),
		RecipientUserIDs: append(legacy.RecipientIDs, legacy.RecipientUserID),
	}
	audience = normalizeAudience(audience)
	if len(audience.StoreCodes) == 0 && len(audience.RecipientUserIDs) == 0 {
		return EventAudience{}, false
	}
	switch eventType {
	case warrantyEventType:
		// The historical warranty publisher had no store or recipient scope.
		// It is intentionally rejected until NestJS publishes an audience.
	case paymentEventType, paymentStreamEventType:
	case statementOrderTransferEventType:
		audience.Roles = []string{"SUPER_ADMIN"}
	case offsetAdjustmentEventType:
		audience.Roles = []string{"SUPER_ADMIN"}
		audience.DepartmentCodes = []string{"ACC", "FIN_ACC"}
		audience.OrganizationAccessCodes = []string{"ACC", "FIN_ACC"}
	case salesReportOrdersEventType:
		audience.Roles = []string{"SUPER_ADMIN"}
	default:
		return EventAudience{}, false
	}
	audience = normalizeAudience(audience)
	return audience, audience.valid()
}

func normalizeAudience(audience EventAudience) EventAudience {
	audience.StoreCodes = normalizeCodes(audience.StoreCodes)
	audience.RecipientUserIDs = normalizeIDs(audience.RecipientUserIDs)
	audience.Roles = normalizeCodes(audience.Roles)
	audience.DepartmentCodes = normalizeCodes(audience.DepartmentCodes)
	audience.OrganizationAccessCodes = normalizeCodes(audience.OrganizationAccessCodes)
	audience.PolicyCodes = normalizeCodes(audience.PolicyCodes)
	audience.FeatureCodes = normalizeCodes(audience.FeatureCodes)
	return audience
}

func normalizeIDs(values []string) []string {
	normalized := make([]string, 0, len(values))
	seen := make(map[string]struct{}, len(values))
	for _, value := range values {
		id := strings.TrimSpace(value)
		if id == "" {
			continue
		}
		if _, exists := seen[id]; exists {
			continue
		}
		seen[id] = struct{}{}
		normalized = append(normalized, id)
	}
	return normalized
}

func (audience EventAudience) valid() bool {
	return len(audience.StoreCodes) > 0 ||
		len(audience.RecipientUserIDs) > 0 ||
		len(audience.Roles) > 0 ||
		len(audience.DepartmentCodes) > 0 ||
		len(audience.OrganizationAccessCodes) > 0 ||
		len(audience.PolicyCodes) > 0
}

func (audience EventAudience) matches(auth *ClientAuth) bool {
	if auth == nil || !audience.valid() {
		return false
	}
	// A store-selected connection is a strict subscription filter for every
	// authenticated role. The ticket issuer already proves that the selected
	// store is inside the user's server-derived scope; the gateway must not let
	// another audience selector widen that connection again.
	if auth.SelectedStore != "" &&
		len(audience.StoreCodes) > 0 &&
		!containsExact(audience.StoreCodes, auth.SelectedStore) {
		return false
	}
	if len(audience.FeatureCodes) > 0 && !intersects(audience.FeatureCodes, auth.FeatureCodes) {
		return false
	}

	if containsExact(audience.RecipientUserIDs, auth.UserID) {
		return true
	}
	storeMatches := auth.matchesAnyStore(audience.StoreCodes)
	if storeMatches {
		return true
	}

	if containsExact(audience.Roles, auth.Role) {
		return true
	}
	if containsExact(audience.DepartmentCodes, auth.DepartmentCode) {
		return true
	}
	if intersects(audience.OrganizationAccessCodes, auth.OrganizationAccessCodes) {
		return true
	}
	if intersects(audience.PolicyCodes, auth.PolicyCodes) {
		return true
	}
	return false
}

func (auth *ClientAuth) hasStoreAccess(storeCode string) bool {
	storeCode = normalizeCode(storeCode)
	if auth == nil || storeCode == "" {
		return false
	}
	if auth.Role == "SUPER_ADMIN" {
		return true
	}
	return auth.StoreCode == storeCode || containsExact(auth.OrganizationAccessCodes, storeCode)
}

func (auth *ClientAuth) matchesAnyStore(storeCodes []string) bool {
	if auth == nil || len(storeCodes) == 0 {
		return false
	}
	if auth.SelectedStore != "" {
		return containsExact(storeCodes, auth.SelectedStore)
	}
	if auth.Role == "SUPER_ADMIN" {
		return true
	}
	for _, storeCode := range storeCodes {
		if auth.hasStoreAccess(storeCode) {
			return true
		}
	}
	return false
}

func containsExact(values []string, expected string) bool {
	if expected == "" {
		return false
	}
	for _, value := range values {
		if value == expected {
			return true
		}
	}
	return false
}

func intersects(left []string, right []string) bool {
	if len(left) == 0 || len(right) == 0 {
		return false
	}
	values := make(map[string]struct{}, len(left))
	for _, value := range left {
		values[value] = struct{}{}
	}
	for _, value := range right {
		if _, ok := values[value]; ok {
			return true
		}
	}
	return false
}
