/**
 * Nook Cloud Functions
 *
 * generateFashionShot (callable):
 *   1. Auth required
 *   2. Read garment + human images from the caller's Firebase Storage paths
 *   3. Create short-lived signed URLs for Replicate
 *   4. Run cuuupid/idm-vton on Replicate
 *   5. Upload the result to users/{uid}/fashion-shots/{id}.jpg
 *   6. Return { path, downloadURL }
 *
 * Secrets:
 *   firebase functions:secrets:set REPLICATE_API_TOKEN
 *
 * License note: IDM-VTON weights are CC BY-NC-SA 4.0 (non-commercial).
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { initializeApp } = require("firebase-admin/app");
const { getStorage } = require("firebase-admin/storage");
const { randomUUID } = require("crypto");

initializeApp();

const replicateToken = defineSecret("REPLICATE_API_TOKEN");

/** Prefer the models API (no pinned version). Fallback version if needed. */
const REPLICATE_MODEL = "cuuupid/idm-vton";
const REPLICATE_VERSION =
  "906425dbca90663ff5427624839572cc56ea7d380343d13e2a4c4b09d3f0c30f";

function mapCategory(category) {
  const c = String(category || "").toLowerCase();
  if (c.includes("dress")) return "dresses";
  if (
    c.includes("bottom") ||
    c.includes("pant") ||
    c.includes("skirt") ||
    c.includes("short")
  ) {
    return "lower_body";
  }
  return "upper_body";
}

function assertOwnPath(uid, path) {
  const prefix = `users/${uid}/`;
  if (!path || typeof path !== "string" || !path.startsWith(prefix)) {
    throw new HttpsError(
      "permission-denied",
      "Image path must belong to the signed-in user."
    );
  }
  if (path.includes("..")) {
    throw new HttpsError("invalid-argument", "Invalid storage path.");
  }
}

async function signedReadUrl(bucket, path, minutes = 60) {
  const file = bucket.file(path);
  const [exists] = await file.exists();
  if (!exists) {
    throw new HttpsError("not-found", `Missing file: ${path}`);
  }
  const [url] = await file.getSignedUrl({
    action: "read",
    expires: Date.now() + minutes * 60 * 1000,
  });
  return url;
}

async function createPrediction(token, input) {
  // Try models endpoint first (always latest).
  let res = await fetch(
    `https://api.replicate.com/v1/models/${REPLICATE_MODEL}/predictions`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
        Prefer: "wait=60",
      },
      body: JSON.stringify({ input }),
    }
  );

  if (res.status === 404 || res.status === 405) {
    res = await fetch("https://api.replicate.com/v1/predictions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
        Prefer: "wait=60",
      },
      body: JSON.stringify({ version: REPLICATE_VERSION, input }),
    });
  }

  if (!res.ok) {
    const text = await res.text();
    throw new HttpsError(
      "internal",
      `Replicate create failed (${res.status}): ${text.slice(0, 400)}`
    );
  }
  return res.json();
}

async function waitForPrediction(token, prediction, maxWaitMs = 180000) {
  let current = prediction;
  const started = Date.now();
  while (
    current.status !== "succeeded" &&
    current.status !== "failed" &&
    current.status !== "canceled"
  ) {
    if (Date.now() - started > maxWaitMs) {
      throw new HttpsError("deadline-exceeded", "Replicate timed out.");
    }
    await new Promise((r) => setTimeout(r, 2500));
    const res = await fetch(current.urls.get, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) {
      throw new HttpsError("internal", "Failed to poll Replicate prediction.");
    }
    current = await res.json();
  }
  if (current.status !== "succeeded") {
    throw new HttpsError(
      "internal",
      `Replicate ${current.status}: ${current.error || "unknown error"}`
    );
  }
  return current;
}

function outputUrl(prediction) {
  const out = prediction.output;
  if (typeof out === "string") return out;
  if (Array.isArray(out) && out.length) return out[0];
  throw new HttpsError("internal", "Replicate returned no image URL.");
}

exports.generateFashionShot = onCall(
  {
    secrets: [replicateToken],
    timeoutSeconds: 300,
    memory: "1GiB",
    region: "us-central1",
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const uid = request.auth.uid;
    const {
      garmentPath,
      humanPath,
      category,
      garmentDescription,
    } = request.data || {};

    assertOwnPath(uid, garmentPath);
    assertOwnPath(uid, humanPath);

    const token = replicateToken.value();
    if (!token) {
      throw new HttpsError(
        "failed-precondition",
        "REPLICATE_API_TOKEN secret is not configured."
      );
    }

    const bucket = getStorage().bucket();
    const [garmUrl, humanUrl] = await Promise.all([
      signedReadUrl(bucket, garmentPath),
      signedReadUrl(bucket, humanPath),
    ]);

    const input = {
      garm_img: garmUrl,
      human_img: humanUrl,
      garment_des:
        garmentDescription ||
        `${category || "clothing"} fashion garment`,
      category: mapCategory(category),
      crop: true,
      steps: 30,
      seed: Math.floor(Math.random() * 1_000_000),
    };

    let prediction = await createPrediction(token, input);
    if (prediction.status !== "succeeded") {
      prediction = await waitForPrediction(token, prediction);
    }

    const imageUrl = outputUrl(prediction);
    const imageRes = await fetch(imageUrl);
    if (!imageRes.ok) {
      throw new HttpsError("internal", "Failed to download Replicate output.");
    }
    const buffer = Buffer.from(await imageRes.arrayBuffer());
    const shotId = randomUUID();
    const outPath = `users/${uid}/fashion-shots/${shotId}.jpg`;
    const outFile = bucket.file(outPath);
    await outFile.save(buffer, {
      contentType: "image/jpeg",
      metadata: {
        metadata: {
          source: "idm-vton",
          replicateId: prediction.id || "",
          garmentPath,
          humanPath,
        },
      },
    });

    // Tokenized download URL for the iOS client (same pattern as client SDK).
    const downloadToken = randomUUID();
    await outFile.setMetadata({
      metadata: {
        firebaseStorageDownloadTokens: downloadToken,
        source: "idm-vton",
      },
    });
    const encoded = encodeURIComponent(outPath);
    const bucketName = bucket.name;
    const downloadURL =
      `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encoded}` +
      `?alt=media&token=${downloadToken}`;

    return {
      path: outPath,
      downloadURL,
      replicateId: prediction.id || null,
      category: input.category,
    };
  }
);
