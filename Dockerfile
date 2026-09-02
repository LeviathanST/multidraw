# syntax=docker/dockerfile:1
# Multi-stage: client (vite/svelte) + server (zig) + runtime (caddy + zig binary)

FROM node:24-alpine AS client-builder
WORKDIR /app/client
COPY client/package.json client/package-lock.json ./
RUN npm ci
COPY client/ ./
RUN npm run build

FROM alpine:3.20 AS server-builder
ARG ZIG_VERSION=0.16.0
RUN apk add --no-cache curl tar xz
WORKDIR /tmp
RUN curl -L https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz | tar -xJ \
 && mv zig-x86_64-linux-${ZIG_VERSION} /opt/zig \
 && ln -s /opt/zig/zig /usr/local/bin/zig
WORKDIR /app/server
COPY server/build.zig server/build.zig.zon ./
COPY server/src ./src
# cache buster for dependencies fetch
RUN zig build -Doptimize=ReleaseSafe --fetch  || true
COPY server/ ./
RUN zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl \
 && cp zig-out/bin/multidraw /app/multidraw

FROM caddy:2-alpine AS runtime
ENV PORT=8080
ENV XDG_CONFIG_HOME=/tmp
ENV XDG_DATA_HOME=/tmp
WORKDIR /srv
COPY --from=client-builder /app/client/dist ./dist
COPY --from=server-builder /app/multidraw ./multidraw
COPY Caddyfile /etc/caddy/Caddyfile
COPY start.sh /start.sh
RUN adduser -D -s /bin/sh app \
 && mkdir -p /tmp/config /tmp/data /config /data \
 && chown -R app:app /srv /etc/caddy /tmp /config /data 2>/dev/null || chown -R app:app /srv /etc/caddy /tmp \
 && chmod +x /start.sh ./multidraw
USER app
EXPOSE 8080
CMD ["/start.sh"]
