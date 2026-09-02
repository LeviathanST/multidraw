export type Position = {
    x: number;
    y: number;
};

function lineTo(ctx: CanvasRenderingContext2D, from: Position, to: Position) {
    if (ctx == null) return;

    ctx.beginPath();
    ctx.moveTo(from.x, from.y);
    ctx.lineTo(to.x, to.y);
    ctx.strokeStyle = "black";
    ctx.lineWidth = 1;
    ctx.lineCap = "round";
    ctx.stroke();
}



function setupCanvas(canvas: HTMLCanvasElement): CanvasRenderingContext2D | null {
    let ctx = canvas.getContext("2d");

    const rect = canvas.getBoundingClientRect();
    canvas.width = rect.width * window.devicePixelRatio;
    canvas.height = rect.height * window.devicePixelRatio;
    ctx?.scale(window.devicePixelRatio, window.devicePixelRatio);
    return ctx;

}

export { lineTo, setupCanvas }
