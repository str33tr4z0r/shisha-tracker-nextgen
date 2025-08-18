FROM golang:1.20-alpine AS builder
WORKDIR /src
RUN apk add --no-cache git build-base
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o /app/server .
 
FROM alpine:3.18
RUN apk add --no-cache ca-certificates wget
COPY --from=builder /app/server /usr/local/bin/server
EXPOSE 8080
ENV PORT=8080
# create non-root user with UID 1000 and ensure binary is executable by that user
RUN adduser -D -u 1000 app && chown app:app /usr/local/bin/server
USER app
HEALTHCHECK --interval=10s --timeout=3s --retries=3 CMD wget -qO- http://localhost:${PORT}/api/healthz || exit 1
ENTRYPOINT ["/usr/local/bin/server"]