/**
 * PocketBase Collections Setup Script
 *
 * Automatically creates the required collections for Partage.
 * This script is idempotent - safe to run multiple times.
 *
 * Requirements:
 * - PocketBase server must be running
 * - .env file must contain POCKETBASE_ADMIN_EMAIL and POCKETBASE_ADMIN_PASSWORD
 *
 * Usage:
 *   node setup-collections.js
 *
 * Notes (key rotation):
 * - Key rotation “fanout” publishes one encrypted key package per recipient.
 * - To make this efficient and robust, we store `keyVersion` and allow de-duplication
 *   (same joinRequestId/groupId/recipient/keyVersion) at the application level.
 *   PocketBase itself doesn’t provide a strict unique constraint for base collections.
 */

import PocketBase from "pocketbase";
import { config } from "dotenv";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

// Load environment variables from .env
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
config({ path: join(__dirname, ".env") });

const PB_URL = process.env.PB_URL || "http://127.0.0.1:8090";
const ADMIN_EMAIL =
  process.env.PB_ADMIN_EMAIL || process.env.POCKETBASE_ADMIN_EMAIL;
const ADMIN_PASSWORD =
  process.env.PB_ADMIN_PASSWORD || process.env.POCKETBASE_ADMIN_PASSWORD;

if (!ADMIN_EMAIL || !ADMIN_PASSWORD) {
  console.error(
    "❌ Error: PB_ADMIN_EMAIL and PB_ADMIN_PASSWORD must be set in .env file",
  );
  console.error("   See .env.example for reference");
  process.exit(1);
}

const pb = new PocketBase(PB_URL);

/**
 * Check if a collection exists
 */
async function collectionExists(name) {
  try {
    await pb.collections.getOne(name);
    return true;
  } catch (error) {
    if (error.status === 404) {
      return false;
    }
    throw error;
  }
}

/**
 * Create the 'users' auth collection
 * Each user is a "group user" - one user account per group for data access
 */
async function createUsersCollection() {
  const collectionName = "users";

  if (await collectionExists(collectionName)) {
    console.log(
      `✅ Collection '${collectionName}' already exists, skipping...`,
    );
    return;
  }

  console.log(`📦 Creating auth collection '${collectionName}'...`);

  await pb.collections.create({
    name: collectionName,
    type: "auth",
    listRule: null, // Admin only
    viewRule: "@request.auth.id = id", // Users can only view themselves
    createRule: "", // Public (hook validates groupId exists)
    updateRule: null, // Not editable
    deleteRule: null, // Admin only
    fields: [
      // Username field - must be defined explicitly with unique index for identityFields
      {
        name: "username",
        type: "text",
        required: true,
      },
      // Email field - override default to make optional
      {
        name: "email",
        type: "email",
        required: false,
      },
      // groupId links to the group - required and unique (one user per group)
      {
        name: "groupId",
        type: "text",
        required: true,
      },
    ],
    // Unique indexes: username for auth, groupId for one-user-per-group
    indexes: [
      "CREATE UNIQUE INDEX `idx_users_username` ON `users` (`username`)",
      "CREATE UNIQUE INDEX `idx_users_groupId` ON `users` (`groupId`)",
    ],
    // Password authentication settings (PocketBase 0.23+ syntax)
    passwordAuth: {
      enabled: true,
      identityFields: ["username"], // Allow login with username only
    },
    // Disable OAuth2
    oauth2: {
      enabled: false,
    },
  });

  console.log(`✅ Collection '${collectionName}' created successfully`);
}

/**
 * Create the 'groups' collection
 * Group creation requires PoW (validated by hook)
 * powChallenge is stored to ensure one PoW = one group (unique constraint)
 */
