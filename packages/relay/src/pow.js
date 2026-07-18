/**
 * Stateless proof-of-work challenges for group creation (anti-spam).
 *
 * The server stores nothing when issuing a challenge: the challenge, the
 * groupId it was requested for, its timestamp, and the difficulty are signed
 * with an HMAC secret, and the signature is verified when the solution comes
 * back. Binding the challenge to one groupId makes replay useless: a solved
 * challenge only works for that group, and the group can only be created
 * once. This must hold without shared state, because on Cloudflare each
 * group's storage lives in its own Durable Object.
 *
 * Wire format (challenge fields, solution field names, and the
 * SHA-256(challenge + solution) leading-zero-bits condition) must match the
 * client solver in vendor/elm-webcrypto (WebCrypto.ProofOfWork).
 *
 * WebCrypto only — runs identically on Node and Cloudflare Workers.
 */

export const DIFFICULTY = 18;
const CHALLENGE_TTL_SECONDS = 600;

const encoder = new TextEncoder();

function toHex(buffer) {
  return Array.from(new Uint8Array(buffer))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

async function hmacSha256Hex(secret, data) {
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  return toHex(await crypto.subtle.sign('HMAC', key, encoder.encode(data)));
}

async function sha256Hex(data) {
  return toHex(await crypto.subtle.digest('SHA-256', encoder.encode(data)));
}

/** Constant-time string comparison (both operands are hex/base64url ASCII). */
export function constantTimeEqual(a, b) {
  if (a.length !== b.length) {
    return false;
  }
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

export async function issueChallenge(secret, groupId) {
  const bytes = new Uint8Array(24);
  crypto.getRandomValues(bytes);
  const challenge = toHex(bytes.buffer);
  const timestamp = Math.floor(Date.now() / 1000);
  const signature = await hmacSha256Hex(secret, `${challenge}:${groupId}:${timestamp}:${DIFFICULTY}`);
  return { challenge, timestamp, difficulty: DIFFICULTY, signature };
}

/**
 * Verify a PoW solution. Returns null when valid, or an error message.
 * `solution` carries the pow_* fields sent by the client.
 */
export async function verifySolution(secret, groupId, solution) {
  const {
    pow_challenge: challenge,
    pow_timestamp: timestamp,
    pow_difficulty: difficulty,
    pow_signature: signature,
    pow_solution: nonce,
  } = solution;

  if (
    typeof challenge !== 'string' ||
    !Number.isInteger(timestamp) ||
    !Number.isInteger(difficulty) ||
    typeof signature !== 'string' ||
    typeof nonce !== 'string' ||
    challenge === '' ||
    nonce === ''
  ) {
    return 'Proof-of-work required for group creation';
  }

  const expectedSignature = await hmacSha256Hex(secret, `${challenge}:${groupId}:${timestamp}:${difficulty}`);
  if (!constantTimeEqual(signature, expectedSignature)) {
    return 'PoW verification failed: Invalid challenge signature';
  }

  const now = Math.floor(Date.now() / 1000);
  if (now - timestamp > CHALLENGE_TTL_SECONDS) {
    return 'PoW verification failed: Challenge expired';
  }

  const hash = await sha256Hex(challenge + nonce);
  const fullHexChars = Math.floor(difficulty / 4);
  const remainingBits = difficulty % 4;

  for (let i = 0; i < fullHexChars; i++) {
    if (hash[i] !== '0') {
      return 'PoW verification failed: Invalid PoW solution';
    }
  }
  if (remainingBits > 0 && fullHexChars < hash.length) {
    const nextChar = parseInt(hash[fullHexChars], 16);
    if (nextChar >= Math.pow(2, 4 - remainingBits)) {
      return 'PoW verification failed: Invalid PoW solution';
    }
  }

  return null;
}
