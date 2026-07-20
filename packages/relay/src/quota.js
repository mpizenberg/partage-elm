/**
 * Per-group storage accounting shared by both storage adapters, so the SQLite
 * file and the Durable Object enforce identical limits. The SQL (reading and
 * writing the counters) lives in each adapter; the policy math lives here.
 *
 * `stats` is a raw group row: {record_count, total_bytes, bytes_this_window,
 * window_start}. `limits` is {maxRecords, maxTotalBytes, rateBytes, windowMs}.
 */

/**
 * Decide whether a `size`-byte append is allowed and, if so, the window
 * counters to persist alongside the insert. Returns either
 * `{ rejection: {status: 'quota'} | {status: 'rate', retryAfterMs} }` or
 * `{ windowStart, bytesThisWindow }` (the roll-forward values to write).
 */
export function planAppend(stats, size, created, limits) {
  if (stats.record_count + 1 > limits.maxRecords || stats.total_bytes + size > limits.maxTotalBytes) {
    return { rejection: { status: 'quota' } };
  }
  const nowMs = Date.parse(created);
  const windowStartMs = Date.parse(stats.window_start);
  // A window older than the period resets: the group only spends against the
  // current period, so honest bursts never accumulate across months.
  const rolled = nowMs - windowStartMs >= limits.windowMs;
  const windowStart = rolled ? created : stats.window_start;
  const bytesBefore = rolled ? 0 : stats.bytes_this_window;
  if (bytesBefore + size > limits.rateBytes) {
    return { rejection: { status: 'rate', retryAfterMs: windowStartMs + limits.windowMs - nowMs } };
  }
  return { windowStart, bytesThisWindow: bytesBefore + size };
}
