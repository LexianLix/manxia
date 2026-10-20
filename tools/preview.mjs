import http from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { resolve, extname, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const root = resolve(fileURLToPath(new URL('../', import.meta.url)));
const webRoot = resolve(root, 'build/web');
const cacheRoot = resolve(root, '.cache/images');
const types = { '.html':'text/html; charset=utf-8', '.js':'text/javascript', '.json':'application/json', '.wasm':'application/wasm', '.png':'image/png', '.jpg':'image/jpeg', '.woff2':'font/woff2', '.ttf':'font/ttf', '.otf':'font/otf', '.bin':'application/octet-stream' };

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

async function upstream(url, referer = 'https://m.dm5.com/', timeout = 18000) {
  const response = await fetch(url, {
    redirect: 'manual', signal: AbortSignal.timeout(timeout),
    headers: { 'User-Agent':'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/130.0 Mobile Safari/537.36', Referer: referer, Connection:'close' }
  });
  if (!response.ok) throw Object.assign(new Error(`动漫屋返回 HTTP ${response.status}`), {status:response.status});
  return response;
}

export function createServer({load = upstream} = {}) {
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
      if (url.pathname === '/api/source') {
        const path = url.searchParams.get('path');
        if (!sourceAllowed(path)) { res.writeHead(400); return res.end('Unsupported source path'); }
        const html = await sourcePage(path);
        res.setHeader('Content-Type','text/html; charset=utf-8');
        res.setHeader('Cache-Control','no-store');
        return res.end(html);
      }
      if (url.pathname === '/api/image') {
        const target = url.searchParams.get('url');
        if (!imageAllowed(target)) { res.writeHead(400); return res.end('Unsupported image host'); }
        const key = createHash('sha256').update(target).digest('hex');
        const file = resolve(cacheRoot, key);
        let bytes;
        try { bytes = await readFile(file); }
        catch {
          const response = await load(target);
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
      res.writeHead(error.code === 'ENOENT' ? 404 : 502, {'Content-Type':'text/plain; charset=utf-8'});
      res.end(error.code === 'ENOENT' ? '请先运行 flutter build web。' : `来源暂不可用：${error.message}`);
    }
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const port = Number(process.env.PORT || 4173);
  createServer().listen(port,'127.0.0.1',()=>console.log(`漫匣预览：http://127.0.0.1:${port}`));
}
