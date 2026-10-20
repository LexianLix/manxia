import http from 'node:http';
import { readFile, mkdir, writeFile, readdir, stat, unlink } from 'node:fs/promises';
import { resolve, extname, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { Readable, Transform } from 'node:stream';
import { pipeline } from 'node:stream/promises';

const root = resolve(fileURLToPath(new URL('../', import.meta.url)));
const webRoot = resolve(root, 'build/web');
const cacheRoot = resolve(root, '.cache/images');
const types = { '.html':'text/html; charset=utf-8', '.js':'text/javascript', '.mjs':'text/javascript', '.json':'application/json', '.wasm':'application/wasm', '.png':'image/png', '.jpg':'image/jpeg', '.woff2':'font/woff2', '.ttf':'font/ttf', '.otf':'font/otf', '.bin':'application/octet-stream' };

export function imageAllowed(input) {
  try {
    const url = new URL(input);
    return url.protocol === 'https:' && !url.username && !url.password && !url.port &&
      /(^|\.)cdndm5\.com$/.test(url.hostname);
  } catch { return false; }
}
export function sourceAllowed(path) {
  return typeof path === 'string' && path.startsWith('/') && !path.startsWith('//') &&
    !/[\\\r\n]/.test(path) && !path.includes('..') &&
    /^\/(?:$|search(?:\?|\/)|manhua-[a-zA-Z0-9-]+\/(?:\?.*)?$|m\d+\/(?:\?.*)?$)/.test(path);
}

async function upstream(url, referer = 'https://m.dm5.com/', timeout = 18000, options = {}) {
  const response = await fetch(url, {
    ...options, redirect: 'manual', signal: AbortSignal.timeout(timeout),
    headers: { 'User-Agent':'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/130.0 Mobile Safari/537.36', Referer: referer, Connection:'close', ...options.headers }
  });
  if (!response.ok) throw Object.assign(new Error(`动漫屋返回 HTTP ${response.status}`), {status:response.status});
  return response;
}

export function createServer({load = upstream, dav = fetch} = {}) {
  const profiles = new Map();
  async function jsonBody(req) {
    if (!req.headers['content-type']?.startsWith('application/json')) throw new Error('JSON required');
    const origin = req.headers.origin;
    if (origin && new URL(origin).host !== req.headers.host) throw new Error('Foreign origin');
    let body = '';
    for await (const chunk of req) { body += chunk; if (body.length > 8*1024*1024) throw new Error('Payload too large'); }
    return JSON.parse(body);
  }
  const sourceCache = new Map();
  const pending = new Map();
  async function sourcePage(path) {
    const cached = sourceCache.get(path);
    if (cached && Date.now() - cached.time < 120000) return cached.html;
    if (pending.has(path)) return pending.get(path);
    const task = (async () => {
      for (let attempt = 0; attempt < 2; attempt++) {
        try {
          const response = await load(`https://m.dm5.com${path}`, 'https://m.dm5.com/', 10000);
          const html = await response.text();
          sourceCache.set(path, {html,time:Date.now()});
          if (sourceCache.size > 64) sourceCache.delete(sourceCache.keys().next().value);
          return html;
        } catch (error) {
          if (attempt === 1 || [401,403,429].includes(error.status)) throw error;
        }
      }
    })();
    pending.set(path, task);
    try { return await task; } finally { pending.delete(path); }
  }
  return http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://localhost');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    try {
      if (url.pathname === '/api/health') {
        res.setHeader('Content-Type','application/json');
        return res.end(JSON.stringify({ ok:true, app:'manxia', source:'dm5' }));
      }
      if(url.pathname === '/api/cache') {
        const clear=req.method==='POST' && (await jsonBody(req)).action==='clear';
        const files=await readdir(cacheRoot,{withFileTypes:true}).catch(()=>[]);
        let bytes=0,count=0;
        for(const f of files.filter(f=>f.isFile() && /^[a-f0-9]{64}$/.test(f.name))) {
          const file=resolve(cacheRoot,f.name);
          if(clear) await unlink(file);
          else {bytes+=(await stat(file)).size;count++;}
        }
        res.setHeader('Content-Type','application/json');
        return res.end(JSON.stringify({bytes,count,cleared:clear}));
      }
      if (url.pathname === '/api/profiles' && req.method === 'POST') {
        const list = await jsonBody(req);
        if (!Array.isArray(list) || list.length > 50) throw new Error('Invalid profiles');
        for (const p of list) {
          const base = new URL(p.baseUrl);
          if (!/^[a-z0-9_-]{1,40}$/.test(p.id) || base.protocol !== 'https:' || base.username || base.password) throw new Error('Invalid source');
          const hosts = p.imageHosts ?? [base.hostname];
          if (!Array.isArray(hosts) || hosts.some(h => !/^[a-zA-Z0-9.-]+$/.test(h))) throw new Error('Invalid image host');
          profiles.set(p.id,{base,hosts});
        }
        res.setHeader('Content-Type','application/json');
        return res.end('{"ok":true}');
      }
      if (url.pathname === '/api/custom') {
        const profile = profiles.get(url.searchParams.get('id'));
        const target = new URL(url.searchParams.get('url'));
        if (!profile || target.origin !== profile.base.origin || target.username || target.password) { res.writeHead(400); return res.end('Unsupported source'); }
        const page = await load(target.toString(),profile.base.toString());
        res.setHeader('Content-Type','text/html; charset=utf-8');
        return res.end(await page.text());
      }
      if (url.pathname === '/api/webdav' && req.method === 'POST') {
        const request = await jsonBody(req);
        const target = new URL(request.url);
        if (target.protocol !== 'https:' || target.username || target.password || !['GET','PUT'].includes(request.method)) throw new Error('Invalid WebDAV request');
        const headers = {};
        for (const [key,value] of Object.entries(request.headers ?? {})) {
          if (['authorization','content-type','if-match','if-none-match'].includes(key.toLowerCase())) headers[key] = String(value);
        }
        const response = await dav(target,{method:request.method,headers,redirect:'manual',
          body:request.method === 'PUT' ? request.body : undefined,signal:AbortSignal.timeout(30000)});
        const body = await response.text();
        if (body.length > 8*1024*1024) throw new Error('WebDAV snapshot too large');
        res.setHeader('Cache-Control','no-store');
        res.setHeader('Content-Type','application/json');
        return res.end(JSON.stringify({status:response.status,headers:{...(response.headers.has('etag') ? {etag:response.headers.get('etag')} : {})},body}));
      }
      if(url.pathname === '/api/webdav-binary' && req.method==='POST') {
        const origin=req.headers.origin;
        if(origin && new URL(origin).host!==req.headers.host)throw new Error('Foreign origin');
        if(!['application/zip','application/octet-stream'].includes(req.headers['content-type']?.split(';')[0]))throw new Error('Binary body required');
        const target=new URL(url.searchParams.get('url'));
        const method=url.searchParams.get('method');
        if(target.protocol!=='https:' || target.username || target.password || !['GET','PUT','HEAD'].includes(method))throw new Error('Invalid WebDAV request');
        const headers={'Content-Type':'application/zip'};
        for(const key of ['authorization','if-match','if-none-match'])if(req.headers[key])headers[key]=req.headers[key];
        const limit=512*1024*1024;
        if(Number(req.headers['content-length'])>limit)throw new Error('Archive too large');
        async function* chunks() {let size=0;for await(const chunk of req){size+=chunk.length;if(size>limit)throw new Error('Archive too large');yield chunk;}}
        const response=await dav(target,{method,headers,redirect:'manual',signal:AbortSignal.timeout(300000),
          ...(method==='PUT'?{body:chunks(),duplex:'half'}:{})});
        if(Number(response.headers.get('content-length'))>limit)throw new Error('Archive too large');
        res.statusCode=response.status;res.setHeader('Content-Type','application/zip');res.setHeader('Cache-Control','no-store');
        if(response.headers.has('etag'))res.setHeader('ETag',response.headers.get('etag'));
        if(method==='HEAD')return res.end();
        let size=0;
        if(response.body) {
          const capped=new Transform({transform(chunk,encoding,done){size+=chunk.length;done(size>limit?new Error('Archive too large'):null,chunk);}});
          await pipeline(Readable.fromWeb(response.body),capped,res);
          return;
        }
        return res.end();
      }
      if (url.pathname === '/api/source') {
        const path = url.searchParams.get('path');
        if (!sourceAllowed(path)) { res.writeHead(400); return res.end('Unsupported source path'); }
        const html = await sourcePage(path);
        res.setHeader('Content-Type','text/html; charset=utf-8');
        res.setHeader('Cache-Control','no-store');
        return res.end(html);
      }
      if(url.pathname === '/api/list' && req.method === 'POST') {
        const fields=await jsonBody(req);
        const body=new URLSearchParams({action:'getclasscomics',iscopyright:'false'});
        for(const key of ['pageindex','pagesize','usergroup','categoryid','tagid','status','sort','pay','areaid']) {
          if(!/^-?\d{1,6}$/.test(String(fields[key])))throw new Error('Invalid catalog parameter');
          body.set(key,String(fields[key]));
        }
        const result=await load('https://m.dm5.com/dm5.ashx','https://m.dm5.com/',18000,{method:'POST',body:body.toString(),headers:{'Content-Type':'application/x-www-form-urlencoded'}});
        res.setHeader('Content-Type','application/json; charset=utf-8');
        return res.end(await result.text());
      }
      if (url.pathname === '/api/image') {
        const target = url.searchParams.get('url');
        const parsed = new URL(target);
        const custom = [...profiles.values()].find(p => p.hosts.includes(parsed.hostname));
        if (!imageAllowed(target) && !(custom && parsed.protocol === 'https:' && !parsed.username && !parsed.password)) { res.writeHead(400); return res.end('Unsupported image host'); }
        const key = createHash('sha256').update(target).digest('hex');
        const file = resolve(cacheRoot, key);
        let bytes;
        try { bytes = await readFile(file); }
        catch {
          const response = await load(target,custom?.base.toString());
          if (!response.headers.get('content-type')?.startsWith('image/')) throw new Error('图片地址未返回图片');
          bytes = Buffer.from(await response.arrayBuffer());
          if (bytes.length > 20 * 1024 * 1024) throw new Error('图片超过预览大小限制');
          await mkdir(cacheRoot, {recursive:true});
          await writeFile(file,bytes);
        }
        res.setHeader('Content-Type', extname(new URL(target).pathname).toLowerCase() === '.png' ? 'image/png' : 'image/jpeg');
        res.setHeader('Cache-Control','private, max-age=3600');
        return res.end(bytes);
      }
      const candidate = resolve(webRoot, '.' + decodeURIComponent(url.pathname));
      if (candidate !== webRoot && !candidate.startsWith(webRoot + sep)) { res.writeHead(403); return res.end(); }
      const file = url.pathname === '/' ? resolve(webRoot,'index.html') : candidate;
      const bytes = await readFile(file);
      res.setHeader('Content-Type', types[extname(file)] || 'application/octet-stream');
      res.setHeader('Cache-Control','no-cache');
      res.end(bytes);
    } catch (error) {
      if(res.headersSent){res.destroy();return;}
      res.writeHead(error.code === 'ENOENT' ? 404 : 502, {'Content-Type':'text/plain; charset=utf-8'});
      res.end(error.code === 'ENOENT' ? '请先运行 flutter build web。' : `来源暂不可用：${error.message}`);
    }
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const port = Number(process.env.PORT || 4173);
  createServer().listen(port,'127.0.0.1',()=>console.log(`漫匣预览：http://127.0.0.1:${port}`));
}
