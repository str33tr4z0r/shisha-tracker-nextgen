# --- build stage ---
FROM node:22-alpine AS builder
WORKDIR /app
# nur was für npm ci nötig ist (cache-freundlich)
COPY package.json package-lock.json* ./
# dev-Dependencies für den Build sind ok, landen nicht im finalen Image
RUN npm ci --include=dev --prefer-offline --no-audit --progress=false \
 || npm install --include=dev --no-audit --progress=false
# rest kopieren & bauen
COPY . .
RUN npm run build

# --- runtime stage ---
FROM nginx:stable-alpine AS runner
# OCI/metadata (der Rest kommt via GoReleaser als --label dazu)
LABEL org.opencontainers.image.source="https://github.com/str33tr4z0r/shisha-tracker-nextgen"
# eigene nginx-config (liegt in frontend/nginx/default.conf)
COPY nginx/default.conf /etc/nginx/conf.d/default.conf
# statische Assets aus dem Build
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 80
STOPSIGNAL SIGTERM
CMD ["nginx", "-g", "daemon off;"]