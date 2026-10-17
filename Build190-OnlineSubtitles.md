# Build 190 · Online subtitle resource hardening

Build 189's opt-in search/panel/player overlay is retained unchanged. Reject 150,000+ newline payloads before allocating a components array; prevents tiny-line allocation bombs within the 8MiB download bound. Added executable production Swift fixtures for the 80-candidate maximum, >20,000 cues, newline bombs and streaming 8MiB download cap.

Both iPad and iPhone native subtitle consent/search/manual selection/offset/disable UI tests and both new hosted model tests passed on build 189. Its general iPad suite failed only the independent MissAV weekly refresh request-count test; iPhone suite passed. A test-only follow-up explicitly selects BOTH the existing DetailPosterQualityTests class and the new OnlineSubtitleModelTests class so adding a more-specific selector cannot mask legacy native tests. None of the old tests were deleted or relaxed.

Normal TLS public query was verified in iSH Python and system WebKit (code0/56 rows for Oppenheimer 2023). macOS CI system URLSession optional live probe timed out (-1001); not a claim of successful native service connectivity. No TLS bypass, production copyrighted subtitle download, local video hash calculation, Range query or 115 credential forwarding. Actual CI-resolved KSPlayer is 2.3.4. Full behavioral/security limitations remain as documented in Build189-OnlineSubtitles.md.

The final security patch increments remote build189 to190 in both pbx settings and plist. Do not overwrite the older package. Verification of the final IPA and exact latest CI statuses are reported with delivery evidence.
