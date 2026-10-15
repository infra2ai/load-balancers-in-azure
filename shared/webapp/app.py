#!/usr/bin/env python3
"""Demo website for the "Load Balancers in Azure" series (Infra2AI).

Python standard library only, so a VM needs nothing but python3 (no apt, no
internet). The same file runs on every web server in every video; what makes
each server different comes from environment variables (/etc/lbdemo.env).

  /              who answered: name, colour, zone, region, and what the server saw
  /watch         live view: asks /api/whoami over and over and draws who answers
  /api/whoami    the same facts as JSON
  /healthz       health probe target (200 while the process runs)
  /api/egress    asks the Internet which public IP this server's outbound traffic uses
  /api/resolve   resolves a *.trafficmanager.net or *.azurefd.net name from this server
  /cache         a response that may be cached (for the Front Door caching demo)

A path that starts with this server's group (for example /red/page for a red
server) is accepted and the prefix is removed, so path-based routing works with
or without "override backend path". A prefix that belongs to another group gets
a 404 that says so, which makes a wrong routing rule visible.
"""
import html
import ipaddress
import json
import os
import socket
import ssl
import sys
import threading
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeout
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def env(name, default=''):
    return os.environ.get('LBDEMO_' + name, default)


CFG = {
    'name': env('NAME') or socket.gethostname(),
    'label': env('LABEL') or env('NAME') or socket.gethostname(),
    'group': env('GROUP').strip('/').lower(),
    'color': env('COLOR', '#34495e'),
    'country': env('COUNTRY'),
    'city': env('CITY'),
    'flag': env('FLAG'),
    'port': int(env('PORT', '80')),
    'tls_port': int(env('TLS_PORT', '443')),
    'tls_cert': env('TLS_CERT'),
    'tls_key': env('TLS_KEY'),
    # Recordings hide the viewer's own public address (see shown_client / shown_headers).
    'hide_client': env('HIDE_CLIENT') == '1',
}
CLIENT_HEADERS = ('x-forwarded-for', 'x-azure-clientip', 'x-azure-socketip', 'x-real-ip', 'forwarded', 'client-ip', 'true-client-ip')
GROUPS = ('red', 'green', 'blue')
STARTED = time.time()
SERVED = {'n': 0}
LOCK = threading.Lock()
META = {'region': '', 'zone': '', 'vmSize': '', 'privateIp': '', 'publicIp': ''}


def load_imds():
    """Region, zone and addresses from the Azure Instance Metadata Service."""
    url = 'http://169.254.169.254/metadata/instance?api-version=2021-02-01'
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    for _ in range(60):
        try:
            with opener.open(urllib.request.Request(url, headers={'Metadata': 'true'}), timeout=3) as r:
                d = json.load(r)
            ip = d['network']['interface'][0]['ipv4']['ipAddress'][0]
            META.update(region=d['compute'].get('location', '').lower(), zone=d['compute'].get('zone', ''),
                        vmSize=d['compute'].get('vmSize', ''), privateIp=ip.get('privateIpAddress', ''),
                        publicIp=ip.get('publicIpAddress', ''))
            return
        except Exception:
            time.sleep(5)


EGRESS = {'at': 0.0}
EGRESS_LOCK = threading.Lock()


def egress():
    """The public IP the Internet sees for this server's outbound traffic."""
    with EGRESS_LOCK:
        if time.time() - EGRESS['at'] < 2:
            return {'ok': False, 'error': 'one test every two seconds, try again'}
        EGRESS['at'] = time.time()
    error = 'no outbound connection'
    for url in ('https://api.ipify.org?format=json', 'https://ifconfig.me/ip'):
        try:
            with urllib.request.urlopen(url, timeout=4) as r:
                body = r.read(200).decode().strip()
            ip = json.loads(body)['ip'] if body.startswith('{') else body
            return {'ok': True, 'ip': ip, 'via': url.split('/')[2]}
        except Exception as e:
            if 'timed out' in str(e):
                error = 'no outbound connection (timed out)'
                break
            error = 'no outbound connection (%s)' % type(e).__name__
    return {'ok': False, 'error': error}


