# Block list format

Each list is one file, `<category>/<id>.txt`. `lumtub-lists check lists` reads them all as the app will; CI runs it on every pull request and prints what changed. A removed record's key goes in `retired.txt` and is never used again.

Anyone can suggest a channel: open a pull request that edits these files, or an issue with the "Block list entry" form. Every entry needs a public source. [README.md](README.md) explains both ways step by step.

## Categories

| tier | categories | new install |
|---|---|---|
| P0 safety | `financial-scams`, `malware-phishing`, `medical-fraud` | on, with the default action |
| P1 quality | `ai-slop`, `clickbait-reuploads`, `religion` | off; turned on in Settings |
| P2 viewpoint | `state-media`, `influence-operations`, `new-age`, `misinformation-farms`, `deceptive-marketing` | off; turned on in Settings |

Only a list of P0 categories may be `default: on`. P0 lists take no `topic` and only confirmed records. A confirmed record needs a `source`: its own on P0 lists, its own or the list's elsewhere. A removed record whose key is not added to `retired.txt` fails the check.

## Syntax

UTF-8 without a BOM. LF line ends. [template.txt](template.txt) is a filled-in example to copy. These kinds of line:

```
! key: value                      list header (only before the first record)
@handle  # comment                one channel by its @handle (the comment is optional)
UCxxxxxxxxxxxxxxxxxxxxxx  # ...   one channel by its channel id
:slug | cond | cond | ...         one channel with several conditions
    key: value                    attribute of the record above (indented)
# comment                         ignored; blank lines are ignored too
```

A channel on a line of its own gets its handle or id, in lowercase with other signs as `-`, as its slug, and the comment after it as its note. Use the `:slug` form when a channel is known by several names or handles: all the ways to recognise one channel belong on one line.

### Header keys

| key | required | meaning |
|---|---|---|
| `id` | yes | Stable list id, `[a-z0-9-]+`. Must match the file name. Never changes. |
| `name` | yes | English name shown in settings. |
| `name.<lang>` | no | Translated name, such as `name.zh-Hans`. |
| `category` | yes | One or more of the categories above, comma separated. Describes the source, not what is done. |
| `action` | yes | What happens to a match by default: `hide`, `quiet`, `demote` or `label` (see Actions). |
| `default` | yes | `on` or `off`: whether the list is on for a new install. CI checks it against the tier: only P0 lists may be `on`. |
| `topic` | no, repeatable | Words a search names this list's subject by, such as `法轮功`, `Falun Gong`, `Russia Today` (see Searches). Not allowed on P0 lists. |
| `note` | no | One line shown in settings, such as "Funded by the US Agency for Global Media with editorial independence in law". |
| `source` | no, repeatable | URL of the evidence for the list as a whole. |

### Records

- A `:slug` record starts with its stable id, `[a-z0-9-]+`. It must be unique within the file. The full key is `list-id/slug`, such as `falun-gong-media/epoch-times`. The key never changes. A renamed channel keeps its slug, and a removed slug is never reused.
- The conditions follow, separated by `|`. A channel matches if any condition matches; their order does not matter.
- Spaces around each field are dropped. Spaces inside a name are kept.
- Each condition starts with a fixed prefix:

| prefix | matches | example |
|---|---|---|
| `UC` | the channel id, exactly (24 characters, case kept) | `UCxxxxxxxxxxxxxxxxxxxxxx` |
| `@` | the @handle, ignoring letter case | `@EpochTimes` |
| `=` | the whole channel name, ignoring letter case | `=The Epoch Times` |
| `^` | the name start, see Name start | `^RT` |

- Escapes inside a name: `\|` for a literal `|`, and `\\` for `\`. Any other `\` is an error.
- A record with no conditions, an unknown prefix, a malformed channel id or a duplicate slug fails the CI check.

### Record attributes (indented `key: value` lines under a record)

| key | meaning |
|---|---|
| `status` | `confirmed` (default) or `unproven`. An unproven record starts unticked, until the user ticks it. P0 lists take confirmed records only. |
| `source` | Evidence URL (repeatable). |
| `reviewed` | `YYYY-MM-DD` of the last check. |
| `note` | Why this channel belongs to the list, if not obvious. |

### Name start (`^`)

`^word` matches the name `word` itself, or `word` followed by a space or a punctuation sign. So `RT Documentary`, `CGTN Français` and `新唐人 NTD` match, but `新天地美食` and `RTL` do not.

A CJK name that really appears with suffixes gets its channel id or `=` forms instead.

### Example

```
! id: falun-gong-media
! name: Falun Gong media
! name.zh-Hans: 法轮功媒体
! category: religion
! action: hide
! default: off
! topic: 法轮功
! topic: Falun Gong
! note: Media the Falun Gong founded or runs
! source: https://example.org/evidence

:epoch-times | UCxxxxxxxxxxxxxxxxxxxxxx | @EpochTimes | =The Epoch Times | =大纪元 | =大紀元
    source: https://example.org/epoch-times
    reviewed: 2026-11-08
:ntd | @NTDTelevision | ^新唐人 | ^NTD
```

## Actions

| action | home feed, explore, related | search | when opened directly |
|---|---|---|---|
| `hide` | left out | left out, except 3.1 | plays |
| `quiet` | left out | shown | plays |
| `demote` | shown, ranked last; never in the home feed's "recommended" share | shown, ranked lower | plays |
| `label` | shown, with the list's name on the card | shown, labelled | plays, labelled |

The user's words for these in settings: 屏蔽 (hide), 不推荐 (quiet), 降低 (demote), 标注 (label).

## Searches

A search for a channel's exact name, handle or id shows it. A search containing one of a list's `topic` words shows that list's matches, labelled and ranked after other channels, even when its action is `hide`.

## Evidence

A record is `confirmed` only with a `source` of the kind below. Anything weaker is `unproven`, which ships unticked.

| category | evidence |
|---|---|
| `financial-scams` | regulator warning list (SEC, CFTC, FCA, ASIC, 证监会 etc.), court ruling, or the scam itself on record (archived video with the fake giveaway wallet) |
| `malware-phishing` | a link in the channel's descriptions that a public feed (URLhaus, PhishTank, VirusTotal) flags, archived |
| `medical-fraud` | FDA or FTC warning letter, a health ministry or court ruling naming the channel's owner or product |
| `influence-operations` | a platform or government takedown report naming the channel (Google TAG bulletin, Meta threat report, EEAS, etc.). No report: `label` at most, `unproven` |
| `state-media` | ownership or editorial control on record (State Media Monitor, the outlet's own filings) |
| `religion` | documented coercion, isolation or exploitation from courts, governments or reputable reporting (ICSA indicators as the written reason, not as a score) |
| `misinformation-farms` | three or more false ratings from IFCN signatory fact-checkers within a year, plus monetisation |
| `deceptive-marketing` | a regulator ruling or reporting that shows the hidden recruitment or sale |
| `clickbait-reuploads` | the original video it copies, linked |
| `new-age` | the channel's own claims (miracle healing, channelling, paid "activations"), archived |
