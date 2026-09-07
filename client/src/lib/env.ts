function getWsURL(sessionId: string | null): string {
    const base = import.meta.env.DEV ? 'ws://127.0.0.1:3030' : `wss://${location.host}/ws`;
    return sessionId ? `${base}?sessionId=${encodeURIComponent(sessionId)}` : base;
}
export { getWsURL };
