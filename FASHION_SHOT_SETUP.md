# Professional fashion shots (IDM-VTON via Replicate)

Flow:

```text
iOS scan cutout + model photo
  → upload to Firebase Storage (users/{uid}/images/…)
  → callable Cloud Function generateFashionShot
  → Replicate cuuupid/idm-vton
  → result saved to users/{uid}/fashion-shots/{id}.jpg
  → iOS downloads & previews; Save stores path on WardrobeItem
```

## One-time setup

1. **Blaze plan** required for Cloud Functions + outbound Replicate calls.  
2. Create a Replicate API token: https://replicate.com/account/api-tokens  
3. From the repo root:

```bash
cd functions && npm install && cd ..
firebase login
firebase use sylyo-fashion
firebase functions:secrets:set REPLICATE_API_TOKEN
# paste the token when prompted
firebase deploy --only functions
```

4. Open the iOS app (Xcode will resolve `FirebaseFunctions`), sign in, scan a garment, tap **Create fashion shot**, pick a full-body model photo (or use your profile avatar).

## License

[IDM-VTON](https://huggingface.co/yisol/IDM-VTON) weights are **CC BY-NC-SA 4.0** (non-commercial). Do not ship a commercial App Store build on this model without a different licensed backend.

## Cost

Replicate IDM-VTON is roughly a few cents per run (A100). See Replicate pricing for `cuuupid/idm-vton`.