async function createGroupsCollection() {
  const collectionName = "groups";

  if (await collectionExists(collectionName)) {
    console.log(
      `✅ Collection '${collectionName}' already exists, skipping...`,
    );
    return;
  }

  console.log(`📦 Creating collection '${collectionName}'...`);

  await pb.collections.create({
    name: collectionName,
    type: "base",
    // Require group auth to read (groupId matches the record id)
    listRule: '@request.auth.id != "" && @request.auth.groupId = id',
    viewRule: '@request.auth.id != "" && @request.auth.groupId = id',
    createRule: "", // Public (PoW validated by hook)
    updateRule: null, // Not editable
    deleteRule: null, // Admin only
    fields: [
      {
        name: "createdBy",
        type: "text",
        required: true,
      },
      // Store the PoW challenge to ensure uniqueness (one PoW = one group)
      {
        name: "powChallenge",
        type: "text",
        required: true,
      },
      {
        name: "created",
        type: "autodate",
        onCreate: true,
        onUpdate: false,
      },
    ],
    // Unique index on powChallenge prevents challenge reuse
    indexes: [
      "CREATE UNIQUE INDEX `idx_groups_powChallenge` ON `groups` (`powChallenge`)",
    ],
  });

  console.log(`✅ Collection '${collectionName}' created successfully`);
}

/**
 * Create the 'events' collection
 */
async function createEventsCollection() {
  const collectionName = "events";

  if (await collectionExists(collectionName)) {
    console.log(
      `✅ Collection '${collectionName}' already exists, skipping...`,
    );
    return;
  }

  console.log(`📦 Creating collection '${collectionName}'...`);

  await pb.collections.create({
    name: collectionName,
    type: "base",
    // Require authenticated group account with matching groupId
    listRule: '@request.auth.id != "" && @request.auth.groupId = groupId',
    viewRule: '@request.auth.id != "" && @request.auth.groupId = groupId',
    createRule: '@request.auth.id != "" && @request.auth.groupId = groupId',
    updateRule: null, // Updates not allowed
    deleteRule: null, // Deletes not allowed
    fields: [
      {
        name: "groupId",
        type: "text",
        required: true,
      },
      {
        name: "actorId",
        type: "text",
        required: true,
      },
      {
        name: "eventData",
        type: "text",
        required: true,
        max: 1000000, // 1MB limit for encrypted event data
      },
      {
        name: "created",
        type: "autodate",
        onCreate: true,
        onUpdate: false,
      },
    ],
  });

  console.log(`✅ Collection '${collectionName}' created successfully`);
  console.log(`   ⚠️  Real-time subscriptions are enabled by default`);
}

/**
 * Main setup function
 */
async function setup() {
  console.log("🚀 Starting PocketBase collection setup...\n");
  console.log(`📡 Connecting to PocketBase at ${PB_URL}`);

  try {
    // Check server health
    await pb.health.check();
    console.log("✅ PocketBase server is healthy\n");
  } catch (error) {
    console.error("❌ Error: PocketBase server is not reachable");
    console.error("   Make sure the pocketbase server is running");
    process.exit(1);
  }

  try {
    // Authenticate as admin
    console.log("🔐 Authenticating as admin...");
    await pb.admins.authWithPassword(ADMIN_EMAIL, ADMIN_PASSWORD);
    console.log("✅ Admin authentication successful\n");
  } catch (error) {
    console.error("❌ Error: Admin authentication failed");
    console.error("   Please check your credentials in .env file");
    console.error(`   Error: ${error.message}`);
    process.exit(1);
  }

  try {
    // Create collections (order matters: users first for auth references)
    await createUsersCollection();
    await createGroupsCollection();
    await createEventsCollection();

    console.log("\n✅ All collections are set up successfully!");
    console.log("\n📋 Collections created:");
    console.log(
      "   - users (auth collection for group accounts, one per group)",
    );
    console.log("   - groups (group metadata, requires PoW to create)");
    console.log("   - events (CRDT sync, requires group auth)");
  } catch (error) {
    console.error("\n❌ Error during setup:", error.message);
    if (error.data) {
      console.error("   Details:", JSON.stringify(error.data, null, 2));
    }
    process.exit(1);
  }
}

// Run setup
setup().catch((error) => {
  console.error("❌ Unexpected error:", error);
  process.exit(1);
});