RESOLVE_SUFFIXES = ('.trafficmanager.net', '.azurefd.net', '.cloudapp.azure.com', '.azure-api.net')


def resolve(name):
    """Resolve a name from this server's point of view (for the Traffic Manager demos)."""
    name = (name or '').strip().lower().rstrip('.')
    if not name.endswith(RESOLVE_SUFFIXES) or len(name) > 120:
        return {'ok': False, 'error': 'only ' + ', '.join(RESOLVE_SUFFIXES) + ' names can be resolved here'}
    pool = ThreadPoolExecutor(max_workers=1)
    try:
        canonical, _, addresses = pool.submit(socket.gethostbyname_ex, name).result(timeout=6)
        return {'ok': True, 'name': name, 'canonical': canonical, 'addresses': sorted(addresses),
                'resolvedFrom': CFG['label'], 'region': META['region']}
    except FutureTimeout:
        return {'ok': False, 'name': name, 'error': 'the lookup took longer than 6 seconds'}
    except OSError as e:
        return {'ok': False, 'name': name, 'error': str(e)}
    finally:
        pool.shutdown(wait=False)


def esc(value):
    return html.escape(str(value), quote=True)


def shown_headers(h):
    """Request headers as shown on screen; with HIDE_CLIENT the headers that carry the viewer's address are hidden."""
    return {k: ('hidden' if CFG['hide_client'] and k.lower() in CLIENT_HEADERS else v) for k, v in h.headers.items()}


def shown_client(h):
    """The TCP peer. It is the viewer's own address when nothing sits in front of this server."""
    ip = h.client_address[0]
    if not CFG['hide_client'] or any(h.headers.get(c) for c in CLIENT_HEADERS):
        return ip
    try:
        return ip if ipaddress.ip_address(ip).is_private else 'hidden'
    except ValueError:
        return 'hidden'


STYLE = """
*{box-sizing:border-box}html,body{height:100%%;margin:0}
body{font-family:-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;color:#fff;
 background:%(color)s linear-gradient(rgba(0,0,0,.16),rgba(0,0,0,.42));display:flex;flex-direction:column}
main{flex:1;display:flex;flex-direction:column;justify-content:center;max-width:1180px;width:100%%;margin:0 auto;padding:32px 40px}
.top{letter-spacing:.14em;text-transform:uppercase;font-size:15px;opacity:.8}
h1{font-size:clamp(56px,9.5vw,132px);line-height:1;margin:.12em 0 .06em;font-weight:800;letter-spacing:-.02em}
.sub{font-size:clamp(22px,2.6vw,34px);opacity:.95;margin:0 0 22px}
.chips{display:flex;flex-wrap:wrap;gap:10px;margin-bottom:26px}
.chip{background:rgba(255,255,255,.18);border:1px solid rgba(255,255,255,.32);border-radius:999px;padding:7px 16px;font-size:20px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:12px}
.cell{background:rgba(0,0,0,.28);border-radius:14px;padding:12px 16px;min-width:0}
.cell b{display:block;font-size:13px;letter-spacing:.1em;text-transform:uppercase;opacity:.75;margin-bottom:3px;font-weight:600}
.cell span{font-size:21px;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;overflow-wrap:anywhere}
details{margin-top:16px}summary{cursor:pointer;font-size:17px;opacity:.9}
table{border-collapse:collapse;margin-top:10px;font-size:16px;width:100%%}td{padding:4px 12px 4px 0;vertical-align:top;font-family:ui-monospace,Menlo,Consolas,monospace;overflow-wrap:anywhere}
td:first-child{opacity:.75;white-space:nowrap}
.links{margin-top:20px;display:flex;gap:22px;flex-wrap:wrap;font-size:19px}
a{color:#fff}button,input{font:inherit;font-size:17px;border-radius:8px;border:1px solid rgba(255,255,255,.4);background:rgba(0,0,0,.3);color:#fff;padding:6px 14px}
button{cursor:pointer}#tool{margin-top:10px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:19px;min-height:1.4em}
"""


