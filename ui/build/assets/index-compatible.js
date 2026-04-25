
const resourceName = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'insane-garbagej';
const appRoot = document.body;
const rows = document.getElementById('rows');

const state = {
  visible: false,
  tasks: [],
  userProfile: {},
  currentLobby: {},
  locale: {
    maps: 'Maps', title: 'Title', level: 'Level', rewards: 'Rewards', rep: 'Rep', gps: 'GPS',
    reputation: 'Reputation', garbage_about: 'Garbage About', desc_garbage_about: 'Street cleaning involves collecting trash from urban areas.',
    victor_goods: 'Victor Goods', money_type: '$'
  }
};

function postNui(name, body) {
  try {
    return fetch(`https://${resourceName}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(body ?? {})
    }).then(r => r.json().catch(() => ({}))).catch(() => ({}));
  } catch (_) {
    return Promise.resolve({});
  }
}

function t(key) {
  const ui = state.locale || {};
  if (ui[key] != null) return ui[key];
  return key;
}

function xpPercent(extraExp = 0) {
  const exp = Number(state.userProfile?.exp || 0);
  const next = Number(state.userProfile?.nextLevelExp || 0);
  if (!next) return 0;
  return Math.max(0, Math.min(100, ((exp + Number(extraExp || 0)) / next) * 100));
}

function setText(id, value) {
  const el = document.getElementById(id);
  if (el) el.textContent = value;
}

function renderProfile() {
  const p = state.userProfile || {};
  setText('workerName', p.name || t('victor_goods') || 'Victor Goods');
  setText('workerJob', p.jobLabel || p.job || 'Sanitation Worker');
  setText('repLabel', t('reputation'));
  setText('aboutTitle', t('garbage_about'));
  setText('aboutText', t('desc_garbage_about'));
  setText('mapsLabel', t('maps'));
  setText('titleLabel', t('title'));
  setText('levelLabel', t('level'));
  setText('rewardsLabel', t('rewards'));
  setText('repColLabel', t('rep'));
  setText('gpsLabel', t('gps'));

  const exp = Number(p.exp || 1200);
  const next = Number(p.nextLevelExp || 1800);
  const level = Number(p.level || 1);
  setText('repText', `${exp.toLocaleString()} / ${next.toLocaleString()} XP`);
  document.getElementById('repFill').style.width = `${xpPercent()}%`;
  setText('levelPill', `Level ${level}`);
}

function normalizeTasks(input) {
  const arr = Array.isArray(input) ? input : Object.values(input || {});
  return arr.map((task, idx) => ({
    unique_id: task.unique_id ?? task.id ?? idx + 1,
    title: task.title ?? `Task #${idx + 1}`,
    max_client: Number(task.max_client ?? task.maxClient ?? 2),
    level: Number(task.level ?? 1),
    fee: Number(task.fee ?? task.reward ?? task.money ?? 0),
    exp: Number(task.exp ?? task.rep ?? 25)
  }));
}

function startTask(uniqueId) {
  postNui('nui:startLobbyWithTask', uniqueId);
}

function renderTasks() {
  rows.innerHTML = '';
  const tasks = normalizeTasks(state.tasks);
  tasks.forEach((task, index) => {
    const row = document.createElement('div');
    row.className = 'row';
    row.innerHTML = `
      <div class="mapbox"></div>
      <div class="title">${task.title} [1-${task.max_client}] <span class="team">👥</span></div>
      <div class="lvl">${task.level}</div>
      <div class="reward">${t('money_type')}${task.fee.toLocaleString()}</div>
      <div class="rep"><div class="reptrack"><div class="repfill" style="width:${xpPercent(task.exp)}%"></div></div></div>
      <button class="gps" data-id="${task.unique_id}">➤</button>`;
    row.querySelector('.gps').addEventListener('click', () => startTask(task.unique_id));
    rows.appendChild(row);
  });
}

function showApp(show) {
  state.visible = !!show;
  appRoot.style.display = state.visible ? 'flex' : 'none';
}

function applySetup(payload) {
  if (payload?.setLocale) state.locale = payload.setLocale.ui || payload.setLocale;
  if (payload?.setTasks) state.tasks = Object.values(payload.setTasks);
  renderProfile();
  renderTasks();
  postNui('nui:onLoadUI', true);
}

window.addEventListener('message', (event) => {
  const data = event.data || {};
  const eventName = data.action || data.type || data.event;

  if (eventName === 'ui:setupUI') return applySetup(data);
  if (eventName === 'ui:setPage') return showApp(data.page === 'garbage' || data.page === 'delivery' || data.page === 'towtruck' || !!data.show);
  if (eventName === 'ui:setUserProfile') { state.userProfile = data.data ?? data.profile ?? data; renderProfile(); return; }
  if (eventName === 'ui:setCurrentLobby') { state.currentLobby = data.data ?? data; return; }
  if (eventName === 'ui:setLobbyMembers') { state.currentLobby.members = data.data ?? data; return; }
  if (eventName === 'ui:setTaskProgress') { state.currentLobby.taskProgress = data.data ?? data; return; }
  if (eventName === 'ui:setTasks') { state.tasks = data.data ?? data.tasks ?? data; renderTasks(); return; }
  if (eventName === 'ui:setTaskInfo') { state.taskInfo = data.data ?? data; return; }
  if (eventName === 'ui:setRanks') { state.ranks = data.data ?? data; return; }
  if (eventName === 'ui:setProfilePhoto') { return; }
  if (eventName === 'ui:setDebug') { showApp(true); return; }

  if (data.setTasks || data.setLocale) return applySetup(data);
  if (typeof data.show === 'boolean') return showApp(data.show);
});

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') postNui('nui:hideFrame', true);
});

postNui('nui:loadUI', true);
renderProfile();
renderTasks();
