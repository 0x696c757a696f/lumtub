"""Adds channel ids and @handles to block list records that only have names.

For each record without a channel id, every name it gives (`=name` and
`^name`) is searched on YouTube as a channel. A channel whose title is that
name exactly (ignoring letter case) is a candidate. When the names of a
record lead to exactly one channel, its id and @handle are added to the
record; such a channel is already matched by the name, so nothing more is
blocked, but the record keeps working after the channel is renamed. When
they lead to several channels, nothing is added and the record is listed
for a person to look at. A channel that another record of the same list
already names is not added either: the two records are probably the same
channel, and the report lists them to merge by hand.

Usage: list_ids.py LISTS_DIR REPORT_FILE [--limit N]
"""

import json
import re
import sys
import time
import urllib.request
from pathlib import Path

SEARCH = 'https://www.youtube.com/youtubei/v1/search?prettyPrint=false'
CLIENT = {'clientName': 'WEB', 'clientVersion': '2.20251105.01.00', 'hl': 'en', 'gl': 'US'}
CHANNELS_ONLY = 'EgIQAg=='
SPLIT = re.compile(r'(?<!\\)\|')


def search(name):
    body = json.dumps({'context': {'client': CLIENT}, 'query': name, 'params': CHANNELS_ONLY}).encode()
    request = urllib.request.Request(SEARCH, data=body, headers={'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0'})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=30) as reply:
                return json.load(reply)
        except Exception as error:  # noqa: BLE001
            if attempt == 2:
                print(f'  search failed for {name!r}: {error}', file=sys.stderr)
                return None
            time.sleep(5 * (attempt + 1))


def subscribers(channel):
    """Subscriber count of a search result channel, 0 when not shown."""
    for key in ('videoCountText', 'subscriberCountText'):
        text = channel.get(key, {}).get('simpleText', '')
        found = re.match(r'([\d.,]+)\s*([KMB]?)\s+subscribers?', text)
        if found:
            number = float(found.group(1).replace(',', ''))
            return int(number * {'': 1, 'K': 1e3, 'M': 1e6, 'B': 1e9}[found.group(2)])
    return 0


def channels(answer):
    """(id, title, handle) of every channel in a search answer."""
    found = []

    def walk(node):
        if isinstance(node, dict):
            channel = node.get('channelRenderer')
            if isinstance(channel, dict) and channel.get('channelId'):
                title = channel.get('title', {}).get('simpleText', '')
                url = channel.get('navigationEndpoint', {}).get('browseEndpoint', {}).get('canonicalBaseUrl', '')
                handle = url[2:] if url.startswith('/@') else ''
                if not handle:
                    text = channel.get('subscriberCountText', {}).get('simpleText', '')
                    handle = text[1:] if text.startswith('@') else ''
                found.append((channel['channelId'], title, handle, subscribers(channel)))
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(answer)
    return found


def unescape(text):
    return text.replace('\\|', '|').replace('\\\\', '\\')


def main():
    lists = Path(sys.argv[1])
    report_path = Path(sys.argv[2])
    limit = int(sys.argv[sys.argv.index('--limit') + 1]) if '--limit' in sys.argv else None
    added, unclear, none, same, sized, asked = [], [], [], [], [], 0
    cache = {}
    for path in sorted(lists.glob('*/*.txt')):
        lines = path.read_text(encoding='utf-8').split('\n')
        list_id = next((l.split(':', 1)[1].strip() for l in lines if l.startswith('! id:')), path.stem)
        changed = False
        # Every channel id and @handle the list's records already name.
        taken = {}
        for line in lines:
            if line.startswith(':'):
                slug = SPLIT.split(line)[0].strip()[1:]
                for c in (p.strip() for p in SPLIT.split(line)[1:]):
                    if c.startswith('UC') or c.startswith('@'):
                        taken.setdefault(c.casefold(), slug)
            else:
                word = line.split('#', 1)[0].strip()
                if word.startswith('@') or re.fullmatch(r'UC[\w-]{22}', word):
                    taken.setdefault(word.casefold(), re.sub(r'[^a-z0-9]+', '-', word.lower()).strip('-'))
        for i, line in enumerate(lines):
            if not line.startswith(':'):
                continue
            parts = [p.strip() for p in SPLIT.split(line)]
            slug, conditions = parts[0][1:], [p for p in parts[1:] if p]
            if any(c.startswith('UC') for c in conditions):
                continue
            names = [unescape(c[1:]) for c in conditions if c[:1] in '=^']
            if not names:
                continue
            if limit is not None and asked >= limit:
                break
            ids = {}
            for name in names:
                if name not in cache:
                    asked += 1
                    answer = search(name)
                    cache[name] = channels(answer) if answer else None
                    time.sleep(0.7)
                for channel_id, title, handle, subs in cache[name] or []:
                    if title.casefold() == name.casefold():
                        ids.setdefault(channel_id, (handle, subs))
            key = f'{list_id}/{slug}'
            if len(ids) > 1:
                # One channel with far more subscribers than all the others of that name is the one meant.
                ranked = sorted(ids.items(), key=lambda item: -item[1][1])
                if ranked[0][1][1] >= 1000 and ranked[0][1][1] >= 5 * ranked[1][1][1]:
                    sized.append(f'{list_id}/{slug}: {ranked[0][0]} @{ranked[0][1][0]} ({ranked[0][1][1]} subscribers, next {ranked[1][1][1]})')
                    ids = {ranked[0][0]: ranked[0][1]}
            if len(ids) == 1:
                channel_id, (handle, _subs) = next(iter(ids.items()))
                other = taken.get(channel_id.casefold()) or (handle and taken.get(f'@{handle}'.casefold()))
                if other and other != slug:
                    same.append(f'{key}: {", ".join(names)} → {channel_id} @{handle}, already {list_id}/{other}')
                    continue
                taken[channel_id.casefold()] = slug
                if handle:
                    taken.setdefault(f'@{handle}'.casefold(), slug)
                extra = [channel_id]
                if handle and f'@{handle}'.casefold() not in (c.casefold() for c in conditions):
                    extra.append(f'@{handle}')
                lines[i] = ' | '.join([f':{slug}', *extra, *conditions])
                added.append(f'{key}: {" ".join(extra)} ({", ".join(names)})')
                changed = True
            elif ids:
                unclear.append(f'{key}: {", ".join(names)} → ' + ', '.join(f'{c} @{h[0]}' for c, h in ids.items()))
            else:
                none.append(f'{key}: {", ".join(names)}')
        if changed:
            path.write_text('\n'.join(lines), encoding='utf-8')
    report = [
        f'# Channel ids for the block lists',
        '',
        f'{asked} names searched. {len(added)} records got an id, {len(same)} are the same channel as another record, {len(unclear)} have several channels of that name, {len(none)} found no channel of that exact name.',
        '',
        '## Chosen by subscriber count (check these)',
        *[f'- {x}' for x in sized],
        '',
        '## Added',
        *[f'- {a}' for a in added],
        '',
        '## The same channel as another record (merge by hand)',
        *[f'- {s}' for s in same],
        '',
        '## Several channels of that name (left for a person)',
        *[f'- {u}' for u in unclear],
        '',
        '## No channel of that exact name',
        *[f'- {n}' for n in none],
    ]
    report_path.write_text('\n'.join(report) + '\n', encoding='utf-8')
    print(report[2])


if __name__ == '__main__':
    main()
