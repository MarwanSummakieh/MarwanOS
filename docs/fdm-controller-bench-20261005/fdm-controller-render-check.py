import hashlib,json,time
from Xlib import X,display
from PIL import Image
c=display.Display(':0'); pid_atom=c.intern_atom('_NET_WM_PID')
candidates=[]
for w in c.screen().root.query_tree().children:
 if w.get_wm_name()=='Free Download Manager - Controller' and w.get_attributes().map_state==X.IsViewable:
  p=w.get_full_property(pid_atom,X.AnyPropertyType)
  if p is not None and p.value:
   cmd=open('/proc/'+str(p.value[0])+'/cmdline','rb').read()
   if b'fdm-controller-20261005' in cmd:candidates.append(w)
if len(candidates)!=1:raise RuntimeError('Expected one controller window, got '+str(len(candidates)))
w=candidates[0];g=w.get_geometry();data=w.get_image(0,0,g.width,g.height,X.ZPixmap,0xffffffff)
Image.frombytes('RGB',(g.width,g.height),data.data,'raw','BGRX').save('/var/tmp/fdm-controller-fixed.png')
scale=min(g.width/1280,g.height/800);ox=int((g.width-1280*scale)/2);oy=int((g.height-800*scale)/2)
x=ox+int(40*scale);y=oy+int(123*scale);width=int(245*scale);height=int(60*scale)
samples=[]
for _ in range(120):
 px=w.get_image(x,y,width,height,X.ZPixmap,0xffffffff)
 samples.append(hashlib.sha256(px.data).hexdigest());time.sleep(.05)
result={'window':w.id,'width':g.width,'height':g.height,'samples':len(samples),'unique_button_frames':len(set(samples))}
open('/var/tmp/fdm-controller-render-results.json','w').write(json.dumps(result,indent=2))
print(json.dumps(result))