def page(h, ctx):
    headers = ''.join('<tr><td>%s</td><td>%s</td></tr>' % (esc(k), esc(v)) for k, v in shown_headers(h).items())
    where = CFG['country'] + (' \u00b7 ' + CFG['city'] if CFG['city'] and CFG['city'] != CFG['country'] else '')
    if CFG['group']:
        sub = '%s pool' % CFG['group'].capitalize() + (' \u00b7 ' + where if where else '')
    else:
        sub = where or 'Hello from this web server'
    chips = [c for c in (
        'Zone ' + META['zone'] if META['zone'] else 'No zone', META['region'], META['privateIp'] or ctx['destination'], META['vmSize']) if c]
    cells = [
        ('Client IP (TCP peer)', ctx['client']),
        ('X-Forwarded-For', ctx['xff'] or '(none)'),
        ('Destination IP', ctx['destination']),
        ('Host header', ctx['host']),
        ('Path as received', ctx['path']),
        ('Requests served', ctx['served']),
        ('Protocol', ctx['scheme'] + ' ' + ctx['version']),
        ('Time (UTC)', ctx['time']),
    ]
    flag = (CFG['flag'] + ' ') if CFG['flag'] else ''
    return ('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            '<title>%s</title><style>%s</style></head><body><main>'
            '<div class="top">Load Balancers in Azure &middot; demo site</div>'
            '<h1>%s%s</h1><p class="sub">%s</p>'
            '<div class="chips">%s</div>'
            '<div class="grid">%s</div>'
            '<details><summary>All request headers</summary><table>%s</table></details>'
            '<details><summary>Server tools</summary>'
            '<p><button id="egress">What public IP does this server use for outbound?</button></p>'
            '<p><input id="name" size="42" placeholder="myprofile.trafficmanager.net"> <button id="resolve">Resolve from here</button></p>'
            '<div id="tool"></div></details>'
            '<div class="links"><a href="watch">Live view</a><a href="api/whoami">JSON</a><a href="healthz">Health</a></div>'
            '</main><script>'
            'const out=document.getElementById("tool");'
            'document.getElementById("egress").onclick=async()=>{out.textContent="testing...";'
            'const j=await (await fetch("api/egress",{cache:"no-store"})).json();'
            'out.textContent=j.ok?"Outbound IP: "+j.ip:"Outbound: "+j.error};'
            'document.getElementById("resolve").onclick=async()=>{const n=document.getElementById("name").value;'
            'const j=await (await fetch("api/resolve?name="+encodeURIComponent(n),{cache:"no-store"})).json();'
            'out.textContent=j.ok?j.name+" -> "+j.addresses.join(", "):j.error};'
            '</script></body></html>') % (
        esc(CFG['label']), STYLE % {'color': CFG['color']}, esc(flag), esc(CFG['label']), esc(sub),
        ''.join('<span class="chip">%s</span>' % esc(c) for c in chips),
        ''.join('<div class="cell"><b>%s</b><span>%s</span></div>' % (esc(k), esc(v)) for k, v in cells), headers)


