#!/bin/sh
set -eu

# Caddy on :$PORT (Render sets 10000, fallback 8080), Zig WS on $WS_ADDR:$WS_PORT
export PORT="${PORT:-8080}"
export WS_ADDR="${WS_ADDR:-127.0.0.1}"
export WS_PORT="${WS_PORT:-3030}"
# Zig reads WS_* (and PORT/ADDR fallback)

echo "[start] launching multidraw on $WS_ADDR:$WS_PORT"
/srv/multidraw &
ZIG_PID=$!

sleep 1

echo "[start] launching caddy on :$PORT -> /srv/dist + /ws -> $WS_ADDR:$WS_PORT"
caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
CADDY_PID=$!

trap "kill $ZIG_PID $CADDY_PID 2>/dev/null; wait" TERM INT

wait -n $ZIG_PID $CADDY_PID
EXIT_CODE=$?
echo "[start] one process exited ($EXIT_CODE), shutting down"
kill $ZIG_PID $CADDY_PID 2>/dev/null || true
wait
exit $EXIT_CODE
