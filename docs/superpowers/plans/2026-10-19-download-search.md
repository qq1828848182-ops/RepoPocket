# Download experience and repository search

User-approved scope: compact release attachments with native actions and inline real download status; repository search accepts a complete repository URL, explicitly separates repository/user searches, and repository headers link their author to the existing profile/repository page. Also audit issue/comment and other typed user identities for profile navigation, preserving account-switch controls. Keep existing 22-point grouped rows and permission/session guards; user requested final version 1.1.0. No multilingual implementation, README edits, release publishing, or shutdown.

- [x] Route complete repository URLs without the keyword search API; preserve strict host and root-path validation. Add explicit repository/user selection and typed author navigation across repository cards, Issue/PR lists/details, discussion/reviews, forks, Actions and public activity. Do not infer account identity from raw Git author names.
- [x] One attachment row per file; native download/copy actions and permission-gated delete menu with existing confirmation.
- [x] Inline authorization/connection/byte progress/save/success/failure/cancel status. Throttle progress and reject obsolete updates after cancel, retry, navigation and account changes.
- [ ] Native production regressions and simulator interactions; independent review; synchronize main and run Build IPA for user download.

Windows preflight: unittest discovery reports 156 tests, no assertion failures; eight legacy modules require unavailable Swift and fail at import, 64 native cases skip. Production Swift regressions and simulator interactions must pass on macOS before completion. The independent review found and prompted fixes for redirected repository ownership, default card/list/fork identities, and stale download state hiding a later file-import error. README and existing download authorization/redirect/save protections remain unchanged.
