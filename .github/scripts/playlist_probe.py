import json, sys, urllib.request

UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36'

def call(endpoint, body):
    data = json.dumps({'context': {'client': {'clientName': 'WEB', 'clientVersion': '2.20260708.00.00', 'hl': 'en', 'timeZone': 'UTC', 'utcOffsetMinutes': 0}}, **body}).encode()
    req = urllib.request.Request(f'https://www.youtube.com/youtubei/v1/{endpoint}?prettyPrint=false', data=data, headers={
        'User-Agent': UA, 'Accept-Language': 'en', 'Content-Type': 'application/json', 'Origin': 'https://www.youtube.com',
        'X-YouTube-Client-Name': '1', 'X-YouTube-Client-Version': '2.20260708.00.00', 'Cookie': 'CONSENT=YES+cb; SOCS=CAI'})
    return json.load(urllib.request.urlopen(req, timeout=30))

def paths(node, path, out, depth=0):
    if depth > 14:
        return
    if isinstance(node, dict):
        for k, v in node.items():
            if k in ('trackingParams', 'loggingDirectives', 'accessibility', 'thumbnail', 'image'):
                continue
            p = f'{path}.{k}'
            if k.endswith('Renderer') or k.endswith('ViewModel') or k in ('contents', 'items', 'tabs', 'continuationItems'):
                out[p] = out.get(p, 0) + 1
            paths(v, p, out, depth + 1)
    elif isinstance(node, list):
        for v in node:
            paths(v, path + '[]', out, depth + 1)

ids = sys.argv[1:]
search = call('search', {'query': 'catholic playlist', 'params': 'EgIQAw=='})
text = json.dumps(search)
import re
ids += [i for i in dict.fromkeys(re.findall(r'"(PL[0-9A-Za-z_-]{16,40})"', text)) if '_' not in i[:12]][:1]
for pid in ids:
    print('=' * 20, pid)
    r = call('browse', {'browseId': 'VL' + pid})
    out = {}
    paths(r, '', out)
    for p, n in out.items():
        if 'header' in p or 'sidebar' in p or 'frameworkUpdates' in p or 'topbar' in p:
            continue
        print(n, p)
    with open(f'probe-{pid}.json', 'w') as f:
        json.dump(r, f)
    sec = r['contents']['twoColumnBrowseResultsRenderer']['tabs'][0]['tabRenderer']['content']['sectionListRenderer']['contents']
    items = sec[0]['itemSectionRenderer']['contents']
    print('ALL', json.dumps(r)[:60000])
    print('TAB', {k: v for k, v in r['contents']['twoColumnBrowseResultsRenderer']['tabs'][0]['tabRenderer'].items() if k != 'content'})
