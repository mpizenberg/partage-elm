/**
 * Self-host storage adapter: one SQLite file for all groups, via node:sqlite.
 * Reference implementation of the storage interface documented in app.js.
 */

import { DatabaseSync } from 'node:sqlite';

export function openStorage(path) {
  const db = new DatabaseSync(path);
  db.exec(`
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS groups (
      id            TEXT PRIMARY KEY,
      created_by    TEXT NOT NULL,
      auth_verifier TEXT NOT NULL,
      pow_challenge TEXT NOT NULL,
      created       TEXT NOT NULL
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

  const insertGroup = db.prepare(
    'INSERT INTO groups (id, created_by, auth_verifier, pow_challenge, created) VALUES (?, ?, ?, ?, ?)',
  );
  const selectVerifier = db.prepare('SELECT auth_verifier FROM groups WHERE id = ?');
  const insertEvent = db.prepare(
    'INSERT INTO events (group_id, record_id, actor_id, data, compressed, created) VALUES (?, ?, ?, ?, ?, ?)',
  );
  const selectSeqByRecordId = db.prepare('SELECT seq FROM events WHERE group_id = ? AND record_id = ?');
  const selectEvents = db.prepare(
    'SELECT seq, actor_id, data, compressed, created FROM events WHERE group_id = ? AND seq > ? ORDER BY seq LIMIT ?',
  );
  const selectMaxSeq = db.prepare('SELECT MAX(seq) AS max_seq FROM events WHERE group_id = ?');

  return {
    createGroup({ groupId, createdBy, authVerifier, powChallenge, created }) {
      try {
        insertGroup.run(groupId, createdBy, authVerifier, powChallenge, created);
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

    appendEvent(groupId, { recordId, actorId, eventData, compressed, created }) {
      if (recordId !== null) {
        const existing = selectSeqByRecordId.get(groupId, recordId);
        if (existing !== undefined) {
          return existing.seq;
        }
      }
      const result = insertEvent.run(groupId, recordId, actorId, eventData, compressed ? 1 : 0, created);
      return Number(result.lastInsertRowid);
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
