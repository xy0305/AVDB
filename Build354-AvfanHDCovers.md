# Build 354 — avfan boards HD covers, pacing, detail magnets play

Author: Muse (Kai), for the AVDB 1.0.2 line. Artifact: unsigned
`AVDB-unsigned-1.0.2-354-avfanhdcovers.ipa` (AVDB-354-release).

## What changed on top of Build 353

1. **Poster chain for the five external boards and the avfan
   detail.** Board cells and the avfan detail hero/works no longer
   pin avfan's raw cover (a watermarked landscape DVD jacket
   spread). They build the poster Movie through
   `AvfanMatchStore.posterMovie` (typed as censored catalog) and run
   AVDB's standard poster machinery with the visible-HQ upgrade on:
   - tier 1: the DMM/MGS official HD portrait resolved by number
     (ListCoverPolicy + VisibleHQPosterScheduler; the winner is
     persisted per number in the learned HQ cache);
   - tier 2: the stored JavDB cover from the frozen pre-matching
     feed (`match.cover`, lifted once from the five published feed
     files into the match store's own persistence, keyed by code) —
     this reads one stored image URL only: no JavDB API request is
     made, the feed matching/detail routing removed in 353 stays
     removed, and boards without a published feed simply skip the
     tier;
   - tier 3: the avfan original cover (or the board's own image).
   HEYZO/FC2/Western numbers keep original-artwork handling inside
   FrontPosterPolicy.

2. **avfan pacing (supersedes LOCK-353's 3 lanes × 0.4 s).** The
   device hit avfan's own rate limit, so: AvfanClient runs ONE
   serial lane at 1.2 s spacing for every fetch (matching and
   detail alike); the match store runs one serial worker; a bulk
   enqueue accepts at most 40 new entries per call — the rest join
   when scrolled into view via prioritize. An avfan rate limit
   (HTTP 429, or a page carrying the wait-ten-minutes notice) trips
   a shared 10-minute gate in AvfanClient: all avfan requests stop,
   the match queue is kept, board status lines say the boards are
   waiting out the limit, and matching resumes by itself when the
   cooldown ends. Persisted matches display throughout.

3. **avfan detail magnets: play.** The parser was verified
   byte-identical to AVFan's own `magnets()` and extracts magnets
   from AVFan's real detail fixtures (12 and 5 items), so empty
   sections mean the page itself listed none. Each magnet row now
   carries the normal detail's full action set — copy, push to 115
   (which also records the magnet in Pan115PlaybackCache), and play
   through Pan115PlayerView with the magnet in hand (search 115 by
   number first, push if missing, then play). The empty state is
   explicit: signed-in shows 「本站暂无磁链」; signed-out shows a
   「登录 avfan 后查看」 action, since avfan may gate magnets
   behind login.

Zero JavDB API requests on all board/detail paths, unchanged from
353. Cover swaps remain two-stage (base cover first, HD winner
paints over it when resolved); with the slower pacing the swap can
take a little longer than in 353.
