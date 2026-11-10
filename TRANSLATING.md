# Translating Lumtub

Lumtub's interface is written in English and translated into other
languages. Every translation is one JSON file in
[`assets/l10n`](assets/l10n), named by its language tag: `de.json`,
`ja.json`, `pt-BR.json`, `zh-Hans.json`, `zh-Hant.json`. No code needs to
change to add a language.

## How a file looks

Each key is the English text as it appears in the code. Its value is the
translation. [`zh-Hans.json`](assets/l10n/zh-Hans.json) has every string,
so it is the list of keys to start from:

```json
{
  "Hidden gems": "冷门宝藏",
  "Couldn't load chat replay: {0}": "无法加载聊天回放：{0}"
}
```

To translate into German, copy `zh-Hans.json` to `de.json` and replace each
value with German:

```json
{
  "Hidden gems": "Versteckte Perlen",
  "Couldn't load chat replay: {0}": "Chat-Wiedergabe konnte nicht geladen werden: {0}"
}
```

- Never change a key. A key that is not in `zh-Hans.json` is an error.
- Keep every placeholder (`{0}`, `{1}` …). Their order may change.
- Keep line breaks (`\n`) where the English has them.
- Leave a value empty (`""`) or remove the line if you have not translated
  it yet. Missing strings are shown in English; in traditional Chinese
  (`zh-Hant`, `zh-HK`) they are shown in simplified Chinese first.
- Product and format names stay as they are: YouTube, Lumtub, yt-dlp,
  FFmpeg, libmpv, H.264, VP9, AV1, SponsorBlock, DeArrow.
- The log is always English and is not translated.

## When a language appears in Lumtub

A language is offered in Settings › Appearance › Language once it translates
at least 90% of the strings, so the interface never shows a patchwork of
languages. "Follow system" picks it when your system uses that language.

The build reports how complete each translation is (look for
`Translation <tag>:` in the test output of the Build workflow).

## Sending a translation

The easiest way is on Weblate: open
https://hosted.weblate.org/engage/lumtub/, sign in, pick your language (or
start a new one) and translate in the browser. Weblate sends the work back as
a pull request.

To work with the files directly instead:

1. Fork the repository and add or edit your file in `assets/l10n`.
2. Open a pull request. The Build workflow checks that every key exists and
   every placeholder is kept.
3. After it is merged, the next release includes it.

New strings appear in the code and in `zh-Hans.json` as Lumtub grows. Until a translation has
them they are shown in English, and a translation that falls below 90% is
not offered again until it catches up.
