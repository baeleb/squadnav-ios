/**
 * SquadNav scheduled maintenance.
 *
 * cleanupGroups — runs daily. Deletes a group when ANY of these hold:
 *   1. Empty: no docs in its members subcollection (covers leader-left-
 *      without-transfer leftovers and failed join/leave races).
 *   2. Solo for a day: <= 1 member and the group is older than 24h
 *      (nobody ever joined — almost always an abandoned test group).
 *   3. Nav-stale: not currently navigating and no navigation started in
 *      the last 14 days (lastNavigatedAt, falling back to createdAt for
 *      groups that predate the field).
 *
 * Deletion is recursive (members/messages/files subcollections) and also
 * removes the group's Storage blobs under groups/{groupId}/.
 */
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");

initializeApp();

const DAY_MS = 24 * 60 * 60 * 1000;
const NAV_STALE_MS = 14 * DAY_MS;

exports.cleanupGroups = onSchedule(
  { schedule: "every 24 hours", region: "us-central1" },
  async () => {
    const db = getFirestore();
    const bucket = getStorage().bucket();
    const now = Date.now();

    const snap = await db.collection("groups").get();
    let deleted = 0;

    for (const doc of snap.docs) {
      const g = doc.data();
      const members = await doc.ref.collection("members").limit(2).get();
      const memberCount = members.size;

      const createdAt = g.createdAt && g.createdAt.toMillis ? g.createdAt.toMillis() : now;
      const lastNav =
        g.lastNavigatedAt && g.lastNavigatedAt.toMillis
          ? g.lastNavigatedAt.toMillis()
          : createdAt;

      const isEmpty = memberCount === 0;
      const isSoloStale = memberCount <= 1 && now - createdAt > DAY_MS;
      const isNavStale = !g.isNavigating && now - lastNav > NAV_STALE_MS;

      if (isEmpty || isSoloStale || isNavStale) {
        const reason = isEmpty ? "empty" : isSoloStale ? "solo>1d" : "nav-stale>14d";
        console.log(`cleanupGroups: deleting ${doc.id} (${g.name || "unnamed"}) — ${reason}`);
        await db.recursiveDelete(doc.ref);
        await bucket.deleteFiles({ prefix: `groups/${doc.id}/` }).catch((err) => {
          console.warn(`cleanupGroups: storage sweep failed for ${doc.id}: ${err.message}`);
        });
        deleted++;
      }
    }

    console.log(`cleanupGroups: scanned ${snap.size} group(s), deleted ${deleted}`);
  }
);
