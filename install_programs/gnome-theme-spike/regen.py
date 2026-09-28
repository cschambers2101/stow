import json, os, re, subprocess, sys
H=os.path.expanduser('~')
c=json.load(open(f'{H}/.cache/DankMaterialShell/dms-colors.json')); d=c['colors']['dark']; d16=c['dank16']
def rgb(h): return tuple(int(h[i:i+2],16) for i in (1,3,5))
def mix(a,b,t): return '#%02x%02x%02x'%tuple(round(x+(y-x)*t) for x,y in zip(rgb(a),rgb(b)))
r=dict(d); r['primary_container_hover']=mix(d['primary_container'],'#ffffff',0.2)
r['surface_rgba92']='rgba(%d,%d,%d,0.92)'%rgb(d['surface'])
t=open(os.path.join(os.path.dirname(__file__),'gnome-shell.css.tmpl')).read()
t=re.sub(r'\{\{(\w+)\}\}', lambda m: r[m.group(1)], t)
open(f'{H}/.themes/S6C-Dank/gnome-shell/gnome-shell.css','w').write(t)
L=["[Palette]","Name=S6C Dank","Primary=true","UseSystemAccent=false",""]
for mode,sec in (('light','Light'),('dark','Dark')):
    m=c['colors'][mode]; L+=[f"[{sec}]",f"Background={m['surface']}",f"Foreground={m['on_surface']}",f"Cursor={m['primary']}"]+[f"Color{i}={d16[f'color{i}'][mode]}" for i in range(16)]+[""]
open(f'{H}/.local/share/org.gnome.Ptyxis/palettes/S6C-Dank.palette','w').write("\n".join(L))
g=lambda *a: subprocess.run(['gsettings','set',*a],check=True)
D='org.gnome.shell.extensions.dash-to-dock'
g(D,'background-color',d['surface_container_highest']); g(D,'custom-theme-running-dots-color',d['primary_container']); g(D,'custom-theme-running-dots-border-color',d['primary_container'])
U='org.gnome.shell.extensions.user-theme'; g(U,'name','Yaru-dark'); subprocess.run(['sleep','1']); g(U,'name','S6C-Dank')
print('source',d['source_color'],'primary',d['primary'],'container',d['primary_container'],'surface',d['surface'],'highest',d['surface_container_highest'])
