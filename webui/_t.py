import urllib.request, json
urls = [
    'http://127.0.0.1:5000/api/visual',
    'http://127.0.0.1:5000/api/power',
    'http://127.0.0.1:5000/api/disk',
    'http://127.0.0.1:5000/api/network',
    'http://127.0.0.1:5000/api/backup/list',
]
for u in urls:
    try:
        with urllib.request.urlopen(u, timeout=25) as r:
            data = json.loads(r.read().decode('utf-8'))
            print(u.split('/')[-1], '=>', 'ok=' + str(data.get('ok')),
                  '| keys:', ','.join(list(data.keys())[:6]))
    except Exception as e:
        print(u.split('/')[-1], '=> ERROR:', str(e)[:120])
