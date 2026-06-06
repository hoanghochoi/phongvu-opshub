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
- Warranty list, search, detail, and status update reads are scoped in the
  backend: `SUPER_ADMIN` can access every warranty; other signed-in users can
  access warranties created by users in the same showroom (`User.storeId`).
- Legacy n8n warranty metadata can be reconciled with
  `npm run migrate:n8n-warranty -- --store=CP62` from `backend-nest/` for a
  dry-run, then `npm run migrate:n8n-warranty -- --store=CP62 --apply` to write
  CP62 changes. Add `--reassign-existing-creators` when existing OpsHub rows
  must have `createdBy` reconciled back to the legacy n8n user, for example rows
  imported earlier under an admin account. Without `--store`, the script
  considers all legacy receipt prefixes. The script creates locked legacy users
  for n8n creators that do not yet exist in OpsHub, patches passwordless locked
  legacy users to the inferred receipt store, and merges normalized n8n image
  links into existing warranty rows instead of skipping them. Existing app image
  links are preserved.

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
