import type { Position } from "./canvas";

export type Stroke = {
    drawFrom: Position;
    drawTo: Position;
};

export type InitData = {
    session_id: string;
};

export type HistoryData = {
    strokes: Stroke[];
};

export type WsMessage =
    | { type: "init"; data: InitData }
    | { type: "history"; data: HistoryData }
    | { type: "draw"; data: Stroke };
