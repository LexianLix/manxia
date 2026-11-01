import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {checkCharacter,checkCharacterPng,characterZip} from './character-package.mjs';
import {validatePlugin} from './plugin-sdk.mjs';

test('bundled role package is deterministic and its PNGs are bounded',async()=>{
  const manifest=JSON.parse(await readFile(new URL('../plugins/packages/xiaxia.json',import.meta.url)));
  const images=new Map();
  for(const f of Object.values(manifest.contributes.character.states)) {
    const bytes=await readFile(new URL('../assets/characters/xiaxia/'+f.file,import.meta.url));
    checkCharacterPng(bytes);images.set(f.file,bytes);
  }
  validatePlugin(manifest);
  const zip=characterZip(manifest,images);
  assert.deepEqual(zip,characterZip(manifest,images));
  assert.deepEqual(zip,await readFile(new URL('../plugins/packages/xiaxia.zip',import.meta.url)));
  assert.equal(zip.readUInt32LE(0),0x04034b50);
  assert.ok(zip.length<2*1024*1024);
});
test('unsafe frame paths and oversized image dimensions are rejected',async()=>{
  assert.throws(()=>checkCharacter({states:{idle:{file:'../outside.png',sha256:'0'.repeat(64)}}}));
  const bytes=await readFile(new URL('../assets/characters/xiaxia/idle.png',import.meta.url));
  const oversized=Buffer.from(bytes);oversized.writeUInt32BE(513,16);
  assert.throws(()=>checkCharacterPng(oversized));
});
test('the legacy catalog excludes newer character contributions',async()=>{
  const legacy=JSON.parse(await readFile(new URL('../plugins/index.json',import.meta.url)));
  const current=JSON.parse(await readFile(new URL('../plugins/v1.1/index.json',import.meta.url)));
  assert.ok(!legacy.plugins.some(p=>p.id==='manxia.xiaxia'));
  assert.ok(current.plugins.some(p=>p.id==='manxia.xiaxia'&&p.url.endsWith('.zip')));
});
