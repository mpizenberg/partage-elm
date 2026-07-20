/**
 * Per-group storage accounting shared by both storage adapters, so the SQLite
 * file and the Durable Object enforce identical limits. The SQL (reading and
 * writing the counters) lives in each adapter; the policy math lives here.
 *
 * `stats` is a raw group row: {record_count, total_bytes, bytes_this_window,
 * window_start}. `limits` is {maxRecords, maxTotalBytes, rateBytes, windowMs}.
 */

/**
 * Decide whether a change of `records` records and `bytes` bytes (both may be
 * negative — compaction is accounted net) is allowed and, if so, the window
 * counters to persist alongside it. Only growth spends the rate window: the
 * spend is floored at zero, never refunded. Returns either
 * `{ rejection: {status: 'quota'} | {status: 'rate', retryAfterMs} }` or
 * `{ windowStart, bytesThisWindow }` (the roll-forward values to write).
 */
export function planChange(stats, { records, bytes }, created, limits) {
  if (stats.record_count + records > limits.maxRecords || stats.total_bytes + bytes > limits.maxTotalBytes) {
    return { rejection: { status: 'quota' } };
  }
  const spend = Math.max(0, bytes);
  const nowMs = Date.parse(created);
  const windowStartMs = Date.parse(stats.window_start);
  // A window older than the period resets: the group only spends against the
  // current period, so honest bursts never accumulate across months.
  const rolled = nowMs - windowStartMs >= limits.windowMs;
  const windowStart = rolled ? created : stats.window_start;
  const bytesBefore = rolled ? 0 : stats.bytes_this_window;
  if (bytesBefore + spend > limits.rateBytes) {
    return { rejection: { status: 'rate', retryAfterMs: Math.max(0, windowStartMs + limits.windowMs - nowMs) } };
  }
  return { windowStart, bytesThisWindow: bytesBefore + spend };
}
