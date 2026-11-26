const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const os = require('node:os');
const cp = require('node:child_process');
const assert = require('node:assert/strict');

(async () => {
  const repo = path.resolve(__dirname, '..');
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
  console.log('WebUI tests PASS: truthful AutoPilot status');
})().catch(error => {console.error(error); process.exitCode = 1;});