WATCH = """<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Live view</title><style>
*{box-sizing:border-box}body{margin:0;background:#0b1220;color:#e6edf7;font-family:-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}
.wrap{max-width:1500px;margin:0 auto;padding:26px 36px}
header{display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:12px}
h1{font-size:34px;margin:0}h2{font-size:15px;letter-spacing:.12em;text-transform:uppercase;color:#8fa3bf;margin:26px 0 10px;font-weight:600}
.ctl{display:flex;gap:10px;align-items:center;color:#8fa3bf;font-size:17px}
select,button{font:inherit;font-size:17px;border-radius:8px;border:1px solid #2b3a55;background:#14203a;color:#e6edf7;padding:6px 14px;cursor:pointer}
#cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(270px,1fr));gap:14px}
.card{border-radius:16px;padding:16px 18px;color:#fff;position:relative;overflow:hidden;min-height:132px}
.card .n{font-size:30px;font-weight:800}.card .c{font-size:17px;opacity:.9}.card .big{font-size:46px;font-weight:800;position:absolute;right:18px;top:10px}
.bar{height:8px;border-radius:4px;background:rgba(255,255,255,.28);margin-top:12px}.bar i{display:block;height:100%;border-radius:4px;background:#fff}
#strip{display:flex;flex-wrap:wrap;gap:5px}.sq{width:34px;height:34px;border-radius:7px;display:flex;align-items:center;justify-content:center;font-size:14px;color:#fff;font-weight:700}
.sq.bad{background:#3b0d12;border:2px solid #ff4d5e;color:#ff8a95}.sq.new{outline:3px solid #fff}
#stats{display:flex;gap:34px;flex-wrap:wrap}.stat b{display:block;font-size:34px}.stat span{color:#8fa3bf;font-size:15px;letter-spacing:.08em;text-transform:uppercase}
#log{list-style:none;margin:0;padding:0;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:18px}
#log li{padding:5px 0;border-bottom:1px solid #1b2943}#log .bad{color:#ff8a95}#log .good{color:#7ee2a8}#log .sw{color:#ffd479}
</style></head><body><div class="wrap">
<header><h1>Live view <small id="where" style="font-size:18px;color:#8fa3bf;font-weight:400"></small></h1>
<div class="ctl">Ask every <select id="every"><option value="250">0.25 s</option><option value="500">0.5 s</option><option value="1000" selected>1 s</option><option value="2000">2 s</option></select>
<button id="toggle">Pause</button><button id="reset">Reset</button></div></header>
<h2>Who answered</h2><div id="cards"></div>
<h2>Last 60 responses (newest on the right)</h2><div id="strip"></div>
<h2>Numbers</h2><div id="stats">
<div class="stat"><b id="sTotal">0</b><span>requests</span></div><div class="stat"><b id="sFail">0</b><span>failed</span></div>
<div class="stat"><b id="sGap">0.0 s</b><span>longest outage</span></div><div class="stat"><b id="sMs">-</b><span>last response</span></div></div>
<h2>Events</h2><ul id="log"></ul></div>
<script>
const q=new URLSearchParams(location.search);
let every=+(q.get('every')||1000),limit=+(q.get('timeout')||4000),running=q.get('autostart')!=='0';
const S={servers:new Map(),strip:[],total:0,fail:0,lastOk:null,lastServer:null,lastLabel:null,failSince:null,maxGap:0};
const $=id=>document.getElementById(id);
$('every').value=String(every);$('where').textContent=location.host;
function hue(s){let h=0;for(const c of s)h=(h*31+c.charCodeAt(0))%360;return 'hsl('+h+',55%,38%)'}
function log(cls,t){const li=document.createElement('li');li.className=cls;li.textContent=new Date().toLocaleTimeString([], {hour12:false})+'  '+t;$('log').prepend(li);while($('log').children.length>40)$('log').lastChild.remove()}
function draw(){
  const tot=[...S.servers.values()].reduce((a,s)=>a+s.n,0)||1;
  $('cards').innerHTML=[...S.servers.values()].sort((a,b)=>a.name<b.name?-1:1).map(s=>
    '<div class="card" style="background:'+s.color+'"><div class="big">'+(s.flag||'')+'</div><div class="n">'+s.label+'</div><div class="c">'+s.n+' responses &middot; '+Math.round(100*s.n/tot)+'%</div>'+
    '<div class="c">'+[s.zone?'zone '+s.zone:'',s.region,s.privateIp].filter(Boolean).join(' &middot; ')+'</div><div class="bar"><i style="width:'+(100*s.n/tot)+'%"></i></div></div>').join('');
  $('strip').innerHTML=S.strip.map((r,i)=>r.ok?'<div class="sq'+(i===S.strip.length-1?' new':'')+'" style="background:'+r.color+'" title="'+r.label+'">'+(r.flag||r.label.slice(-1))+'</div>':
    '<div class="sq bad'+(i===S.strip.length-1?' new':'')+'" title="'+r.why+'">&times;</div>').join('');
  $('sTotal').textContent=S.total;$('sFail').textContent=S.fail;$('sGap').textContent=S.maxGap.toFixed(1)+' s';
}
function record(r){
  S.total++;S.strip.push(r);if(S.strip.length>60)S.strip.shift();
  if(r.ok){
    let s=S.servers.get(r.name);if(!s){s=Object.assign({n:0},r);S.servers.set(r.name,s);log('good','first answer from '+r.label)}
    s.n++;$('sMs').textContent=r.ms+' ms';
    if(S.failSince!==null){const gap=(r.t-S.lastOk)/1000;S.maxGap=Math.max(S.maxGap,gap);
      log(r.name!==S.lastServer?'sw':'good','answers again after '+gap.toFixed(1)+' s without a response'+(r.name!==S.lastServer?': '+S.lastLabel+' -> '+r.label:''));S.failSince=null}
    else if(S.lastServer&&r.name!==S.lastServer&&q.get('switch')==='1')log('sw','answer moved: '+S.lastLabel+' -> '+r.label);
    S.lastOk=r.t;S.lastServer=r.name;S.lastLabel=r.label;
  }else{
    S.fail++;if(S.failSince===null){S.failSince=r.t;log('bad','no good answer ('+r.why+')')}
  }
  draw();
}
async function tick(){
  const t0=performance.now();let r;
  try{
    const c=new AbortController(),to=setTimeout(()=>c.abort(),limit);
    const res=await fetch('api/whoami?_='+Date.now()+Math.random().toString(36).slice(2),{cache:'no-store',signal:c.signal});
    clearTimeout(to);
    if(!res.ok)r={ok:false,why:'HTTP '+res.status};
    else{const j=await res.json();r={ok:true,name:j.server,label:j.label,color:j.color||hue(j.server),flag:j.flag,zone:j.zone,region:j.region,privateIp:j.privateIp}}
  }catch(e){r={ok:false,why:e.name==='AbortError'?'no answer within '+limit/1000+' s':'connection failed'}}
  r.ms=Math.round(performance.now()-t0);r.t=Date.now();record(r);
}
async function loop(){while(true){const t=performance.now();if(running)await tick();await new Promise(ok=>setTimeout(ok,Math.max(50,every-(performance.now()-t))))}}
$('every').onchange=e=>every=+e.target.value;
$('toggle').onclick=()=>{running=!running;$('toggle').textContent=running?'Pause':'Resume'};
$('reset').onclick=()=>{S.servers.clear();S.strip=[];S.total=S.fail=0;S.maxGap=0;S.lastOk=S.lastServer=S.lastLabel=S.failSince=null;$('log').innerHTML='';$('sMs').textContent='-';draw()};
$('toggle').textContent=running?'Pause':'Resume';loop();
</script></body></html>"""


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    server_version = 'lbdemo'
    sys_version = ''
    timeout = 15  # a stalled or half-open connection must not hold a thread forever

    def version_string(self):
        return self.server_version

    def log_message(self, fmt, *args):
        sys.stdout.write('%s %s xff=%s host=%s "%s" %s\n' % (
            time.strftime('%H:%M:%S'), self.client_address[0], self.headers.get('X-Forwarded-For', '-'),
            self.headers.get('Host', '-'), self.requestline, args[1] if len(args) > 1 else '-'))
        sys.stdout.flush()

    def send_body(self, code, body, ctype, cache='no-store'):
        data = body.encode('utf-8') if isinstance(body, str) else body
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', cache)
        self.send_header('X-Served-By', CFG['name'])
        if META['region']:
            self.send_header('X-Served-Region', META['region'])
        # One request per connection: a load balancer then picks a backend for every request.
        self.send_header('Connection', 'close')
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(data)
        self.close_connection = True

    def context(self, path):
        with LOCK:
            SERVED['n'] += 1
            served = SERVED['n']
        tls = isinstance(self.connection, ssl.SSLSocket)
        xff = self.headers.get('X-Forwarded-For', '')
        return {
            'client': shown_client(self), 'xff': 'hidden' if xff and CFG['hide_client'] else xff,
            'destination': self.connection.getsockname()[0], 'host': self.headers.get('Host', ''),
            'path': self.path, 'served': served, 'scheme': 'https' if tls else 'http',
            'version': self.request_version, 'time': time.strftime('%H:%M:%S', time.gmtime()),
        }

    def facts(self, ctx):
        return {
            'server': CFG['name'], 'label': CFG['label'], 'group': CFG['group'], 'color': CFG['color'],
            'country': CFG['country'], 'city': CFG['city'], 'flag': CFG['flag'],
            'region': META['region'], 'zone': META['zone'], 'vmSize': META['vmSize'],
            'privateIp': META['privateIp'], 'publicIp': META['publicIp'],
            'clientIp': ctx['client'], 'forwardedFor': ctx['xff'], 'destinationIp': ctx['destination'],
            'host': ctx['host'], 'path': ctx['path'], 'scheme': ctx['scheme'], 'httpVersion': ctx['version'],
            'requestsServed': ctx['served'], 'uptimeSeconds': int(time.time() - STARTED),
            'headers': shown_headers(self),
        }

    def route(self):
        parsed = urllib.parse.urlsplit(self.path)
        path = parsed.path or '/'
        first = path.strip('/').split('/')[0].lower()
        if first in GROUPS:
            if first != CFG['group']:
                return self.send_body(404, self.not_found(
                    'This is %s. There is no /%s here, so a routing rule sent this request to the wrong pool.' % (CFG['label'], first)),
                    'text/html; charset=utf-8')
            path = '/' + '/'.join(path.strip('/').split('/')[1:])
        query = urllib.parse.parse_qs(parsed.query)
        if path == '/healthz':  # probes are not counted as requests served
            return self.send_body(200, 'ok\n', 'text/plain; charset=utf-8')
        ctx = self.context(path)
        if path in ('/', '/index.html'):
            return self.send_body(200, page(self, ctx), 'text/html; charset=utf-8')
        if path == '/watch':
            return self.send_body(200, WATCH, 'text/html; charset=utf-8')
        if path == '/api/whoami':
            return self.send_body(200, json.dumps(self.facts(ctx), indent=2) + '\n', 'application/json')
        if path == '/api/egress':
            return self.send_body(200, json.dumps(egress()) + '\n', 'application/json')
        if path == '/api/resolve':
            return self.send_body(200, json.dumps(resolve((query.get('name') or [''])[0])) + '\n', 'application/json')
        if path == '/cache':
            body = json.dumps({'server': CFG['name'], 'generatedAt': time.strftime('%H:%M:%S', time.gmtime()) + ' UTC',
                               'note': 'This response may be cached for 60 seconds.'}) + '\n'
            return self.send_body(200, body, 'application/json', cache='public, max-age=60')
        return self.send_body(404, self.not_found('This is %s and it has no page at %s.' % (CFG['label'], path)), 'text/html; charset=utf-8')

    def not_found(self, message):
        return ('<!doctype html><meta charset="utf-8"><title>404</title><body style="font:26px sans-serif;margin:12vh 10vw;'
                'background:#222;color:#fff"><h1 style="font-size:84px;margin:0">404</h1><p>%s</p></body>' % esc(message))

    do_GET = do_HEAD = route

    def do_POST(self):
        self.send_body(405, 'GET and HEAD only\n', 'text/plain; charset=utf-8')

    do_PUT = do_DELETE = do_PATCH = do_POST


class DemoServer(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 128
    tls = None

    def get_request(self):
        sock, addr = self.socket.accept()
        if self.tls:
            # The handshake happens in the request's own thread, so one stalled client cannot block accept().
            sock = self.tls.wrap_socket(sock, server_side=True, do_handshake_on_connect=False)
        return sock, addr


def serve(port, tls=None):
    server = DemoServer(('0.0.0.0', port), Handler)
    if tls:
        server.tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        server.tls.load_cert_chain(*tls)
    server.serve_forever()


if __name__ == '__main__':
    threading.Thread(target=load_imds, daemon=True).start()
    if CFG['tls_cert'] and os.path.exists(CFG['tls_cert']):
        threading.Thread(target=serve, args=(CFG['tls_port'], (CFG['tls_cert'], CFG['tls_key'])), daemon=True).start()
    print('lbdemo %s listening on %d' % (CFG['name'], CFG['port']), flush=True)
    serve(CFG['port'])
