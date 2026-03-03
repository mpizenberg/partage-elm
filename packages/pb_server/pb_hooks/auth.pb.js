/// <reference path="../pb_data/types.d.ts" />

/**
 * PocketBase Authentication & Anti-Spam Hooks for Partage
 *
 * This file handles:
 * 1. Proof-of-Work validation for GROUP creation (anti-spam)
 * 2. Validation that groupId exists when creating group users
 *
 * Security model:
 * - Group creation requires PoW (anti-spam, one PoW = one group via unique powChallenge)
 * - User creation requires valid groupId (must reference existing group)
 * - One user account per group (enforced by unique groupId on users)
 *
 * PoW Configuration (hardcoded to avoid goja runtime issues):
 * - Difficulty: 18 (number of leading zero bits, ~2-4 seconds to solve)
 * - Challenge TTL: 600 seconds (10 minutes)
 * - Secret: from POW_SECRET env var or default
 */

// ==================== PoW Challenge Endpoint ====================

/**
 * Generate a PoW challenge
 * GET /api/pow/challenge
 */
routerAdd('GET', '/api/pow/challenge', function (e) {
  var secret = $os.getenv('POW_SECRET') || 'partage-pow-secret-change-in-production';
  var difficulty = 18;
  var timestamp = Math.floor(Date.now() / 1000);
  var challenge = $security.randomString(32);

  var dataToSign = challenge + ':' + timestamp + ':' + difficulty;
  var signature = $security.hs256(dataToSign, secret);

  return e.json(200, {
    challenge: challenge,
    timestamp: timestamp,
    difficulty: difficulty,
    signature: signature,
  });
});

// ==================== Group Creation Hook ====================

/**
 * Handle group creation:
 * 1. Validate PoW (anti-spam)
 * 2. Store powChallenge in record (unique constraint prevents reuse)
 */
onRecordCreateRequest(function (e) {
  var secret = $os.getenv('POW_SECRET') || 'partage-pow-secret-change-in-production';
  var challengeTTL = 600;
  var body = e.requestInfo().body || {};

  // --- Validate PoW ---
  var powChallenge = body.pow_challenge;
  var powTimestamp = body.pow_timestamp;
  var powDifficulty = body.pow_difficulty;
  var powSignature = body.pow_signature;
  var powSolution = body.pow_solution;

  if (!powChallenge || !powTimestamp || !powDifficulty || !powSignature || !powSolution) {
    throw new BadRequestError('Proof-of-work required for group creation');
  }

  // Verify signature
  var dataToSign = powChallenge + ':' + powTimestamp + ':' + powDifficulty;
  var expectedSignature = $security.hs256(dataToSign, secret);

  if (powSignature !== expectedSignature) {
    throw new BadRequestError('PoW verification failed: Invalid challenge signature');
  }

  // Check timestamp
  var now = Math.floor(Date.now() / 1000);
  if (now - powTimestamp > challengeTTL) {
    throw new BadRequestError('PoW verification failed: Challenge expired');
  }

  // Verify PoW solution
  var input = powChallenge + powSolution;
  var hash = $security.sha256(input);

  var fullHexChars = Math.floor(powDifficulty / 4);
  var remainingBits = powDifficulty % 4;
  var powValid = true;

  for (var i = 0; i < fullHexChars; i++) {
    if (hash[i] !== '0') {
      powValid = false;
      break;
    }
  }

  if (powValid && remainingBits > 0 && fullHexChars < hash.length) {
    var nextChar = parseInt(hash[fullHexChars], 16);
    var maxValue = Math.pow(2, 4 - remainingBits);
    if (nextChar >= maxValue) {
      powValid = false;
    }
  }

  if (!powValid) {
    throw new BadRequestError('PoW verification failed: Invalid PoW solution');
  }

  // Store the challenge in the record (unique index prevents reuse)
  e.record.set('powChallenge', powChallenge);

  e.next();
}, 'groups');

// ==================== User Creation Hook ====================

/**
 * Handle user creation:
 * Validate that the groupId references an existing group
 */
onRecordCreateRequest(function (e) {
  var groupId = e.record.get('groupId');

  if (!groupId) {
    throw new BadRequestError('groupId is required for user creation');
  }

  // Check that the group exists
  try {
    $app.findRecordById('groups', groupId);
  } catch (err) {
    throw new BadRequestError('Invalid groupId: group does not exist');
  }

  e.next();
}, 'users');
