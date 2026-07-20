/**
 * Cloudflare storage adapter: one Durable Object per group, backed by the
 * DO's SQLite. Same schema as the self-host file so the two adapters stay
 * interchangeable; the group_id column simply always holds the DO's one group.
 */

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

  return {
    createGroup({ groupId, createdBy, authVerifier, powChallenge, created }) {
      try {
        sql.exec(
          'INSERT INTO groups (id, created_by, auth_verifier, pow_challenge, created, last_access) VALUES (?, ?, ?, ?, ?, ?)',
          groupId,
          createdBy,
          authVerifier,
          powChallenge,
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

    appendEvent(groupId, { recordId, actorId, eventData, compressed, created }) {
      if (recordId !== null) {
        const existing = sql
          .exec('SELECT seq FROM events WHERE group_id = ? AND record_id = ?', groupId, recordId)
          .toArray();
        if (existing.length > 0) {
          return existing[0].seq;
        }
      }
      return sql
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
