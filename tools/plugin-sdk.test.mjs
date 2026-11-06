import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readFile, rm, rmdir} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {validatePlugin} from './plugin-sdk.mjs';
import {Script} from 'node:vm';

test('a real package resolves defaults and validates its contributions', async () => {
  const plugin = JSON.parse(await readFile(new URL('../plugins/packages/manxia.warm-paper.json', import.meta.url)));
  assert.equal(validatePlugin(plugin).id, 'manxia.warm-paper');
  assert.throws(() => validatePlugin({...plugin, apiVersion: 2}));
  assert.throws(() => validatePlugin({...plugin, contributes:{theme:{seed:'javascript:code'}}}));
  assert.throws(() => validatePlugin({...plugin, contributes:{reader:{warmth:20}}}));
  assert.throws(() => validatePlugin({...plugin, contributes:{navigation:[0,0,3]}}));
});

test('a standalone source catalog points at the packaged bytes', async () => {
  const workspace = await mkdtemp(join(tmpdir(), 'manxia-source-'));
  const target = join(workspace, 'site');
  try {
    execFileSync(process.execPath, [
      fileURLToPath(new URL('./plugin-sdk.mjs', import.meta.url)),
      'publish-source',
      fileURLToPath(new URL('../plugins/examples/script-source/', import.meta.url)),
      'https://example.com/comics', target,
    ]);
    const catalog = JSON.parse(await readFile(join(target, 'index.json')));
    assert.equal(catalog.schemaVersion, 1);
    assert.equal(catalog.plugins.length, 1);
    const [entry] = catalog.plugins;
    assert.equal(entry.url, 'https://example.com/comics/manxia.script-demo-1.0.0.json');
    const bytes = await readFile(join(target, 'manxia.script-demo-1.0.0.json'));
    assert.equal(entry.sha256, createHash('sha256').update(bytes).digest('hex'));
    assert.equal(validatePlugin(JSON.parse(bytes)).id, entry.id);
  } finally {
    await rm(join(target, 'index.json'), {force: true});
    await rm(join(target, 'manxia.script-demo-1.0.0.json'), {force: true});
    await rmdir(target).catch(error => { if (error.code !== 'ENOENT') throw error; });
    await rmdir(workspace);
  }
});

test('author script is packaged reproducibly and provides search, detail and pages', async () => {
  const directory = new URL('../plugins/examples/script-source/', import.meta.url);
  const code = (await readFile(new URL('source.js', directory), 'utf8')).replace(/\r\n/g, '\n');
  const body = await readFile(new URL('../assets/characters/index.json', import.meta.url), 'utf8');
  const plugin = validatePlugin(JSON.parse(await readFile(new URL('../plugins/packages/manxia.script-demo.json', import.meta.url))));
  const source = plugin.contributes.source;
  assert.equal(source.script, code);
  const run = (hook, ctx) => JSON.parse(new Script(
    `JSON.stringify((${code}\n).${hook}(${JSON.stringify(ctx)}))`,
  ).runInNewContext({}, {timeout: 500}));
  const input = {baseUrl: source.baseUrl, query: 'Manxia Demo', responses: []};
  assert.deepEqual(run('search', input), {request: 'assets/characters/index.json'});
  input.responses.push(body);
  const [book] = run('search', input).result;
  assert.equal(book.title, '漫匣试读');
  const [chapter] = run('detail', {...input, url: source.baseUrl + book.path}).result.chapters;
  assert.equal(run('pages', {...input, url: source.baseUrl + chapter.path}).result.length, 3);
  const legacy = JSON.parse(await readFile(new URL('../plugins/v1.1/index.json', import.meta.url)));
  assert.ok(legacy.plugins.every(item => item.id !== plugin.id));
});
