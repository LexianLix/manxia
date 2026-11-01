import {readFile, writeFile, readdir, mkdir} from 'node:fs/promises';
import {resolve, dirname, basename} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {checkCharacter,characterZip} from './character-package.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export function validatePlugin(p) {
  const fail = s => { throw new Error(s); };
  if (Buffer.byteLength(JSON.stringify(p)) > 128*1024) fail('Manifest exceeds 128 KB');
  if (p.description !== undefined && (typeof p.description !== 'string' || p.description.length > 1200)) fail('Invalid description');
  if (p.apiVersion !== 1) fail('Expected apiVersion: 1');
  if (!/^[a-z][a-z0-9_-]{0,31}\.[a-z0-9][a-z0-9_.-]{0,63}$/.test(p.id)) fail('Invalid author.name id');
  if (!/^\d+\.\d+\.\d+$/.test(p.version)) fail('Expected x.y.z version');
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
    for (const key of ['name','cards','title','link','cover','chapters','pages']) if (typeof s[key] !== 'string' || !s[key].trim()) fail(`Missing source ${key}`);
  }
  if(resolved.character)checkCharacter(resolved.character);
  return p;
}

async function main() {
  const [command, path, output] = process.argv.slice(2);
  if (command === 'validate') {
    const p = validatePlugin(JSON.parse(await readFile(resolve(path), 'utf8')));
    console.log(`Valid: ${p.id}@${p.version} (host additionally validates CSS selectors)`);
  } else if (command === 'build') {
    const folder = resolve(root, 'plugins/packages');
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
    const legacy=entries.filter(e=>!manifests.find(p=>p.id===e.id).contributes.character);
    await writeFile(resolve(root,'plugins/index.json'), JSON.stringify({schemaVersion:1, plugins:legacy},null,2)+'\n');
    await mkdir(resolve(root,'plugins/v1.1'),{recursive:true});
    await writeFile(resolve(root,'plugins/v1.1/index.json'),JSON.stringify({schemaVersion:1,plugins:entries},null,2)+'\n');
    await writeFile(resolve(root,'assets/plugins/catalog.json'), JSON.stringify({schemaVersion:1,plugins:manifests},null,2)+'\n');
    console.log(`Built ${manifests.length} plugins and SHA-256 catalog`);
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
  } else throw new Error('Usage: node tools/plugin-sdk.mjs validate <manifest.json> | build | pack-character <folder> [output.zip]');
}
if (process.argv[1] && basename(process.argv[1]) === 'plugin-sdk.mjs') main().catch(e => {console.error(e.message);process.exitCode=1;});
