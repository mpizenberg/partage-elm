import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createAdminThrottle } from '../src/admin-throttle.js';

function at(start) {
  let t = start;
  return { now: () => t, advance: (ms) => (t += ms) };
}

describe('admin throttle', () => {
  it('locks an address only once it reaches the failure limit', () => {
    const clock = at(1000);
    const th = createAdminThrottle({ maxFailures: 3, durationMs: 1000, now: clock.now });
    assert.equal(th.fail('a'), 0); // 1
    assert.equal(th.fail('a'), 0); // 2
    assert.equal(th.lockedForMs('a'), 0);
    assert.ok(th.fail('a') > 0); // 3 -> locked
    assert.ok(th.lockedForMs('a') > 0);
  });

  it('keeps addresses independent', () => {
    const clock = at(1000);
    const th = createAdminThrottle({ maxFailures: 2, durationMs: 1000, now: clock.now });
    th.fail('a');
    assert.ok(th.fail('a') > 0); // 'a' locked
    assert.equal(th.lockedForMs('b'), 0); // 'b' untouched
    assert.equal(th.fail('b'), 0);
  });

  it('clears the lockout once the duration elapses and starts a fresh window', () => {
    const clock = at(1000);
    const th = createAdminThrottle({ maxFailures: 2, durationMs: 1000, now: clock.now });
    th.fail('a');
    assert.ok(th.fail('a') > 0);
    clock.advance(1000);
    assert.equal(th.lockedForMs('a'), 0);
    assert.equal(th.fail('a'), 0); // window reset: one failure, not yet locked
  });

  it('does not accumulate failures spaced beyond the window', () => {
    const clock = at(1000);
    const th = createAdminThrottle({ maxFailures: 2, durationMs: 1000, now: clock.now });
    assert.equal(th.fail('a'), 0);
    clock.advance(1001);
    assert.equal(th.fail('a'), 0); // stale failure decayed, still one in the window
    assert.equal(th.lockedForMs('a'), 0);
  });

  it('resets an address after a success', () => {
    const clock = at(1000);
    const th = createAdminThrottle({ maxFailures: 2, durationMs: 1000, now: clock.now });
    th.fail('a');
    th.succeed('a');
    assert.equal(th.fail('a'), 0); // count restarted, not locked on the next failure
    assert.equal(th.lockedForMs('a'), 0);
  });
});
