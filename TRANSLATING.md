# Translating Lumtub

Lumtub's interface is written in simplified Chinese and translated into
other languages. Every translation is one JSON file in
[`assets/l10n`](assets/l10n), named by its language tag: `de.json`,
`ja.json`, `pt-BR.json`, `zh-Hant.json`. No code needs to change to add a
language.

## How a file looks

Each key is the simplified-Chinese text as it appears in the code. Its value
is the translation. Start from [`en.json`](assets/l10n/en.json), which has
every string with its English text:

```json
{
  "冷门宝藏": "Hidden gems",
  "无法加载聊天回放：{0}": "Couldn't load chat replay: {0}"
}
```

To translate into German, copy `en.json` to `de.json` and replace each
English value with German:

```json
{
  "冷门宝藏": "Versteckte Perlen",
  "无法加载聊天回放：{0}": "Chat-Wiedergabe konnte nicht geladen werden: {0}"
}
```

- Never change a key. A key that is not in `en.json` is an error.
- Keep every placeholder (`{0}`, `{1}` …). Their order may change.
- Keep line breaks (`\n`) where the English has them.
- Leave a value empty (`""`) or remove the line if you have not translated
  it yet. Missing strings are shown in English.
- Product and format names stay as they are: YouTube, Lumtub, yt-dlp,
  FFmpeg, libmpv, H.264, VP9, AV1, SponsorBlock, DeArrow.
- The log is always English and is not translated.

## When a language appears in Lumtub

A language is offered in Settings › Appearance › Language once it translates
at least 90% of the strings, so the interface never shows a patchwork of
languages. "Follow system" picks it when Windows uses that language.

The build reports how complete each translation is (look for
`Translation <tag>:` in the test output of the Build workflow).

## Sending a translation

1. Fork the repository and add or edit your file in `assets/l10n`.
2. Open a pull request. The Build workflow checks that every key exists and
   every placeholder is kept.
3. After it is merged, the next release includes it.

New strings appear in `en.json` as Lumtub grows. Until a translation has
them they are shown in English, and a translation that falls below 90% is
not offered again until it catches up.
