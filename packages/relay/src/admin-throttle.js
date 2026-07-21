/**
 * Per-IP lockout for the operator endpoint's bearer check, so a strong
 * ADMIN_SECRET can be exposed on the public origin without inviting brute force.
 *
 * The lockout is per-IP, not global: only an offending address is blocked, so an
 * attacker cannot lock the operator out. The caller keys it off the reverse
 * proxy's rightmost X-Forwarded-For entry — the value the proxy appends from the
 * real peer, which a client cannot spoof — so the operator's own address cannot
 * be framed into a lockout either. State is in-memory (self-host is one process)
 * and expendable across restarts.
 */
export function createAdminThrottle({ maxFailures, durationMs, now = () => Date.now() }) {
  const byIp = new Map();
  let lastSweep = 0;

  function sweep(t) {
    for (const [ip, e] of byIp) {
      if (t >= e.lockedUntil && t - e.windowStart >= durationMs) {
        byIp.delete(ip);
      }
    }
    lastSweep = t;
  }

  return {
    /** Remaining lockout in ms for `ip`, or 0 if it may attempt. */
    lockedForMs(ip, t = now()) {
      const e = byIp.get(ip);
      return e && t < e.lockedUntil ? e.lockedUntil - t : 0;
    },

    /** Record a failed attempt; returns the resulting lockout in ms (0 if none). */
    fail(ip, t = now()) {
      const e = byIp.get(ip) ?? { count: 0, windowStart: t, lockedUntil: 0 };
      if (t - e.windowStart >= durationMs) {
        e.count = 0;
        e.windowStart = t;
      }
      e.count += 1;
      if (e.count >= maxFailures) {
        e.lockedUntil = t + durationMs;
      }
      byIp.set(ip, e);
      if (t - lastSweep >= durationMs) {
        sweep(t);
      }
      return t < e.lockedUntil ? e.lockedUntil - t : 0;
    },

    /** Clear an address's state after a successful authentication. */
    succeed(ip) {
      byIp.delete(ip);
    },
  };
}
