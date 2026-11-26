const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const os = require('node:os');
const cp = require('node:child_process');
const assert = require('node:assert/strict');

(async () => {
  const repo = path.resolve(__dirname, '..');
  const html = fs.readFileSync(path.join(repo, 'webroot/KeyboxLoader/index.html'), 'utf8');
  const take = (from, to) => {
    const begin = html.indexOf(from);
    const end = html.indexOf(to, begin);
    assert(begin >= 0 && end > begin, 'KeyboxLoader page: ' + from + ' ... ' + to + ' not found (the page changed: adapt this test)');
    return html.slice(begin, end);
  };
  // the author's v48.1 page: constants, shellQuote and setKeybox are run for real; the main Tricky Store slot must go
  // through the AutoPilot engine (validation + rollback), the other targets keep the author's plain copy
  const code = take('const BACKUP_DIR', 'let allFiles') + take('function shellQuote', '\nfunction showToast') +
    take('async function setKeybox', '\ndocument.getElementById("closePreview")');
  let commands, toast, reply, closedWhileSetting;
  const context = vm.createContext({runShell: async command => {
    commands.push(command);
    return reply;
  }, showToast: (...args) => {toast = args;}, closeConfirmation: () => {closedWhileSetting = context.isSettingNow();}, isSettingNow: () => vm.runInContext('isSetting', context), console: {error: () => {}},
  document: {querySelectorAll: () => []}});
  vm.runInContext('let selectedFile = null, isSetting = false, isCheckingStatus = false;', context);
  vm.runInContext(code, context);
  const select = file => {context.__file = file; vm.runInContext('selectedFile = __file;', context);};
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'box-webui-'));
  try {
    const marker = path.join(dir, 'must-not-exist');
    const input = "odd'; touch " + marker + "; echo '$(touch " + marker + ')';
    select({path: input, name: 'odd.xml'});
    commands = []; reply = 'IMPORT_EXIT=0';
    await context.setKeybox('tricky');
    assert.equal(toast[1], 'success');
    assert.equal(closedWhileSetting, false, 'closeConfirmation() (it deletes the imported keybox copy) must run after isSetting is released');
    assert(/autopilot\.sh import .* 1 2>&1;/.test(commands[1]), 'stderr must reach the user: the engine explains a refusal there');
    assert.equal(commands.length, 2, 'backup step, then the engine import');
    assert(!/cp -f "\$src" "\$target"/.test(commands[0]), 'the main slot must not be copied blindly');
    assert(/cp -f "\$target" "\$backup_file"/.test(commands[0]), "the author's backup of the previous key stays");
    const output = path.join(dir, 'argv');
    const stub = path.join(dir, 'sh');
    fs.writeFileSync(stub, '#!/bin/sh\nprintf "%s" "$3" > "$CAPTURE"\nexit 0\n', {mode: 0o700});
    const result = cp.spawnSync('/bin/sh', ['-c', commands[1]], {
      env: {...process.env, PATH: dir + path.delimiter + process.env.PATH, CAPTURE: output},
      encoding: 'utf8'
    });
    assert.equal(result.status, 0);
    assert.equal(fs.readFileSync(output, 'utf8'), input);
    assert.equal(fs.existsSync(marker), false);
    reply = 'misleading IMPORT_EXIT=0\nIMPORT_EXIT=1';
    commands = [];
    await context.setKeybox('tricky');
    assert.equal(toast[1], 'error');
    // the bridge timeout (15 s) is not an engine failure
    const realRun = context.runShell;
    let calls = 0;
    context.runShell = async command => {commands.push(command); if (++calls === 2) throw new Error('Shell command timed out'); return reply;};
    commands = [];
    await context.setKeybox('tricky');
    assert.equal(toast[1], 'error');
    assert(/still running/.test(toast[0]), 'a bridge timeout must say the import may still finish, got: ' + toast[0]);
    context.runShell = realRun;
    // OhMyKeyMint / TEE Simulator: the author's plain copy, the engine is not involved
    for (const key of ['omk', 'teesim']) {
      reply = '';
      commands = [];
      await context.setKeybox(key);
      assert.equal(commands.length, 1);
      assert(/cp -f "\$src" "\$target"/.test(commands[0]) && !/autopilot\.sh/.test(commands[0]), key + ': plain copy expected');
      assert.equal(toast[1], 'success');
    }
  } finally {fs.rmSync(dir, {recursive: true, force: true});}

  const pilot = fs.readFileSync(path.join(repo, 'webroot/Pilot/index.html'), 'utf8');
  const a = pilot.indexOf('function checkAutopilot()');
  const b = pilot.indexOf('\nfunction checkMode()', a);
  const nodes = new Map();
  let response = JSON.stringify({desired_enabled: true, running: false, phase: 'waiting',
    revocation_state: 'unknown', next_due: '0001-01-01', heartbeat: '0001-01-01'});
  const pilotContext = vm.createContext({DAEMON_SCRIPT: '/test/controller',
    runShell: (_command, callback) => callback(response),
    updateHeartbeatUI: () => {},
    document: {getElementById: id => {
      if (!nodes.has(id)) nodes.set(id, {});
      return nodes.get(id);
    }}});
  vm.runInContext(pilot.slice(a, b), pilotContext);
  pilotContext.checkAutopilot();
  assert.equal(nodes.get('autopilotToggle').checked, true);
  assert.equal(nodes.get('statusSubtitle').textContent, 'Waiting for service');
  for (const [consumer, expected] of [
    [{id: 'tricky_store', present: true, state: 'rejected', evidence: 'rejection_logged'}, 'Tricky Store: refused the key'],
    [{id: 'tricky_store', present: true, state: 'accepted', evidence: 'no_rejection_logged'}, 'Tricky Store: no refusal logged'],
    [{id: 'tricky_store', present: true, state: 'unknown', evidence: 'no_log_channel'}, 'Tricky Store: not verified (no_log_channel)'],
    [{id: 'tricky_store', present: false, state: 'unknown', evidence: 'not_installed'}, 'Tricky Store: not installed'],
  ]) {
    response = JSON.stringify({desired_enabled: true, running: true, phase: 'waiting', revocation_state: 'fresh',
      next_due: '0001-01-01', heartbeat: '2026-01-01T00:00:00Z', consumer});
    pilotContext.checkAutopilot();
    assert.equal(nodes.get('githubSubtitle').textContent, expected + ' • Revocation: fresh');
  }
  response = JSON.stringify({desired_enabled: true, running: true, phase: 'waiting', revocation_state: 'fresh',
    next_due: '0001-01-01', heartbeat: '2026-01-01T00:00:00Z', reason: 'required keybox consumer is not installed'});
  pilotContext.checkAutopilot();
  assert.equal(nodes.get('githubSubtitle').textContent, 'required keybox consumer is not installed');
  response = 'invalid JSON';
  pilotContext.checkAutopilot();
  assert.equal(nodes.get('statusSubtitle').textContent, 'Status unavailable');
  const heartbeatStart = pilot.indexOf('function updateHeartbeatUI(');
  const heartbeatEnd = pilot.indexOf('\nfunction updateGithubUI(', heartbeatStart);
  pilotContext.getHeartbeatStatus = () => ({status: 'dead', text: 'Not responding'});
  pilotContext.timeAgo = () => 'old';
  pilotContext.formatExactTime = () => 'timestamp';
  nodes.set('heartbeatIcon', {classList: {add: () => {}}});
  vm.runInContext(pilot.slice(heartbeatStart, heartbeatEnd), pilotContext);
  pilotContext.updateHeartbeatUI(1, true);
  assert.equal(nodes.get('heartbeatSubtitle').textContent, 'Process alive');
  pilotContext.updateHeartbeatUI(1, false);
  assert.equal(nodes.get('heartbeatSubtitle').textContent, 'Not running');
  console.log('WebUI bridge tests PASS: quoting, import failure, truthful status');
})().catch(error => {console.error(error); process.exitCode = 1;});
