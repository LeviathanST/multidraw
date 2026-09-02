<script lang="ts">
  import { onMount } from "svelte";
  import { lineTo, setupCanvas, type Position } from "./lib/canvas";
  import { getWsURL } from "./lib/env";
  type SendPayload = {
    drawFrom: Position;
    drawTo: Position;
  };

  let ctx = $state<CanvasRenderingContext2D | null>(null);
  let canvas = $state<HTMLCanvasElement | null>(null);
  let error = $state<string | null>(null);
  let isDrawing = $state<boolean>(false);

  let prevPos = $state<Position | null>(null);
  let currPos = $state<Position | null>(null);

  let ws = new WebSocket(getWsURL());

  function send(data: SendPayload) {
    ws.send(JSON.stringify(data));
  }

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
  });

  ws.onmessage = (event) => {
    if (ctx == null) return;

    let payload: SendPayload = JSON.parse(event.data);
    lineTo(ctx, payload.drawFrom, payload.drawTo);
  };

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
