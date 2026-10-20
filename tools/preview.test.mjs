import test from 'node:test';
import assert from 'node:assert/strict';
import { imageAllowed, sourceAllowed, createServer } from './preview.mjs';

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
test('deduplicate and briefly cache successful public source reads', async () => {
  let reads = 0;
  const server = createServer({load:async()=>{reads++;return new Response('<html>catalog</html>');}});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  try {
    const endpoint=`http://127.0.0.1:${server.address().port}/api/source?path=/`;
    const responses=await Promise.all([fetch(endpoint),fetch(endpoint)]);
    for(const response of responses)assert.equal(await response.text(),'<html>catalog</html>');
    await fetch(endpoint);
    assert.equal(reads,1);
  } finally { await new Promise(resolve=>server.close(resolve)); }
});
