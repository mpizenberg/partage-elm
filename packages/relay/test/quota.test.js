import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { planChange } from '../src/quota.js';

const LIMITS = { maxRecords: 10, maxTotalBytes: 1000, rateBytes: 1000, windowMs: 60 * 60 * 1000 };

function stats(overrides = {}) {
  return { record_count: 0, total_bytes: 0, bytes_this_window: 0, window_start: '2030-01-01T00:00:00.000Z', ...overrides };
}

function append(theStats, size, created) {
  return planChange(theStats, { records: 1, bytes: size }, created, LIMITS);
}

describe('planChange', () => {
  it('accepts an append within all limits and rolls the window forward', () => {
    const plan = append(stats(), 100, '2030-01-01T00:01:00.000Z');
    assert.deepEqual(plan, { windowStart: '2030-01-01T00:00:00.000Z', bytesThisWindow: 100 });
  });

  it('rejects when the record cap would be exceeded', () => {
    const plan = append(stats({ record_count: 10 }), 1, '2030-01-01T00:01:00.000Z');
    assert.deepEqual(plan.rejection, { status: 'quota' });
  });

  it('rejects when the byte cap would be exceeded', () => {
    const plan = append(stats({ total_bytes: 950 }), 100, '2030-01-01T00:01:00.000Z');
    assert.deepEqual(plan.rejection, { status: 'quota' });
  });

  it('rejects over the rate cap with time until the window resets', () => {
    const plan = append(stats({ bytes_this_window: 950 }), 100, '2030-01-01T00:10:00.000Z');
    assert.equal(plan.rejection.status, 'rate');
    assert.equal(plan.rejection.retryAfterMs, LIMITS.windowMs - 10 * 60 * 1000);
  });

  it('resets the rate counter once the window has elapsed', () => {
    // window_start is 2 h old (> windowMs), so the near-full window empties.
    const plan = append(stats({ bytes_this_window: 950 }), 100, '2030-01-01T02:00:00.000Z');
    assert.deepEqual(plan, { windowStart: '2030-01-01T02:00:00.000Z', bytesThisWindow: 100 });
  });

  it('a shrinking change spends nothing from the rate window', () => {
    const plan = planChange(
      stats({ record_count: 10, total_bytes: 1000, bytes_this_window: 950 }),
      { records: -8, bytes: -600 },
      '2030-01-01T00:10:00.000Z',
      LIMITS,
    );
    assert.deepEqual(plan, { windowStart: '2030-01-01T00:00:00.000Z', bytesThisWindow: 950 });
  });

  it('a shrinking change passes even when the group sits at both caps', () => {
    const plan = planChange(
      stats({ record_count: 10, total_bytes: 1000 }),
      { records: -1, bytes: 0 },
      '2030-01-01T00:10:00.000Z',
      LIMITS,
    );
    assert.equal(plan.rejection, undefined);
  });

  it('a growing change spends only its net bytes and honors the caps', () => {
    const grow = planChange(stats(), { records: 2, bytes: 300 }, '2030-01-01T00:10:00.000Z', LIMITS);
    assert.equal(grow.bytesThisWindow, 300);
    const tooBig = planChange(
      stats({ bytes_this_window: 800 }),
      { records: 2, bytes: 300 },
      '2030-01-01T00:10:00.000Z',
      LIMITS,
    );
    assert.equal(tooBig.rejection.status, 'rate');
  });
});
