/**
 * PocketBase Database Clear Script
 *
 * Clears all data from the Partage collections.
 * This script is useful for resetting the database during development.
 *
 * Requirements:
 * - PocketBase server must be running
 * - .env file must contain PB_ADMIN_EMAIL and PB_ADMIN_PASSWORD
 *
 * Usage:
 *   node clear-database.js
 *
 * To fully reset the database, run:
 *   node clear-database.js --delete-collections && node setup-collections.js
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
 * Delete all records from a collection
 */
async function clearCollection(name) {
  if (!(await collectionExists(name))) {
    console.log(`⏭️  Collection '${name}' does not exist, skipping...`);
    return 0;
  }

  console.log(`🗑️  Clearing collection '${name}'...`);

  let deletedCount = 0;
  const perPage = 100;

  // Keep fetching and deleting until no records remain
  while (true) {
    const result = await pb.collection(name).getList(1, perPage);

    if (result.items.length === 0) {
      break;
    }

    for (const record of result.items) {
      await pb.collection(name).delete(record.id);
      deletedCount++;
    }
  }

  console.log(`✅ Deleted ${deletedCount} records from '${name}'`);
  return deletedCount;
}

/**
 * Delete a collection entirely
 */
async function deleteCollection(name) {
  if (!(await collectionExists(name))) {
    console.log(`⏭️  Collection '${name}' does not exist, skipping...`);
    return;
  }

  console.log(`🗑️  Deleting collection '${name}'...`);
  await pb.collections.delete(name);
  console.log(`✅ Collection '${name}' deleted`);
}

/**
 * Main clear function
 */
async function clear() {
  const deleteCollections = process.argv.includes("--delete-collections");

  console.log("🧹 Starting PocketBase database clear...\n");
  console.log(`📡 Connecting to PocketBase at ${PB_URL}`);

  try {
    // Check server health
    await pb.health.check();
    console.log("✅ PocketBase server is healthy\n");
  } catch (error) {
    console.error("❌ Error: PocketBase server is not reachable");
    console.error(
      "   Make sure the server is running: pnpm --filter pb_server serve",
    );
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
    if (deleteCollections) {
      // Delete collections entirely (order matters: events first due to potential references)
      console.log("📦 Deleting collections...\n");
      await deleteCollection("events");
      await deleteCollection("groups");
      await deleteCollection("users");

      console.log("\n✅ All collections deleted!");
      console.log("\n📋 Next steps:");
      console.log("   Run setup-collections.js to recreate collections:");
    } else {
      // Clear records from collections (order matters: events first, then groups, then users)
      console.log("📦 Clearing collection records...\n");
      const loroCount = await clearCollection("events");
      const groupsCount = await clearCollection("groups");
      const usersCount = await clearCollection("users");

      const totalDeleted = loroCount + groupsCount + usersCount;
      console.log(
        `\n✅ Database cleared! Total records deleted: ${totalDeleted}`,
      );

      if (totalDeleted === 0) {
        console.log("\n💡 Database was already empty.");
      }
    }
  } catch (error) {
    console.error("\n❌ Error during clear:", error.message);
    if (error.data) {
      console.error("   Details:", JSON.stringify(error.data, null, 2));
    }
    process.exit(1);
  }
}

// Run clear
clear().catch((error) => {
  console.error("❌ Unexpected error:", error);
  process.exit(1);
});
