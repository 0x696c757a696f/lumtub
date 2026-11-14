# Explore: language filter

What the Language filter on the Explore page promises, and how it keeps
that promise. Code: `lib/video_languages.dart`, `lib/youtube_player_probe.dart`,
`lib/app/explore_controller.dart`, `spoken_language` in
`native/lumtub_core/src/innertube.rs`. Tests: `test/video_languages_test.dart`,
`test/explore_filters_test.dart`.

## Promise

With a language picked, Explore shows only videos **spoken** in that
language. A video whose spoken language cannot be confirmed is not shown.
There is no switch to loosen this.

## What counts as confirmation

From the video's own `/youtubei/v1/player` answer, in this order:

1. **The original audio track.** On a video with audio in several
   languages, the track whose `xtags` say `acont=original` (else whose
   name says "original"). A dub is never taken for the original, even
   when YouTube makes it the default.
2. **The automatic captions** (`captionTracks[].kind == "asr"`). YouTube
   makes them from the audio, so their language is the spoken one. They
   are listed once, in the spoken language; translations are not in
   `captionTracks`.

What never decides, because uploaders and YouTube translate it:

- the title or description, in any language they are asked in;
- the listed title (search is asked in English; YouTube may show a
  translation there);
- the region or the search words.

## Finding candidates

The zone's search words are put into the language picked before
searching, so that the search finds videos in it to begin with:

- words in another script (Chinese, Japanese…) always;
- for a language other than English, English words too
  (`哲学 philosophy lecture` → `filosofia lezione di filosofia`), except
  names and words titles write the same everywhere (`Minecraft`, `Plato`,
  `lofi`, `vlog`, see `keptSearchWords`);
- a zone of the person's own is searched as they wrote it.

The search is also asked from the language's home country (`gl`) when no
region is picked.

## Asking YouTube

- Each video is asked once per language check, at most 6 at a time.
- The apps are asked in turn until one tells by audio or captions:
  the visionOS app a quick start uses, then the TV app, then the website.
  Whichever told last is asked first from then on.
- The visitor id YouTube gives in its first answer is sent back with
  every later request, as a browser does with its cookie.
- Answers are cut down with `X-Goog-FieldMask`; if the mask loses the
  video, whole answers are asked for.
- Texts are asked in the language picked, so the title shown is the one
  a viewer in that language would see.
- If YouTube leaves the video out of half of the last 20 answers (as when
  it asks this network to sign in), nothing is asked for 10 minutes.

## Keeping answers

Only answers told by audio or captions are kept, in memory and in
`cache/heard_languages.json` (up to 20 000). An answer without either is
asked again next time. Guesses from titles kept by earlier versions are
not read back.

## When YouTube does not tell

- After 40 answers none of which told by audio or captions, the check
  stops and the page says YouTube is not giving this app the audio tracks
  or captions right now, with a Retry button. It does not fall back to
  titles.
- After 240 videos with none kept (more after Keep looking), it stops
  and offers to look further.
- Every check writes one log line:
  `Language <name>: kept K of N videos, H told by audio or captions; <source language count>…`.
  That line is the first thing to read when the filter misbehaves.
