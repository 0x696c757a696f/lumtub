import re, sys, urllib.request, urllib.error
for h in sys.argv[1:]:
    req = urllib.request.Request('https://www.youtube.com/' + h, headers={'User-Agent': 'Mozilla/5.0', 'Accept-Language': 'en', 'Cookie': 'CONSENT=YES+1; SOCS=CAI'})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            page = r.read().decode('utf-8', 'replace')
            m = re.search(r'"externalId":"(UC[\w-]{22})"', page) or re.search(r'channel/(UC[\w-]{22})', page)
            t = re.search(r'<title>(.*?)</title>', page)
            print('RESULT', h, r.status, m.group(1) if m else None, t.group(1) if t else None)
    except urllib.error.HTTPError as e:
        print('RESULT', h, e.code)
    except Exception as e:
        print('RESULT', h, 'err', e)
