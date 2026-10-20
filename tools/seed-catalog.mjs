// Capture public thumbnail metadata, never comic image files.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
const input=process.argv[2] ? await readFile(process.argv[2],'utf8') : await (await fetch('https://m.dm5.com/')).text();
const wanted=['萤火虫之婚','海贼王','青之芦苇','冰之城壁','咒术回战','火影忍者','排球','蓝箱'];
const matches=[...input.matchAll(/<a href="(\/manhua-[\w-]+\/)" title="([^"]+)">\s*(?:<div[^>]*>\s*)?<img[^>]+src="([^"]+)"/g)];
const data=wanted.map(name=>matches.find(m=>m[2]===name)).filter(Boolean).map(m=>({path:m[1],title:m[2],cover:m[3]}));
await mkdir('assets',{recursive:true});
await writeFile('assets/catalog.json',JSON.stringify(data,null,2)+'\n');
console.log(`Captured ${data.length} thumbnail references`);
