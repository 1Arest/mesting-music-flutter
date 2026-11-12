'use strict';
(() => {
  const root = document.documentElement;
  const systemDark = window.matchMedia('(prefers-color-scheme: dark)');
  const motion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const palettes = ['sea', 'sakura', 'lavender', 'caramel'];
  const modes = ['auto', 'light', 'dark'];
  const names = {auto: '跟随系统', light: '浅色', dark: '深色'};
  const read = (key, fallback, allowed) => {
    try { const value = localStorage.getItem(key); return allowed.includes(value) ? value : fallback; }
    catch (_) { return fallback; }
  };
  const store = (key, value) => { try { localStorage.setItem(key, value); } catch (_) {} };
  function setMode(value) {
    if (!modes.includes(value)) return;
    root.dataset.mode = value;
    root.dataset.resolved = value === 'auto' ? (systemDark.matches ? 'dark' : 'light') : value;
    document.querySelectorAll('button[data-mode]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.mode === value)));
    const toggle = document.querySelector('.mode-toggle');
    toggle.setAttribute('aria-label', `外观：${names[value]}，点击切换`);
    toggle.setAttribute('title', `网页外观：${names[value]}`);
    toggle.querySelector('use').setAttribute('href', root.dataset.resolved === 'dark' ? '#moon' : '#sun');
    document.querySelector('meta[name="theme-color"]').content = root.dataset.resolved === 'dark' ? '#11151c' : '#f5f7fb';
    store('mesting-web-mode', value);
  }
  function setPalette(value) {
    if (!palettes.includes(value)) return;
    root.dataset.palette = value;
    document.querySelectorAll('button[data-palette]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.palette === value)));
    store('mesting-web-palette', value);
  }
  setMode(read('mesting-web-mode', 'auto', modes));
  setPalette(read('mesting-web-palette', 'sea', palettes));
  systemDark.addEventListener('change', () => { if (root.dataset.mode === 'auto') setMode('auto'); });
  document.querySelector('.mode-toggle').addEventListener('click', () => setMode(modes[(modes.indexOf(root.dataset.mode) + 1) % modes.length]));
  document.querySelectorAll('button[data-mode]').forEach(button => button.addEventListener('click', () => setMode(button.dataset.mode)));
  document.querySelectorAll('button[data-palette]').forEach(button => button.addEventListener('click', () => setPalette(button.dataset.palette)));
  const nav = document.querySelector('#navigation');
  const menu = document.querySelector('.menu-toggle');
  const closeMenu = () => { nav.classList.remove('open'); menu.setAttribute('aria-expanded', 'false'); menu.setAttribute('aria-label', '展开导航'); };
  menu.addEventListener('click', () => { const open = nav.classList.toggle('open'); menu.setAttribute('aria-expanded', String(open)); menu.setAttribute('aria-label', open ? '收起导航' : '展开导航'); });
  nav.querySelectorAll('a').forEach(link => link.addEventListener('click', closeMenu));
  document.addEventListener('keydown', event => { if (event.key === 'Escape' && nav.classList.contains('open')) { closeMenu(); menu.focus(); } });
  document.addEventListener('click', event => { if (!event.target.closest('.site-nav')) closeMenu(); });
  const player = document.querySelector('#player-demo');
  const play = document.querySelector('#demo-play');
  const mute = document.querySelector('#song-mute');
  const skips = player.querySelectorAll('[data-skip]');
  const songPlayer = document.querySelector('#song-player');
  const songStatus = document.querySelector('#song-status');
  const progress = document.querySelector('#song-progress');
  const elapsed = document.querySelector('#song-elapsed');
  const duration = document.querySelector('#song-duration');

  function showSongStatus(message) {
    songStatus.textContent = message;
    songStatus.hidden = !message;
  }

  function formatTime(seconds) {
    const value = Math.floor(seconds);
    return [Math.floor(value / 60), value % 60].map(part => String(part).padStart(2, '0')).join(':');
  }

  function updateSongProgress() {
    const total = songPlayer.duration;
    const canSeek = Number.isFinite(total) && total > 0;
    progress.disabled = !canSeek;
    skips.forEach(button => { button.disabled = !canSeek; });
    if (!canSeek) return;
    const position = Math.min(total, songPlayer.currentTime);
    progress.max = String(total);
    progress.value = String(position);
    progress.style.setProperty('--played', `${position / total * 100}%`);
    elapsed.textContent = formatTime(songPlayer.ended ? Math.round(total) : position);
    duration.textContent = formatTime(Math.round(total));
    progress.setAttribute('aria-valuetext', `${elapsed.textContent} / ${duration.textContent}`);
  }

  function updatePlayButton() {
    const playing = !songPlayer.paused && !songPlayer.ended;
    play.setAttribute('aria-label', playing ? '暂停《暖一杯茶》' : '播放《暖一杯茶》');
    play.querySelector('use').setAttribute('href', playing ? '#pause' : '#play');
  }

  play.addEventListener('click', () => {
    if (!songPlayer.paused && !songPlayer.ended) {
      songPlayer.pause();
      return;
    }
    showSongStatus('');
    if (!songPlayer.hasAttribute('src') || songPlayer.error) songPlayer.src = songPlayer.dataset.src;
    songPlayer.play().catch(error => {
      if (error.name !== 'AbortError') showSongStatus('暂时无法播放，请再点一次播放键。');
    });
  });

  progress.addEventListener('input', () => {
    songPlayer.currentTime = Number(progress.value);
    updateSongProgress();
  });

  ['loadedmetadata', 'durationchange', 'timeupdate', 'pause', 'ended', 'emptied'].forEach(event => {
    songPlayer.addEventListener(event, updateSongProgress);
  });
  ['play', 'pause', 'ended', 'error'].forEach(event => {
    songPlayer.addEventListener(event, updatePlayButton);
  });
  skips.forEach(button => button.addEventListener('click', () => {
    songPlayer.currentTime = Math.min(songPlayer.duration, Math.max(0, songPlayer.currentTime + Number(button.dataset.skip)));
    updateSongProgress();
  }));
  mute.addEventListener('click', () => { songPlayer.muted = !songPlayer.muted; });
  songPlayer.addEventListener('volumechange', () => {
    const muted = songPlayer.muted;
    mute.setAttribute('aria-pressed', String(muted));
    mute.querySelector('use').setAttribute('href', muted ? '#speaker-off' : '#speaker');
  });
  songPlayer.addEventListener('playing', () => {
    player.dataset.playing = 'true';
    showSongStatus('');
  });
  ['pause', 'ended', 'waiting', 'error'].forEach(event => {
    songPlayer.addEventListener(event, () => { player.dataset.playing = 'false'; });
  });
  songPlayer.addEventListener('error', () => showSongStatus('音频暂时无法加载，请再点一次播放键。'));
  const lyricWindow = document.querySelector('.lyrics-window');
  document.querySelectorAll('[data-lyric]').forEach(button => button.addEventListener('click', () => { lyricWindow.dataset.effect = button.dataset.lyric; document.querySelectorAll('[data-lyric]').forEach(item => item.setAttribute('aria-pressed', String(item === button))); }));
  document.querySelector('#lyric-size').addEventListener('input', event => { const size = Number(event.target.value); document.querySelector('#size-value').textContent = size; document.querySelector('.lyric-preview').style.setProperty('--lyric-size', `${size}px`); });
  let toastTimer;
  function toast(message) { const element = document.querySelector('#toast'); clearTimeout(toastTimer); element.textContent = message; element.hidden = false; toastTimer = setTimeout(() => { element.hidden = true; }, 2800); }
  document.querySelector('#copy-link').addEventListener('click', async () => {
    const url = 'https://download.csnas.asia/music/';
    try { await navigator.clipboard.writeText(url); toast('官网链接已复制，可发送到手机打开'); }
    catch (_) { const dialog = document.querySelector('#copy-dialog'); dialog.showModal(); dialog.querySelector('input').select(); }
  });
  // Initial page load only fetches the small public release manifest.
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 5000);
  fetch('/api/app/music/health', {signal: controller.signal, credentials: 'omit', cache: 'no-store'})
    .then(response => { if (!response.ok) throw new Error('release unavailable'); return response.json(); })
    .then(data => {
      if (data.app_slug !== 'music' || data.status !== 'ok' || typeof data.version !== 'string' || !/^[\dA-Za-z.+_-]{1,40}$/.test(data.version)) throw new Error('invalid release');
      const bytes = Number(data.file_size);
      const size = Number.isFinite(bytes) && bytes > 0 ? ` · ${(bytes / 1048576).toFixed(1)} MiB` : '';
      document.querySelectorAll('[data-release]').forEach(element => { element.textContent = `Android · 当前发布 ${data.version}${size}`; });
    })
    .catch(() => { document.querySelectorAll('[data-release]').forEach(element => { element.textContent = 'Android 安装包 · 版本信息以下载入口为准'; }); })
    .finally(() => clearTimeout(timeout));
  if (!motion.matches && 'IntersectionObserver' in window) {
    const reveals = document.querySelectorAll('.reveal');
    const observer = new IntersectionObserver(entries => {
      const visible = entries.filter(entry => entry.isIntersecting);
      visible.forEach((entry, index) => {
        entry.target.style.setProperty('--reveal-delay', `${Math.min(index, 3) * 65}ms`);
        entry.target.classList.add('visible');
        observer.unobserve(entry.target);
      });
    }, {threshold: .1});
    root.classList.add('motion-ready'); reveals.forEach(element => observer.observe(element));
    // A background tab may defer IntersectionObserver; content remains usable.
    window.addEventListener('beforeprint', () => { reveals.forEach(element => element.classList.add('visible')); });
  }
})();
