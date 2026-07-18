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
      created       TEXT NOT NULL
    )
  `);
  sql.exec(`
    CREATE TABLE IF NOT EXISTS events (
      seq        INTEGER PRIMARY KEY AUTOINCREMENT,
      group_id   TEXT NOT NULL REFERENCES groups(id),
      actor_id   TEXT NOT NULL,
      data       TEXT NOT NULL,
      compressed INTEGER NOT NULL,
      created    TEXT NOT NULL
    )
  `);

  return {
    createGroup({ groupId, createdBy, authVerifier, powChallenge, created }) {
      try {
        sql.exec(
          'INSERT INTO groups (id, created_by, auth_verifier, pow_challenge, created) VALUES (?, ?, ?, ?, ?)',
          groupId,
          createdBy,
          authVerifier,
          powChallenge,
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

    appendEvent(groupId, { actorId, eventData, compressed, created }) {
      return sql
        .exec(
          'INSERT INTO events (group_id, actor_id, data, compressed, created) VALUES (?, ?, ?, ?, ?) RETURNING seq',
          groupId,
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
  };
}
