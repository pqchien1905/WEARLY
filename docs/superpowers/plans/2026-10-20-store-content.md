# Store content: draft and explicit publication

Existing scope: `AdminContentPage` has campaign title and policy fields;
`docs/api-contracts-frontend.md` requires explicit publication and drafts
remaining private. Home hero and `/shipping-returns` are existing destinations.

## Design

- Add one `StoreContent` record identified by fixed key `storefront`, created
  only on first save. No seed of unapproved policy text.
- Private read/save draft and explicit publish endpoints, ADMIN-only.
  Required expectedVersion prevents stale saves/publication and duplicated
  writes after uncertain responses. Save/publication each increments version.
- Publication copies the saved draft into separate published fields; later
  edits do not affect public reads. Public response omits every draft field.
- Add two admin audit actions; activity and content changes commit atomically.
- Text only: campaign title <=120 characters; policy <=5000 characters,
  nonblank after trim. No HTML rendering or automatic financial/rule changes.
- Admin page shows saved draft and published state; saving does not publish.
  Publish is a separate explicit action; errors require rereading current state.
- Home uses published title; policy page uses published policy. Before first
  publication existing demo copy remains explicitly identified. Loading/error
  states must not display a private draft or silently claim a publication.
- Product/FAQ links in remote mode refer to the published policy page instead
  of repeating a conflicting hardcoded return period.

## Checks

Regression-first API tests for RBAC, validation, draft isolation, stale version,
concurrent publication, duplicate request, atomic audit and public output.
Widget tests for separate save/publish, conflict/retry/session lifecycle,
plain-text rendering and mobile layout. Real Chrome admin save/publish ->
public title/policy -> edit draft without public change. Migrations only in
dedicated test databases; no production publication.
