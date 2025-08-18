FROM node:18-alpine AS builder
WORKDIR /app
RUN apk add --no-cache git
COPY package.json package-lock.json* ./
RUN npm ci --prefer-offline --no-audit --progress=false || npm install --no-audit --progress=false
COPY . .
RUN npm run build

FROM nginx:stable-alpine AS runner
LABEL org.opencontainers.image.source="https://example.com/your-repo"
# Copy custom nginx config for local proxying
COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 80
STOPSIGNAL SIGTERM
CMD ["nginx", "-g", "daemon off;"]