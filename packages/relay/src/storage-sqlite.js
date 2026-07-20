/**
 * Self-host storage adapter: one SQLite file for all groups, via node:sqlite.
 * Reference implementation of the storage interface documented in app.js.
 */

import { DatabaseSync } from 'node:sqlite';
import { planChange } from './quota.js';

export function openStorage(path) {
  const db = new DatabaseSync(path);
  db.exec(`
    PRAGMA auto_vacuum = INCREMENTAL;
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS groups (
      id            TEXT PRIMARY KEY,
      created_by    TEXT NOT NULL,
      auth_verifier TEXT NOT NULL,
      pow_challenge TEXT NOT NULL,
      created       TEXT NOT NULL,
      last_access   TEXT
    );
    CREATE TABLE IF NOT EXISTS events (
      seq        INTEGER PRIMARY KEY AUTOINCREMENT,
      group_id   TEXT NOT NULL REFERENCES groups(id),
      record_id  TEXT,
      actor_id   TEXT NOT NULL,
      data       TEXT NOT NULL,
      compressed INTEGER NOT NULL,
      created    TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS events_group_seq ON events (group_id, seq);
  `);
  const hasRecordId =
    db.prepare("SELECT COUNT(*) AS n FROM pragma_table_info('events') WHERE name = 'record_id'").get().n === 1;
  if (!hasRecordId) {
    db.exec('ALTER TABLE events ADD COLUMN record_id TEXT');
  }
  db.exec('CREATE UNIQUE INDEX IF NOT EXISTS events_group_record ON events (group_id, record_id)');
  const hasLastAccess =
    db.prepare("SELECT COUNT(*) AS n FROM pragma_table_info('groups') WHERE name = 'last_access'").get().n === 1;
  if (!hasLastAccess) {
    db.exec('ALTER TABLE groups ADD COLUMN last_access TEXT');
    db.exec('UPDATE groups SET last_access = created WHERE last_access IS NULL');
  }
  db.exec('CREATE INDEX IF NOT EXISTS groups_last_access ON groups (last_access)');
  const hasQuota =
    db.prepare("SELECT COUNT(*) AS n FROM pragma_table_info('groups') WHERE name = 'record_count'").get().n === 1;
  if (!hasQuota) {
    db.exec(`
      ALTER TABLE groups ADD COLUMN record_count INTEGER NOT NULL DEFAULT 0;
      ALTER TABLE groups ADD COLUMN total_bytes INTEGER NOT NULL DEFAULT 0;
      ALTER TABLE groups ADD COLUMN bytes_this_window INTEGER NOT NULL DEFAULT 0;
      ALTER TABLE groups ADD COLUMN window_start TEXT;
      UPDATE groups SET
        record_count = (SELECT COUNT(*) FROM events WHERE events.group_id = groups.id),
        total_bytes = (SELECT COALESCE(SUM(LENGTH(data)), 0) FROM events WHERE events.group_id = groups.id),
        window_start = created;
    `);
  }

  const insertGroup = db.prepare(
    'INSERT INTO groups (id, created_by, auth_verifier, pow_challenge, created, last_access, window_start) VALUES (?, ?, ?, ?, ?, ?, ?)',
  );
  const selectVerifier = db.prepare('SELECT auth_verifier FROM groups WHERE id = ?');
  const selectLastAccess = db.prepare('SELECT last_access FROM groups WHERE id = ?');
  const touchAccessStmt = db.prepare(
    'UPDATE groups SET last_access = ? WHERE id = ? AND (last_access IS NULL OR last_access < ?)',
  );
  const deleteIdleEvents = db.prepare(
    'DELETE FROM events WHERE group_id IN (SELECT id FROM groups WHERE last_access < ?)',
  );
  const deleteIdleGroups = db.prepare('DELETE FROM groups WHERE last_access < ?');
  const insertEvent = db.prepare(
    'INSERT INTO events (group_id, record_id, actor_id, data, compressed, created) VALUES (?, ?, ?, ?, ?, ?)',
  );
  const selectStats = db.prepare(
    'SELECT record_count, total_bytes, bytes_this_window, window_start FROM groups WHERE id = ?',
  );
  const updateStats = db.prepare(
    'UPDATE groups SET record_count = record_count + ?, total_bytes = total_bytes + ?, window_start = ?, bytes_this_window = ? WHERE id = ?',
  );
  const selectSeqByRecordId = db.prepare('SELECT seq FROM events WHERE group_id = ? AND record_id = ?');
  const selectSurvivorByRecordId = db.prepare(
    'SELECT seq FROM events WHERE group_id = ? AND record_id = ? AND seq > ?',
  );
  const selectDeletable = db.prepare(
    'SELECT COUNT(*) AS n, COALESCE(SUM(LENGTH(data)), 0) AS bytes FROM events WHERE group_id = ? AND seq <= ?',
  );
  const deleteUpTo = db.prepare('DELETE FROM events WHERE group_id = ? AND seq <= ?');
  const selectEvents = db.prepare(
    'SELECT seq, actor_id, data, compressed, created FROM events WHERE group_id = ? AND seq > ? ORDER BY seq LIMIT ?',
  );
  const selectMaxSeq = db.prepare('SELECT MAX(seq) AS max_seq FROM events WHERE group_id = ?');

  return {
    createGroup({ groupId, createdBy, authVerifier, powChallenge, created }) {
      try {
        insertGroup.run(groupId, createdBy, authVerifier, powChallenge, created, created, created);
        return null;
      } catch (err) {
        if (String(err.message).includes('groups.id')) {
          return 'group_exists';
        }
        throw err;
      }
    },

    getGroupVerifier(groupId) {
      const row = selectVerifier.get(groupId);
      return row === undefined ? null : row.auth_verifier;
    },

    getLastAccess(groupId) {
      const row = selectLastAccess.get(groupId);
      return row === undefined ? null : row.last_access;
    },

    touchAccess(groupId, now, staleBefore) {
      return touchAccessStmt.run(now, groupId, staleBefore).changes > 0;
    },

    purgeIdleGroups(cutoff) {
      deleteIdleEvents.run(cutoff);
      const purged = deleteIdleGroups.run(cutoff).changes;
      if (purged > 0) {
        db.exec('PRAGMA incremental_vacuum');
      }
      return purged;
    },

    getGroupStats(groupId) {
      const row = selectStats.get(groupId);
      return row === undefined
        ? null
        : {
            recordCount: row.record_count,
            totalBytes: row.total_bytes,
            bytesThisWindow: row.bytes_this_window,
            windowStart: row.window_start,
          };
    },

    appendEvent(groupId, { recordId, actorId, eventData, compressed, created }, limits) {
      if (recordId !== null) {
        const existing = selectSeqByRecordId.get(groupId, recordId);
        if (existing !== undefined) {
          return { status: 'ok', seq: existing.seq };
        }
      }
      const size = eventData.length;
      const plan = planChange(selectStats.get(groupId), { records: 1, bytes: size }, created, limits);
      if (plan.rejection) {
        return plan.rejection;
      }
      const result = insertEvent.run(groupId, recordId, actorId, eventData, compressed ? 1 : 0, created);
      updateStats.run(1, size, plan.windowStart, plan.bytesThisWindow, groupId);
      return { status: 'ok', seq: Number(result.lastInsertRowid) };
    },

    compact(groupId, uptoSeq, expectedCount, records, created, limits) {
      db.exec('BEGIN IMMEDIATE');
      try {
        const maxSeq = selectMaxSeq.get(groupId).max_seq ?? 0;
        const deletable = selectDeletable.get(groupId, uptoSeq);
        // The delete range must hold exactly the records the caller pulled:
        // fewer means another compaction landed since its snapshot (a lost
        // race, or a retry of one that already succeeded) — reject rather
        // than delete blind. Concurrent pushes sit above uptoSeq and never
        // trip this.
        if (uptoSeq > maxSeq || deletable.n !== expectedCount) {
          db.exec('ROLLBACK');
          return { status: 'stale' };
        }
        // A record whose recordId survives above the boundary already holds
        // the same content (ids are content-derived): skip, don't duplicate.
        const fresh = records.filter(
          (record) =>
            record.recordId === null || selectSurvivorByRecordId.get(groupId, record.recordId, uptoSeq) === undefined,
        );
        const recordDelta = fresh.length - deletable.n;
        const byteDelta = fresh.reduce((sum, record) => sum + record.eventData.length, 0) - deletable.bytes;
        const plan = planChange(selectStats.get(groupId), { records: recordDelta, bytes: byteDelta }, created, limits);
        if (plan.rejection) {
          db.exec('ROLLBACK');
          return plan.rejection;
        }
        deleteUpTo.run(groupId, uptoSeq);
        for (const record of fresh) {
          insertEvent.run(groupId, record.recordId, record.actorId, record.eventData, record.compressed ? 1 : 0, created);
        }
        updateStats.run(recordDelta, byteDelta, plan.windowStart, plan.bytesThisWindow, groupId);
        const newMaxSeq = selectMaxSeq.get(groupId).max_seq ?? 0;
        db.exec('COMMIT');
        return { status: 'ok', maxSeq: newMaxSeq };
      } catch (err) {
        db.exec('ROLLBACK');
        throw err;
      }
    },

    listEventsSince(groupId, sinceSeq, limit) {
      return selectEvents.all(groupId, sinceSeq, limit).map((row) => ({
        seq: row.seq,
        actorId: row.actor_id,
        eventData: row.data,
        compressed: row.compressed === 1,
        created: row.created,
      }));
    },

    getMaxSeq(groupId) {
      return selectMaxSeq.get(groupId).max_seq ?? 0;
    },

    close() {
      db.close();
    },
  };
}
