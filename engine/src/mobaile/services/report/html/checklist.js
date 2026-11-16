/* Checklist dos prints do Figma: marcar, filtrar, buscar e copiar o Markdown.
   O conteúdo inteiro vem desenhado do motor; aqui só muda estado. As marcas
   ficam no navegador (localStorage, por conteúdo do Markdown) e "Copiar
   Markdown" devolve o arquivo com [x] onde foi marcado e [!] onde é bug.
   "Salvar" baixa uma cópia deste HTML com as marcações gravadas nele. */
(function () {
  'use strict';
  var root = document.documentElement;
  var THEME_KEY = 'mobaile-report-theme';
  var STORE = 'mobaile-checklist:' + (document.body.dataset.doc || '');
  function $(sel, el) { return (el || document).querySelector(sel); }
  function $$(sel, el) { return Array.prototype.slice.call((el || document).querySelectorAll(sel)); }

  /* ------------------------------------------------------------ tema */
  var media = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;
  function placeThumb(seg) {
    if (!seg) return;
    var thumb = $('.mb-seg__thumb', seg), sel = $('.mb-seg__item.is-selected', seg);
    if (!thumb || !sel) return;
    thumb.style.left = sel.offsetLeft + 'px';
    thumb.style.width = sel.offsetWidth + 'px';
  }
  function select(seg, attr, value) {
    $$('.mb-seg__item', seg).forEach(function (b) {
      var on = b.dataset[attr] === value;
      b.classList.toggle('is-selected', on);
      b.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
    placeThumb(seg);
  }
  function applyTheme(pref) {
    var dark = pref === 'dark' || (pref === 'auto' && media && media.matches);
    root.dataset.theme = dark ? 'dark' : 'light';
    root.dataset.themePref = pref;
    select($('.rp-theme'), 'pickTheme', pref);
  }
  if (media && media.addEventListener) {
    media.addEventListener('change', function () { if (root.dataset.themePref === 'auto') applyTheme('auto'); });
  }

  /* ----------------------------------------------------------- estado */
  var saved = {};
  try { saved = JSON.parse(localStorage.getItem(STORE) || '{}') || {}; } catch (e) { saved = {}; }
  function persist() {
    var out = {};
    $$('.ck-item').forEach(function (li) { out[li.dataset.line] = li.classList.contains('is-bug') ? 'bug' : li.classList.contains('is-done'); });
    try { localStorage.setItem(STORE, JSON.stringify(out)); } catch (e) { /* sem armazenamento: só nesta aba */ }
  }
  function setDone(li, on) {
    li.classList.toggle('is-done', on);
    var box = $('.mb-check__box', li);
    if (box) box.setAttribute('aria-checked', on ? 'true' : 'false');
  }
  function setBug(li, on) {
    li.classList.toggle('is-bug', on);
    var b = $('.ck-bug', li);
    if (b) b.setAttribute('aria-pressed', on ? 'true' : 'false');
    if (on) setDone(li, false);
  }
  $$('.ck-item').forEach(function (li) {
    if (!Object.prototype.hasOwnProperty.call(saved, li.dataset.line)) return;
    var v = saved[li.dataset.line];
    setBug(li, v === 'bug');
    if (v !== 'bug') setDone(li, !!v);
  });

  /* --------------------------------------------------- dados do teste */
  var FSTORE = STORE + ':dados';
  var fsaved = {};
  try { fsaved = JSON.parse(localStorage.getItem(FSTORE) || '{}') || {}; } catch (e) { fsaved = {}; }
  function fieldsEls() { return $$('[data-field]'); }
  fieldsEls().forEach(function (f) {
    if (Object.prototype.hasOwnProperty.call(fsaved, f.dataset.field)) f.value = fsaved[f.dataset.field];
  });
  function fieldsCount() {
    var all = fieldsEls(), filled = all.filter(function (f) { return f.value.trim(); }).length;
    setText('.ck-test__count', filled + '/' + all.length);
    var dot = $('.ck-test-dot'); if (dot) dot.classList.toggle('rp-dot--ok', filled === all.length);
    return all.length - filled;
  }
  function persistFields() {
    var out = {};
    fieldsEls().forEach(function (f) { out[f.dataset.field] = f.value; });
    try { localStorage.setItem(FSTORE, JSON.stringify(out)); } catch (e) { /* só nesta aba */ }
    fieldsCount();
  }
  document.addEventListener('input', function (e) { if (e.target.dataset && e.target.dataset.field) persistFields(); });
  document.addEventListener('change', function (e) { if (e.target.dataset && e.target.dataset.field) persistFields(); });
  function fmt(f) {
    var v = f.value.trim();
    var m = f.type === 'date' && /^(\d{4})-(\d{2})-(\d{2})$/.exec(v);
    return m ? m[3] + '/' + m[2] + '/' + m[1] : v;
  }

  function setText(sel, text) { $$(sel).forEach(function (el) { el.textContent = text; }); }
  function counts() {
    var items = $$('.ck-item'), total = items.length, done = 0, warnOpen = 0, bugs = 0;
    items.forEach(function (li) {
      var d = li.classList.contains('is-done');
      if (d) done++;
      if (li.classList.contains('is-bug')) bugs++;
      if (!d && li.dataset.warn === '1') warnOpen++;
    });
    setText('[data-n="all"]', String(total));
    setText('[data-n="done"]', String(done));
    setText('[data-n="open"]', String(total - done));
    setText('[data-n="warn"]', String(warnOpen));
    setText('[data-n="bug"]', String(bugs));
    var bugTile = $('.rp-tile[data-filter="bug"] .mb-status');
    if (bugTile) {
      bugTile.classList.toggle('mb-status--error', bugs > 0);
      bugTile.classList.toggle('mb-status--off', bugs === 0);
    }
    setText('.ck-sub', done + ' de ' + total + ' feitos');
    setText('.ck-total-count', done + '/' + total);
    var pct = total ? Math.round(done / total * 100) : 0;
    setText('.ck-pct', pct + '%');
    var ring = $('.ck-ring'), seg = $('.ck-ring__seg');
    if (ring && seg) {
      var c = parseFloat(ring.dataset.c) || 0;
      seg.setAttribute('stroke-dasharray', (total ? c * done / total : 0).toFixed(2) + ' ' + c.toFixed(2));
    }
    var warnTile = $('.rp-tile[data-filter="warn"] .mb-status');
    if (warnTile) {
      warnTile.classList.toggle('mb-status--warn', warnOpen > 0);
      warnTile.classList.toggle('mb-status--off', warnOpen === 0);
    }
    var resumoDot = $('.rp-nav a[href="#resumo"] .rp-dot');
    if (resumoDot) resumoDot.classList.toggle('rp-dot--ok', total > 0 && done === total);
    $$('.ck-section').forEach(function (sec) {
      var all = $$('.ck-item', sec), d = all.filter(function (li) { return li.classList.contains('is-done'); }).length;
      setText('[data-sec="' + sec.id + '"]', d + '/' + all.length);
      var dot = $('.rp-nav a[href="#' + sec.id + '"] .rp-dot');
      if (dot) dot.classList.toggle('rp-dot--ok', all.length > 0 && d === all.length);
    });
    $$('.ck-card').forEach(function (card) {
      var all = $$('.ck-item', card), d = all.filter(function (li) { return li.classList.contains('is-done'); }).length;
      var pill = $('.ck-card__count', card);
      if (pill) pill.textContent = d + '/' + all.length;
      card.classList.toggle('is-complete', all.length > 0 && d === all.length);
    });
  }

  /* ---------------------------------------------------- filtro e busca */
  var state = { filter: 'all', query: '' };
  var MATCH = {
    all: function () { return true; },
    open: function (li) { return !li.classList.contains('is-done'); },
    done: function (li) { return li.classList.contains('is-done'); },
    warn: function (li) { return li.dataset.warn === '1' && !li.classList.contains('is-done'); },
    bug: function (li) { return li.classList.contains('is-bug'); }
  };
  function terms() { return state.query.toLowerCase().split(/\s+/).filter(Boolean); }
  function hit(text, ts) {
    for (var i = 0; i < ts.length; i++) if (text.indexOf(ts[i]) < 0) return false;
    return true;
  }
  function apply() {
    var ts = terms(), ok = MATCH[state.filter] || MATCH.all, shown = 0, total = 0, filtering = state.filter !== 'all' || ts.length > 0;
    $$('.ck-card').forEach(function (card) {
      // A busca vale para o card inteiro: achar 'screen_name' mostra os disparos dele.
      var cardHit = !ts.length || hit(card.textContent.toLowerCase(), ts);
      var any = false;
      $$('.ck-item', card).forEach(function (li) {
        total++;
        var on = ok(li) && cardHit;
        li.hidden = !on;
        if (on) { shown++; any = true; }
      });
      card.hidden = filtering && !any;
    });
    $$('.ck-section').forEach(function (sec) {
      var visible = !!$('.ck-card:not([hidden])', sec);
      sec.hidden = filtering && !visible;
      var link = $('.rp-nav a[href="#' + sec.id + '"]');
      if (link) link.classList.toggle('is-empty', filtering && !visible);
    });
    var counter = $('.rp-result-count');
    if (counter) counter.textContent = shown === total ? total + ' itens' : shown + ' de ' + total + ' itens';
    var empty = $('.rp-empty');
    if (empty) empty.hidden = shown > 0 || total === 0;
  }
  function setFilter(value) {
    state.filter = MATCH[value] ? value : 'all';
    select($('.rp-filter'), 'filter', state.filter);
    apply();
  }

  /* ------------------------------------------------- copiar e aviso */
  var toastTimer = null;
  function toast(msg) {
    var t = $('.rp-toast');
    if (!t) return;
    $('span', t).textContent = msg;
    t.style.transition = 'opacity .18s';
    t.style.opacity = '1';
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { t.style.opacity = '0'; }, 1600);
  }
  function legacyCopy(text) {
    var ta = document.createElement('textarea');
    ta.value = text; ta.setAttribute('readonly', ''); ta.style.position = 'fixed'; ta.style.opacity = '0';
    document.body.appendChild(ta); ta.select();
    var ok = false;
    try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
    document.body.removeChild(ta);
    return ok;
  }
  function copy(text, msg) {
    var done = function () { toast(msg || 'Markdown copiado com as marcações'); };
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(done, function () { if (legacyCopy(text)) done(); });
    } else if (legacyCopy(text)) { done(); }
  }
  function markdown() {
    var src = $('#ck-md');
    var lines = (src ? src.value : '').split('\n');
    $$('.ck-item').forEach(function (li) {
      var n = parseInt(li.dataset.line, 10);
      if (isNaN(n) || lines[n] === undefined) return;
      var mark = li.classList.contains('is-bug') ? '[!]' : li.classList.contains('is-done') ? '[x]' : '[ ]';
      lines[n] = lines[n].replace(/\[[ xX!]\]/, mark);
    });
    // Dados do teste no cabeçalho, como `- Rótulo: valor` (troca os que já houver).
    var labels = fieldsEls().map(function (f) { return f.dataset.label.toLowerCase(); });
    var head = lines.findIndex(function (l) { return /^##\s/.test(l); });
    if (head < 0) head = lines.length;
    var top = lines.slice(0, head).filter(function (l) {
      var m = /^\s*[-*+]\s+([^:]+):/.exec(l);
      return !(m && labels.indexOf(m[1].trim().toLowerCase()) >= 0);
    });
    var at = 0;
    top.forEach(function (l, i) { if (/^\s*[-*+]\s/.test(l)) at = i + 1; });
    var add = fieldsEls().filter(function (f) { return f.value.trim(); })
      .map(function (f) { return '- ' + f.dataset.label + ': ' + fmt(f); });
    top.splice.apply(top, [at, 0].concat(add));
    return top.concat(lines.slice(head)).join('\n');
  }

  /* --------------------------------------------------------- salvar */
  function save() {
    // Grava o estado no próprio HTML: as classes dos itens e o Markdown embutido.
    var src = $('#ck-md'); if (src) src.textContent = markdown();
    var missing = fieldsCount();
    var clone = root.cloneNode(true);
    // Os valores digitados não vão no outerHTML: grava como atributo.
    var cf = $$('[data-field]', clone);
    fieldsEls().forEach(function (f, i) {
      var c = cf[i]; if (!c) return;
      if (c.tagName === 'SELECT') {
        $$('option', c).forEach(function (o) { if (o.value === f.value) o.setAttribute('selected', ''); else o.removeAttribute('selected'); });
      } else { c.setAttribute('value', f.value); }
    });
    $$('[hidden]', clone).forEach(function (el) {
      if (!el.classList.contains('rp-empty') && el.id !== 'ck-md') el.hidden = false;
    });
    $$('.is-current', clone).forEach(function (el) { el.classList.remove('is-current'); });
    var t = $('.rp-toast', clone); if (t) t.style.cssText = '';
    delete clone.dataset.theme;
    var html = '<!doctype html>' + clone.outerHTML;
    var name = decodeURIComponent(location.pathname.split('/').pop() || '') || 'checklist.html';
    if (!/\.html?$/i.test(name)) name += '.html';
    var a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([html], { type: 'text/html' }));
    a.download = name;
    document.body.appendChild(a); a.click(); document.body.removeChild(a);
    setTimeout(function () { URL.revokeObjectURL(a.href); }, 1000);
    toast(missing ? 'HTML salvo · faltam ' + missing + ' dados do teste' : 'HTML salvo com o que já foi conferido');
  }

  /* -------------------------------------------------------- eventos */
  function changed() { persist(); counts(); if (state.filter !== 'all') apply(); }
  function toggleBug(li) { setBug(li, !li.classList.contains('is-bug')); changed(); }
  function toggle(li) {
    if (li.classList.contains('is-bug')) setBug(li, false);
    setDone(li, !li.classList.contains('is-done'));
    persist(); counts();
    if (state.filter !== 'all') apply();
  }
  document.addEventListener('click', function (e) {
    var cp = e.target.closest('.ck-copy');
    if (cp) { copy(cp.dataset.copy || '', 'Copiado: ' + (cp.dataset.copy || '').replace(/\n/g, ' · ')); return; }
    var bug = e.target.closest('.ck-bug');
    if (bug) { toggleBug(bug.closest('.ck-item')); return; }
    var el = e.target.closest('[data-filter], [data-pick-theme], [data-act], .ck-item');
    if (!el) return;
    if (el.dataset.filter) { setFilter(el.dataset.filter); return; }
    if (el.dataset.pickTheme) {
      try { localStorage.setItem(THEME_KEY, el.dataset.pickTheme); } catch (err) { /* só nesta aba */ }
      applyTheme(el.dataset.pickTheme); return;
    }
    if (el.dataset.act === 'copy') { copy(markdown()); return; }
    if (el.dataset.act === 'print') { window.print(); return; }
    if (el.dataset.act === 'save') { save(); return; }
    if (el.dataset.act === 'all') {
      state.query = ''; var q = $('#ck-q'); if (q) q.value = '';
      setFilter('all'); return;
    }
    if (el.classList.contains('ck-item') && !e.target.closest('a')) toggle(el);
  });
  var q = $('#ck-q');
  if (q) q.addEventListener('input', function () { state.query = q.value; apply(); });
  document.addEventListener('keydown', function (e) {
    var typing = /^(INPUT|TEXTAREA|SELECT)$/.test((e.target.tagName || '')) || e.target.isContentEditable;
    if (e.key === 'Escape' && typing && q) { q.value = ''; state.query = ''; q.blur(); apply(); return; }
    if (typing || e.metaKey || e.ctrlKey || e.altKey) return;
    if (e.key === '/') { e.preventDefault(); if (q) q.focus(); return; }
    var keys = { '1': 'all', '2': 'open', '3': 'done', '4': 'warn', '5': 'bug' };
    if (keys[e.key]) { setFilter(keys[e.key]); return; }
    if (e.key === 'c') copy(markdown());
    if (e.key === 's') save();
  });

  /* Barra lateral: marca a seção visível. */
  if ('IntersectionObserver' in window) {
    var links = {};
    $$('.rp-nav a').forEach(function (a) { links[a.getAttribute('href').slice(1)] = a; });
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (!en.isIntersecting || !links[en.target.id]) return;
        $$('.rp-nav a.is-current').forEach(function (a) { a.classList.remove('is-current'); });
        links[en.target.id].classList.add('is-current');
      });
    }, { rootMargin: '-120px 0px -65% 0px' });
    $$('#resumo, #dados-teste, .ck-section').forEach(function (s) { io.observe(s); });
  }
  window.addEventListener('scroll', function () {
    var tb = $('.rp-toolbar'); if (tb) tb.classList.toggle('is-scrolled', window.scrollY > 4);
  }, { passive: true });

  applyTheme(root.dataset.themePref || 'auto');
  fieldsCount();
  counts();
  apply();
  window.addEventListener('resize', function () { placeThumb($('.rp-filter')); placeThumb($('.rp-theme')); });
}());
