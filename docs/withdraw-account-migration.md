# Withdrawal authorId remapping — legacy data migration

## Context

Method A (`withdrawAccount` Cloud Function) remaps withdrawn posts/comments:

- `authorId` → `deleted_<serverGeneratedId>`
- `authorWithdrawn` → `true`
- display nickname → `탈퇴한 사용자`

This severs ownership and live nickname resolution after the same Kakao UID rejoins.

## Legacy rows that still need a one-shot migration

Accounts that withdrew **before** `withdrawAccount` was deployed may still have:

```
authorWithdrawn == true
authorId == <real Kakao / Firebase Auth UID>
```

Those rows will reconnect to a rejoin of the same Kakao account (display + Rules ownership) until migrated.

## Out of scope for the Method A implementation PR

- Do **not** run migration as part of the CF/Flutter ship.
- Do **not** change live `firestore.rules` for this.

## Migration tool (script + dry-run)

Use the standalone Admin SDK tool:

[`tools/withdrawn-content-migration/`](../tools/withdrawn-content-migration/README.md)

```bash
cd tools/withdrawn-content-migration
npm install
# set GOOGLE_APPLICATION_CREDENTIALS=...
npm run migrate:dry-run   # default: no writes
# npm run migrate:apply   # explicit only — review preview JSON first
```

Do **not** apply until dry-run preview (especially RE-REGISTERED UIDs) is reviewed.

## Notifications

Historical `notifications.actorUserId` may still point at a real Kakao UID. Inbox live-nickname policy is a separate concern and is not covered by this migration note.
