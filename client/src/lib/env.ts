function getWsURL(): string {
    return import.meta.env.DEV ? 'ws://127.0.0.1:3030' : 'wss://' + location.host + '/ws';
}
export { getWsURL };
