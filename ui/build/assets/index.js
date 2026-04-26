/* insane-garbagej UI v3 - tasks fix + mugshot nativo GTA V */
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

function resolvePlayerName(p) {
  return p.characterName || p.name || 'Sanitation Worker';
}

/* Resolve mugshot para CSS.
   txdString do GTA V nativo → img://txdString
   URL http(s) → url('https://...') */
function resolveAvatarCSS(p) {
  const mugshot = p.mugshot || p.photo || null;
  if (!mugshot || typeof mugshot !== 'string' || mugshot.length === 0) return '';
  if (mugshot.startsWith('http')) return `url('${mugshot}')`;
  return `url('img://${mugshot}')`;
}

function applyAvatarToElement(el, p) {
  if (!el) return;
  const css = resolveAvatarCSS(p);
  if (css) {
    el.style.backgroundImage = css;
    el.style.backgroundSize = 'cover';
    el.style.backgroundPosition = 'center top';
  } else {
    el.style.backgroundImage = '';
  }
}

/* Tenta re-aplicar o mugshot com pequeno delay para garantir
   que o txd do GTA V já está pronto na NUI */
function applyMugshotWithRetry(el, p, attempts) {
  if (!el) return;
  const tries = attempts || 0;
  const css = resolveAvatarCSS(p);
  if (css) {
    el.style.backgroundImage = css;
    el.style.backgroundSize = 'cover';
    el.style.backgroundPosition = 'center top';
  } else if (tries < 10) {
    setTimeout(() => applyMugshotWithRetry(el, p, tries + 1), 300);
  }
}

function renderProfile() {
  const p = state.userProfile || {};
  const $ = id => document.getElementById(id);

  const nameEl = $('workerName'); if (nameEl) nameEl.textContent = resolvePlayerName(p);
  const jobEl  = $('workerJob');  if (jobEl)  jobEl.textContent  = p.jobLabel || p.job || 'Sanitation Worker';
  const repLbl = $('repLabel');   if (repLbl) repLbl.textContent = ui('reputation', 'Reputation');
  const repTxt = $('repText');    if (repTxt) repTxt.textContent = `${Number(p.exp || 0).toLocaleString()} / ${Number(p.nextLevelExp || 0).toLocaleString()} XP`;
  const repFil = $('repFill');    if (repFil) repFil.style.width = `${profilePercent()}%`;
  const lvlPil = $('levelPill'); if (lvlPil) lvlPil.textContent = `Level ${Number(p.level || 1)}`;
  const mL = $('mapsLabel');    if (mL) mL.textContent    = ui('maps', 'Maps');
  const tL = $('titleLabel');   if (tL) tL.textContent   = ui('title', 'Title');
  const lL = $('levelLabel');   if (lL) lL.textContent   = ui('level', 'Level');
  const rL = $('rewardsLabel'); if (rL) rL.textContent   = ui('rewards', 'Rewards');
  const rC = $('repColLabel'); if (rC) rC.textContent   = ui('rep', 'Rep');
  const gL = $('gpsLabel');    if (gL) gL.textContent   = ui('gps', 'GPS');
  const lbL = $('lobbyLabel'); if (lbL) lbL.textContent = ui('lobby', 'Lobby');
  const rkL = $('rankLabel');  if (rkL) rkL.textContent = ui('top_reputation', 'Top Reputation');

  const avatarEl = document.querySelector('.avatar');
  applyMugshotWithRetry(avatarEl, p, 0);
  injectSelfIntoLobby();
}

