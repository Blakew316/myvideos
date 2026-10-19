/* My Videos for iPhone — a companion to My Videos on the Mac. */
(() => {
  'use strict';

  // ---------------------------------------------------------------- Utilities

  const $ = (sel, root = document) => root.querySelector(sel);
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const store = {
    get(key) { try { return localStorage.getItem('mv.' + key); } catch { return null; } },
    set(key, value) { try { value == null ? localStorage.removeItem('mv.' + key) : localStorage.setItem('mv.' + key, value); } catch {} },
  };
  const isStandalone = () => window.navigator.standalone === true || matchMedia('(display-mode: standalone)').matches;
  const isLink = (s) => /^https?:\/\/[^\s/]+\.[^\s]+/i.test((s || '').trim());

  function fmtDuration(sec) {
    sec = Math.round(sec || 0);
    if (!sec) return '';
    const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
    return h ? `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}` : `${m}:${String(s).padStart(2, '0')}`;
  }
  function fmtBytes(n) {
    if (!n) return '';
    const units = ['bytes', 'KB', 'MB', 'GB', 'TB'];
    let i = 0;
    while (n >= 1000 && i < units.length - 1) { n /= 1000; i++; }
    return `${n >= 100 || i === 0 ? Math.round(n) : n.toFixed(1)} ${units[i]}`;
  }
  const rtf = new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' });
  function relTime(iso) {
    if (!iso) return 'never';
    const diff = (new Date(iso) - Date.now()) / 1000;
    const steps = [[60, 'second'], [3600, 'minute'], [86400, 'hour'], [604800, 'day'], [2629800, 'week'], [31557600, 'month'], [Infinity, 'year']];
    const div = [1, 60, 3600, 86400, 604800, 2629800, 31557600];
    for (let i = 0; i < steps.length; i++) {
      if (Math.abs(diff) < steps[i][0]) return rtf.format(Math.round(diff / div[i]), steps[i][1]);
    }
    return '';
  }
  function dayBucket(iso) {
    const d = new Date(iso), now = new Date();
    const start = (x) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
    const days = Math.round((start(now) - start(d)) / 86400000);
    if (days <= 0) return 'Today';
    if (days === 1) return 'Yesterday';
    if (days < 7) return 'This Week';
    if (days < 31) return 'This Month';
    return 'Earlier';
  }

  // ---------------------------------------------------------------- Icons
  // Line icons in the spirit of SF Symbols (24pt grid). Entries starting with "F:" are filled.

  const ICONS = {
    download: ['M12 2.75a9.25 9.25 0 1 0 0 18.5 9.25 9.25 0 0 0 0-18.5Z', 'M12 7.25v9M8.25 12.75 12 16.5l3.75-3.75'],
    queue: ['M9 6.5h11M9 12h11M9 17.5h11', 'M4.75 6.5h.01M4.75 12h.01M4.75 17.5h.01'],
    library: ['M3.75 7.75a2.5 2.5 0 0 1 2.5-2.5h11.5a2.5 2.5 0 0 1 2.5 2.5v8.5a2.5 2.5 0 0 1-2.5 2.5H6.25a2.5 2.5 0 0 1-2.5-2.5Z', 'F:M10.25 9.25v5.5l4.75-2.75Z'],
    antenna: ['M12 12h.01', 'M8.6 8.6a4.8 4.8 0 0 0 0 6.8M15.4 8.6a4.8 4.8 0 0 1 0 6.8M5.6 5.6a9 9 0 0 0 0 12.8M18.4 5.6a9 9 0 0 1 0 12.8'],
    gear: ['M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z', 'M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1Z'],
    back: ['M15 18.5 8.5 12 15 5.5'],
    chevron: ['M9.5 6l6 6-6 6'],
    updown: ['M8 9.5 12 5.5l4 4M8 14.5l4 4 4-4'],
    plus: ['M12 5v14M5 12h14'],
    play: ['F:M8 5.2v13.6a.8.8 0 0 0 1.2.7l10.6-6.8a.8.8 0 0 0 0-1.4L9.2 4.5a.8.8 0 0 0-1.2.7Z'],
    pause: ['F:M7 5h3.25v14H7ZM13.75 5H17v14h-3.25Z'],
    xmark: ['M17.5 6.5l-11 11M6.5 6.5l11 11'],
    retry: ['M19.5 12a7.5 7.5 0 1 1-2.2-5.3', 'M19.5 4.5v4.25h-4.25'],
    share: ['M12 3.5v11.5M8 7.25l4-3.75 4 3.75', 'M7 10.5H6a1.5 1.5 0 0 0-1.5 1.5v7A1.5 1.5 0 0 0 6 20.5h12a1.5 1.5 0 0 0 1.5-1.5v-7a1.5 1.5 0 0 0-1.5-1.5h-1'],
    paste: ['M9 3.75h6v3H9Z', 'M9 5.25H6.75a1.5 1.5 0 0 0-1.5 1.5v12.5a1.5 1.5 0 0 0 1.5 1.5h10.5a1.5 1.5 0 0 0 1.5-1.5V6.75a1.5 1.5 0 0 0-1.5-1.5H15'],
    link: ['M10 13.5a4 4 0 0 0 5.66 0l3-3a4 4 0 1 0-5.66-5.66l-1.5 1.46', 'M14 10.5a4 4 0 0 0-5.66 0l-3 3a4 4 0 1 0 5.66 5.66l1.5-1.46'],
    search: ['M10.75 17.5a6.75 6.75 0 1 0 0-13.5 6.75 6.75 0 0 0 0 13.5ZM20 20l-4.4-4.4'],
    music: ['M9 18V5.75l10.5-2V16', 'M9 18a3 3 0 1 1-3-3 3 3 0 0 1 3 3ZM19.5 16a3 3 0 1 1-3-3 3 3 0 0 1 3 3Z'],
    film: ['M4.5 5.5h15v13h-15Z', 'M8.25 5.5v13M15.75 5.5v13M4.5 9.75h3.75M4.5 14.25h3.75M15.75 9.75h3.75M15.75 14.25h3.75'],
    check: ['M5 12.5l4.5 4.5L19 7.5'],
    checkCircle: ['F:M12 2.5a9.5 9.5 0 1 0 0 19 9.5 9.5 0 0 0 0-19Zm4.53 6.97a.75.75 0 0 1 0 1.06l-5 5a.75.75 0 0 1-1.06 0l-2.5-2.5a.75.75 0 1 1 1.06-1.06l1.97 1.97 4.47-4.47a.75.75 0 0 1 1.06 0Z'],
    trash: ['M4.5 7h15M10 11v6M14 11v6', 'M6 7l.9 12.1A1.5 1.5 0 0 0 8.4 20.5h7.2a1.5 1.5 0 0 0 1.5-1.4L18 7M9.25 7V4.75h5.5V7'],
    wifiOff: ['M3.5 3.5l17 17', 'M8.5 16.25a5 5 0 0 1 6.2-.6M5.25 12.75a9.6 9.6 0 0 1 3.9-2.2M18.75 12.75a9.6 9.6 0 0 0-2-1.5M2 9.25a14.6 14.6 0 0 1 4.6-3M22 9.25A14.6 14.6 0 0 0 10.6 5M12 19.75h.01'],
    sparkles: ['M11 3.5l1.7 4.8 4.8 1.7-4.8 1.7L11 16.5l-1.7-4.8L4.5 10l4.8-1.7Z', 'M18 14.5l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8Z'],
    globe: ['M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z', 'M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18'],
    laptop: ['M4.5 6.5A1.5 1.5 0 0 1 6 5h12a1.5 1.5 0 0 1 1.5 1.5V16h-15Z', 'M2.5 19h19'],
    upgrade: ['M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z', 'M12 16V8.5M8.5 12 12 8.5l3.5 3.5'],
    captions: ['M4 6h16v12H4Z', 'M10.5 10.25a2 2 0 1 0 0 3.5M16.5 10.25a2 2 0 1 0 0 3.5'],
    forward: ['M4.5 6.5v11l7-5.5ZM12.5 6.5v11l7-5.5Z'],
    speaker: ['M4 9.5h3.5l4.5-4v13l-4.5-4H4Z', 'M15.5 9a4 4 0 0 1 0 6M18.25 6.5a7.5 7.5 0 0 1 0 11'],
    quote: ['M6.5 17c2 0 3.5-1.5 3.5-3.5V7.5H5V13h3M16.5 17c2 0 3.5-1.5 3.5-3.5V7.5H15V13h3'],
    photo: ['M4 5h16v14H4Z', 'M4 15.5l4.5-4.5 5 5M13.5 13.5l2-2 4.5 4.5M15.75 8.75h.01'],
    waveform: ['M4 12h.01M8 8.5v7M12 5v14M16 9v6M20 11v2'],
    bolt: ['M13.5 2.5 5 13.5h6.5l-1 8 8.5-11H12.5Z'],
    bookmark: ['M7 3.5h10v17l-5-3.75-5 3.75Z'],
    ellipsis: ['M6 12h.01M12 12h.01M18 12h.01'],
    exclaim: ['M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z', 'M12 7.5v5.5M12 16.5h.01'],
    folder: ['M3.5 7a2 2 0 0 1 2-2h4l2 2.5h7a2 2 0 0 1 2 2V17a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2Z'],
    clock: ['M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z', 'M12 7v5l3.5 2'],
  };

  function icon(name, extra = '') {
    const paths = (ICONS[name] || []).map((d) => d.startsWith('F:')
      ? `<path d="${d.slice(2)}" fill="currentColor" stroke="none"/>`
      : `<path d="${d}"/>`).join('');
    return `<svg class="sym ${extra}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths}</svg>`;
  }

  // ---------------------------------------------------------------- State & API

  const state = {
    token: store.get('token'),
    mac: store.get('mac') || 'your Mac',
    online: true,
    jobs: [],
    pending: 0,
    paused: 0,
    history: null,
    subs: null,
    checking: [],
    settings: null,
    tab: 'download',
    composer: { url: '', preview: null, loading: false, error: '', format: 'video', quality: '', playlist: false },
    library: { filter: 'all', query: '' },
    saves: {},   // history id → { progress, file, error }
  };

  async function api(path, { method = 'GET', body } = {}) {
    let res;
    try {
      res = await fetch(path, {
        method,
        cache: 'no-store',
        headers: { Authorization: 'Bearer ' + (state.token || ''), ...(body ? { 'Content-Type': 'application/json' } : {}) },
        body: body ? JSON.stringify(body) : undefined,
      });
    } catch (e) {
      setOnline(false);
      throw new Error(`Can’t reach ${state.mac}.`);
    }
    setOnline(true);
    const data = await res.json().catch(() => ({}));
    if (res.status === 401 && path !== '/api/pair') { disconnect(); throw new Error('Not connected'); }
    if (!res.ok) throw new Error(data.error || 'Something went wrong.');
    return data;
  }

  const mediaURL = (id, index, download) => `/media/${id}/${index}?t=${encodeURIComponent(state.token)}${download ? '&download=1' : ''}`;

  function setOnline(online) {
    if (state.online === online) return;
    state.online = online;
    renderOfflineBanner();
  }

  // ---------------------------------------------------------------- Navigation

  const TABS = [
    { id: 'download', title: 'Download', icon: 'download' },
    { id: 'queue', title: 'Queue', icon: 'queue' },
    { id: 'library', title: 'Library', icon: 'library' },
    { id: 'subs', title: 'Subscriptions', icon: 'antenna' },
    { id: 'settings', title: 'Settings', icon: 'gear' },
  ];
  const stacks = {};
  let app;

  function buildShell() {
    app.innerHTML = TABS.map((t) => `<div class="tab-screen" data-tab="${t.id}"></div>`).join('') +
      `<nav class="tabbar ui" role="tablist">${TABS.map((t) => `
        <button class="tab" role="tab" data-act="tab" data-tab="${t.id}" aria-label="${t.title}">
          ${icon(t.icon)}<span>${t.title}</span><span class="badge" hidden></span>
        </button>`).join('')}</nav>`;
    for (const t of TABS) {
      stacks[t.id] = [];
      push(t.id, ROOTS[t.id](), true);
    }
    switchTab(state.tab);
  }

  function pageHTML(def, isRoot) {
    const back = isRoot ? '' : `<button class="nav-btn back" data-act="back">${icon('back')}<span>${esc(def.backTitle || 'Back')}</span></button>`;
    return `
      <div class="nav ${def.largeTitle === false && !def.hero ? 'always' : ''}">
        <div class="left">${back}${def.navLeft ? def.navLeft() : ''}</div>
        <div class="title">${esc(def.title)}</div>
        <div class="right">${def.navRight ? def.navRight() : ''}</div>
      </div>
      <div class="content">
        ${def.largeTitle === false || def.hero ? '' : `<div class="large-title">${esc(def.title)}</div>`}
        <div class="body">${def.render()}</div>
      </div>`;
  }

  function push(tab, def, isRoot = false) {
    const screen = $(`.tab-screen[data-tab="${tab}"]`);
    const stack = stacks[tab];
    const el = document.createElement('section');
    el.className = 'page' + (isRoot ? '' : ' offscreen');
    el.innerHTML = pageHTML(def, isRoot);
    el.addEventListener('scroll', () => {
      const nav = el.querySelector('.nav');
      nav.classList.toggle('scrolled', el.scrollTop > (def.hero ? 150 : def.largeTitle === false ? 2 : 40));
    }, { passive: true });
    screen.appendChild(el);
    const entry = { def, el };
    stack.push(entry);
    def.mount?.(el);
    if (!isRoot) {
      const below = stack[stack.length - 2];
      requestAnimationFrame(() => requestAnimationFrame(() => {
        el.classList.remove('offscreen');
        below.el.classList.add('below');
      }));
      attachSwipeBack(tab, entry);
    }
    return entry;
  }

  function pop(tab) {
    const stack = stacks[tab];
    if (stack.length < 2) return;
    const top = stack.pop();
    const below = stack[stack.length - 1];
    top.el.classList.add('offscreen');
    below.el.classList.remove('below');
    top.def.unmount?.();
    setTimeout(() => top.el.remove(), 420);
    below.def.refresh?.(below.el);
  }

  /** Drag from the left edge to go back, as in every iOS app. */
  function attachSwipeBack(tab, entry) {
    const el = entry.el;
    let startX = 0, startY = 0, dx = 0, tracking = false, decided = false;
    el.addEventListener('touchstart', (e) => {
      const t = e.touches[0];
      if (t.clientX > 28) return;
      tracking = true; decided = false; startX = t.clientX; startY = t.clientY; dx = 0;
    }, { passive: true });
    el.addEventListener('touchmove', (e) => {
      if (!tracking) return;
      const t = e.touches[0];
      dx = Math.max(0, t.clientX - startX);
      if (!decided) {
        if (Math.abs(t.clientY - startY) > Math.abs(dx) && Math.abs(t.clientY - startY) > 8) { tracking = false; return; }
        if (dx > 8) { decided = true; el.classList.add('dragging'); }
      }
      if (decided) {
        el.style.transform = `translateX(${dx}px)`;
        const below = stacks[tab][stacks[tab].length - 2];
        if (below) {
          below.el.classList.add('dragging');
          below.el.style.transform = `translateX(${-28 + (dx / innerWidth) * 28}%)`;
        }
      }
    }, { passive: true });
    el.addEventListener('touchend', () => {
      if (!tracking) return;
      tracking = false;
      const below = stacks[tab][stacks[tab].length - 2];
      el.classList.remove('dragging');
      el.style.transform = '';
      if (below) { below.el.classList.remove('dragging'); below.el.style.transform = ''; }
      if (decided && dx > innerWidth * 0.33) pop(tab);
    });
  }

  function switchTab(tab) {
    if (state.tab === tab) {
      const stack = stacks[tab];
      if (stack.length > 1) { while (stack.length > 1) pop(tab); }
      else stack[0].el.scrollTo({ top: 0, behavior: 'smooth' });
    }
    state.tab = tab;
    document.querySelectorAll('.tab-screen').forEach((s) => s.classList.toggle('active', s.dataset.tab === tab));
    document.querySelectorAll('.tab').forEach((b) => {
      b.classList.toggle('active', b.dataset.tab === tab);
      b.setAttribute('aria-selected', b.dataset.tab === tab);
    });
    if (tab === 'library') loadHistory();
    if (tab === 'subs') loadSubs();
    if (tab === 'settings') loadSettings();
    poll.kick();
  }

  /** Re-renders every page that shows a given kind of data. */
  function refresh(kind) {
    for (const tab of Object.keys(stacks)) {
      for (const entry of stacks[tab]) {
        if (!entry.def.watch || entry.def.watch.includes(kind)) entry.def.refresh?.(entry.el);
      }
    }
    if (kind === 'jobs') updateBadges();
  }

  function updateBadges() {
    const queueBadge = $('.tab[data-tab="queue"] .badge');
    queueBadge.hidden = !state.pending;
    queueBadge.textContent = state.pending;
    const unseen = (state.subs || []).reduce((n, s) => n + (s.unseen || 0), 0);
    const subsBadge = $('.tab[data-tab="subs"] .badge');
    subsBadge.hidden = !unseen;
    subsBadge.textContent = unseen;
  }

  // ---------------------------------------------------------------- Overlays

  function hud(text, iconName = 'check') {
    const el = document.createElement('div');
    el.className = 'hud';
    el.innerHTML = `${icon(iconName)}<div class="t">${esc(text)}</div>`;
    document.body.appendChild(el);
    requestAnimationFrame(() => el.classList.add('show'));
    setTimeout(() => { el.classList.remove('show'); setTimeout(() => el.remove(), 300); }, 1300);
  }

  function actionSheet({ title, actions }) {
    const backdrop = document.createElement('div');
    backdrop.className = 'backdrop';
    const sheet = document.createElement('div');
    sheet.className = 'action-sheet';
    sheet.innerHTML = `<div class="group">${title ? `<div class="head">${esc(title)}</div>` : ''}
      ${actions.map((a, i) => `<button data-i="${i}" class="${a.destructive ? 'destructive' : ''}">${esc(a.label)}</button>`).join('')}</div>
      <button class="cancel">Cancel</button>`;
    const close = () => {
      sheet.classList.remove('show'); backdrop.classList.remove('show');
      setTimeout(() => { sheet.remove(); backdrop.remove(); }, 350);
    };
    backdrop.onclick = close;
    sheet.onclick = (e) => {
      const b = e.target.closest('button');
      if (!b) return;
      close();
      if (b.dataset.i != null) actions[+b.dataset.i].run();
    };
    document.body.append(backdrop, sheet);
    requestAnimationFrame(() => { backdrop.classList.add('show'); sheet.classList.add('show'); });
  }

  /** A card-style sheet that slides up; drag the grabber down to dismiss. */
  function openSheet({ title, left, right, body, mount }) {
    const backdrop = document.createElement('div');
    backdrop.className = 'backdrop';
    const sheet = document.createElement('div');
    sheet.className = 'sheet';
    sheet.innerHTML = `<div class="grabber"></div>
      <div class="sheet-nav"><div>${left || ''}</div><div class="title">${esc(title)}</div><div style="justify-self:end">${right || ''}</div></div>
      <div class="sheet-body">${body}</div>`;
    const close = () => {
      sheet.classList.remove('show'); backdrop.classList.remove('show');
      setTimeout(() => { sheet.remove(); backdrop.remove(); }, 420);
    };
    backdrop.onclick = close;
    let startY = 0, dy = 0, dragging = false;
    const grab = sheet.querySelector('.grabber');
    const nav = sheet.querySelector('.sheet-nav');
    for (const handle of [grab, nav]) {
      handle.addEventListener('touchstart', (e) => { startY = e.touches[0].clientY; dragging = true; sheet.classList.add('dragging'); }, { passive: true });
    }
    sheet.addEventListener('touchmove', (e) => {
      if (!dragging) return;
      dy = Math.max(0, e.touches[0].clientY - startY);
      sheet.style.transform = `translateY(${dy}px)`;
    }, { passive: true });
    sheet.addEventListener('touchend', () => {
      if (!dragging) return;
      dragging = false;
      sheet.classList.remove('dragging');
      sheet.style.transform = '';
      if (dy > 120) close();
      dy = 0;
    });
    document.body.append(backdrop, sheet);
    requestAnimationFrame(() => { backdrop.classList.add('show'); sheet.classList.add('show'); });
    mount?.(sheet, close);
    return { sheet, close };
  }

  function renderOfflineBanner() {
    let el = $('.banner.offline');
    if (state.online || !state.token) { el?.remove(); return; }
    if (el) return;
    el = document.createElement('div');
    el.className = 'banner offline';
    el.innerHTML = `<span style="color:var(--orange)">${icon('wifiOff')}</span>
      <div class="grow" style="flex:1"><div class="t">Can’t Reach ${esc(state.mac)}</div>
      <div class="s">Make sure My Videos is open on your Mac and you’re on the same Wi-Fi.</div></div>
      <button class="btn small gray" data-act="retry-connection">Retry</button>`;
    document.body.appendChild(el);
  }

  // ---------------------------------------------------------------- Shared pieces

  function thumb(url, { duration, isAudio, cls = '' } = {}) {
    return `<div class="thumb ${cls}">
      <div class="placeholder">${icon(isAudio ? 'music' : 'film')}</div>
      ${url ? `<img src="${esc(url)}" alt="" loading="lazy" onerror="this.remove()">` : ''}
      ${duration ? `<span class="dur">${fmtDuration(duration)}</span>` : ''}
    </div>`;
  }

  function avatar(url, title, size) {
    return `<div class="avatar" style="width:${size}px;height:${size}px;font-size:${Math.round(size * 0.42)}px">
      ${esc((title || '•').trim().charAt(0).toUpperCase())}
      ${url ? `<img src="${esc(url)}" alt="" loading="lazy" onerror="this.remove()">` : ''}</div>`;
  }

  function pickerRow({ icon: iconName, color, label, value, options, act, detail }) {
    const current = options.find((o) => o.id === value);
    return `<label class="row picker ${iconName ? 'has-icon' : ''}">
      ${iconName ? `<span class="icon-tile" style="background:${color}">${icon(iconName)}</span>` : ''}
      <div class="grow"><div class="label">${esc(label)}</div>${detail ? `<div class="detail">${esc(detail)}</div>` : ''}</div>
      <span class="value">${esc(current ? current.name : '')}${icon('updown')}</span>
      <select data-change="${act}" aria-label="${esc(label)}">
        ${options.map((o) => `<option value="${esc(o.id)}" ${o.id === value ? 'selected' : ''}>${esc(o.name)}</option>`).join('')}
      </select></label>`;
  }

  function switchRow({ icon: iconName, color, label, detail, checked, act, data = '' }) {
    return `<label class="row ${iconName ? 'has-icon' : ''}">
      ${iconName ? `<span class="icon-tile" style="background:${color}">${icon(iconName)}</span>` : ''}
      <div class="grow"><div class="label">${esc(label)}</div>${detail ? `<div class="detail">${esc(detail)}</div>` : ''}</div>
      <span class="switch"><input type="checkbox" data-change="${act}" ${data} ${checked ? 'checked' : ''} aria-label="${esc(label)}"><span></span></span>
    </label>`;
  }

  function progressBar(job) {
    const indeterminate = job.indeterminate || job.phase === 'preparing';
    return `<div class="progress ${indeterminate ? 'indeterminate' : ''} ${job.phase === 'processing' ? 'orange' : ''}">
      <span style="width:${Math.round((job.progress || 0) * 100)}%"></span></div>`;
  }

  const ACTIVE = ['preparing', 'downloading', 'processing'];

  // ---------------------------------------------------------------- Download tab

  function downloadPage() {
    return {
      title: 'Download',
      hero: true,
      watch: ['jobs', 'settings'],
      render: () => `
        <div class="hero">
          <div class="glyph"><img src="/touch-icon.png" alt=""></div>
          <h1>My Videos</h1>
          <p>Downloads on ${esc(state.mac)} — videos, songs and playlists.</p>
        </div>
        <div class="section">
          <div class="field">
            ${icon('link')}
            <input id="link" type="url" inputmode="url" autocomplete="off" autocorrect="off" autocapitalize="off"
              spellcheck="false" placeholder="Paste a video or playlist link" value="${esc(state.composer.url)}">
            <button class="clear" data-act="paste-or-clear" aria-label="Paste or clear"></button>
          </div>
        </div>
        <div id="composer-preview"></div>
        <div id="composer-options"></div>
        <div id="composer-active"></div>
        <div class="section">
          <button class="row has-icon tappable" data-act="push-sendlinks">
            <span class="icon-tile" style="background:var(--blue)">${icon('bolt')}</span>
            <div class="grow"><div class="label">Download from Safari & Share</div>
            <div class="detail">Send links without opening this app</div></div>${icon('chevron', 'chev')}
          </button>
        </div>`,
      mount(el) {
        const input = $('#link', el);
        let timer;
        input.addEventListener('input', () => {
          state.composer.url = input.value;
          updatePasteButton(el);
          clearTimeout(timer);
          timer = setTimeout(() => lookUp(input.value), 550);
        });
        input.addEventListener('keydown', (e) => { if (e.key === 'Enter') { input.blur(); lookUp(input.value, true); } });
        updatePasteButton(el);
        this.refresh(el);
      },
      refresh(el) {
        renderComposer(el);
        renderActiveCard(el);
      },
    };
  }

  function updatePasteButton(el) {
    const btn = $('[data-act="paste-or-clear"]', el);
    const empty = !state.composer.url;
    btn.innerHTML = empty ? icon('paste') : icon('xmark');
    btn.style.color = empty ? 'var(--tint)' : '';
    btn.setAttribute('aria-label', empty ? 'Paste' : 'Clear');
  }

  let lookUpSerial = 0;
  async function lookUp(raw, immediate) {
    const url = (raw || '').trim();
    const c = state.composer;
    const serial = ++lookUpSerial;
    c.preview = null; c.error = ''; c.playlist = false;
    if (!isLink(url)) { c.loading = false; refresh('composer'); renderComposerAll(); return; }
    c.loading = true;
    renderComposerAll();
    try {
      const info = await api('/api/preview?url=' + encodeURIComponent(url));
      if (serial !== lookUpSerial) return;
      c.preview = info;
      c.playlist = !!info.isPlaylist;
    } catch (e) {
      if (serial !== lookUpSerial) return;
      c.error = e.message;
    }
    c.loading = false;
    renderComposerAll();
  }

  function renderComposerAll() {
    const entry = stacks.download?.[0];
    if (entry) renderComposer(entry.el);
  }

  function renderComposer(el) {
    const c = state.composer;
    const s = state.settings;
    const previewEl = $('#composer-preview', el);
    const optionsEl = $('#composer-options', el);
    if (!previewEl) return;

    if (c.loading) {
      previewEl.innerHTML = `<div class="preview"><div class="thumb"><div class="placeholder"><div class="spinner"></div></div></div>
        <div class="meta"><div class="skeleton" style="width:85%"></div><div class="skeleton" style="width:45%;margin-top:8px"></div></div></div>`;
    } else if (c.preview) {
      const p = c.preview;
      const chips = [
        p.isPlaylist ? `<span class="chip red">${icon('queue')} ${p.playlistCount || ''} videos</span>` : '',
        p.site ? `<span class="chip">${esc(p.site)}</span>` : '',
      ].join('');
      const existing = p.existing ? `
        <div class="banner" style="margin:12px 0 0;padding:10px 12px;background:var(--fill)">
          <span style="color:var(--green)">${icon('checkCircle')}</span>
          <div style="flex:1"><div class="t">You’ve downloaded this before</div>
          <div class="s">${esc(new Date(p.existing.date).toLocaleDateString())}${p.existing.files.length ? '' : ' · file moved or deleted'}</div></div>
          ${p.existing.files.length ? `<button class="btn small gray" data-act="open-item" data-id="${p.existing.id}">Open</button>` : ''}
        </div>` : '';
      const subscribe = p.channelURL && !p.subscribed
        ? `<button class="btn small gray" data-act="subscribe-from-preview" data-url="${esc(p.channelURL)}">${icon('plus')} Follow</button>` : '';
      previewEl.innerHTML = `<div class="preview">
        ${thumb(p.thumbnail, { duration: p.isPlaylist ? 0 : p.duration, isAudio: c.format === 'audio' })}
        <div class="meta">
          <div class="title clamp2">${esc(p.title)}</div>
          <div class="sub"><span class="ellipsis" style="max-width:55%">${esc(p.uploader)}</span>${chips}</div>
          ${subscribe ? `<div style="margin-top:10px">${subscribe}</div>` : ''}
          ${existing}
        </div></div>`;
    } else if (c.error) {
      previewEl.innerHTML = `<div class="banner"><span style="color:var(--orange)">${icon('exclaim')}</span>
        <div><div class="t">Preview Unavailable</div><div class="s">${esc(c.error)} You can still try downloading it.</div></div></div>`;
    } else {
      previewEl.innerHTML = '';
    }

    const valid = isLink(c.url);
    const qualities = (s?.qualities || ['Best quality', '1080p', '720p']).map((q) => ({ id: q, name: q }));
    if (!c.quality) c.quality = s && s.quality !== 'Audio only' ? s.quality : qualities[0].id;
    optionsEl.innerHTML = `
      <div class="section" style="margin-bottom:14px">
        <div class="segmented" role="radiogroup">
          <button class="${c.format === 'video' ? 'on' : ''}" data-act="format" data-v="video">${icon('film')} Video</button>
          <button class="${c.format === 'audio' ? 'on' : ''}" data-act="format" data-v="audio">${icon('music')} Audio Only</button>
        </div>
      </div>
      <div class="section">
        <div class="list">
          ${c.format === 'video' ? pickerRow({ icon: 'sparkles', color: 'var(--purple)', label: 'Quality', value: c.quality, options: qualities, act: 'compose-quality' }) : ''}
          ${c.format === 'audio' && s ? switchRow({ icon: 'music', color: 'var(--pink)', label: 'Add to Apple Music', detail: `On ${state.mac}`, checked: s.addToMusic, act: 'setting', data: 'data-key="addToMusic"' }) : ''}
          ${c.preview?.hasPlaylist ? switchRow({ icon: 'queue', color: 'var(--red)', label: 'Entire Playlist', detail: c.preview.isPlaylist && c.preview.playlistCount ? `${c.preview.playlistCount} videos` : 'Download every video in the list', checked: c.playlist, act: 'compose-playlist' }) : ''}
        </div>
      </div>
      <div class="section">
        <button class="btn primary" data-act="download" ${valid ? '' : 'disabled'}>${icon('download')} Download</button>
      </div>`;
  }

  function renderActiveCard(el) {
    const host = $('#composer-active', el);
    if (!host) return;
    const active = state.jobs.filter((j) => ACTIVE.includes(j.phase));
    if (!active.length) { host.innerHTML = ''; return; }
    const job = active[0];
    host.innerHTML = `<div class="section"><div class="section-header">Now Downloading${state.pending > 1 ? ` · ${state.pending} in queue` : ''}</div>
      <div class="list"><button class="row thumb-row tappable" data-act="tab" data-tab="queue">
        ${thumb(job.thumbnail, { isAudio: job.isAudio, cls: 'thumb-sm' })}
        <div class="grow"><div class="label ellipsis">${esc(job.title)}</div>${progressBar(job)}
        <div class="detail ellipsis">${esc(job.status)}</div></div>${icon('chevron', 'chev')}</button></div></div>`;
  }

  // ---------------------------------------------------------------- Queue tab

  function queuePage() {
    return {
      title: 'Queue',
      watch: ['jobs'],
      navRight: () => `<span id="queue-actions"></span>`,
      render: () => `<div id="queue-body"></div>`,
      mount(el) { this.refresh(el); },
      refresh(el) {
        const jobs = state.jobs;
        const actions = $('#queue-actions', el);
        const canResume = state.paused > 0 && state.pending === 0;
        actions.innerHTML = `
          ${jobs.some((j) => ['finished', 'failed', 'cancelled'].includes(j.phase)) ? `<button class="nav-btn" data-act="queue-clear">Clear</button>` : ''}
          ${jobs.length ? `<button class="nav-btn bold" data-act="${canResume ? 'queue-resume' : 'queue-pause'}" ${!canResume && !state.pending ? 'disabled style="opacity:.3"' : ''}>${canResume ? 'Resume All' : 'Pause All'}</button>` : ''}`;
        const body = $('#queue-body', el);
        if (!jobs.length) {
          body.innerHTML = `<div class="empty">${icon('download')}<h3>Nothing in the Queue</h3>
            <p>Links you send to ${esc(state.mac)} appear here while they download.</p>
            <button class="btn primary" data-act="tab" data-tab="download">New Download</button></div>`;
          return;
        }
        const active = jobs.filter((j) => ACTIVE.includes(j.phase));
        const waiting = jobs.filter((j) => ['queued', 'paused'].includes(j.phase));
        const done = jobs.filter((j) => ['finished', 'failed', 'cancelled'].includes(j.phase)).reverse();
        const section = (title, list) => list.length ? `<div class="section"><div class="section-header">${title}</div>
          <div class="list">${list.map(jobRow).join('')}</div></div>` : '';
        body.innerHTML = section('Downloading', active) + section('Up Next', waiting) + section('Finished', done);
      },
    };
  }

  function jobRow(job) {
    const buttons = {
      preparing: [['pause', 'pause', 'Pause'], ['cancel', 'xmark', 'Stop']],
      downloading: [['pause', 'pause', 'Pause'], ['cancel', 'xmark', 'Stop']],
      processing: [['cancel', 'xmark', 'Stop']],
      queued: [['pause', 'pause', 'Pause'], ['remove', 'xmark', 'Remove']],
      paused: [['resume', 'play', 'Resume'], ['remove', 'xmark', 'Remove']],
      failed: [['retry', 'retry', 'Try Again'], ['remove', 'xmark', 'Remove']],
      cancelled: [['retry', 'retry', 'Try Again'], ['remove', 'xmark', 'Remove']],
      finished: [],
    }[job.phase] || [];
    const status = [job.status, job.music].filter(Boolean).join(' · ');
    return `<div class="row thumb-row">
      ${thumb(job.thumbnail, { isAudio: job.isAudio, cls: 'thumb-sm' })}
      <div class="grow">
        <div class="label ellipsis" style="font-weight:500">${esc(job.title)}</div>
        ${ACTIVE.includes(job.phase) ? progressBar(job) : ''}
        <div class="detail" style="${job.phase === 'failed' ? 'color:var(--red)' : ''}">${esc(status)}</div>
      </div>
      ${job.phase === 'finished' ? `<span style="color:var(--green);font-size:22px">${icon('checkCircle')}</span>` : ''}
      ${buttons.map(([act, ic, label]) => `<button class="circle-btn ${act === 'cancel' ? 'red' : ''}" data-act="job" data-op="${act}" data-id="${job.id}" aria-label="${label}">${icon(ic)}</button>`).join('')}
    </div>`;
  }

  // ---------------------------------------------------------------- Library tab

  function libraryPage() {
    return {
      title: 'Library',
      watch: ['history'],
      render: () => `
        <div class="search">${icon('search')}<input id="lib-search" type="search" placeholder="Search" autocomplete="off" value="${esc(state.library.query)}"></div>
        <div class="section" style="margin-bottom:18px"><div class="segmented">
          ${['all', 'videos', 'music'].map((f) => `<button class="${state.library.filter === f ? 'on' : ''}" data-act="lib-filter" data-v="${f}">${f === 'all' ? 'All' : f === 'videos' ? 'Videos' : 'Music'}</button>`).join('')}
        </div></div>
        <div id="lib-body"></div>`,
      mount(el) {
        $('#lib-search', el).addEventListener('input', (e) => { state.library.query = e.target.value; this.refresh(el); });
        this.refresh(el);
      },
      refresh(el) {
        el.querySelectorAll('[data-act="lib-filter"]').forEach((b) => b.classList.toggle('on', b.dataset.v === state.library.filter));
        const body = $('#lib-body', el);
        if (!state.history) {
          body.innerHTML = `<div class="empty"><div class="spinner" style="margin:0 auto"></div></div>`;
          return;
        }
        const q = state.library.query.trim().toLowerCase();
        const items = state.history.filter((i) =>
          (state.library.filter === 'all' || (state.library.filter === 'music') === i.isAudio) &&
          (!q || i.title.toLowerCase().includes(q) || i.uploader.toLowerCase().includes(q)));
        if (!state.history.length) {
          body.innerHTML = `<div class="empty">${icon('library')}<h3>No Downloads Yet</h3>
            <p>Everything you download is collected here, ready to play or save to your iPhone.</p></div>`;
          return;
        }
        if (!items.length) {
          body.innerHTML = `<div class="empty">${icon('search')}<h3>No Results</h3><p>Try a different search.</p></div>`;
          return;
        }
        const groups = [];
        for (const item of items) {
          const key = dayBucket(item.date);
          let g = groups.find((x) => x.key === key);
          if (!g) groups.push(g = { key, items: [] });
          g.items.push(item);
        }
        body.innerHTML = groups.map((g) => `<div class="section"><div class="section-header">${g.key}</div><div class="list">
          ${g.items.map((i) => `<button class="row thumb-row tappable" data-act="open-item" data-id="${i.id}">
            ${thumb(i.thumbnail, { duration: i.isPlaylist ? 0 : i.duration, isAudio: i.isAudio, cls: 'thumb-sm' })}
            <div class="grow"><div class="label clamp2" style="font-weight:500;font-size:.94rem;line-height:1.25">${esc(i.title)}</div>
            <div class="detail ellipsis">${esc([i.uploader, i.isPlaylist ? `${i.files.length} files` : '', fmtBytes(i.bytes)].filter(Boolean).join(' · '))}
            ${!i.files.length ? `<span style="color:var(--orange)"> · ${i.device ? 'On ' + esc(i.device) : 'Not on Mac'}</span>` : ''}</div></div>
            ${icon('chevron', 'chev')}</button>`).join('')}</div></div>`).join('');
      },
    };
  }

  function itemPage(id) {
    const find = () => state.history?.find((i) => i.id === id);
    return {
      title: find()?.isAudio ? 'Song' : 'Video',
      backTitle: 'Library',
      largeTitle: false,
      watch: ['history', 'saves'],
      render: () => `<div id="item-media"></div><div id="item-body"></div>`,
      mount(el) { this.renderMedia(el); this.refresh(el); },
      renderMedia(el) {
        const item = find();
        const host = $('#item-media', el);
        if (!item) return;
        const file = item.files.find((f) => f.playable);
        if (item.isAudio) {
          host.innerHTML = `<div class="artwork-hero">
              ${item.thumbnail ? `<div class="bgblur" style="background-image:url('${esc(item.thumbnail)}')"></div>` : ''}
              <div class="art">${item.thumbnail ? `<img src="${esc(item.thumbnail)}" alt="">` : `<div class="placeholder" style="display:grid;place-items:center;height:100%;font-size:60px;color:var(--tertiary)">${icon('music')}</div>`}</div>
            </div>
            ${file ? `<audio controls preload="metadata" src="${mediaURL(item.id, file.index)}"></audio>` : ''}`;
        } else if (file) {
          host.innerHTML = `<div class="player"><video controls playsinline preload="metadata"
            poster="${esc(item.thumbnail)}" src="${mediaURL(item.id, file.index)}"></video></div>`;
        } else {
          host.innerHTML = `<div style="margin:12px 16px 0">${thumb(item.thumbnail, { duration: item.duration })}</div>`;
        }
      },
      refresh(el) {
        const item = find();
        const body = $('#item-body', el);
        if (!item) { body.innerHTML = `<div class="empty"><h3>Not Found</h3></div>`; return; }
        const save = state.saves[item.id];
        const first = item.files[0];
        let saveRow = '';
        if (first) {
          if (save?.file) {
            saveRow = `<button class="row has-icon tappable tint" data-act="share-file" data-id="${item.id}">
              <span class="icon-tile" style="background:var(--green)">${icon('share')}</span>
              <div class="grow"><div class="label">Save “${esc(save.file.name)}”</div><div class="detail">Ready — choose Save Video or Save to Files</div></div></button>`;
          } else if (save && save.progress != null && !save.error) {
            saveRow = `<div class="row has-icon"><span class="icon-tile" style="background:var(--blue)">${icon('download')}</span>
              <div class="grow"><div class="label">Getting it from ${esc(state.mac)}…</div>
              <div class="progress"><span style="width:${Math.round(save.progress * 100)}%"></span></div></div></div>`;
          } else {
            saveRow = `<button class="row has-icon tappable" data-act="save-item" data-id="${item.id}">
              <span class="icon-tile" style="background:var(--blue)">${icon('share')}</span>
              <div class="grow"><div class="label">Save to iPhone</div><div class="detail">${save?.error ? esc(save.error) : (item.isAudio ? 'To Files' : 'To Photos or Files')}</div></div></button>`;
          }
        }
        const files = item.files.length > 1 ? `<div class="section"><div class="section-header">${item.files.length} Files</div><div class="list">
          ${item.files.map((f) => `<a class="row has-icon tappable" href="${mediaURL(item.id, f.index)}" target="_blank" rel="noopener">
            <span class="icon-tile" style="background:var(--gray)">${icon(item.isAudio ? 'music' : 'film')}</span>
            <div class="grow"><div class="label ellipsis">${esc(f.name)}</div></div>${icon('play', 'chev')}</a>`).join('')}</div></div>` : '';
        body.innerHTML = `
          <div class="detail-head"><h2>${esc(item.title)}</h2>
            <div class="m">${esc([item.uploader, fmtDuration(item.duration), fmtBytes(item.bytes)].filter(Boolean).join(' · '))}</div>
            <div class="m" style="margin-top:2px">Downloaded ${esc(relTime(item.date))}${item.device ? ` on ${esc(item.device)}` : ''}</div></div>
          ${!item.files.length ? `<div class="banner"><span style="color:var(--orange)">${icon('exclaim')}</span>
            <div><div class="t">Not on ${esc(state.mac)}</div><div class="s">The file was moved, deleted or downloaded on another Mac.</div></div></div>` : ''}
          <div class="section"><div class="list">
            ${saveRow}
            ${item.isAudio && item.files.length ? `<button class="row has-icon tappable" data-act="item-music" data-id="${item.id}">
              <span class="icon-tile" style="background:var(--pink)">${icon('music')}</span>
              <div class="grow"><div class="label">Add to Apple Music</div><div class="detail">On ${esc(state.mac)}; syncs to your iPhone with iCloud Music Library</div></div></button>` : ''}
            ${item.canUpgrade ? `<button class="row has-icon tappable" data-act="item-upgrade" data-id="${item.id}">
              <span class="icon-tile" style="background:var(--purple)">${icon('upgrade')}</span>
              <div class="grow"><div class="label">Replace with Best Quality</div></div></button>` : ''}
            <a class="row has-icon tappable" href="${esc(item.source)}" target="_blank" rel="noopener">
              <span class="icon-tile" style="background:var(--gray)">${icon('globe')}</span>
              <div class="grow"><div class="label">Open Original Page</div></div>${icon('chevron', 'chev')}</a>
          </div></div>
          ${files}
          <div class="section"><div class="list">
            <button class="row center destructive tappable" data-act="item-remove" data-id="${item.id}"><span class="label">Remove from Library</span></button>
          </div><div class="section-footer">The file stays on your Mac.</div></div>`;
      },
    };
  }

  // ---------------------------------------------------------------- Subscriptions tab

  function subsPage() {
    return {
      title: 'Subscriptions',
      watch: ['subs'],
      navRight: () => `<button class="nav-btn" data-act="add-sub" aria-label="Add Subscription">${icon('plus')}</button>`,
      render: () => `<div id="subs-body"></div>`,
      mount(el) { this.refresh(el); },
      refresh(el) {
        const body = $('#subs-body', el);
        if (!state.subs) { body.innerHTML = `<div class="empty"><div class="spinner" style="margin:0 auto"></div></div>`; return; }
        if (!state.subs.length) {
          body.innerHTML = `<div class="empty">${icon('antenna')}<h3>No Subscriptions</h3>
            <p>Follow a channel or playlist and new uploads download on ${esc(state.mac)} automatically.</p>
            <button class="btn primary" data-act="add-sub">Add Subscription</button></div>`;
          return;
        }
        body.innerHTML = `<div class="section"><div class="list">${state.subs.map((s) => `
          <button class="row tappable" data-act="open-sub" data-id="${s.id}" style="gap:14px;${s.enabled ? '' : 'opacity:.55'}">
            ${avatar(s.avatar, s.title, 44)}
            <div class="grow"><div class="label ellipsis" style="font-weight:500">${esc(s.title)}</div>
            <div class="detail ellipsis" style="${s.error ? 'color:var(--orange)' : ''}">${esc(subStatus(s))}</div></div>
            ${s.unseen ? `<span class="badge" style="position:static;background:var(--tint);min-width:22px;height:22px;border-radius:11px;color:#fff;display:grid;place-items:center;font-size:13px;font-weight:600;padding:0 7px">${s.unseen}</span>` : ''}
            ${icon('chevron', 'chev')}</button>`).join('')}</div>
          <div class="section-footer">New uploads download on ${esc(state.mac)} while My Videos is open.</div></div>`;
      },
    };
  }

  function subStatus(s) {
    if (state.checking.includes(s.id)) return 'Checking…';
    if (!s.enabled) return 'Paused';
    if (s.error) return s.error;
    return `${s.format === 'audio' ? 'Audio' : s.format} · checked ${relTime(s.lastChecked)}`;
  }

  function subPage(id) {
    const find = () => state.subs?.find((s) => s.id === id);
    return {
      title: find()?.title || 'Subscription',
      backTitle: 'Subscriptions',
      largeTitle: false,
      watch: ['subs'],
      render: () => `<div id="sub-body"></div>`,
      mount(el) {
        this.refresh(el);
        api(`/api/subscriptions/${id}/viewed`, { method: 'POST' }).then(() => {
          const s = find();
          if (s) { s.unseen = 0; updateBadges(); }
        }).catch(() => {});
      },
      refresh(el) {
        const s = find();
        const body = $('#sub-body', el);
        if (!s) { body.innerHTML = `<div class="empty"><h3>Not Found</h3></div>`; return; }
        const formats = [...(state.settings?.qualities || ['Best quality', '1080p', '720p']).map((q) => ({ id: q, name: q })), { id: 'audio', name: 'Audio Only' }];
        body.innerHTML = `
          <div style="text-align:center;padding:12px 24px 22px">
            <div style="display:inline-block;box-shadow:var(--shadow);border-radius:50%">${avatar(s.avatar, s.title, 88)}</div>
            <h2 style="margin:14px 0 4px;font-size:1.4rem">${esc(s.title)}</h2>
            <div style="color:var(--secondary);font-size:.9rem">${esc(subStatus(s))} · ${s.downloadedCount} downloaded</div>
            <button class="btn small gray" style="margin:14px auto 0" data-act="sub-check" data-id="${s.id}" ${state.checking.includes(s.id) ? 'disabled' : ''}>
              ${icon('retry')} ${state.checking.includes(s.id) ? 'Checking…' : 'Check Now'}</button>
          </div>
          <div class="section"><div class="list">
            ${switchRow({ icon: 'download', color: 'var(--blue)', label: 'Download New Uploads', checked: s.enabled, act: 'sub-enabled', data: `data-id="${s.id}"` })}
            ${pickerRow({ icon: 'sparkles', color: 'var(--purple)', label: 'Format', value: s.format, options: formats, act: 'sub-format' }).replace('data-change="sub-format"', `data-change="sub-format" data-id="${s.id}"`)}
            ${s.format === 'audio' ? switchRow({ icon: 'music', color: 'var(--pink)', label: 'Add to Apple Music', checked: s.addToMusic, act: 'sub-music', data: `data-id="${s.id}"` }) : ''}
          </div></div>
          <div class="section-header big" style="margin:0 20px 12px">Recent Uploads</div>
          <div class="grid2">${s.recent.map((e) => `
            <button class="tile" data-act="upload" data-sub="${s.id}" data-entry="${esc(e.id)}">
              ${thumb(e.thumbnail, { duration: e.duration })}
              <div class="t clamp2">${esc(e.title)}</div>
              <div class="s">${e.state === 'downloaded' ? `<span style="color:var(--green)">${icon('checkCircle')}</span> Downloaded`
                : e.state === 'downloading' ? `<div class="spinner" style="width:12px;height:12px;border-width:2px"></div> Downloading` : 'Tap to download'}</div>
            </button>`).join('')}</div>
          <div class="section" style="margin-top:28px"><div class="list">
            <button class="row center destructive tappable" data-act="unsubscribe" data-id="${s.id}"><span class="label">Unsubscribe</span></button>
          </div></div>`;
      },
    };
  }

  function addSubscriptionSheet(prefill = '') {
    let feed = null, format = 'video', latest = 0, serial = 0;
    const { sheet, close } = openSheet({
      title: 'Add Subscription',
      left: `<button class="nav-btn" data-sheet="cancel">Cancel</button>`,
      right: `<button class="nav-btn bold" data-sheet="subscribe" disabled style="opacity:.3">Follow</button>`,
      body: `
        <div class="section" style="margin-top:8px"><div class="field">${icon('link')}
          <input id="sub-url" type="url" inputmode="url" autocomplete="off" autocapitalize="off" spellcheck="false"
            placeholder="Channel or playlist link" value="${esc(prefill)}"></div>
          <div class="section-footer">For example youtube.com/@name, or any playlist link.</div></div>
        <div id="sub-preview"></div>
        <div id="sub-options"></div>`,
      mount(sheet, close) {
        const input = $('#sub-url', sheet);
        const btn = $('[data-sheet="subscribe"]', sheet);
        const renderOptions = () => {
          $('#sub-options', sheet).innerHTML = feed ? `
            <div class="section"><div class="segmented">
              <button class="${format === 'video' ? 'on' : ''}" data-sheet="format" data-v="video">Video</button>
              <button class="${format === 'audio' ? 'on' : ''}" data-sheet="format" data-v="audio">Audio Only</button></div></div>
            <div class="section"><div class="list">
              ${pickerRow({ icon: 'clock', color: 'var(--orange)', label: 'Right Now', value: String(latest), act: 'sheet-latest',
                options: [{ id: '0', name: 'Only Future Uploads' }, { id: '1', name: 'Also the Latest 1' }, { id: '3', name: 'Also the Latest 3' }, { id: '5', name: 'Also the Latest 5' }] })}
            </div></div>` : '';
        };
        const load = async () => {
          const url = input.value.trim();
          const my = ++serial;
          feed = null;
          btn.disabled = true; btn.style.opacity = '.3';
          renderOptions();
          const host = $('#sub-preview', sheet);
          if (!isLink(url)) { host.innerHTML = ''; return; }
          host.innerHTML = `<div class="banner"><div class="spinner"></div><div class="t" style="font-weight:400;color:var(--secondary)">Looking up the channel…</div></div>`;
          try {
            const f = await api('/api/subscriptions/preview', { method: 'POST', body: { url } });
            if (my !== serial) return;
            feed = f;
            host.innerHTML = `<div class="preview" style="padding:14px">
              <div style="display:flex;gap:12px;align-items:center">${avatar(f.avatar, f.title, 48)}
                <div style="min-width:0"><div class="title ellipsis">${esc(f.title)}</div>
                <div class="sub ellipsis" style="${f.subscribed ? 'color:var(--orange)' : ''}">${f.subscribed ? 'You’re already following this.' : 'Latest: ' + esc(f.latest)}</div></div></div>
              <div style="display:grid;grid-template-columns:repeat(4,1fr);gap:6px;margin-top:12px">
                ${f.thumbnails.map((t) => thumb(t)).join('')}</div></div>`;
            if (!f.subscribed) { btn.disabled = false; btn.style.opacity = ''; }
            renderOptions();
          } catch (e) {
            if (my !== serial) return;
            host.innerHTML = `<div class="banner"><span style="color:var(--orange)">${icon('exclaim')}</span><div class="s" style="color:var(--label)">${esc(e.message)}</div></div>`;
          }
        };
        let timer;
        input.addEventListener('input', () => { clearTimeout(timer); timer = setTimeout(load, 600); });
        sheet.addEventListener('change', (e) => { if (e.target.dataset.change === 'sheet-latest') { latest = +e.target.value; renderOptions(); } });
        sheet.addEventListener('click', async (e) => {
          const t = e.target.closest('[data-sheet]');
          if (!t) return;
          if (t.dataset.sheet === 'cancel') close();
          if (t.dataset.sheet === 'format') { format = t.dataset.v; renderOptions(); }
          if (t.dataset.sheet === 'subscribe' && feed) {
            t.disabled = true;
            try {
              const r = await api('/api/subscriptions', { method: 'POST', body: { url: input.value.trim(), format: format === 'audio' ? 'audio' : (state.settings?.quality === 'Audio only' ? 'Best quality' : state.settings?.quality), latest } });
              state.subs = r.items;
              refresh('subs');
              updateBadges();
              close();
              hud('Following');
            } catch (err) { t.disabled = false; hud(err.message, 'exclaim'); }
          }
        });
        if (prefill) load(); else setTimeout(() => input.focus(), 400);
      },
    });
    return { sheet, close };
  }

  // ---------------------------------------------------------------- Settings tab

  function settingsPage() {
    return {
      title: 'Settings',
      watch: ['settings'],
      render: () => `<div id="settings-body"></div>`,
      mount(el) { this.refresh(el); },
      refresh(el) {
        const s = state.settings;
        const body = $('#settings-body', el);
        if (!s) { body.innerHTML = `<div class="empty"><div class="spinner" style="margin:0 auto"></div></div>`; return; }
        const opt = (list) => list.map((x) => typeof x === 'string' ? { id: x, name: x } : x);
        body.innerHTML = `
          <div class="section"><div class="list">
            <div class="row" style="gap:14px;padding:14px 16px">
              <span class="icon-tile" style="background:var(--gray);width:52px;height:52px;border-radius:12px;font-size:28px">${icon('laptop')}</span>
              <div class="grow"><div class="label" style="font-size:1.15rem;font-weight:600">${esc(s.mac)}</div>
              <div class="detail" style="display:flex;align-items:center;gap:6px">
                <span style="width:8px;height:8px;border-radius:4px;background:${state.online ? 'var(--green)' : 'var(--orange)'}"></span>
                ${state.online ? 'Connected' : 'Not reachable'}</div></div>
            </div></div></div>

          <div class="section"><div class="section-header">Video</div><div class="list">
            ${pickerRow({ icon: 'sparkles', color: 'var(--purple)', label: 'Quality', value: s.quality === 'Audio only' ? 'Best quality' : s.quality, options: opt(s.qualities), act: 'setting-select', detail: '' }).replace('data-change="setting-select"', 'data-change="setting-select" data-key="quality"')}
            ${pickerRow({ icon: 'captions', color: 'var(--teal)', label: 'Subtitles', value: s.subtitles, options: s.subtitleModes, act: 'setting-select' }).replace('data-change="setting-select"', 'data-change="setting-select" data-key="subtitles"')}
            ${pickerRow({ icon: 'forward', color: 'var(--green)', label: 'Sponsored Segments', value: s.sponsorBlock, options: s.sponsorModes, act: 'setting-select' }).replace('data-change="setting-select"', 'data-change="setting-select" data-key="sponsorBlock"')}
            ${switchRow({ icon: 'photo', color: 'var(--blue)', label: 'Cover Art & Details', checked: s.embedArtwork, act: 'setting', data: 'data-key="embedArtwork"' })}
          </div></div>

          <div class="section"><div class="section-header">Music</div><div class="list">
            ${pickerRow({ icon: 'waveform', color: 'var(--pink)', label: 'Audio Format', value: s.audioFormat, options: s.audioFormats, act: 'setting-select' }).replace('data-change="setting-select"', 'data-change="setting-select" data-key="audioFormat"')}
            ${switchRow({ icon: 'music', color: 'var(--red)', label: 'Add to Apple Music', checked: s.addToMusic, act: 'setting', data: 'data-key="addToMusic"' })}
            ${switchRow({ icon: 'quote', color: 'var(--purple)', label: 'Find Lyrics', checked: s.fetchLyrics, act: 'setting', data: 'data-key="fetchLyrics"' })}
            ${switchRow({ icon: 'speaker', color: 'var(--teal)', label: 'Even Out Volume', checked: s.normalizeVolume, act: 'setting', data: 'data-key="normalizeVolume"' })}
          </div><div class="section-footer">Songs added to Apple Music on your Mac appear on your iPhone when Sync Library is on.</div></div>

          <div class="section"><div class="list">
            <button class="row has-icon tappable" data-act="push-sendlinks">
              <span class="icon-tile" style="background:var(--blue)">${icon('bolt')}</span>
              <div class="grow"><div class="label">Download from Safari & Share</div></div>${icon('chevron', 'chev')}</button>
          </div></div>

          <div class="section"><div class="list">
            <button class="row center destructive tappable" data-act="disconnect"><span class="label">Disconnect from ${esc(s.mac)}</span></button>
          </div></div>`;
      },
    };
  }

  function sendLinksPage() {
    const base = `${location.protocol}//${location.host}/add?t=${encodeURIComponent(state.token)}`;
    const bookmark = `javascript:location.href='${base}&url='+encodeURIComponent(location.href)`;
    return {
      title: 'Download from Safari',
      backTitle: 'Back',
      largeTitle: false,
      render: () => `
        <div class="hero" style="padding-top:18px"><div class="glyph" style="background:var(--blue);display:grid;place-items:center;color:#fff;font-size:38px">${icon('bolt')}</div>
          <h1 style="font-size:1.4rem">Send Links in One Tap</h1>
          <p>Start a download on ${esc(state.mac)} from any page or app — without opening My Videos.</p></div>

        <div class="section"><div class="section-header">Safari Bookmark</div>
          <div class="steps">
            <div class="step"><span class="n">1</span><div>Tap <b>Copy Bookmark</b> below.</div></div>
            <div class="step"><span class="n">2</span><div>In Safari, tap ${icon('share')} on any page, then <b>Add Bookmark</b> and save it to Favorites as “Download”.</div></div>
            <div class="step"><span class="n">3</span><div>Open <b>Bookmarks</b>, tap <b>Edit</b>, choose “Download” and paste the copied text as its address.</div></div>
          </div>
          <button class="btn primary" data-act="copy" data-text="${esc(bookmark)}">Copy Bookmark</button>
          <div class="section-footer">On a video page, open Favorites and tap “Download”.</div></div>

        <div class="section"><div class="section-header">Share Sheet Shortcut</div>
          <div class="steps">
            <div class="step"><span class="n">1</span><div>In the <b>Shortcuts</b> app, create a shortcut and turn on <b>Show in Share Sheet</b> (receives URLs).</div></div>
            <div class="step"><span class="n">2</span><div>Add the action <b>Open URLs</b> with the text you copy below, followed by the <b>Shortcut Input</b> variable.</div></div>
            <div class="step"><span class="n">3</span><div>Name it “Download with My Videos”. It appears when you tap ${icon('share')} in YouTube, Safari and more.</div></div>
          </div>
          <button class="btn gray" data-act="copy" data-text="${esc(base + '&url=')}">Copy Shortcut Address</button>
          <div class="section-footer">Add “&amp;format=audio” before the input for an audio-only version.</div></div>`,
    };
  }

  const ROOTS = { download: downloadPage, queue: queuePage, library: libraryPage, subs: subsPage, settings: settingsPage };

  // ---------------------------------------------------------------- Data loading

  async function loadState() {
    const data = await api('/api/state');
    state.jobs = data.jobs;
    state.pending = data.pending;
    state.paused = data.paused;
    refresh('jobs');
  }
  async function loadHistory() {
    try { state.history = (await api('/api/history')).items; refresh('history'); } catch {}
  }
  async function loadSubs() {
    try {
      const r = await api('/api/subscriptions');
      state.subs = r.items; state.checking = r.checking;
      refresh('subs'); updateBadges();
    } catch {}
  }
  async function loadSettings() {
    try {
      state.settings = await api('/api/settings');
      if (state.settings.mac) { state.mac = state.settings.mac; store.set('mac', state.mac); }
      refresh('settings');
      renderComposerAll();
    } catch {}
  }

  const poll = (() => {
    let timer = null, lastHistory = 0, lastSubs = 0, lastFinished = 0;
    async function tick() {
      clearTimeout(timer);
      if (!state.token) return;
      if (document.hidden) { timer = setTimeout(tick, 4000); return; }
      try {
        await loadState();
        const finished = state.jobs.filter((j) => j.phase === 'finished').length;
        if (finished !== lastFinished) { lastFinished = finished; lastHistory = 0; }
        const now = Date.now();
        if (state.tab === 'library' && now - lastHistory > 15000) { lastHistory = now; loadHistory(); }
        if (state.tab === 'subs' && now - lastSubs > (state.checking.length ? 2000 : 15000)) { lastSubs = now; loadSubs(); }
      } catch {}
      const busy = state.jobs.some((j) => ACTIVE.includes(j.phase));
      timer = setTimeout(tick, busy || state.tab === 'queue' ? 1500 : 5000);
    }
    return { kick: () => { clearTimeout(timer); timer = setTimeout(tick, 50); } };
  })();

  // ---------------------------------------------------------------- Save to iPhone

  async function saveItem(id) {
    const item = state.history?.find((i) => i.id === id);
    const file = item?.files[0];
    if (!file) return;
    const url = mediaURL(id, file.index);
    // Very large files go straight to Safari's downloads (Files app) instead of memory.
    if (!navigator.canShare || item.bytes > 700e6) {
      location.href = mediaURL(id, file.index, true);
      return;
    }
    state.saves[id] = { progress: 0 };
    refresh('saves');
    try {
      const res = await fetch(url);
      if (!res.ok) throw new Error('Couldn’t get the file.');
      const total = +res.headers.get('Content-Length') || item.bytes || 0;
      const reader = res.body.getReader();
      const chunks = [];
      let received = 0, lastPaint = 0;
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        chunks.push(value);
        received += value.length;
        if (total && Date.now() - lastPaint > 120) {
          lastPaint = Date.now();
          state.saves[id].progress = received / total;
          refresh('saves');
        }
      }
      const type = res.headers.get('Content-Type') || 'application/octet-stream';
      const f = new File(chunks, file.name, { type });
      if (!navigator.canShare({ files: [f] })) throw new Error('This iPhone can’t save this file type.');
      state.saves[id] = { file: f };
    } catch (e) {
      state.saves[id] = { error: e.message };
    }
    refresh('saves');
  }

  async function shareSaved(id) {
    const save = state.saves[id];
    if (!save?.file) return;
    try {
      await navigator.share({ files: [save.file] });
      delete state.saves[id];
      refresh('saves');
    } catch (e) {
      if (e.name !== 'AbortError') hud('Couldn’t share', 'exclaim');
    }
  }

  // ---------------------------------------------------------------- Actions

  const actions = {
    tab: (d) => switchTab(d.tab),
    back: () => pop(state.tab),
    'retry-connection': () => { poll.kick(); loadSettings(); },

    async 'paste-or-clear'() {
      const input = $('#link');
      if (state.composer.url) {
        input.value = ''; state.composer.url = ''; updatePasteButton(stacks.download[0].el);
        lookUp('');
        input.focus();
        return;
      }
      try {
        const text = (await navigator.clipboard.readText()).trim();
        if (!text) { input.focus(); return; }
        input.value = text; state.composer.url = text;
        updatePasteButton(stacks.download[0].el);
        lookUp(text, true);
      } catch {
        input.focus();
        hud('Long-press the field to paste', 'paste');
      }
    },
    format(d) { state.composer.format = d.v; renderComposerAll(); },
    async download(_, btn) {
      const c = state.composer;
      if (!isLink(c.url)) return;
      btn.disabled = true;
      try {
        await api('/api/download', { method: 'POST', body: { url: c.url.trim(), format: c.format, quality: c.quality, playlist: c.playlist } });
        hud(state.pending ? 'Added to Queue' : 'Downloading');
        Object.assign(c, { url: '', preview: null, error: '', playlist: false });
        const input = $('#link'); if (input) input.value = '';
        updatePasteButton(stacks.download[0].el);
        renderComposerAll();
        poll.kick();
      } catch (e) {
        hud(e.message, 'exclaim');
        btn.disabled = false;
      }
    },
    'subscribe-from-preview': (d) => addSubscriptionSheet(d.url),
    'push-sendlinks': () => push(state.tab, sendLinksPage()),

    async job(d) {
      try {
        const r = await api(`/api/jobs/${d.id}/${d.op}`, { method: 'POST' });
        Object.assign(state, { jobs: r.jobs, pending: r.pending, paused: r.paused });
        refresh('jobs');
      } catch (e) { hud(e.message, 'exclaim'); }
    },
    async 'queue-clear'() { const r = await api('/api/queue/clear', { method: 'POST' }); Object.assign(state, r); refresh('jobs'); },
    async 'queue-pause'() { const r = await api('/api/queue/pause-all', { method: 'POST' }); Object.assign(state, r); refresh('jobs'); },
    async 'queue-resume'() { const r = await api('/api/queue/resume-all', { method: 'POST' }); Object.assign(state, r); refresh('jobs'); },

    'lib-filter'(d) { state.library.filter = d.v; refresh('history'); },
    async 'open-item'(d) {
      if (!state.history) await loadHistory();
      if (state.tab !== 'library') switchTab('library');
      push('library', itemPage(d.id));
    },
    'save-item': (d) => saveItem(d.id),
    'share-file': (d) => shareSaved(d.id),
    async 'item-music'(d) { try { await api(`/api/history/${d.id}/music`, { method: 'POST' }); hud('Adding to Apple Music', 'music'); } catch (e) { hud(e.message, 'exclaim'); } },
    async 'item-upgrade'(d) {
      actionSheet({ title: 'Download the best version available and replace the current file?', actions: [{ label: 'Replace with Best Quality', run: async () => {
        try { await api(`/api/history/${d.id}/upgrade`, { method: 'POST' }); hud('Upgrading'); poll.kick(); } catch (e) { hud(e.message, 'exclaim'); }
      } }] });
    },
    'item-remove'(d) {
      actionSheet({ title: 'The file stays on your Mac.', actions: [{ label: 'Remove from Library', destructive: true, run: async () => {
        await api(`/api/history/${d.id}`, { method: 'DELETE' });
        state.history = state.history.filter((i) => i.id !== d.id);
        pop('library');
        refresh('history');
      } }] });
    },

    'add-sub': () => addSubscriptionSheet(),
    'open-sub': (d) => push('subs', subPage(d.id)),
    async 'sub-check'(d) {
      state.checking = [...state.checking, d.id];
      refresh('subs');
      try { const r = await api(`/api/subscriptions/${d.id}/check`, { method: 'POST' }); replaceSub(r.item); } catch (e) { hud(e.message, 'exclaim'); }
      state.checking = state.checking.filter((x) => x !== d.id);
      refresh('subs');
      poll.kick();
    },
    upload(d) {
      const sub = state.subs.find((s) => s.id === d.sub);
      const entry = sub?.recent.find((e) => e.id === d.entry);
      if (!entry) return;
      const list = [];
      if (entry.state === 'available') list.push({ label: 'Download', run: async () => {
        try { const r = await api(`/api/subscriptions/${sub.id}/download`, { method: 'POST', body: { entry: entry.id } }); replaceSub(r.item); hud('Added to Queue'); poll.kick(); }
        catch (e) { hud(e.message, 'exclaim'); }
      } });
      list.push({ label: 'Open in Browser', run: () => window.open(entry.url, '_blank') });
      actionSheet({ title: entry.title, actions: list });
    },
    unsubscribe(d) {
      const sub = state.subs.find((s) => s.id === d.id);
      actionSheet({ title: `New uploads from ${sub?.title || 'this channel'} will stop downloading.`, actions: [{ label: 'Unsubscribe', destructive: true, run: async () => {
        await api(`/api/subscriptions/${d.id}`, { method: 'DELETE' });
        state.subs = state.subs.filter((s) => s.id !== d.id);
        pop('subs');
        refresh('subs'); updateBadges();
      } }] });
    },

    disconnect() {
      actionSheet({ title: `You’ll need the code from ${state.mac} to connect again.`, actions: [{ label: 'Disconnect', destructive: true, run: disconnect }] });
    },
    async copy(d) {
      try { await navigator.clipboard.writeText(d.text); hud('Copied'); }
      catch { hud('Couldn’t copy', 'exclaim'); }
    },
  };

  function replaceSub(item) {
    if (!item || !state.subs) return;
    state.subs = state.subs.map((s) => s.id === item.id ? item : s);
    refresh('subs');
  }

  const changes = {
    'compose-quality': (t) => { state.composer.quality = t.value; renderComposerAll(); },
    'compose-playlist': (t) => { state.composer.playlist = t.checked; },
    setting: (t) => saveSetting(t.dataset.key, t.checked),
    'setting-select': (t) => saveSetting(t.dataset.key, t.value),
    'sub-enabled': (t) => subSetting(t.dataset.id, 'enabled', t.checked),
    'sub-format': (t) => subSetting(t.dataset.id, 'format', t.value),
    'sub-music': (t) => subSetting(t.dataset.id, 'music', t.checked),
  };

  async function saveSetting(key, value) {
    try {
      state.settings = await api('/api/settings', { method: 'POST', body: { [key]: value } });
      refresh('settings');
      renderComposerAll();
    } catch (e) { hud(e.message, 'exclaim'); }
  }

  async function subSetting(id, action, value) {
    try { const r = await api(`/api/subscriptions/${id}/${action}`, { method: 'POST', body: { value } }); replaceSub(r.item); }
    catch (e) { hud(e.message, 'exclaim'); }
  }

  function bindEvents() {
    document.addEventListener('click', (e) => {
      const target = e.target.closest('[data-act]');
      if (!target || target.disabled) return;
      const fn = actions[target.dataset.act];
      if (fn) { e.preventDefault(); fn.call(actions, target.dataset, target); }
    });
    document.addEventListener('change', (e) => {
      const fn = changes[e.target.dataset?.change];
      if (fn) fn(e.target);
    });
    document.addEventListener('visibilitychange', () => { if (!document.hidden) poll.kick(); });
  }

  // ---------------------------------------------------------------- Pairing & install

  function showInstall(code) {
    app.innerHTML = `<div class="onboard">
      <div class="glyph"><img src="/touch-icon.png" alt=""></div>
      <h1>Add My Videos to Your Home Screen</h1>
      <p>It opens full screen, like any other app.${code ? ` When it asks, enter <b style="color:var(--label);letter-spacing:.08em">${esc(code.slice(0, 3))} ${esc(code.slice(3))}</b>.` : ''}</p>
      <div class="steps">
        <div class="step"><span class="n">1</span><div>Tap ${icon('share')} <b>Share</b> in Safari’s toolbar.</div></div>
        <div class="step"><span class="n">2</span><div>Scroll down and tap <b>Add to Home Screen</b>.</div></div>
        <div class="step"><span class="n">3</span><div>Open <b>My Videos</b> from your Home Screen.</div></div>
      </div>
      <button class="link-btn" id="skip-install">Continue in Safari</button>
    </div>`;
    $('#skip-install').onclick = () => { store.set('skipInstall', '1'); showPairing('', code); };
  }

  function showPairing(message = '', presetCode = '') {
    app.innerHTML = `<div class="onboard">
      <div class="glyph"><img src="/touch-icon.png" alt=""></div>
      <h1>Connect to Your Mac</h1>
      <p>On your Mac, open My Videos › Settings › iPhone and enter the code shown there.</p>
      <input class="code-input" id="code" inputmode="numeric" autocomplete="one-time-code" maxlength="7" placeholder="000000" aria-label="Pairing code">
      <div class="error" id="pair-error">${esc(message)}</div>
      <button class="btn primary" id="pair-btn" disabled>Connect</button>
    </div>`;
    const input = $('#code'), btn = $('#pair-btn');
    const fromLink = presetCode || (isStandalone() ? '' : new URLSearchParams(location.search).get('code'));
    if (fromLink) input.value = fromLink;
    if (location.search) history.replaceState(null, '', '/');
    const sync = () => { btn.disabled = input.value.replace(/\D/g, '').length !== 6; };
    input.addEventListener('input', () => {
      input.value = input.value.replace(/\D/g, '').slice(0, 6);
      sync();
      if (input.value.length === 6) btn.click();
    });
    btn.onclick = async () => {
      btn.disabled = true;
      $('#pair-error').textContent = '';
      try {
        const r = await api('/api/pair', { method: 'POST', body: { code: input.value } });
        state.token = r.token; state.mac = r.mac;
        store.set('token', r.token); store.set('mac', r.mac);
        start();
      } catch (e) {
        $('#pair-error').textContent = e.message;
        input.value = ''; sync(); input.focus();
      }
    };
    sync();
    if (fromLink && fromLink.length === 6) btn.click(); else setTimeout(() => input.focus(), 300);
  }

  function disconnect() {
    state.token = null;
    store.set('token', null);
    $('.banner.offline')?.remove();
    showPairing();
  }

  function start() {
    buildShell();
    loadSettings();
    loadSubs();
    poll.kick();
  }

  // ---------------------------------------------------------------- Boot

  document.addEventListener('DOMContentLoaded', () => {
    app = $('#app');
    bindEvents();
    // The QR code on the Mac carries the pairing code. In Safari, guide to the Home Screen
    // first (a Home Screen app has its own storage, so pairing there is what sticks).
    const code = (new URLSearchParams(location.search).get('code') || '').replace(/\D/g, '').slice(0, 6);
    if (state.token) start();
    else if (!isStandalone() && !store.get('skipInstall')) showInstall(code);
    else showPairing('', isStandalone() ? '' : code);
  });
})();
