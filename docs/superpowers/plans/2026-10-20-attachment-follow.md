# Attachment actions and account follow controls

## Requirements and implementation

- Replace the competing filename confirmation dialog and ellipsis menu with one native Menu covering the attachment's whole row, including its icon and empty space. Preserve inline progress, cancel/retry, fixed-target permission-checked deletion and its separate confirmation.
- Put one follow/unfollow action in the shared CommunityProfileSection used by search, repository owners, issue/comment/review authors, forks, stargazers, connections and public activity. Show no action for self or non-User profiles.
- Read the real relationship first. A shared, bounded, account-scoped store deduplicates reads, rechecks before writes and accepts only 204 as acknowledgement. Failed checks never imply not-followed. Account changes cancel pending reads; stale reads cannot overwrite a write. No timers or scrolling-triggered polling.
- Keep default OAuth scopes unchanged. An optional follow authorization toggle requests user:follow; failed token writes show a permissions hint.
- Preserve version 1.1.0 and the established SoftGroupRows/22-point continuous group geometry. No README or release publication changes.

## Review and validation

Independent read-only review found two follow lifecycle races (cancelled first waiter and a read concurrent with a write). Both were fixed before merge. The cancellation regression now waits until the actual request starts and asserts one shared read.

Windows validation: focused Python checks, shell/Python syntax, diff whitespace and the complete existing grouped-style/byte-exact API protections pass. Native Swift cases are intentionally skipped on Windows and run in macOS Actions.

Native tests exercise production API methods/store against a URLProtocol fixture: scopes, headers, exact status handling, deduplication, permissions failures, account changes, cancellation and read/write ordering. UI tests exercise repeated attachment menu presentation, trailing-space hit testing, copy, cancelled and acknowledged deletion, download failure/retry/cancel/completion; profile tests cover shared follow state, an existing followed user, self and failed reads/writes.

UI workflow uses the installed iOS 17 simulator; it does not prove iOS 16.3 device behavior. The user-reported iOS 16 modal conflict is addressed structurally by removing the competing attachment presenter.

CI results will be recorded after the workflows complete. Only after the IPA artifact is available will the requested forced shutdown be scheduled.
