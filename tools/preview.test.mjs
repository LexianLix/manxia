import test from 'node:test';
import assert from 'node:assert/strict';
import { imageAllowed, sourceAllowed, createServer } from './preview.mjs';
import { latestRelease, publicRelease } from './update-check.mjs';

test('update check recovers from anonymous rate limits using only the same repository', async () => {
  const calls=[];
  const result=await latestRelease(async(url)=>{calls.push(url);return calls.length===1
    ? new Response('{}',{status:403})
    : new Response(null,{status:302,headers:{location:'/LexianLix/manxia/releases/tag/v0.3.10'}});});
  assert.equal(result.tag_name,'v0.3.10');assert.equal(result.source,'public-page');
  assert.equal(calls.length,2);
  for(const url of ['https://evil.com/LexianLix/manxia/releases/tag/v1.0.0',
    'https://github.com/other/repo/releases/tag/v1.0.0','/LexianLix/manxia/releases/tag/latest'])
    assert.throws(()=>publicRelease(url));
});
test('web update endpoint returns version metadata and rejects arbitrary targets', async()=>{
  let reads=0; const server=createServer({updateRequest:async()=>{reads++;return Response.json({tag_name:'v0.3.9',assets:[]});}});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  try {
    const base=`http://127.0.0.1:${server.address().port}/api/update`;
    assert.equal((await (await fetch(base)).json()).tag_name,'v0.3.9');
    assert.equal((await fetch(`${base}?url=https://evil.com`)).status,400);assert.equal(reads,1);
  } finally {await new Promise(resolve=>server.close(resolve));}
});

test('gateway only proxies known source routes and image hosts', () => {
  for (const path of ['/', '/search?title=test', '/manhua-bingzhichengbi/', '/m12345/']) assert.equal(sourceAllowed(path),true,path);
  for (const path of ['//evil.com/', '/\\evil.com/', '/../../secret', '/login/', '/m123/../../a']) assert.equal(sourceAllowed(path),false,path);
  assert.equal(imageAllowed('https://mhfm6us.cdndm5.com/86/a.jpg'),true);
  for (const url of ['http://mhfm6us.cdndm5.com/a.jpg','https://cdndm5.com.evil.com/a','https://127.0.0.1/a','https://user@cdndm5.com/a']) assert.equal(imageAllowed(url),false,url);
});
test('reject invalid proxy requests before network access', async () => {
  const server = createServer();
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    assert.equal((await fetch(`${base}/api/source?path=//evil.com`)).status,400);
    assert.equal((await fetch(`${base}/api/image?url=https://127.0.0.1/a`)).status,400);
    assert.equal((await (await fetch(`${base}/api/health`)).json()).ok,true);
  } finally { await new Promise(resolve=>server.close(resolve)); }
});

test('source gateway preserves explicit missing and access statuses for reader classification', async () => {
  let status = 404;
  const server = createServer({load: async () => {
    throw Object.assign(new Error('upstream unavailable'), {status});
  }});
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    for (status of [401,403,404,410,429,500]) {
      const response = await fetch(`${base}/api/source?path=/manhua-missing/`);
      assert.equal(response.status, status === 500 ? 502 : status);
    }
    const home = await fetch(base);
    assert.equal(home.headers.get('cross-origin-opener-policy'), 'same-origin');
    assert.equal(home.headers.get('cross-origin-embedder-policy'), 'credentialless');
  } finally { await new Promise(resolve => server.close(resolve)); }
});
test('deduplicate and briefly cache successful public source reads', async () => {
  let reads = 0;
  const server = createServer({load:async()=>{reads++;return new Response('<html>catalog</html>');}});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  try {
    const endpoint=`http://127.0.0.1:${server.address().port}/api/source?path=/`;
    const responses=await Promise.all([fetch(endpoint),fetch(endpoint)]);
    assert.match(responses[0].headers.get('content-security-policy'),/sandbox/);
    for(const response of responses)assert.equal(await response.text(),'<html>catalog</html>');
    await fetch(endpoint);
    assert.equal(reads,1);
  } finally { await new Promise(resolve=>server.close(resolve)); }
});

