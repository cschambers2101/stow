import sys, shutil, urllib.parse
from gi.repository import Gio, GLib
out = sys.argv[1]
bus = Gio.bus_get_sync(Gio.BusType.SESSION)
loop = GLib.MainLoop(); res = {}
token = 'claudeshot'
sender = bus.get_unique_name()[1:].replace('.', '_')
path = f'/org/freedesktop/portal/desktop/request/{sender}/{token}'
def on(conn, s, p, i, sig, params):
    code, r = params.unpack(); res['code'] = code; res['uri'] = r.get('uri'); loop.quit()
bus.signal_subscribe('org.freedesktop.portal.Desktop', 'org.freedesktop.portal.Request', 'Response', path, None, 0, on)
bus.call_sync('org.freedesktop.portal.Desktop', '/org/freedesktop/portal/desktop', 'org.freedesktop.portal.Screenshot', 'Screenshot',
    GLib.Variant('(sa{sv})', ('', {'handle_token': GLib.Variant('s', token), 'interactive': GLib.Variant('b', False)})), None, 0, -1, None)
GLib.timeout_add_seconds(60, loop.quit); loop.run()
if res.get('code') == 0:
    src = urllib.parse.unquote(urllib.parse.urlparse(res['uri']).path); shutil.move(src, out); print('ok', out)
else: print('failed', res); sys.exit(1)
