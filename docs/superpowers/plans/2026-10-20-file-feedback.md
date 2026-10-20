# Project file actions and ZIP completion feedback

The user's IMG_2459 video shows the local Git project's file list: each ordinary file has an ellipsis that only exposes deletion. Remove that redundant control and keep native long-press deletion with the existing confirmation. A regular tap continues to open the established code/DEB editor. Group corners and dividers remain unchanged.

The repository ZIP download previously stored a success string directly in the repository list indefinitely. Use the actual URL returned after successful persistence to present a native dismissible completion alert instead. Display the saved filename and immediate destination folder without exposing the container path. Dismissal clears the state; the next successful save can present again. Account/session and download authorization checks are preserved. Other download and release-attachment flows are unchanged.

Validation before CI: the two new regression checks failed against the old UI and pass with the change. Related Windows checks: 29 tests, 24 passed and 5 native skips. The complete existing grouped-style and protected-operation checks pass. Independent read-only review found no P1/P2.

The `file-feedback` native UI scope exercises the shipping project file list (preview, long-press deletion confirmation/cancel and direct DEB editing), the existing DEB save flow, and the production native completion presenter (no long path, dismiss and present again). Strict screenshot export requires all three expected captures. The completion presenter fixture simulates a successful save event; it does not claim to test a real ZIP network download. Existing persistence and API tests continue to validate those boundaries on macOS.

Version remains 1.1.0. README and release publication are outside this change. CI results will be appended after completion.
