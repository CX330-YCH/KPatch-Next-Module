import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { spawnSync } from 'node:child_process';
import { test } from 'node:test';

const root = new URL('../', import.meta.url);
const index = readFileSync(new URL('webui/index.js', root), 'utf8');
const shellFunction = index.slice(index.indexOf('export function escapeShell'), index.indexOf('export async function initInfo')).replace('export ', '');
const quoteContext = vm.createContext({});
vm.runInContext(shellFunction + '\nglobalThis.quote = escapeShell;', quoteContext);

function kpmContext(exec) {
    const elements = new Map();
    const element = () => ({
        classList: { add() {}, remove() {} },
        querySelector(key) { if (!elements.has(key)) elements.set(key, element()); return elements.get(key); },
        show() {}, close() {}
    });
    const document = { getElementById(key) { if (!elements.has(key)) elements.set(key, element()); return elements.get(key); } };
    const context = vm.createContext({
        exec, spawn() { throw new Error('Unexpected spawn'); }, toast() {}, document,
        modDir: '/module', persistDir: '/persistent', MAX_CHUNK_SIZE: 1024,
        initInfo() {}, getString(...args) { return args.join(':'); }, escapeShell: quoteContext.quote,
    });
    let source = readFileSync(new URL('webui/page/kpm.js', root), 'utf8');
    source = source.replace(/^import .*;$/gm, '').replace(/export function /g, 'function ').replace(/^export \{.*\}$/gm, '').replaceAll('import.meta.env.DEV', 'false');
    vm.runInContext(source + '\nglobalThis.api = { unloadModule, uploadAndLoadModule, isSafeModuleName };', context);
    return { context, document };
}

test('shell quoting preserves apostrophes, brackets, newlines and command substitutions literally', () => {
    const value = "spaces ' [x] $HOME $(echo injected) `echo injected` \\ \nend";
    const r = spawnSync('sh', ['-c', `printf %s ${quoteContext.quote(value)}`], { encoding: 'utf8' });
    assert.equal(r.status, 0);
    assert.equal(r.stdout, value);
});

test('failed unload retains the boot-persistent module', async () => {
    const calls = [];
    const { context } = kpmContext(async command => { calls.push(command); return { errno: 1 }; });
    assert.equal(await context.api.unloadModule('example'), false);
    assert.equal(calls.length, 1);
    assert.match(calls[0], /^kpatch kpm unload /);
});

test('successful unload waits for persistence removal', async () => {
    const calls = [];
    const { context } = kpmContext(async command => { calls.push(command); return { errno: 0 }; });
    assert.equal(await context.api.unloadModule('example'), true);
    assert.equal(calls.length, 2);
    assert.match(calls[1], /^rm -f /);
});

test('module names cannot escape their persistence directory', () => {
    const { context } = kpmContext(async () => ({ errno: 0 }));
    assert.equal(context.api.isSafeModuleName('../boot'), false);
    assert.equal(context.api.isSafeModuleName('a/b'), false);
    assert.equal(context.api.isSafeModuleName('test\0name'), false);
    assert.equal(context.api.isSafeModuleName("example's module"), true);
});

test('upload persistence finishes before its source directory is removed', async () => {
    const calls = [];
    let finishCopy;
    const copyPending = new Promise(resolve => { finishCopy = resolve; });
    const { context, document } = kpmContext(async command => {
        calls.push(command);
        if (command.includes('cp -f')) await copyPending;
        return { errno: 0, stdout: '', stderr: '' };
    });
    // Mock the browser file picker and binary transfer. Exercise the actual
    // dialog handler and command sequencing after selection.
    vm.runInContext(`
        handleFileUpload = (accept, id, callback) => {
            globalThis.selected = callback({ name: 'example.kpm' }, () => {}, {});
        };
        uploadFile = async () => {};
        getKpmInfo = async () => ({ name: 'example' });
        refreshKpmList = async () => {};
    `, context);
    context.api.uploadAndLoadModule();
    await context.selected;
    const confirmation = document.getElementById('load-dialog').querySelector('.confirm').onclick();
    // Flush continuations until cp has begun but has not completed.
    for (let i = 0; i < 5; i++) await Promise.resolve();
    assert.ok(calls.some(command => command.includes('cp -f')));
    assert.ok(!calls.some(command => command.startsWith('rm -rf')));
    finishCopy();
    await confirmation;
    assert.match(calls.at(-1), /^rm -rf '\/module\/tmp\/kpm-/);
    assert.ok(!calls.some(command => command === 'rm -rf /module/tmp'));
});
