import {readFile, writeFile, readdir, mkdir} from 'node:fs/promises';
import {resolve, dirname, basename} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {Script} from 'node:vm';
import {checkCharacter,characterZip} from './character-package.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export function validatePlugin(p) {
  const fail = s => { throw new Error(s); };
  if (Buffer.byteLength(JSON.stringify(p)) > 128*1024) fail('Manifest exceeds 128 KB');
  if (p.description !== undefined && (typeof p.description !== 'string' || p.description.length > 1200)) fail('Invalid description');
  if (![1, 2].includes(p.apiVersion)) fail('Expected apiVersion: 1 or 2');
  if (typeof p.id !== 'string' || !/^[a-z][a-z0-9_-]{0,31}\.[a-z0-9][a-z0-9_.-]{0,63}$/.test(p.id)) fail('Invalid author.name id');
  if (typeof p.version !== 'string' || !/^\d+\.\d+\.\d+$/.test(p.version)) fail('Expected x.y.z version');
  for (const key of ['name', 'author', 'license']) if (typeof p[key] !== 'string' || !p[key].trim() || p[key].length > 100) fail(`Invalid ${key}`);
  if(p.locales!=null) {
    if(typeof p.locales!=='object'||Array.isArray(p.locales))fail('Invalid plugin locales');
    for(const [tag,fields] of Object.entries(p.locales)) {
      if(!['en','zh_TW'].includes(tag)||!fields||typeof fields!=='object'||Array.isArray(fields))fail('Invalid plugin locale');
      for(const [key,text] of Object.entries(fields))if(!['name','description'].includes(key)||typeof text!=='string'||!text.trim()||text.length>(key==='name'?100:1200))fail('Invalid localized plugin text');
    }
  }
  const c = p.contributes;
  if (!c || Array.isArray(c) || !Object.keys(c).length || Object.keys(c).some(k => !['theme','reader','navigation','source','character'].includes(k))) fail('Unsupported contribution');
  if (p.apiVersion === 2 && (!c.source || Object.keys(c).length !== 1 || p.settings?.length)) {
    fail('API 2 currently supports only script sources');
  }
  const settings = new Map();
  for (const s of p.settings ?? []) {
    if (!/^[a-z][a-zA-Z0-9_]{0,39}$/.test(s.key) || settings.has(s.key)) fail('Invalid/duplicate setting');
    const valid = s.type === 'boolean' ? typeof s.default === 'boolean'
      : s.type === 'number' ? Number.isFinite(s.default) && Number.isFinite(s.min) && Number.isFinite(s.max) && s.min <= s.default && s.default <= s.max
      : s.type === 'choice' ? Array.isArray(s.choices) && s.choices.every(v => typeof v === 'string') && s.choices.includes(s.default)
      : s.type === 'color' ? /^#[a-f\d]{6}$/i.test(s.default) : false;
    if (!valid || typeof s.label !== 'string') fail(`Invalid setting ${s.key}`);
    settings.set(s.key, s.default);
  }
  const deref = v => {
    if (Array.isArray(v)) return v.map(deref);
    if (v && typeof v === 'object') {
      if (Object.keys(v).length === 1 && 'setting' in v) {
        if (!settings.has(v.setting)) fail(`Unknown setting ${v.setting}`);
        return settings.get(v.setting);
      }
      return Object.fromEntries(Object.entries(v).map(([k,v]) => [k,deref(v)]));
    }
    return v;
  };
  const resolved = deref(c);
  if (resolved.theme) for (const [k,v] of Object.entries(resolved.theme)) {
    if (!['seed','lightSurface','darkSurface'].includes(k) || typeof v !== 'string' || !/^#[a-f\d]{6}$/i.test(v)) fail('Invalid theme');
  }
  if (resolved.reader) for (const [k,v] of Object.entries(resolved.reader)) {
    const choice = {mode:['page','strip'],background:['ink','paper','sepia'],turn:['slide','paper']}[k];
    if (!(choice ? choice.includes(v) : ['rtl','doublePage','tapZones'].includes(k) ? typeof v === 'boolean' : k === 'warmth' && typeof v === 'number' && v >= 0 && v <= .8)) fail(`Invalid reader field ${k}`);
  }
  if (resolved.navigation) {
    const n = resolved.navigation;
    if (!Array.isArray(n) || n.length < 3 || n.length > 6 || new Set(n).size !== n.length || !n.includes(0) || !n.includes(3) || n.some(v => !Number.isInteger(v) || v < 0 || v > 5)) fail('Invalid navigation');
  }
  if (resolved.source) {
    const s = resolved.source, url = new URL(s.baseUrl);
    if (url.protocol !== 'https:' || url.username || url.password || !/^[a-z0-9_-]{1,40}$/.test(s.id) || ['dm5','local'].includes(s.id)) fail('Invalid source address/id');
    if (p.apiVersion === 2) {
      const domain = host => typeof host === 'string' && host.length <= 253 &&
        /^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]{1,62}$/.test(host);
      if (url.port || url.hash || !domain(url.hostname) || s.baseUrl.length > 2048 ||
          typeof s.name !== 'string' || !s.name.trim() ||
          typeof s.script !== 'string' || !s.script.trim() || Buffer.byteLength(s.script) > 24 * 1024) {
        fail('Invalid script source');
      }
      for (const hosts of [s.requestHosts, s.imageHosts]) {
        if (hosts != null && (!Array.isArray(hosts) || hosts.length < 1 || hosts.length > 8 || !hosts.every(domain))) {
          fail('Script permissions require 1–8 exact lowercase domains');
        }
      }
      if (s.requestHosts && !s.requestHosts.includes(url.hostname)) fail('Request permission must include the source domain');
      new Script(`(${s.script}\n)`, {filename: 'source.js'});
    } else {
      if ('script' in s || 'requestHosts' in s) fail('Script sources require API 2');
      for (const key of ['name','cards','title','link','cover','chapters','pages']) if (typeof s[key] !== 'string' || !s[key].trim()) fail(`Missing source ${key}`);
    }
  }
  if(resolved.character)checkCharacter(resolved.character);
  return p;
}

