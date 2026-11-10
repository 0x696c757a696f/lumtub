"""Prints the real name and @handle of each channel id given, as YouTube shows them.

Used to check channel ids from elsewhere before they go into a block list.

Usage: channel_names.py ID [ID ...]
"""

import json
import sys
import time
import urllib.request

BROWSE = 'https://www.youtube.com/youtubei/v1/browse?prettyPrint=false'
CLIENT = {'clientName': 'WEB', 'clientVersion': '2.20251105.01.00', 'hl': 'en', 'gl': 'US'}


def channel(channel_id):
    body = json.dumps({'context': {'client': CLIENT}, 'browseId': channel_id}).encode()
    request = urllib.request.Request(BROWSE, data=body, headers={'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0'})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=30) as reply:
                answer = json.load(reply)
            meta = answer.get('metadata', {}).get('channelMetadataRenderer', {})
            if not meta:
                alert = json.dumps(answer.get('alerts', ''), ensure_ascii=False)
                return None, None, 'not found ' + alert[:120]
            url = meta.get('vanityChannelUrl', '')
            handle = url.rsplit('/', 1)[-1] if '/@' in url else ''
            return meta.get('title', ''), handle, ''
        except urllib.error.HTTPError as error:
            if error.code in (400, 404):
                return None, None, f'not found (HTTP {error.code})'
            if attempt == 2:
                return None, None, f'failed: {error}'
        except Exception as error:  # noqa: BLE001
            if attempt == 2:
                return None, None, f'failed: {error}'
        time.sleep(5 * (attempt + 1))


def main():
    print('| id | name | handle | note |')
    print('|---|---|---|---|')
    for channel_id in sys.argv[1:]:
        title, handle, note = channel(channel_id)
        print(f'| {channel_id} | {title or ""} | {handle or ""} | {note} |', flush=True)
        time.sleep(0.7)


if __name__ == '__main__':
    main()
