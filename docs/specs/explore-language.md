# Explore: language filter

What the Language filter on the Explore page promises, and how it keeps
that promise. Code: `lib/video_languages.dart`, `lib/youtube_player_probe.dart`,
`lib/app/explore_controller.dart`, `spoken_language` in
`native/lumtub_core/src/innertube.rs`. Tests: `test/video_languages_test.dart`,
`test/explore_filters_test.dart`.

## Promise

With a language picked, Explore shows only videos **spoken** in that
language, never one in another. Videos confirmed by their audio come
first; videos YouTube makes no automatic captions for (most Chinese
videos, and many in other languages) follow when their own texts, not a
translation of them, are in the language. There is no switch to loosen or
tighten this.

## What decides

From the video's own `/youtubei/v1/player` answer, in this order:

1. **The original audio track.** On a video with audio in several
   languages, the track whose `xtags` say `acont=original` (else whose
   name says "original"). A dub is never taken for the original, even
   when YouTube makes it the default.
2. **The automatic captions** (`captionTracks[].kind == "asr"`). YouTube
   makes them from the audio, so their language is the spoken one;
   translations are not in `captionTracks`. A video with automatic
   captions in two languages (seen with dubbed videos) is not told by
   them.
3. **Only when neither exists**, the title and description read
   together, and only when the title is not a translation: the title
   listed in the language picked (the search is asked in it) is the same
   as the one `/player` gives asked in English. A title the uploader
   translated differs between the two, and such a video is left out.

Whenever 1 or 2 exists it decides, whatever the texts say: an English
lecture with an Italian title and English captions is left out. A video
YouTube does not answer for is left out.

Videos confirmed by 1 or 2 are shown as they come; videos let in by 3
wait behind them and are shown 12 at a time, or when the search ends.

Text is read by `title_language` in the Rust core: the script, then small
words (`LATIN_WORDS`, which leave out words two languages share, such as
`con`, `una`, `in`), then whatlang trigrams, which overrule small words
only when sure and when the language they name has no fewer small words.

## Finding candidates

The zone's search words are put into the language picked before
searching, so that the search finds videos in it to begin with:

- words in another script (Chinese, Japanese…) always;
- for a language other than English, English words too
  (`哲学 philosophy lecture` → `filosofia lezione di filosofia`), except
  names and words titles write the same everywhere (`Minecraft`, `Plato`,
  `lofi`, `vlog`, see `keptSearchWords`);
- a zone of the person's own too; when its translated search runs out,
  its words as written are searched as well.

An English word a zone gives beside its Chinese keyword
(`基督宗教 Christianity`) is that keyword's English, not a name, and is
translated with it (kept as a name, Italian Christianity searched
"Christianity" and kept 0 of 240, 2026-11-19).

The zones' Chinese keywords are not translated themselves: each has its
English in `searchPivots` (`lib/explore_pivots.dart`), which is translated
instead, a run of English words at a time, and which an English search
takes as it is. Translated one by one from Chinese, keywords lost their
sense (体育 → "educazione fisica", 后端 → "rear end"). `直播` and other
words of `searchGlossary` are searched as `live` everywhere, and so is
an English `live`, kept apart from the words around it (put into other
languages with them it became "living": `art live` in Indonesian was
"the art of living"). Jargon and names titles write in English
(`tutorial`, `startup`, `writeup`, `hololive`…) are kept as they are. A test checks
that every Chinese keyword of every zone, sub-category and filter has its
English. Each word of the result is kept once.

Keywords no pivot covers, such as those of a zone the person added, go
into English first and from there into the language picked, in the same
way. Chinese, Japanese and Korean are put into each other directly. A
search already in the language picked is not translated.

