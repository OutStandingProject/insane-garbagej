/* insane-garbagej UI — lobby members + invite + leave */
const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'nui-resource';
const body = document.body;
const state = { visible: false, tasks: [], userProfile: {}, locale: {}, lobby: [], ranks: [], lobbyLeaderId: null };

function post(name, data) {
  return fetch(`https://${resourceName}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data ?? {})
  }).then(r => r.json().catch(() => ({}))).catch(() => ({}));
}

function ui(key, fallback) { return (state.locale && state.locale[key]) || fallback || key; }

function normalizePayload(raw) {
  if (!raw || typeof raw !== 'object') return { event: null, payload: {} };
  const event = raw.action || raw.type || raw.event || null;
  const payload = raw.data ?? raw.payload ?? raw;
  return { event, payload };
}

/* === Window === */
const win = document.getElementById('appWindow');
function closeWindow() { win.classList.add('win-hidden'); post('nui:hideFrame', true); }
function openWindow()  { win.classList.remove('win-hidden'); }

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
  tick(); setInterval(tick, 10000);
})();

/* === Visibility === */
function setVisible(show) {
  state.visible = !!show;
  body.style.display = state.visible ? 'block' : 'none';
  if (state.visible) openWindow();
}

/* === Profile helpers === */
function profilePercent(extra) {
  const exp  = Number(state.userProfile.exp || 0);
  const next = Number(state.userProfile.nextLevelExp || 0);
  if (!next) return 0;
  return Math.max(0, Math.min(100, ((exp + Number(extra || 0)) / next) * 100));
}

function resolvePlayerName(p) {
  return p.characterName || p.name || 'Sanitation Worker';
}

function applyAvatar(el, src) {
  if (!el) return;
  if (src && typeof src === 'string' && src.length > 0) {
    el.style.backgroundImage = `url('${src}')`;
    el.style.backgroundSize = 'cover';
    el.style.backgroundPosition = 'center top';
  } else {
    el.style.backgroundImage = '';
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
  const imgSrc = p.mugshot || p.photo || null;
  applyAvatar(avatarEl, imgSrc);
  injectSelfIntoLobby();
}

/* Injeta o proprio jogador no slot 0 do lobby enquanto estiver sozinho */
function injectSelfIntoLobby() {
  const p = state.userProfile || {};
  if (!p.source) return;
  /* so injeta se a lobby estiver vazia ou so tiver o proprio */
  const existing = Array.isArray(state.lobby) ? state.lobby : [];
  const hasOthers = existing.some(m => m && !m.isSelf);
  if (hasOthers) return; /* ja ha membros do servidor — nao sobrescreve */
  const selfMember = {
    source:        p.source,
    characterName: resolvePlayerName(p),
    mugshot:       p.mugshot || p.photo || null,
    isLeader:      true,
    isSelf:        true
  };
  state.lobby = [selfMember];
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

/* ============================================================
   INVITE MODAL
   ============================================================ */
(function setupInviteModal() {
  document.body.insertAdjacentHTML('beforeend', `
    <div id="inviteModal">
      <div id="inviteBackdrop"></div>
      <div id="inviteBox" role="dialog" aria-modal="true" aria-labelledby="inviteTitle">
        <button id="inviteCloseBtn" aria-label="Fechar">&#x2715;</button>
        <h3 id="inviteTitle">Convidar para Lobby</h3>
        <p>Insere o ID do jogador que queres convidar.</p>
        <input id="inviteIdInput" type="number" min="1" placeholder="ID do jogador" />
        <button id="inviteSendBtn">Convidar</button>
        <div id="inviteFeedback"></div>
      </div>
    </div>
  `);

  const modal    = document.getElementById('inviteModal');
  const backdrop = document.getElementById('inviteBackdrop');
  const input    = document.getElementById('inviteIdInput');
  const sendBtn  = document.getElementById('inviteSendBtn');
  const closeBtn = document.getElementById('inviteCloseBtn');
  const feedback = document.getElementById('inviteFeedback');

  function openInviteModal() {
    input.value = '';
    feedback.textContent = '';
    feedback.className = '';
    modal.classList.add('open');
    setTimeout(() => input.focus(), 80);
  }
  function closeInviteModal() { modal.classList.remove('open'); }

  function sendInvite() {
    const id = parseInt(input.value, 10);
    if (!id || id < 1) {
      feedback.textContent = 'ID inválido.';
      feedback.className = 'error';
      return;
    }
    feedback.textContent = 'A enviar convite...';
    feedback.className = '';
    post('nui:invitePlayer', { targetId: id })
      .then(res => {
        if (res && res.success === false) {
          feedback.textContent = res.message || 'Erro ao enviar convite.';
          feedback.className = 'error';
        } else {
          feedback.textContent = `Convite enviado para o jogador ${id}!`;
          feedback.className = '';
          setTimeout(() => closeInviteModal(), 1200);
        }
      })
      .catch(() => { feedback.textContent = 'Erro de ligação.'; feedback.className = 'error'; });
  }

  closeBtn.addEventListener('click', closeInviteModal);
  backdrop.addEventListener('click', closeInviteModal);
  sendBtn.addEventListener('click', sendInvite);
  input.addEventListener('keydown', e => {
    if (e.key === 'Enter') sendInvite();
    if (e.key === 'Escape') closeInviteModal();
  });
  window._openInviteModal = openInviteModal;
})();

/* ============================================================
   LEAVE MODAL
   ============================================================ */
(function setupLeaveModal() {
  document.body.insertAdjacentHTML('beforeend', `
    <div id="leaveModal">
      <div id="leaveBackdrop"></div>
      <div id="leaveBox" role="dialog" aria-modal="true" aria-labelledby="leaveTitle">
        <h3 id="leaveTitle">&#x26A0; Sair da Lobby</h3>
        <p>Tens a certeza que queres sair?<br><span style="opacity:.65;font-size:10px;">Os restantes jogadores mantêm-se juntos e um novo líder será promovido.</span></p>
        <div class="leave-btns">
          <button id="leaveCancelBtn">Cancelar</button>
          <button id="leaveConfirmBtn">Sair</button>
        </div>
      </div>
    </div>
  `);

  const modal     = document.getElementById('leaveModal');
  const backdrop  = document.getElementById('leaveBackdrop');
  const cancelBtn = document.getElementById('leaveCancelBtn');
  const confirmBtn= document.getElementById('leaveConfirmBtn');

  function openLeaveModal()  { modal.classList.add('open'); }
  function closeLeaveModal() { modal.classList.remove('open'); }

  function confirmLeave() {
    closeLeaveModal();
    post('nui:leaveLobby', {}).then(() => {
      /* Volta ao estado de lobby solo com o proprio jogador */
      const self = (state.lobby || []).find(m => m && m.isSelf);
      state.lobby = self ? [{ ...self, isLeader: true }] : [];
      state.lobbyLeaderId = null;
      renderLobby(state.lobby);
    });
  }

  cancelBtn.addEventListener('click', closeLeaveModal);
  backdrop.addEventListener('click', closeLeaveModal);
  confirmBtn.addEventListener('click', confirmLeave);
  window._openLeaveModal = openLeaveModal;
})();

/* ============================================================
   LOBBY RENDER — max 4 slots
   slot 0 = sempre o proprio jogador
   slots preenchidos = avatar (mugshot/photo) + nome + coroa se lider
   slots vazios = botao +
   Botao sair aparece so com >= 2 membros
   ============================================================ */
function renderLobby(members) {
  const slots = document.getElementById('lobbySlots');
  const leaveBtn = document.getElementById('lobbyLeaveBtn');
  if (!slots) return;

  const list = Array.isArray(members) ? members.filter(Boolean) : [];
  const MAX  = 4;

  /* Controla visibilidade do botao sair */
  if (leaveBtn) {
    leaveBtn.style.display = list.length > 1 ? 'flex' : 'none';
  }

  slots.innerHTML = '';

  for (let i = 0; i < MAX; i++) {
    const m    = list[i] || null;
    const slot = document.createElement('div');
    slot.className = 'lobby-slot ' + (m ? 'filled' : 'empty');

    if (m) {
      /* ── Slot preenchido ── */
      const avatarDiv = document.createElement('div');
      avatarDiv.className = 'slot-avatar';

      const imgSrc = m.mugshot || m.photo || null;
      if (imgSrc) {
        avatarDiv.style.backgroundImage  = `url('${imgSrc}')`;
        avatarDiv.style.backgroundSize   = 'cover';
        avatarDiv.style.backgroundPosition = 'center top';
      }

      /* Badge "Eu" */
      if (m.isSelf) {
        const badge = document.createElement('span');
        badge.className   = 'slot-self-badge';
        badge.textContent = 'Eu';
        avatarDiv.appendChild(badge);
      }

      /* Coroa do lider — aparece por cima do slot */
      if (m.isLeader) {
        const crown = document.createElement('span');
        crown.className   = 'slot-crown';
        crown.innerHTML   = '&#x1F451;';
        slot.appendChild(crown);
      }

      const nameDiv = document.createElement('div');
      nameDiv.className   = 'slot-name';
      nameDiv.textContent = m.characterName || m.name || '';

      slot.appendChild(avatarDiv);
      slot.appendChild(nameDiv);
    } else {
      /* ── Slot vazio — botao + ── */
      const avatarDiv = document.createElement('div');
      avatarDiv.className = 'slot-avatar';

      const plusBtn = document.createElement('button');
      plusBtn.className = 'slot-invite-btn';
      plusBtn.setAttribute('aria-label', 'Convidar jogador');
      plusBtn.setAttribute('title', 'Convidar jogador');
      plusBtn.textContent = '+';
      plusBtn.addEventListener('click', () => {
        if (typeof window._openInviteModal === 'function') window._openInviteModal();
      });

      avatarDiv.appendChild(plusBtn);
      slot.appendChild(avatarDiv);
    }

    slots.appendChild(slot);
  }
}

/* ============================================================
   BOTAO SAIR — ligado ao elemento HTML
   ============================================================ */
(function setupLeaveButton() {
  const btn = document.getElementById('lobbyLeaveBtn');
  if (!btn) return;
  btn.style.display = 'none';
  btn.addEventListener('click', () => {
    if (typeof window._openLeaveModal === 'function') window._openLeaveModal();
  });
})();

/* ============================================================
   NUI CALLBACK — sair da lobby
   ============================================================ */
post('nui:registerCallbacks', {});

/* ============================================================
   NORMALIZAR MEMBROS vindos do servidor
   ============================================================ */
function applyLobbyData(rawMembers, leaderId) {
  const selfSource = state.userProfile && state.userProfile.source;
  const leader     = leaderId || state.lobbyLeaderId || (rawMembers[0] && rawMembers[0].source);
  if (leaderId) state.lobbyLeaderId = leaderId;

  const normalized = rawMembers.map(m => ({
    ...m,
    isLeader: m.source === leader || !!m.isLeader,
    isSelf:   m.source === selfSource  || !!m.isSelf,
  }));

  /* Garante que o proprio jogador esta sempre no slot 0 */
  const selfIdx = normalized.findIndex(m => m.isSelf);
  if (selfIdx > 0) {
    const [self] = normalized.splice(selfIdx, 1);
    normalized.unshift(self);
  } else if (selfIdx === -1 && selfSource) {
    /* O servidor nao enviou o proprio — injeta a partir do perfil */
    const selfFallback = {
      source:        selfSource,
      characterName: resolvePlayerName(state.userProfile),
      mugshot:       state.userProfile.mugshot || state.userProfile.photo || null,
      isLeader:      selfSource === leader,
      isSelf:        true,
    };
    normalized.unshift(selfFallback);
  }

  state.lobby = normalized;
  renderLobby(state.lobby);
}

/* === TOP 3 RANKS === */
const RANK_MEDALS = ['&#x1F947;','&#x1F948;','&#x1F949;'];
function renderRanks(ranks) {
  const list = document.getElementById('rankList');
  if (!list) return;
  const top = (Array.isArray(ranks) ? ranks : []).slice(0, 3);
  list.innerHTML = '';
  for (let i = 0; i < 3; i++) {
    const r    = top[i];
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

  /* Formato legado (React build antigo) */
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

    case 'ui:setPlayerMugshot': {
      const url = typeof payload === 'string' ? payload : '';
      if (url.length > 0) {
        state.userProfile.mugshot = url;
        const avatarEl = document.querySelector('.avatar');
        applyAvatar(avatarEl, url);
        /* Atualiza o mugshot do proprio no lobby se ja la estiver */
        const selfInLobby = state.lobby.find(m => m && m.isSelf);
        if (selfInLobby) { selfInLobby.mugshot = url; renderLobby(state.lobby); }
      }
      return;
    }

    case 'ui:setTasks':
      state.tasks = Array.isArray(payload) ? payload : Object.values(payload || {});
      renderTasks();
      return;

    case 'ui:setDebug':
      setVisible(true);
      return;

    /* --- LOBBY COMPLETO (enviado ao entrar numa lobby ou ao iniciar tarefa) --- */
    case 'ui:setCurrentLobby': {
      /* payload vazio = jogador saiu, fica sozinho */
      if (!payload || (typeof payload === 'object' && !Array.isArray(payload) && Object.keys(payload).length === 0)) {
        const self = state.lobby.find(m => m && m.isSelf);
        state.lobby = self ? [{ ...self, isLeader: true }] : [];
        state.lobbyLeaderId = null;
        renderLobby(state.lobby);
        return;
      }
      const members  = Array.isArray(payload) ? payload : (Array.isArray(payload.members) ? payload.members : []);
      const leaderId = payload.leaderId ?? null;
      applyLobbyData(members, leaderId);
      return;
    }

    /* --- MEMBROS ATUALIZADOS (alguem entrou ou saiu) --- */
    case 'ui:setLobbyMembers': {
      const members  = Array.isArray(payload) ? payload : (Array.isArray(payload.members) ? payload.members : []);
      const leaderId = payload.leaderId ?? null;
      applyLobbyData(members, leaderId);
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

/* === NUI Callback — leaveLobby === */
window.addEventListener('message', ev => {
  /* handler separado para nao interferir com o switch principal */
});

/* === Keyboard === */
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeWindow(); });

/* === Init === */
renderProfile();
renderTasks();
renderLobby([]);
renderRanks([]);
post('nui:loadUI', true);
