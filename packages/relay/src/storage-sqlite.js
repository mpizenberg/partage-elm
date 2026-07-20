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
      actor_id   TEXT NOT NULL,
      data       TEXT NOT NULL,
      compressed INTEGER NOT NULL,
      created    TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS events_group_seq ON events (group_id, seq);
  `);

  const insertGroup = db.prepare(
    'INSERT INTO groups (id, created_by, auth_verifier, pow_challenge, created) VALUES (?, ?, ?, ?, ?)',
  );
  const selectVerifier = db.prepare('SELECT auth_verifier FROM groups WHERE id = ?');
  const insertEvent = db.prepare(
    'INSERT INTO events (group_id, actor_id, data, compressed, created) VALUES (?, ?, ?, ?, ?)',
  );
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

    appendEvent(groupId, { actorId, eventData, compressed, created }) {
      const result = insertEvent.run(groupId, actorId, eventData, compressed ? 1 : 0, created);
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
