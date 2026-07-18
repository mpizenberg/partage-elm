import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { issueChallenge, verifySolution, DIFFICULTY } from '../src/pow.js';
import { TEST_SECRET, solve, signChallenge } from './helpers.js';

const GROUP = 'g1';

function asSolution(challenge, nonce) {
  return {
    pow_challenge: challenge.challenge,
    pow_timestamp: challenge.timestamp,
    pow_difficulty: challenge.difficulty,
    pow_signature: challenge.signature,
    pow_solution: nonce,
  };
}

describe('proof of work', () => {
  it('issues challenges at the fixed difficulty with a valid signature', async () => {
    const challenge = await issueChallenge(TEST_SECRET, GROUP);
    assert.equal(challenge.difficulty, DIFFICULTY);
    assert.equal(
      challenge.signature,
      signChallenge(challenge.challenge, GROUP, challenge.timestamp, challenge.difficulty),
    );
  });

  it('accepts a correctly solved challenge', async () => {
    const challenge = await issueChallenge(TEST_SECRET, GROUP);
    const nonce = solve(challenge.challenge, challenge.difficulty);
    assert.equal(await verifySolution(TEST_SECRET, GROUP, asSolution(challenge, nonce)), null);
  });

  it('rejects a wrong nonce', async () => {
    const challenge = await issueChallenge(TEST_SECRET, GROUP);
    const nonce = solve(challenge.challenge, challenge.difficulty);
    const error = await verifySolution(TEST_SECRET, GROUP, asSolution(challenge, nonce + 'x'));
    assert.match(error, /Invalid PoW solution/);
  });

  it('rejects a tampered signature', async () => {
    const challenge = await issueChallenge(TEST_SECRET, GROUP);
    const nonce = solve(challenge.challenge, challenge.difficulty);
    const solution = asSolution(challenge, nonce);
    solution.pow_signature = signChallenge(challenge.challenge, GROUP, challenge.timestamp, challenge.difficulty, 'other-secret');
    const error = await verifySolution(TEST_SECRET, GROUP, solution);
    assert.match(error, /Invalid challenge signature/);
  });

  it('rejects a challenge solved for a different group', async () => {
    const challenge = await issueChallenge(TEST_SECRET, GROUP);
    const nonce = solve(challenge.challenge, challenge.difficulty);
    const error = await verifySolution(TEST_SECRET, 'other-group', asSolution(challenge, nonce));
    assert.match(error, /Invalid challenge signature/);
  });

  it('rejects a downgraded difficulty (signature covers it)', async () => {
    const challenge = await issueChallenge(TEST_SECRET, GROUP);
    const easy = { ...challenge, difficulty: 1 };
    const nonce = solve(easy.challenge, easy.difficulty);
    const error = await verifySolution(TEST_SECRET, GROUP, asSolution(easy, nonce));
    assert.match(error, /Invalid challenge signature/);
  });

  it('rejects an expired challenge', async () => {
    const timestamp = Math.floor(Date.now() / 1000) - 601;
    const challenge = {
      challenge: 'expired-challenge',
      timestamp,
      difficulty: 4,
      signature: signChallenge('expired-challenge', GROUP, timestamp, 4),
    };
    const nonce = solve(challenge.challenge, challenge.difficulty);
    const error = await verifySolution(TEST_SECRET, GROUP, asSolution(challenge, nonce));
    assert.match(error, /Challenge expired/);
  });

  it('rejects missing fields', async () => {
    const error = await verifySolution(TEST_SECRET, GROUP, {});
    assert.match(error, /Proof-of-work required/);
  });
});
