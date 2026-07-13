package main

import (
	"encoding/json"
	"strings"
)

const (
	warrantyRedisChannel               = "WARRANTY_STATUS_UPDATED"
	paymentRedisChannel                = "PAYMENT_NOTIFICATION_READY"
	paymentStreamRedisChannel          = "PAYMENT_SPEAKER_STREAM"
	appVersionRedisChannel             = "APP_VERSION_UPDATED"
	statementOrderTransferRedisChannel = "STATEMENT_ORDER_TRANSFER_REQUESTED"
	offsetAdjustmentRedisChannel       = "OFFSET_ADJUSTMENT_UPDATED"
	salesReportOrdersRedisChannel      = "SALES_REPORT_ORDERS_UPDATED"

	warrantyEventType               = "WARRANTY_EVENT"
	paymentEventType                = "PAYMENT_NOTIFICATION"
	paymentStreamEventType          = "PAYMENT_SPEAKER_STREAM"
	appUpdateEventType              = "APP_UPDATE"
	statementOrderTransferEventType = "STATEMENT_ORDER_TRANSFER_REQUEST"
	offsetAdjustmentEventType       = "OFFSET_ADJUSTMENT_NOTIFICATION"
	salesReportOrdersEventType      = "SALES_REPORT_ORDERS_UPDATED"
)

type EventAudience struct {
	StoreCodes              []string `json:"storeCodes,omitempty"`
	RecipientUserIDs        []string `json:"recipientUserIds,omitempty"`
	Roles                   []string `json:"roles,omitempty"`
	DepartmentCodes         []string `json:"departmentCodes,omitempty"`
	OrganizationAccessCodes []string `json:"organizationAccessCodes,omitempty"`
	FeatureCodes            []string `json:"featureCodes,omitempty"`
}

type RoutedEvent struct {
	Type     string
	Message  []byte
	Audience EventAudience
	Public   bool
}

type redisEventEnvelope struct {
	SchemaVersion int             `json:"schemaVersion"`
	Type          string          `json:"type"`
	EventID       string          `json:"eventId"`
	OccurredAt    string          `json:"occurredAt"`
	Audience      *EventAudience  `json:"audience"`
	Payload       json.RawMessage `json:"payload"`
}

func formatRedisEvent(channel string, payload string) (RoutedEvent, bool) {
	eventType, ok := eventTypeForChannel(channel)
	if !ok || !json.Valid([]byte(payload)) {
		return RoutedEvent{}, false
	}

	rawPayload := json.RawMessage(payload)
	audience := EventAudience{}
	if eventType != appUpdateEventType {
		var envelope redisEventEnvelope
		if err := json.Unmarshal(rawPayload, &envelope); err != nil {
			return RoutedEvent{}, false
		}
		if envelope.Audience != nil || len(envelope.Payload) > 0 {
			if envelope.SchemaVersion != 1 ||
				strings.TrimSpace(envelope.EventID) == "" ||
				strings.TrimSpace(envelope.OccurredAt) == "" ||
				envelope.Audience == nil ||
				!json.Valid(envelope.Payload) {
				return RoutedEvent{}, false
			}
			if envelope.Type != "" && envelope.Type != eventType {
				return RoutedEvent{}, false
			}
			rawPayload = envelope.Payload
			audience = normalizeAudience(*envelope.Audience)
		} else {
			audience, ok = inferLegacyAudience(eventType, rawPayload)
			if !ok {
				return RoutedEvent{}, false
			}
		}
		if !audience.valid() {
			return RoutedEvent{}, false
		}
	}

	message, err := json.Marshal(struct {
		Type    string          `json:"type"`
		Payload json.RawMessage `json:"payload"`
	}{
		Type:    eventType,
		Payload: rawPayload,
	})
	if err != nil {
		return RoutedEvent{}, false
	}
	return RoutedEvent{
		Type:     eventType,
		Message:  message,
		Audience: audience,
		Public:   eventType == appUpdateEventType,
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
	case appVersionRedisChannel:
		return appUpdateEventType, true
	case statementOrderTransferRedisChannel:
		return statementOrderTransferEventType, true
	case offsetAdjustmentRedisChannel:
		return offsetAdjustmentEventType, true
	case salesReportOrdersRedisChannel:
		return salesReportOrdersEventType, true
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
		len(audience.FeatureCodes) > 0
}

func (audience EventAudience) matches(auth *ClientAuth) bool {
	if auth == nil || !audience.valid() {
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

	// A selected store narrows a SUPER_ADMIN subscription. Role-level access
	// must not silently widen it back to all stores.
	if auth.Role == "SUPER_ADMIN" && auth.SelectedStore != "" && len(audience.StoreCodes) > 0 {
		return false
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
	return len(audience.FeatureCodes) > 0 &&
		len(audience.StoreCodes) == 0 &&
		len(audience.RecipientUserIDs) == 0 &&
		len(audience.Roles) == 0 &&
		len(audience.DepartmentCodes) == 0 &&
		len(audience.OrganizationAccessCodes) == 0
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
	if auth.Role == "SUPER_ADMIN" {
		return auth.SelectedStore != "" && containsExact(storeCodes, auth.SelectedStore)
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
