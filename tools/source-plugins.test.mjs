import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {Script} from 'node:vm';
import {validatePlugin} from './plugin-sdk.mjs';

async function source(name) {
  const p=validatePlugin(JSON.parse(await readFile(new URL(`../plugins/packages/manxia.source-${name}.json`,import.meta.url),'utf8')));
  return new Script(`(${p.contributes.source.script})`).runInNewContext({}, {timeout:1500});
}
const ctx=(responses=[],args={})=>({baseUrl:'https://example.com/',responses,query:'',page:1,...args});

test('Kanman uses real page numbers and requests encoded search terms',async()=>{
  const api=await source('kanman');
  assert.match(api.discover(ctx([], {page:2})).request,/\?page=2&/);
  assert.match(api.search(ctx([], {query:'龙王 &'})).request,/search_key=%E9%BE%99%E7%8E%8B%20%26$/);
  const list=api.discover(ctx([JSON.stringify({status:0,data:[{comic_id:12,comic_name:'Book',cover_img:'http://image.yqmh.com/12.jpg'}]})])).result;
  assert.equal(list[0].cover,'https://image.yqmh.com/12.jpg');
});

test('Kanman reads public chapters without inventing paid image access',async()=>{
  const api=await source('kanman');
  const body=JSON.stringify({status:0,data:[{chapter_newid:'one',chapter_name:'One',order_num:1,price:0},{chapter_newid:'two',chapter_name:'Two',order_num:2,price:0},{chapter_newid:'paid',chapter_name:'Paid',order_num:3,price:100}]});
  const chapters=api.detail(ctx([body],{url:'https://www.kanman.com/12/'})).result.chapters;
  assert.equal(chapters.length,2);assert.equal(chapters[0].title,'Two');
  assert.equal(api.pages(ctx(['chapter_img_list:["https://image.yqmh.com/1.jpg","https://image.yqmh.com/2.jpg"]'])).result.length,2);
  assert.throws(()=>api.pages(ctx(['chapter_img_list:runRemoteCode()'])),/未公开图片/);
});

test('Manhuagui decodes data without evaluating a packed function',async()=>{
  const api=await source('manhuagui');
  const dictionary='MoWQEgPglgtg5gEQIYBckQGZQDYFMDOEADknLgHQBWRcxqAFhAPRECuARtlAMZMT7YIARgBMAZgAs/KHAB2qVgCdcQA=';
  const payload='0.1({"2":["3"],"4":"5","6":{"e":7,"m":"8"}})';
  const html=`window.eval(function(p,a,c,k){throw Error('must never run');}('${payload}',36,9,'${dictionary}'))`;
  const pages=api.pages(ctx([html])).result;
  assert.equal(pages[0],'https://i.hamreus.com/public/page.jpg?e=1234&m=signature');
  assert.throws(()=>api.pages(ctx(['<title>Just a moment...</title>'])),/未返回公开图片/);
});

test('Manhuagui keeps real volume and side-story groups even with repeated DOM ids',async()=>{
  const api=await source('manhuagui');
  const html='<h4><span>番外篇</span></h4><div id="chapter-list-0"><ul><li><a href="/comic/12/2.html" title="Extra">Extra</a></li></ul></div><h4><span>单行本</span></h4><div id="chapter-list-0"><ul><li><a href="/comic/12/1.html" title="第01卷">第01卷</a></li></ul></div>';
  const rows=api.detail(ctx([html],{url:'https://www.manhuagui.com/comic/12/'})).result.chapters;
  assert.equal(rows[0].group,'番外篇');assert.equal(rows[1].group,'单行本');
});

test('Pepper Carrot preserves Chinese pages and excludes header and other-language images',async()=>{
  const api=await source('peppercarrot');
  assert.equal(api.search(ctx([], {query:'萝卜头'})).result.length,1);
  assert.equal(api.search(ctx([], {query:'not-this-book'})).result.length,0);
  const path='https://www.peppercarrot.com/0_sources/ep01/low-res/';
  const html=[`<img src="${path}cn_title_E01P00.jpg">`,`<img src="${path}cn_title_E01P01.jpg">`,`<img src="${path}en_title_E01P01.jpg">`].join('');
  const pages=api.pages(ctx([html])).result;
  assert.equal(pages.length,1);assert.match(pages[0],/cn_title_E01P01.jpg$/);
});
