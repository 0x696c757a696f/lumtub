"""Checks the channel ids and @handles named by the block lists.

Every `UC...` id is looked up (title, @handle); every `@handle` is resolved to
its channel id. A record is `ok` when its id and handle lead to the same live
channel, `mismatch` when they lead to different channels, and `dead` when a
lookup finds no channel. Writes a Markdown table and a JSON file.

Usage: verify_ids.py LISTS_DIR OUT_PREFIX
"""

import json
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

CLIENT = {'clientName': 'WEB', 'clientVersion': '2.20251105.01.00', 'hl': 'en', 'gl': 'US'}
BASE = 'https://www.youtube.com/youtubei/v1/'
SPLIT = re.compile(r'(?<!\\)\|')


def post(endpoint, payload):
    body = json.dumps({'context': {'client': CLIENT}, **payload}).encode()
    request = urllib.request.Request(BASE + endpoint + '?prettyPrint=false', data=body,
                                     headers={'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0'})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=30) as reply:
                return json.load(reply)
        except urllib.error.HTTPError as error:
            if error.code in (400, 404):
                return {}
            time.sleep(4 * (attempt + 1))
        except Exception:  # noqa: BLE001
            time.sleep(4 * (attempt + 1))
    return None


def by_id(channel_id):
    answer = post('browse', {'browseId': channel_id})
    if answer is None:
        return 'error', '', ''
    meta = answer.get('metadata', {}).get('channelMetadataRenderer')
    if not meta:
        return 'dead', '', ''
    url = meta.get('vanityChannelUrl', '')
    handle = url.rsplit('/', 1)[-1] if '/@' in url else ''
    return 'ok', meta.get('title', ''), handle


def by_handle(handle):
    answer = post('navigation/resolve_url', {'url': f'https://www.youtube.com/{handle}'})
    if answer is None:
        return 'error', ''
    browse = answer.get('endpoint', {}).get('browseEndpoint', {}).get('browseId', '')
    return ('ok', browse) if browse.startswith('UC') else ('dead', '')


def main():
    lists = Path(sys.argv[1])
    out = sys.argv[2]
    rows = []
    ids, handles = {}, {}
    for path in sorted(lists.glob('*/*.txt')):
        for line in path.read_text(encoding='utf-8').split('\n'):
            parts = [p.strip() for p in SPLIT.split(line)]
            if line.startswith(':'):
                slug, items = parts[0][1:], parts[1:]
            elif line.strip() and not line.startswith(('!', '#')):
                slug, items = '', [line.split('#', 1)[0].strip()]
            else:
                continue
            uc = [i for i in items if re.fullmatch(r'UC[\w-]{22}', i)]
            at = [i for i in items if i.startswith('@')]
            names = [i[1:] for i in items if i[:1] in '=^']
            if not uc and not at:
                continue
            rows.append((path.parent.name + '/' + path.stem, slug or (at + uc)[0], uc, at, names))
            for i in uc:
                ids.setdefault(i, None)
            for h in at:
                handles.setdefault(h, None)
    for n, i in enumerate(ids):
        ids[i] = by_id(i)
        time.sleep(0.5)
    for h in handles:
        handles[h] = by_handle(h)
        time.sleep(0.5)
    result = []
    for lst, slug, uc, at, names in rows:
        notes, status = [], 'ok'
        found = set()
        for i in uc:
            state, title, handle = ids[i]
            if state == 'dead':
                notes.append(f'{i} dead')
                status = 'dead'
            elif state == 'error':
                notes.append(f'{i} lookup error')
                status = 'error' if status == 'ok' else status
            else:
                notes.append(f'{i} = "{title}" @{handle}')
                found.add(i)
        for h in at:
            state, browse = handles[h]
            if state == 'dead':
                notes.append(f'{h} dead')
                status = 'dead'
            elif state == 'error':
                notes.append(f'{h} lookup error')
                status = 'error' if status == 'ok' else status
            else:
                notes.append(f'{h} -> {browse}')
                found.add(browse)
        if len(found) > 1:
            status = 'mismatch' if status in ('ok', 'error') else status
        result.append({'list': lst, 'slug': slug, 'status': status, 'ids': uc, 'handles': at, 'names': names, 'notes': notes})
    Path(out + '.json').write_text(json.dumps(result, ensure_ascii=False, indent=1), encoding='utf-8')
    counts = {}
    for r in result:
        counts[r['status']] = counts.get(r['status'], 0) + 1
    md = [f'# Verified ids: {counts}', '', '| status | list/record | names | lookup |', '|---|---|---|---|']
    for r in sorted(result, key=lambda r: (r['status'] == 'ok', r['list'], r['slug'])):
        md.append(f"| {r['status']} | {r['list']}/{r['slug']} | {', '.join(r['names'][:2])} | {'; '.join(r['notes'])} |")
    Path(out + '.md').write_text('\n'.join(md) + '\n', encoding='utf-8')
    print(md[0])


if __name__ == '__main__':
    main()
