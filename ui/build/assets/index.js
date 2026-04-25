const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'nui-resource';
const body = document.body;
const state = { visible: false, tasks: [], userProfile: {}, locale: {}, lobby: [], ranks: [] };

function post(name, data){
  return fetch(`https://${resourceName}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data ?? {})
  }).then(r => r.json().catch(() => ({}))).catch(() => ({}));
}

function ui(key, fallback){ return (state.locale && state.locale[key]) || fallback || key; }

function normalizePayload(raw){
  if (!raw || typeof raw !== 'object') return { event: null, payload: {} };
  const event = raw.action || raw.type || raw.event || null;
  const payload = raw.data ?? raw.payload ?? raw;
  return { event, payload };
}

/* === Window State === */
const win = document.getElementById('appWindow');

function closeWindow() {
  win.classList.add('win-hidden');
  post('nui:hideFrame', true);
}

function openWindow() {
  win.classList.remove('win-hidden');
}

const btnRed = document.getElementById('btnRed');
if (btnRed) btnRed.addEventListener('click', e => { e.stopPropagation(); closeWindow(); });

/* === Clock === */
(function clock() {
  const el = document.getElementById('mbClock');
  if (!el) return;
  function tick() {
    const d = new Date();
    el.textContent = d.getHours().toString().padStart(2,'0') + ':' + d.getMinutes().toString().padStart(2,'0');
  }
  tick();
  setInterval(tick, 10000);
})();

/* === Visibility === */
function setVisible(show) {
  state.visible = !!show;
  body.style.display = state.visible ? 'block' : 'none';
  if (state.visible) openWindow();
}

/* === Profile & Tasks === */
function profilePercent(extra) {
  const exp  = Number(state.userProfile.exp || 0);
  const next = Number(state.userProfile.nextLevelExp || 0);
  if (!next) return 0;
  return Math.max(0, Math.min(100, ((exp + Number(extra || 0)) / next) * 100));
}

function renderProfile() {
  const p = state.userProfile || {};
  const el = id => document.getElementById(id);
  el('workerName').textContent   = p.name     || ui('victor_goods', 'Victor Goods');
  el('workerJob').textContent    = p.jobLabel || p.job || 'Sanitation Worker';
  el('repLabel').textContent     = ui('reputation', 'Reputation');
  el('repText').textContent      = `${Number(p.exp || 1200).toLocaleString()} / ${Number(p.nextLevelExp || 1800).toLocaleString()} XP`;
  el('repFill').style.width      = `${profilePercent()}%`;
  el('levelPill').textContent    = `Level ${Number(p.level || 1)}`;
  el('mapsLabel').textContent    = ui('maps', 'Maps');
  el('titleLabel').textContent   = ui('title', 'Title');
  el('levelLabel').textContent   = ui('level', 'Level');
  el('rewardsLabel').textContent = ui('rewards', 'Rewards');
  el('repColLabel').textContent  = ui('rep', 'Rep');
  el('gpsLabel').textContent     = ui('gps', 'GPS');
  el('lobbyLabel').textContent   = ui('lobby', 'Lobby');
  el('rankLabel').textContent    = ui('top_reputation', 'Top Reputation');
  if (p.photo) document.querySelector('.avatar').style.backgroundImage = `url('${p.photo}')`;
}

function normalizeTasks(tasks) {
  const arr = Array.isArray(tasks) ? tasks : Object.values(tasks || {});
  return arr.map((t, i) => ({
    unique_id:  t.unique_id ?? t.id ?? i + 1,
    title:      t.title ?? `Task #${i + 1}`,
    max_client: Number(t.max_client ?? 2),
    level:      Number(t.level ?? 1),
    fee:        Number(t.fee ?? 0),
    exp:        Number(t.exp ?? 0)
  }));
}

function renderTasks() {
  const rows = document.getElementById('rows');
  rows.innerHTML = '';
  normalizeTasks(state.tasks).forEach(task => {
    const row = document.createElement('div');
    row.className = 'row';
    row.innerHTML = `
      <div class="mapbox"></div>
      <div class="row-title">${task.title} [1-${task.max_client}] <span class="team-icon">&#x1F465;</span></div>
      <div class="lvl">${task.level}</div>
      <div class="reward">${ui('money_type','$')}${task.fee.toLocaleString()}</div>
      <div class="rep-col"><div class="reptrack"><div class="repfill" style="width:${profilePercent(task.exp)}%"></div></div></div>
      <button class="gps" aria-label="Start task GPS">&#x25BA;</button>
    `;
    row.querySelector('.gps').addEventListener('click', () => post('nui:startLobbyWithTask', task.unique_id));
    rows.appendChild(row);
  });
}

