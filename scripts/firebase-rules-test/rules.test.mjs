/**
 * Security-rules tests for Sylyo (Firestore + Cloud Storage).
 *
 * Run from the repo root via the Firebase Emulator Suite:
 *   cd scripts/firebase-rules-test && npm install && npm test
 *
 * `npm test` wraps the run in `firebase emulators:exec`, which starts the
 * firestore + storage emulators, loads firestore.rules / storage.rules, runs
 * this file, and tears the emulators down afterwards. No credentials or live
 * Firebase project are required (uses the `demo-sylyo` offline project).
 */
import { readFileSync } from "node:fs";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import { doc, setDoc, getDoc, updateDoc, deleteDoc } from "firebase/firestore";
import { ref, uploadBytes, getBytes, deleteObject } from "firebase/storage";

const OWNER = "alice";
const OTHER = "bob";
const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0]);
const IMG_META = { contentType: "image/png" };

let passed = 0;
let failed = 0;

async function check(label, fn) {
  try {
    await fn();
    console.log(`\u2705 ${label}`);
    passed++;
  } catch (e) {
    console.log(`\u274c ${label}\n     ${e.message || e}`);
    failed++;
  }
}

const testEnv = await initializeTestEnvironment({
  projectId: "demo-sylyo",
  firestore: { rules: readFileSync("firestore.rules", "utf8") },
  storage: { rules: readFileSync("storage.rules", "utf8") },
});

const ownerDb = testEnv.authenticatedContext(OWNER).firestore();
const otherDb = testEnv.authenticatedContext(OTHER).firestore();
const anonDb = testEnv.unauthenticatedContext().firestore();
const ownerStore = testEnv.authenticatedContext(OWNER).storage();
const otherStore = testEnv.authenticatedContext(OTHER).storage();

console.log("--- Firestore rules ---");
await check("owner can write a wardrobe item to their own path", () =>
  assertSucceeds(
    setDoc(doc(ownerDb, `users/${OWNER}/wardrobeItems/i1`), {
      name: "Blue Denim Jacket",
      category: "outerwear",
    })
  )
);
await check("owner can read their own wardrobe item", () =>
  assertSucceeds(getDoc(doc(ownerDb, `users/${OWNER}/wardrobeItems/i1`)))
);
await check("other user cannot read owner's wardrobe item", () =>
  assertFails(getDoc(doc(otherDb, `users/${OWNER}/wardrobeItems/i1`)))
);
await check("unauthenticated user cannot read owner's wardrobe item", () =>
  assertFails(getDoc(doc(anonDb, `users/${OWNER}/wardrobeItems/i1`)))
);
await check("owner can create an analyticsEvent", () =>
  assertSucceeds(
    setDoc(doc(ownerDb, `users/${OWNER}/analyticsEvents/e1`), { name: "item_saved" })
  )
);
await check("analyticsEvents are immutable: update denied", () =>
  assertFails(updateDoc(doc(ownerDb, `users/${OWNER}/analyticsEvents/e1`), { name: "x" }))
);
await check("analyticsEvents are immutable: delete denied", () =>
  assertFails(deleteDoc(doc(ownerDb, `users/${OWNER}/analyticsEvents/e1`)))
);

console.log("--- Storage rules ---");
await check("owner can upload an image to their own path", () =>
  assertSucceeds(uploadBytes(ref(ownerStore, `users/${OWNER}/images/jacket.png`), PNG, IMG_META))
);
await check("owner can read back their own image", () =>
  assertSucceeds(getBytes(ref(ownerStore, `users/${OWNER}/images/jacket.png`)))
);
await check("owner can delete their own image", () =>
  assertSucceeds(deleteObject(ref(ownerStore, `users/${OWNER}/images/jacket.png`)))
);
await check("upload with non-image content type is denied", () =>
  assertFails(
    uploadBytes(ref(ownerStore, `users/${OWNER}/images/notes.txt`), new Uint8Array([1, 2, 3]), {
      contentType: "text/plain",
    })
  )
);
await check("other user cannot upload into owner's path", () =>
  assertFails(uploadBytes(ref(otherStore, `users/${OWNER}/images/hack.png`), PNG, IMG_META))
);

await testEnv.cleanup();

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
