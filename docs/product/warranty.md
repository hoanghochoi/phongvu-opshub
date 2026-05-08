# Warranty Contract

## Intent

Staff can capture warranty or repair images, upload them through OpsHub, and
receive status updates.

## Current Shape

- Flutter warranty screens live under `lib/features/warranty/`.
- Upload and warranty APIs live under `backend-nest/src/upload/` and
  `backend-nest/src/warranty/`.
- Redis publishes warranty status events.
- Go realtime service broadcasts Redis updates through `/ws`.

## Contract Notes

- Uploads are security-sensitive because they touch local files and public image
  URLs.
- Changes to file paths, image URL construction, file size/type validation, or
  status event payloads require explicit proof.
- `UPLOAD_BASE_DIR` must point to persistent storage in production.
- `IMAGE_BASE_URL` must match how uploaded files are served.

## Expected Proof

- NestJS upload/warranty tests.
- Go Redis/WebSocket tests when event behavior changes.
- Manual platform smoke for image picker, camera, permissions, and upload.
