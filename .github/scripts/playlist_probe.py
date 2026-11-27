import json, re, urllib.request
UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36'
def call(endpoint, body, gl=None):
    client = {'clientName': 'WEB', 'clientVersion': '2.20260708.00.00', 'hl': 'en', 'timeZone': 'UTC', 'utcOffsetMinutes': 0}
    if gl: client['gl'] = gl
    data = json.dumps({'context': {'client': client}, **body}).encode()
    req = urllib.request.Request(f'https://www.youtube.com/youtubei/v1/{endpoint}?prettyPrint=false', data=data, headers={
        'User-Agent': UA, 'Accept-Language': 'en', 'Content-Type': 'application/json', 'Origin': 'https://www.youtube.com',
        'X-YouTube-Client-Name': '1', 'X-YouTube-Client-Version': '2.20260708.00.00', 'Cookie': 'CONSENT=YES+cb; SOCS=CAI'})
    return json.load(urllib.request.urlopen(req, timeout=30))
pid = 'PLuqpGDexlvGyhwQ4ZpHD17jrcOOWSXSpA'
r = call('browse', {'browseId': 'VL' + pid})
items = r['contents']['twoColumnBrowseResultsRenderer']['tabs'][0]['tabRenderer']['content']['sectionListRenderer']['contents'][0]['itemSectionRenderer']['contents']
print('ALERTS', json.dumps(r.get('alerts'))[:2000])
hdr = json.dumps(r.get('header'))
print('STATS', re.findall(r'"content": "([^"]*(?:video|view|Updated)[^"]*)"', hdr)[:6])
for it in items:
    m = it.get('lockupViewModel')
    if not m: continue
    vid = m.get('contentId')
    title = m['metadata']['lockupMetadataViewModel']['title']['content']
    rows = m['metadata']['lockupMetadataViewModel'].get('metadata', {}).get('contentMetadataViewModel', {}).get('metadataRows', [])
    print('VIDEO', vid, '|', title, '|', [p.get('text', {}).get('content') for r in rows for p in r.get('metadataParts', [])])
for gl in ['IT', 'CN', 'HK', 'TW', 'DE']:
    r2 = call('browse', {'browseId': 'VL' + pid}, gl=gl)
    n = json.dumps(r2).count('"lockupViewModel"')
    print('gl', gl, 'lockups', n)
