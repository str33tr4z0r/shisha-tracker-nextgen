FROM golang:1.20-alpine AS builder
WORKDIR /app
RUN apk add --no-cache git
# copy go.mod/go.sum first to leverage cache
COPY go.mod go.sum ./
RUN go mod download
COPY . .
# ensure sum entries and tidy modules
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/server .

FROM alpine:3.18
RUN apk add --no-cache ca-certificates
COPY --from=builder /app/server /usr/local/bin/server
EXPOSE 8080
USER 1000
ENTRYPOINT ["/usr/local/bin/server"]