/* === LOBBY ===
   Espera array de membros: [{name, photo, isLeader}, ...] máx 4
   Ou número (apenas count de jogadores online no lobby) */
function renderLobby(members) {
  const slots = document.getElementById('lobbySlots');
  if (!slots) return;
  const list = Array.isArray(members) ? members : [];
  const MAX = 4;
  slots.innerHTML = '';
  for (let i = 0; i < MAX; i++) {
    const m = list[i];
    const slot = document.createElement('div');
    slot.className = 'lobby-slot' + (m ? ' filled' : ' empty');
    if (m) {
      const crown = m.isLeader ? '<span class="slot-crown">&#x1F451;</span>' : '';
      const photo = m.photo ? `url('${m.photo}')` : '';
      slot.innerHTML = `
        ${crown}
        <div class="slot-avatar" ${photo ? `style="background-image:${photo}"` : ''}></div>
        <div class="slot-name">${m.name || ''}</div>
      `;
    } else {
      slot.innerHTML = '<div class="slot-avatar"></div>';
    }
    slots.appendChild(slot);
  }
}

/* === TOP 3 RANKS ===
   Espera array: [{name, exp, photo}, ...] ordenado por exp desc */
const RANK_MEDALS = ['&#x1F947;','&#x1F948;','&#x1F949;'];

function renderRanks(ranks) {
  const list = document.getElementById('rankList');
  if (!list) return;
  const top = (Array.isArray(ranks) ? ranks : []).slice(0, 3);
  list.innerHTML = '';
  for (let i = 0; i < 3; i++) {
    const r = top[i];
    const item = document.createElement('div');
    item.className = `rank-item rank-${i+1}`;
    item.innerHTML = `
      <span class="rank-pos">${RANK_MEDALS[i]}</span>
      <span class="rank-name">${r ? r.name : '—'}</span>
      <span class="rank-xp">${r ? Number(r.exp || 0).toLocaleString() + ' XP' : '0 XP'}</span>
    `;
    list.appendChild(item);
  }
}

/* === Message Handler === */
window.addEventListener('message', (ev) => {
  const raw = ev.data || {};
  const { event, payload } = normalizePayload(raw);

  if (raw.setLocale || raw.setTasks) {
    state.locale = (raw.setLocale && (raw.setLocale.ui || raw.setLocale)) || state.locale;
    state.tasks  = raw.setTasks || state.tasks;
    renderProfile(); renderTasks();
    post('nui:onLoadUI', true);
    return;
  }

  switch (event) {
    case 'ui:setupUI':
      state.locale = (payload.setLocale && (payload.setLocale.ui || payload.setLocale)) || state.locale;
      state.tasks  = payload.setTasks || state.tasks;
      renderProfile(); renderTasks();
      post('nui:onLoadUI', true);
      return;
    case 'ui:setVisible':
      if (typeof payload === 'boolean')       setVisible(payload);
      else if (typeof raw.show === 'boolean') setVisible(raw.show);
      else if (typeof payload === 'string')   setVisible(payload === 'true' || payload === '1');
      return;
    case 'ui:setPage':
      if (typeof payload === 'string')
        setVisible(payload === 'garbage' || payload === 'delivery' || payload === 'towtruck');
      else if (typeof raw.page === 'string')
        setVisible(raw.page === 'garbage' || raw.page === 'delivery' || raw.page === 'towtruck');
      else if (typeof raw.show === 'boolean')
        setVisible(raw.show);
      return;
    case 'ui:setUserProfile': state.userProfile = payload; renderProfile(); return;
    case 'ui:setTasks':       state.tasks = payload; renderTasks(); return;
    case 'ui:setDebug':       setVisible(true); return;
    case 'ui:setCurrentLobby':
    case 'ui:setLobbyMembers':
      state.lobby = Array.isArray(payload) ? payload : (payload.members || []);
      renderLobby(state.lobby);
      return;
    case 'ui:setRanks':
      state.ranks = Array.isArray(payload) ? payload : (payload.ranks || []);
      renderRanks(state.ranks);
      return;
    case 'ui:setTaskInfo':
    case 'ui:setTaskProgress':
    case 'ui:setProfilePhoto':
      return;
  }
  if (typeof raw.show === 'boolean') setVisible(raw.show);
});

/* === Keyboard === */
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeWindow(); });

/* === Init === */
renderProfile();
renderTasks();
renderLobby([]);
renderRanks([]);
post('nui:loadUI', true);
