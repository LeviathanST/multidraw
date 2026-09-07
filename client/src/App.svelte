<script lang="ts">
  import { onMount } from "svelte";
  import { lineTo, setupCanvas, type Position } from "./lib/canvas";
  import { getWsURL } from "./lib/env";
  import type { WsMessage, Stroke } from "./lib/types";

  let ctx = $state<CanvasRenderingContext2D | null>(null);
  let canvas = $state<HTMLCanvasElement | null>(null);
  let error = $state<string | null>(null);
  let isDrawing = $state<boolean>(false);
  let ws = $state<WebSocket | null>(null);

  let prevPos = $state<Position | null>(null);
  let currPos = $state<Position | null>(null);

  onMount(() => {
    if (canvas == null) {
      error = "Cannot found the canvas";
      return null;
    }
    if (canvas.getContext("2d") == null) {
      error = "Cannot get the 2d canvas";
      return null;
    }
    ctx = setupCanvas(canvas);

    const sid = new URLSearchParams(window.location.search).get("sessionId");
    ws = new WebSocket(getWsURL(sid));

    ws.onmessage = (event) => {
      let payload: WsMessage | null = null;

      try {
        payload = JSON.parse(event.data);
      } catch (err) {
        error = "There are some issues when parsing data";
        return;
      }

      if (payload?.type != undefined && payload.type === "init") {
        const url = new URL(window.location.href);
        url.searchParams.set("sessionId", payload.data.session_id);
        history.replaceState(null, "", url);
        return;
      }

      if (payload?.type == "history")
        payload.data.strokes.forEach(
          (e) => ctx && lineTo(ctx, e.drawFrom, e.drawTo),
        );

      if (payload?.type === "draw" && ctx != null)
        lineTo(ctx, payload.data.drawFrom, payload.data.drawTo);
    };

    return () => ws?.close();
  });

  function send(data: Stroke) {
    if (ws == null || ws.readyState !== WebSocket.OPEN) return;
    const msg: WsMessage = { type: "draw", data };
    ws.send(JSON.stringify(msg));
  }

  function resize() {
    if (canvas == null) return;
    const rect = canvas.getBoundingClientRect();

    canvas.width = rect.width * window.devicePixelRatio;
    canvas.height = rect.height * window.devicePixelRatio;
    ctx?.scale(window.devicePixelRatio, window.devicePixelRatio);
  }

  function onDown(e: PointerEvent) {
    canvas?.setPointerCapture(e.pointerId);

    isDrawing = true;
    currPos = { x: e.offsetX, y: e.offsetY };
  }

  function onUp() {
    isDrawing = false;
  }

  function onMove(e: PointerEvent) {
    if (!isDrawing) return;
    prevPos = currPos;
    currPos = { x: e.offsetX, y: e.offsetY };

    if (ctx == null) return;
    if (prevPos == null) return;
    lineTo(ctx, prevPos, currPos);
    send({ drawFrom: prevPos, drawTo: currPos });
  }
</script>

<svelte:window on:resize={resize} />

{#if error == null}
  <canvas
    id="panel"
    class="h-screen w-screen"
    bind:this={canvas}
    onpointerdown={onDown}
    onpointerup={onUp}
    onpointermove={onMove}
  ></canvas>
{:else}
  <h1>{error}</h1>
{/if}
