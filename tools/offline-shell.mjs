import { readdir, readFile, writeFile } from 'node:fs/promises';
import { join, relative } from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
const root = new URL('../build/web/',import.meta.url);
async function walk(dir) {
  const entries = await readdir(dir,{withFileTypes:true});
  const files=[];
  for(const e of entries) { const path=join(dir,e.name); if(e.isDirectory()) files.push(...await walk(path)); else files.push(path); }
  return files;
}
const base=fileURLToPath(root);
const files=(await walk(base)).filter(p=>!p.endsWith('.map') && !p.endsWith('sw.js'));
const digest=createHash('sha256');
for(const file of [...files].sort())digest.update(relative(base,file)).update(await readFile(file));
const version=digest.digest('hex').slice(0,12);
const urls=files.map(p=>'./'+relative(base,p).replaceAll('\\','/'));
const worker=`const CACHE='manxia-shell-${version}';
const ASSETS=${JSON.stringify(urls)};
self.addEventListener('install',e=>e.waitUntil(caches.open(CACHE).then(c=>c.addAll(ASSETS)).then(()=>self.skipWaiting())));
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('manxia-shell-')&&k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',e=>{const u=new URL(e.request.url);if(e.request.method!=='GET'||u.origin!==self.location.origin||u.pathname.includes('/api/')||u.pathname.includes('/offline-data/'))return;const scope=new URL(self.registration.scope);const key=e.request.mode==='navigate'&&u.pathname===scope.pathname?new URL('./index.html',scope).href:e.request;e.respondWith(caches.match(key,{cacheName:CACHE}).then(hit=>hit||fetch(e.request)));});`;
await writeFile(new URL('sw.js',root),worker);
console.log(`Offline app shell ${version}: ${urls.length} files. First visit downloads assets; personal comics use a separate cache.`);
