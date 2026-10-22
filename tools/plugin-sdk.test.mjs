import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {validatePlugin} from './plugin-sdk.mjs';

test('a real package resolves defaults and validates its contributions', async () => {
  const plugin = JSON.parse(await readFile(new URL('../plugins/packages/manxia.warm-paper.json', import.meta.url)));
  assert.equal(validatePlugin(plugin).id, 'manxia.warm-paper');
  assert.throws(() => validatePlugin({...plugin, apiVersion: 2}));
  assert.throws(() => validatePlugin({...plugin, contributes:{theme:{seed:'javascript:code'}}}));
  assert.throws(() => validatePlugin({...plugin, contributes:{reader:{warmth:20}}}));
  assert.throws(() => validatePlugin({...plugin, contributes:{navigation:[0,0,3]}}));
});
