/**
 * Cloudflare storage adapter: one Durable Object per group, backed by the
 * DO's SQLite. Same schema as the self-host file so the two adapters stay
 * interchangeable; the group_id column simply always holds the DO's one group.
 */

import { planAppend } from './quota.js';

export function createDoStorage(sql) {
  sql.exec(`
    CREATE TABLE IF NOT EXISTS groups (
      id            TEXT PRIMARY KEY,
      created_by    TEXT NOT NULL,
      auth_verifier TEXT NOT NULL,
      pow_challenge TEXT NOT NULL,
      created       TEXT NOT NULL,
      last_access   TEXT
    )
  `);
  sql.exec(`
    CREATE TABLE IF NOT EXISTS events (
      seq        INTEGER PRIMARY KEY AUTOINCREMENT,
      group_id   TEXT NOT NULL REFERENCES groups(id),
      record_id  TEXT,
      actor_id   TEXT NOT NULL,
      data       TEXT NOT NULL,
      compressed INTEGER NOT NULL,
      created    TEXT NOT NULL
    )
  `);
  const hasRecordId =
    sql.exec("SELECT COUNT(*) AS n FROM pragma_table_info('events') WHERE name = 'record_id'").one().n === 1;
  if (!hasRecordId) {
    sql.exec('ALTER TABLE events ADD COLUMN record_id TEXT');
  }
  sql.exec('CREATE UNIQUE INDEX IF NOT EXISTS events_group_record ON events (group_id, record_id)');
  const hasLastAccess =
    sql.exec("SELECT COUNT(*) AS n FROM pragma_table_info('groups') WHERE name = 'last_access'").one().n === 1;
  if (!hasLastAccess) {
    sql.exec('ALTER TABLE groups ADD COLUMN last_access TEXT');
    sql.exec('UPDATE groups SET last_access = created WHERE last_access IS NULL');
  }
  const hasQuota =
    sql.exec("SELECT COUNT(*) AS n FROM pragma_table_info('groups') WHERE name = 'record_count'").one().n === 1;
  if (!hasQuota) {
    sql.exec('ALTER TABLE groups ADD COLUMN record_count INTEGER NOT NULL DEFAULT 0');
    sql.exec('ALTER TABLE groups ADD COLUMN total_bytes INTEGER NOT NULL DEFAULT 0');
    sql.exec('ALTER TABLE groups ADD COLUMN bytes_this_window INTEGER NOT NULL DEFAULT 0');
    sql.exec('ALTER TABLE groups ADD COLUMN window_start TEXT');
    sql.exec(
      'UPDATE groups SET record_count = (SELECT COUNT(*) FROM events WHERE events.group_id = groups.id), total_bytes = (SELECT COALESCE(SUM(LENGTH(data)), 0) FROM events WHERE events.group_id = groups.id), window_start = created',
    );
  }

  return {
    createGroup({ groupId, createdBy, authVerifier, powChallenge, created }) {
      try {
        sql.exec(
          'INSERT INTO groups (id, created_by, auth_verifier, pow_challenge, created, last_access, window_start) VALUES (?, ?, ?, ?, ?, ?, ?)',
          groupId,
          createdBy,
          authVerifier,
          powChallenge,
          created,
          created,
          created,
        );
        return null;
      } catch (err) {
        if (String(err.message).includes('groups.id')) {
          return 'group_exists';
        }
        throw err;
      }
    },

    getGroupVerifier(groupId) {
      const rows = sql.exec('SELECT auth_verifier FROM groups WHERE id = ?', groupId).toArray();
      return rows.length === 0 ? null : rows[0].auth_verifier;
    },

    getLastAccess(groupId) {
      const rows = sql.exec('SELECT last_access FROM groups WHERE id = ?', groupId).toArray();
      return rows.length === 0 ? null : rows[0].last_access;
    },

    touchAccess(groupId, now, staleBefore) {
      sql.exec(
        'UPDATE groups SET last_access = ? WHERE id = ? AND (last_access IS NULL OR last_access < ?)',
        now,
        groupId,
        staleBefore,
      );
      return sql.exec('SELECT changes() AS n').one().n > 0;
    },

    purgeIdleGroups(cutoff) {
      sql.exec('DELETE FROM events WHERE group_id IN (SELECT id FROM groups WHERE last_access < ?)', cutoff);
      sql.exec('DELETE FROM groups WHERE last_access < ?', cutoff);
      return sql.exec('SELECT changes() AS n').one().n;
    },

    // The DO holds a single group; the alarm reads it without knowing the id.
    soleGroup() {
      const rows = sql.exec('SELECT id, last_access FROM groups LIMIT 1').toArray();
      return rows.length === 0 ? null : { groupId: rows[0].id, lastAccess: rows[0].last_access };
    },

    getGroupStats(groupId) {
      const rows = sql
        .exec('SELECT record_count, total_bytes, bytes_this_window, window_start FROM groups WHERE id = ?', groupId)
        .toArray();
      return rows.length === 0
        ? null
        : {
            recordCount: rows[0].record_count,
            totalBytes: rows[0].total_bytes,
            bytesThisWindow: rows[0].bytes_this_window,
            windowStart: rows[0].window_start,
          };
    },

    appendEvent(groupId, { recordId, actorId, eventData, compressed, created }, limits) {
      if (recordId !== null) {
        const existing = sql
          .exec('SELECT seq FROM events WHERE group_id = ? AND record_id = ?', groupId, recordId)
          .toArray();
        if (existing.length > 0) {
          return { status: 'ok', seq: existing[0].seq };
        }
      }
      const size = eventData.length;
      const stats = sql
        .exec('SELECT record_count, total_bytes, bytes_this_window, window_start FROM groups WHERE id = ?', groupId)
        .one();
      const plan = planAppend(stats, size, created, limits);
      if (plan.rejection) {
        return plan.rejection;
      }
      const seq = sql
        .exec(
          'INSERT INTO events (group_id, record_id, actor_id, data, compressed, created) VALUES (?, ?, ?, ?, ?, ?) RETURNING seq',
          groupId,
          recordId,
          actorId,
          eventData,
          compressed ? 1 : 0,
          created,
        )
        .one().seq;
      sql.exec(
        'UPDATE groups SET record_count = record_count + 1, total_bytes = total_bytes + ?, window_start = ?, bytes_this_window = ? WHERE id = ?',
        size,
        plan.windowStart,
        plan.bytesThisWindow,
        groupId,
      );
      return { status: 'ok', seq };
    },

    listEventsSince(groupId, sinceSeq, limit) {
      return sql
        .exec(
          'SELECT seq, actor_id, data, compressed, created FROM events WHERE group_id = ? AND seq > ? ORDER BY seq LIMIT ?',
          groupId,
          sinceSeq,
          limit,
        )
        .toArray()
        .map((row) => ({
          seq: row.seq,
          actorId: row.actor_id,
          eventData: row.data,
          compressed: row.compressed === 1,
          created: row.created,
        }));
    },

    getMaxSeq(groupId) {
      return sql.exec('SELECT MAX(seq) AS max_seq FROM events WHERE group_id = ?', groupId).one().max_seq ?? 0;
    },
  };
}
