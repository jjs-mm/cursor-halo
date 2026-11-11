import {test} from 'node:test';
import assert from 'node:assert/strict';
import {appearance, clickColor, COLORS, finitePoint, MAX_PULSES, PULSE_MS} from '../model.js';

test('invalid settings cannot create unbounded drawing surfaces', () => {
    assert.deepEqual(appearance({diameter: Infinity, stroke: NaN, opacity: '90', color: null}),
        {style: 0, color: 0, diameter: 56, opacity: 85, stroke: 3});
    assert.deepEqual(appearance({style: 100, color: -20, diameter: 1e100, opacity: -1, stroke: 99}),
        {style: 1, color: 0, diameter: 120, opacity: 20, stroke: 8});
});
test('virtual-desktop coordinates support negatives but reject invalid geometry', () => {
    assert.ok(finitePoint(-1500, 400));
    for (const x of [NaN, Infinity, '2', undefined, 100001]) assert.equal(finitePoint(x, 0), false);
});
test('secondary click stays distinct for every selectable color', () => {
    for (let i = 0; i < COLORS.length; i++) {
        assert.equal(clickColor(i, 1), COLORS[i]);
        assert.notDeepEqual(clickColor(i, 3), COLORS[i]);
    }
    assert.ok(MAX_PULSES > 0 && MAX_PULSES <= 8 && PULSE_MS <= 500);
});