async function packSource(folder) {
  const manifest = JSON.parse(await readFile(resolve(folder, 'manifest.json'), 'utf8'));
  if (manifest.apiVersion !== 2) throw new Error('pack-source requires API 2');
  manifest.contributes.source.script = (await readFile(resolve(folder, 'source.js'), 'utf8')).replace(/\r\n/g, '\n');
  return JSON.stringify(validatePlugin(manifest), null, 2) + '\n';
}

async function main() {
  const [command, path, output] = process.argv.slice(2);
  if (command === 'validate') {
    const p = validatePlugin(JSON.parse(await readFile(resolve(path), 'utf8')));
    console.log(`Valid: ${p.id}@${p.version} (host additionally validates CSS selectors)`);
  } else if (command === 'build') {
    const folder = resolve(root, 'plugins/packages');
    await writeFile(resolve(folder, 'manxia.script-demo.json'), await packSource(resolve(root, 'plugins/examples/script-source')));
    const manifests = [], entries = [], ids = new Set();
    for (const name of (await readdir(folder)).filter(n => n.endsWith('.json')).sort()) {
      const original = await readFile(resolve(folder,name));
      const bytes = Buffer.from(original.toString('utf8').replace(/\r\n/g,'\n'));
      const p = validatePlugin(JSON.parse(bytes));
      if (!bytes.equals(original)) await writeFile(resolve(folder,name),bytes);
      if (ids.has(p.id)) throw new Error(`Duplicate id ${p.id}`);
      ids.add(p.id); manifests.push(p);
      let packageName=name,packageBytes=bytes;
      if(p.contributes.character) {
        const index=JSON.parse(await readFile(resolve(root,'assets/characters/index.json'),'utf8'));
        const images=new Map();
        for(const f of Object.values(p.contributes.character.states)) {
          const asset=index.images[f.sha256];
          if(typeof asset!=='string' || !asset.startsWith('assets/characters/') || asset.includes('..'))throw new Error(`Missing bundled image ${f.file}`);
          images.set(f.file,await readFile(resolve(root,asset)));
        }
        packageName=name.replace(/\.json$/,'.zip');packageBytes=characterZip(p,images);
        await writeFile(resolve(folder,packageName),packageBytes);
      }
      entries.push({id:p.id, version:p.version, url:`https://raw.githubusercontent.com/LexianLix/manxia/main/plugins/packages/${encodeURIComponent(packageName)}`,sha256:createHash('sha256').update(packageBytes).digest('hex')});
    }
    await mkdir(resolve(root,'assets/plugins'), {recursive:true});
    // Keep the original catalog consumable by hosts predating character packs.
    const api1=entries.filter(e=>manifests.find(p=>p.id===e.id).apiVersion === 1);
    const legacy=api1.filter(e=>!manifests.find(p=>p.id===e.id).contributes.character);
    await writeFile(resolve(root,'plugins/index.json'), JSON.stringify({schemaVersion:1, plugins:legacy},null,2)+'\n');
    await mkdir(resolve(root,'plugins/v1.1'),{recursive:true});
    await writeFile(resolve(root,'plugins/v1.1/index.json'),JSON.stringify({schemaVersion:1,plugins:api1},null,2)+'\n');
    await mkdir(resolve(root,'plugins/v2'),{recursive:true});
    await writeFile(resolve(root,'plugins/v2/index.json'),JSON.stringify({schemaVersion:1,plugins:entries},null,2)+'\n');
    await writeFile(resolve(root,'assets/plugins/catalog.json'), JSON.stringify({schemaVersion:1,plugins:manifests},null,2)+'\n');
    console.log(`Built ${manifests.length} plugins and SHA-256 catalog`);
  } else if (command === 'pack-source') {
    const folder = resolve(path);
    await writeFile(resolve(output ?? `${basename(folder)}.json`), await packSource(folder), {flag: 'wx'});
  } else if (command === 'publish-source') {
    const [baseUrl, destination = '_site'] = process.argv.slice(4);
    const base = new URL(baseUrl);
    if (base.protocol !== 'https:' || base.username || base.password || base.search || base.hash) {
      throw new Error('Use a public HTTPS directory for the plugin repository');
    }
    if (!base.pathname.endsWith('/')) base.pathname += '/';
    const packed = await packSource(resolve(path));
    const {id, version} = JSON.parse(packed);
    const filename = `${id}-${version}.json`;
    const entry = {
      id, version,
      url: new URL(encodeURIComponent(filename), base).href,
      sha256: createHash('sha256').update(packed).digest('hex'),
    };
    const target = resolve(destination);
    await mkdir(target);
    await writeFile(resolve(target, filename), packed, {flag: 'wx'});
    await writeFile(resolve(target, 'index.json'), JSON.stringify({schemaVersion: 1, plugins: [entry]}, null, 2) + '\n', {flag: 'wx'});
  } else if(command==='pack-character') {
    const folder=resolve(path),p=JSON.parse(await readFile(resolve(folder,'manifest.json'),'utf8')),images=new Map();
    for(const f of Object.values(p.contributes?.character?.states??{})) {
      if(!/^[a-z][a-z0-9_-]{0,30}\.png$/.test(f.file))throw new Error('Invalid character image filename');
      const bytes=await readFile(resolve(folder,f.file));images.set(f.file,bytes);f.sha256=createHash('sha256').update(bytes).digest('hex');
    }
    validatePlugin(p);
    const target=resolve(output??`${basename(folder)}.zip`);
    await writeFile(target,characterZip(p,images),{flag:'wx'});
    console.log(`Created ${target}`);
  } else throw new Error('Usage: node tools/plugin-sdk.mjs validate <manifest.json> | build | pack-source <folder> [output.json] | publish-source <folder> <base-url> [output-dir] | pack-character <folder> [output.zip]');
}
if (process.argv[1] && basename(process.argv[1]) === 'plugin-sdk.mjs') main().catch(e => {console.error(e.message);process.exitCode=1;});
