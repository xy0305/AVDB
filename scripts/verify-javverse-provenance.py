"""Offline raw-public-text provenance verification; never fetches/evals remote scripts."""
import argparse, hashlib, json, pathlib, re
ROOT = pathlib.Path(__file__).resolve().parents[1]
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def document(path):
    wrapper = json.loads(path.read_text())
    return json.JSONDecoder().raw_decode(wrapper['data']['text'])[0]
def verify(evidence):
    snapshot_path = ROOT/'AVDB/Resources/JavVerseSnapshot.json'
    snapshot = json.loads(snapshot_path.read_text())
    boards = {b['id']: b for b in snapshot['boards']}
    proof = {'mode': snapshot['mode'], 'snapshotSHA256': sha(snapshot_path),
             'preparedAt': snapshot['preparedAt'], 'networkUsed': False,
             'meaning': '520 rows equal saved public text/SSR literals; not a signed timestamp or live API validation',
             'boards': [], 'evidenceSHA256': {}}
    for name in ['home','daily','weekly','monthly','actresses','series']:
        path = evidence/f'{name}-capture.json'
        proof['evidenceSHA256'][path.name] = sha(path)
        doc = document(path)
        if name == 'home':
            flight = ''
            for script in doc['staticFlight']:
                literal = json.JSONDecoder().raw_decode(script[len('self.__next_f.push('):])[0]
                flight += literal[1]
            marker = re.search(r'"slides":', flight)
            assert marker, 'No homepage slides'
            slides = json.JSONDecoder().raw_decode(flight[marker.end():])[0]
            featured = boards['featured']
            expected = [(i+1, s['name'], f"https://javverse.com/actress/{s['id']}") for i,s in enumerate(slides)]
            assert [(e['rank'],e['label'],e['sourceURL']) for e in featured['entries']] == expected
            recent = []
            for link in doc['links']:
                match = re.match(r'^([A-Z0-9]+)\n(-[A-Z0-9]+)\n',link['text'])
                if match: recent.append((''.join(match.groups()),'https://javverse.com'+link['href']))
            assert [(e['code'],e['sourceURL']) for e in boards['recent']['entries']] == recent
            assert len(expected) == 8 and len(recent) == 12
            for key in ['featured','recent']:
                assert boards[key]['capturedAt'] == doc['capturedAt']
                assert boards[key]['sourceURL'] == doc['url']
                proof['boards'].append({'id':key,'verifiedRows':len(boards[key]['entries']), 'capturedAt':doc['capturedAt']})
            continue
        board = boards[name]
        movie = name in ['daily','weekly','monthly']
        text = doc['text']
        start = text.index('随便抽一部')+len('随便抽一部') if movie else text.index('\n01\n')
        text = text[start:].split('JAV Verse ·')[0]
        markers = list(re.finditer(r'(?m)^(0[1-9]|[1-9][0-9]|100)\n', text))
        assert len(markers) == len(board['entries']) == 100
        for i, marker in enumerate(markers):
            rank = int(marker[1]); entry = board['entries'][i]
            assert rank == entry['rank'] == i+1
            body = text[marker.end():markers[i+1].start() if i+1<len(markers) else len(text)].strip()
            if movie:
                match = re.match(r'([A-Z0-9]+)\n(-[A-Z0-9]+)', body)
                assert match and entry['code'] == entry['label'] == ''.join(match.groups())
            else: assert entry['label'] == body.split('\n')[0]
            prefix = '/work/' if movie else '/actress/' if name == 'actresses' else '/series/'
            link = next((l['href'] for l in doc['links'] if re.match(r'^0*'+str(rank)+r'\n',l['text']) and l['href'].startswith(prefix)),None)
            assert entry['sourceURL'] == ('https://javverse.com'+link if link else doc['url'])
        assert board['capturedAt'] == doc['capturedAt'] and board['sourceURL'] == doc['url']
        proof['boards'].append({'id':name,'verifiedRows':100,'capturedAt':doc['capturedAt']})
    proof['verifiedRows'] = sum(b['verifiedRows'] for b in proof['boards'])
    assert proof['verifiedRows'] == 520
    return proof
if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence-dir',required=True,type=pathlib.Path)
    parser.add_argument('--output',type=pathlib.Path)
    args = parser.parse_args()
    output = json.dumps(verify(args.evidence_dir),ensure_ascii=False,indent=2)+'\n'
    if args.output: args.output.write_text(output)
    print(output)
