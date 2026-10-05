import hashlib,json,struct,time
from pathlib import Path
from http.server import BaseHTTPRequestHandler,HTTPServer
from urllib.parse import urlsplit,parse_qs
root=Path('/var/home/player/.local/share/marwanos/fdm-controller-test')
root.mkdir(parents=True,exist_ok=False)
name='fdm-controller-bench-fixture'
seed=root/'seed'/name
seed.mkdir(parents=True)
def encode(v):
    if isinstance(v,str):v=v.encode()
    if isinstance(v,bytes):return str(len(v)).encode()+b':'+v
    if isinstance(v,int):return b'i'+str(v).encode()+b'e'
    if isinstance(v,list):return b'l'+b''.join(map(encode,v))+b'e'
    return b'd'+b''.join(encode(k)+encode(v[k]) for k in sorted(v))+b'e'
files=[('alpha.bin',768*1024),('beta.bin',512*1024+713)]
data=[]
for filename,size in files:
    block=hashlib.sha256(('PC1 '+filename).encode()).digest()
    content=(block*((size+31)//32))[:size]
    (seed/filename).write_bytes(content)
    data.append(content)
all_data=b''.join(data);piece=64*1024
info={'name':name,'piece length':piece,'pieces':b''.join(hashlib.sha1(all_data[p:p+piece]).digest() for p in range(0,len(all_data),piece)),
      'files':[{'length':size,'path':[filename]} for filename,size in files]}
tracker='http://127.0.0.1:18973/announce'
torrent=encode({'announce':tracker,'info':info})
(root/'fixture.torrent').write_bytes(torrent)
download_torrent=Path('/var/home/player/Downloads/PC1-controller-test.torrent')
with download_torrent.open('xb') as f:f.write(torrent)
manifest={'name':name,'total':len(all_data),'info_hash':hashlib.sha1(encode(info)).hexdigest(),
          'files':[{'name':n,'size':s,'sha256':hashlib.sha256(d).hexdigest()} for (n,s),d in zip(files,data)]}
(root/'manifest.json').write_text(json.dumps(manifest,indent=2))
peers={}
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        values=parse_qs(urlsplit(self.path).query)
        port=int(values.get('port',['0'])[0])
        if not 0<port<65536:self.send_error(400);return
        if values.get('event')==['stopped']:peers.pop(port,None)
        else:peers[port]=(int(values.get('left',['0'])[0]),time.time())
        rows=[p for p,(left,at) in peers.items() if p!=port and time.time()-at<180]
        answer=encode({'interval':2,'min interval':1,'complete':sum(left==0 for left,at in peers.values()),
                       'incomplete':sum(left!=0 for left,at in peers.values()),
                       'peers':b''.join(bytes([127,0,0,1])+struct.pack('!H',p) for p in rows)})
        self.send_response(200);self.end_headers();self.wfile.write(answer)
        with (root/'tracker.log').open('a') as f:f.write(json.dumps({'port':port,'left':values.get('left'),'returned':rows})+'\n')
    def log_message(self,*args):pass
print('Fixture ready',flush=True)
HTTPServer(('127.0.0.1',18973),Handler).serve_forever()
