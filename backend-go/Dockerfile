FROM golang:1.25-alpine AS build

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /out/opshub-realtime .

FROM alpine:3.22

RUN addgroup -S app && adduser -S app -G app
COPY --from=build /out/opshub-realtime /usr/local/bin/opshub-realtime

USER app
EXPOSE 8080
CMD ["opshub-realtime"]