test('public detail editions have separate caches and fixed source origins', async () => {
  const reads=[];
  const server=createServer({load:async(url)=>{reads.push(url);return new Response(url);}});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  try {
    const base=`http://127.0.0.1:${server.address().port}/api/source?path=/manhua-test/`;
    assert.equal(await (await fetch(base)).text(),'https://m.dm5.com/manhua-test/');
    assert.equal(await (await fetch(`${base}&edition=desktop`)).text(),'https://www.dm5.com/manhua-test/');
    await fetch(`${base}&edition=desktop`);
    assert.equal(reads.length,2);
    assert.equal((await fetch(`${base}&edition=https://evil.com`)).status,400);
    assert.equal((await fetch(`${base.replace('/manhua-test/', '/m123/')}&edition=desktop`)).status,400);
  } finally {await new Promise(resolve=>server.close(resolve));}
});

test('custom sources require explicit registration and keep reads on that source origin',async()=>{
  const requests=[];
  const server=createServer({load:async(url)=>{requests.push(url);return new Response('<main>source</main>');}});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${server.address().port}`;
  try {
    const registered=await fetch(`${base}/api/profiles`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify([{id:'test',baseUrl:'https://example.com',imageHosts:['images.example.com']}])});
    assert.equal(registered.status,200);
    const endpoint=(url)=>`${base}/api/custom?id=test&url=${encodeURIComponent(url)}`;
    assert.equal((await fetch(endpoint('https://evil.com/book'))).status,400);
    assert.equal((await fetch(endpoint('https://example.com/book'))).status,200);
    assert.deepEqual(requests,['https://example.com/book']);
    assert.equal((await fetch(`${base}/api/profiles`,{method:'POST',headers:{'Content-Type':'application/json',Origin:'https://foreign.example'},body:'[]'})).status,502);
    assert.equal((await fetch(`${base}/api/webdav`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({url:'https://example.com',method:'DELETE'})})).status,502);
  } finally { await new Promise(resolve=>server.close(resolve)); }
});

test('catalog pagination proxies only the known source action and numeric parameters',async()=>{
  let upstream;
  const server=createServer({load:async(url,ref,timeout,options)=>{upstream={url,options};return new Response('{"UpdateComicItems":[]}');}});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${server.address().port}`;
  try {
    const fields={pageindex:'2',pagesize:'10',usergroup:'0',categoryid:'0',tagid:'31',status:'2',sort:'18',pay:'-1',areaid:'0'};
    const response=await fetch(`${base}/api/list`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(fields)});
    assert.equal(response.status,200);assert.equal(upstream.url,'https://m.dm5.com/dm5.ashx');
    assert.equal(upstream.options.method,'POST');assert.equal(new URLSearchParams(upstream.options.body).get('tagid'),'31');
    const rejected=await fetch(`${base}/api/list`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({...fields,tagid:'bad'})});
    assert.equal(rejected.status,502);
  } finally {await new Promise(resolve=>server.close(resolve));}
});

test('WebDAV archive transfer streams binary data and preserves conditional writes',async()=>{
  let uploaded;
  const server=createServer({dav:async(url,options)=>{
    assert.equal(url.origin,'https://dav.example.com');
    if(options.method==='HEAD')return new Response(null,{status:404});
    if(options.method==='PUT') {
      assert.equal(options.headers['if-none-match'],'*');
      const chunks=[];for await(const c of options.body)chunks.push(c);
      uploaded=Buffer.concat(chunks);return new Response(null,{status:201});
    }
    return new Response(new Uint8Array([80,75,3,4]),{headers:{etag:'"archive-1"'}});
  }});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${server.address().port}/api/webdav-binary?url=${encodeURIComponent('https://dav.example.com/library.offline.zip')}`;
  try {
    assert.equal((await fetch(`${base}&method=HEAD`,{method:'POST',headers:{'Content-Type':'application/zip'}})).status,404);
    assert.equal((await fetch(`${base}&method=PUT`,{method:'POST',headers:{'Content-Type':'application/zip','If-None-Match':'*'},body:new Uint8Array([80,75,3,4])})).status,201);
    assert.deepEqual([...uploaded],[80,75,3,4]);
    const read=await fetch(`${base}&method=GET`,{method:'POST',headers:{'Content-Type':'application/zip'}});
    assert.equal(read.headers.get('etag'),'"archive-1"');assert.deepEqual([...new Uint8Array(await read.arrayBuffer())],[80,75,3,4]);
  } finally {await new Promise(resolve=>server.close(resolve));}
});
