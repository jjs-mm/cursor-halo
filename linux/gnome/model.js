// SPDX-License-Identifier: MIT
// Kept independent of GJS so validation and pulse limits can run in Node too.
export const COLORS = [
    [1, 0.72, 0.16], [0.25, 0.88, 0.68], [0.25, 0.65, 1],
    [1, 0.35, 0.65], [1, 1, 1],
];
export const SHORTCUTS = ['<Control><Alt>h', '<Control><Alt>c', '<Control><Shift>h'];
export const MAX_PULSES = 8;
export const PULSE_MS = 420;

function bounded(value, fallback, min, max) {
    return typeof value === 'number' && Number.isFinite(value)
        ? Math.max(min, Math.min(max, Math.round(value))) : fallback;
}

export function appearance(values) {
    return {
        style: bounded(values.style, 0, 0, 1),
        color: bounded(values.color, 0, 0, 4),
        diameter: bounded(values.diameter, 56, 28, 120),
        opacity: bounded(values.opacity, 85, 20, 100),
        stroke: bounded(values.stroke, 3, 1, 8),
    };
}

export function finitePoint(x, y) {
    return typeof x === 'number' && typeof y === 'number' &&
        Number.isFinite(x) && Number.isFinite(y) && Math.abs(x) <= 100000 && Math.abs(y) <= 100000;
}

export function clickColor(colorIndex, button) {
    return COLORS[button === 3 ? (colorIndex === 3 ? 2 : 3) : colorIndex] ?? COLORS[0];
}