/* Injeta o proprio jogador no primeiro slot do lobby */
function injectSelfIntoLobby() {
  const p = state.userProfile || {};
  if (!p.source) return;
  const selfMember = {
    source:        p.source,
    characterName: resolvePlayerName(p),
    mugshot:       p.mugshot || p.photo || null,
    isLeader:      true,
    isSelf:        true
  };
  const currentLobby = Array.isArray(state.lobby) ? state.lobby : [];
  const withoutSelf  = currentLobby.filter(m => m && !m.isSelf);
  state.lobby = [selfMember, ...withoutSelf];
  renderLobby(state.lobby);
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
  if (!rows) return;
  rows.innerHTML = '';
  const tasks = normalizeTasks(state.tasks);
  if (tasks.length === 0) {
    rows.innerHTML = '<div style="padding:24px;color:#666;text-align:center;">Sem tarefas disponíveis</div>';
    return;
  }
  tasks.forEach(task => {
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
   Slot 0 = sempre o proprio jogador.
   Restantes slots = outros membros recebidos do servidor. */
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
      const imgSrc = m.mugshot || m.photo || null;
      let bgStyle = '';
      if (imgSrc) {
        const cssUrl = (typeof imgSrc === 'string' && !imgSrc.startsWith('http'))
          ? `img://${imgSrc}`
          : imgSrc;
        bgStyle = `style="background-image:url('${cssUrl}');background-size:cover;background-position:center top;"`;
      }
      const displayName = m.characterName || m.name || '';
      slot.innerHTML = `${crown}<div class="slot-avatar" ${bgStyle}></div><div class="slot-name">${displayName}</div>`;
    } else {
      slot.innerHTML = '<div class="slot-avatar"></div>';
    }
    slots.appendChild(slot);
  }
}

/* === TOP 3 RANKS === */
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
    const rankName = r ? (r.characterName || r.name || '—') : '—';
    item.innerHTML = `<span class="rank-pos">${RANK_MEDALS[i]}</span><span class="rank-name">${rankName}</span><span class="rank-xp">${r ? Number(r.exp || 0).toLocaleString() + ' XP' : '0 XP'}</span>`;
    list.appendChild(item);
  }
}

/* === Message Handler === */
window.addEventListener('message', (ev) => {
  const raw = ev.data || {};
  const { event, payload } = normalizePayload(raw);

  /* Formato legado: { setLocale, setTasks } direto no raw */
  if (raw.setLocale || raw.setTasks) {
    if (raw.setLocale) state.locale = raw.setLocale.ui || raw.setLocale;
    if (raw.setTasks)  state.tasks  = raw.setTasks;
    renderProfile(); renderTasks();
    post('nui:onLoadUI', true);
    return;
  }

  switch (event) {
    case 'ui:setupUI':
      if (payload.setLocale) state.locale = payload.setLocale.ui || payload.setLocale;
      if (payload.setTasks)  state.tasks  = payload.setTasks;
      renderProfile(); renderTasks();
      post('nui:onLoadUI', true);
      return;

    /* openMenu envia este evento com tasks + profile + mugshot tudo junto */
    case 'ui:openMenu': {
      if (payload.setLocale) state.locale = payload.setLocale.ui || payload.setLocale;
      if (payload.setTasks)  state.tasks  = payload.setTasks;
      if (payload.profile)   state.userProfile = payload.profile;
      renderProfile();
      renderTasks();
      setVisible(true);
      return;
    }

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

    case 'ui:setUserProfile':
      state.userProfile = payload;
      renderProfile();
      return;

    case 'ui:setPlayerMugshot':
      if (typeof payload === 'string' && payload.length > 0) {
        state.userProfile.mugshot = payload;
        const avatarEl = document.querySelector('.avatar');
        applyMugshotWithRetry(avatarEl, state.userProfile, 0);
        injectSelfIntoLobby();
      }
      return;

    case 'ui:setTasks':
      state.tasks = Array.isArray(payload) ? payload : Object.values(payload || {});
      renderTasks();
      return;

    case 'ui:setDebug':
      setVisible(true);
      return;

    case 'ui:setCurrentLobby':
    case 'ui:setLobbyMembers': {
      const incoming = Array.isArray(payload) ? payload : (payload.members || []);
      const selfMember = (state.lobby || []).find(m => m && m.isSelf);
      state.lobby = selfMember ? [selfMember, ...incoming.filter(m => m && !m.isSelf)] : incoming;
      renderLobby(state.lobby);
      return;
    }

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