The built-in zones' phrases come translated with the app
(`assets/search_phrases.json`): `.github/search_phrases/phrases.txt` lists
them (a test checks every zone's phrase is there), and the Search phrases
workflow translates the list into every language of the filter and
commits the file. Other translated phrases are kept in `cache/search_phrases.json` (language →
phrase → translation) and never asked again; one page's phrases go in
one request, 30 lines at most. A phrase no translator would take is
searched in English, and the log says how many were left so and why.

The search is asked in the language picked (`hl`, as YouTube spells it:
`fil`, `iw`), which YouTube ranks results by: on 2026-11-19, asked from
the same connection, `cristianismo` brought 1 Spanish video in 18 with
`hl=en` and 16 with `hl=es`; `Christentum` 3 German in 6 with `hl=en`,
14 in 16 with `hl=de`. `gl` changed little. Such a listing writes views
and dates its own way: views are read with any thousands separator, and
the exact count and publishing date of each kept video are taken from
its `/player` answer (the date is kept with heard answers). If the
website listing fails, yt-dlp searches in English.

It is also asked from the language's home country (`gl`) when no region
is picked.

A whole zone's words put into another language may find few videos or
none (`知识 科普` as `conoscenza Scienza popolare` found none uploaded in
the past month, seen on 2026-11-16). When its search runs out, the zone
goes on with its sub-categories' searches, one after another.

## Asking YouTube

- Each video is asked once per language check, at most 6 at a time.
- The apps are asked in turn until one tells by audio or captions:
  the visionOS app a quick start uses, then the TV app, then the website.
  Whichever told last is asked first from then on. When none tells, the
  answer kept is one with the video's title (its texts are read from it),
  and of those one YouTube would play. Live streams never have automatic
  captions or audio track languages, so they are always read by their
  texts; visionOS gives their title and description, while the TV app
  answers them with empty details (seen on 2026-11-14), which once made
  every live stream unreadable. After 20 videos in a
  row where the first app answered without captions and the others did
  not tell either, only one video in 20 still asks the others.
- Every signed-out `/player` request (language checks, quick starts,
  video facts) carries a visitor: the `VISITOR_DATA` and visitor cookies
  of YouTube's home page, opened once every 30 minutes (again after 5
  minutes if it failed), with the consent cookie (`SOCS`). When the page
  names none (seen on 2026-11-14: the page came back without readable
  `VISITOR_DATA`), requests go without a field mask, the
  `responseContext.visitorData` of the first answer becomes the visitor,
  and a request refused with `LOGIN_REQUIRED` is asked once more with it
  (verified the same day: such a visitor gets `OK`). Without one,
  YouTube answers most videos with `LOGIN_REQUIRED` "Sign in to confirm
  you're not a bot" (seen on 2026-11-14 for every app, on a home
  connection in Germany; with any visitor data every answer was `OK`).
- Answers are cut down with `X-Goog-FieldMask`; if the mask loses the
  video, whole answers are asked for.
- Explore's listing is already in the language picked, so its titles
  are shown as they are and `/player` is asked in English, for rule 3
  to compare. A caller whose listing is in English asks `/player` in the
  language picked and shows the title it gives.
- If YouTube leaves the video out of half of the last 20 answers (as when
  it asks this network to sign in), nothing is asked for 10 minutes.

## Channels

The videos heard of each channel are counted by language. A channel with
at least 3 heard videos, all in one language other than the one picked,
is left out without asking about its other videos. A channel heard in
two languages is never skipped. A channel is never let in this way:
each of its videos still has to be heard.

## Keeping answers

Answers told by audio or captions are kept in memory and in
`cache/heard_languages.json` (up to 20 000). Answers told by the video's
texts are kept in `cache/text_languages.json` for the language they were
asked in, for a week, then asked again, as YouTube may have made captions
by then. Answers that told nothing are kept in memory only, until Lumtub
is closed (up to 5 000 unheard answers in all). Guesses from titles kept
by earlier versions in `heard_languages.json` are not read back.

## When nothing is found

- Each search of a page (the zone's, then each wider one it goes on
  with) is checked on its own. One that, after 60 answers, has kept none
  and was told another language by audio, captions or the channel for
  at least three in four, stops, and the next search starts.
- After 240 videos with none kept (more after Keep looking), it stops
  and offers to look further.
- Every check writes one log line:
  `Language <name>: kept K of N videos in S s (V a second, first shown after F s), H told by audio or captions; <source language count>…`.
  That line is the first thing to read when the filter misbehaves.
