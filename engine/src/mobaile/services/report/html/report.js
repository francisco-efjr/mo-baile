/* Relatório de tagueamento — interação do HTML exportado.
   Todo o conteúdo já vem desenhado pelo motor; este script só filtra, ordena,
   amplia e anima. Sem ele (ou sem o Motion) a página continua completa.
   Molas do design system: snappy 0,35 s / bounce 0,15 e smooth 0,5 s / bounce 0.
   Nada aqui usa innerHTML: o texto da spec e do log nunca vira marcação. */
(function () {
  'use strict';
  var M = window.Motion || null;
  var root = document.documentElement;
  var reduce = root.dataset.reduceMotion === 'true';
  var SNAPPY = { type: 'spring', visualDuration: 0.35, bounce: 0.15 };
  var SMOOTH = { type: 'spring', visualDuration: 0.5, bounce: 0 };
  var THEME_KEY = 'mobaile-report-theme';

  function $(sel, ctx) { return (ctx || document).querySelector(sel); }
  function $$(sel, ctx) { return Array.prototype.slice.call((ctx || document).querySelectorAll(sel)); }

  // Rede de segurança: toda animação termina em até 1,5 s, mesmo quando o
  // navegador não roda quadros (aba em segundo plano, máquina ocupada). Sem
  // isso, um card que começou em opacidade 0 podia ficar invisível.
  function settle(controls) {
    if (controls && controls.complete) {
      setTimeout(function () { try { controls.complete(); } catch (e) { /* já terminou */ } }, 1500);
    }
    return controls;
  }

  // Com Reduzir movimento, deslizar e escalar viram só esmaecer (como no app).
  function anim(el, kf, opt) {
    if (!M || !el || (el.length === 0)) return null;
    if (reduce) {
      if (!kf.opacity) return null;
      return settle(M.animate(el, { opacity: kf.opacity }, { duration: 0.18 }));
    }
    return settle(M.animate(el, kf, opt || SMOOTH));
  }
  function stagger(step) { return M && M.stagger ? M.stagger(step) : 0; }

  function fmtPct(v) { return v.toLocaleString('pt-BR', { minimumFractionDigits: 1, maximumFractionDigits: 1 }) + '%'; }

  /* ------------------------------------------------------------ tema */
  var media = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;
  function applyTheme(pref) {
    var dark = pref === 'dark' || (pref === 'auto' && media && media.matches);
    var set = function () { root.dataset.theme = dark ? 'dark' : 'light'; root.dataset.themePref = pref; };
    if (document.startViewTransition && !reduce && root.dataset.theme !== (dark ? 'dark' : 'light')) {
      document.startViewTransition(set);
    } else { set(); }
    $$('.rp-theme .mb-seg__item').forEach(function (b) {
      var on = b.dataset.pickTheme === pref;
      b.classList.toggle('is-selected', on);
      b.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
    placeThumb($('.rp-theme'));
  }
  if (media && media.addEventListener) {
    media.addEventListener('change', function () { if (root.dataset.themePref === 'auto') applyTheme('auto'); });
  }

  /* ------------------------------------------------------ segmentado */
  function placeThumb(seg) {
    if (!seg) return;
    var thumb = $('.mb-seg__thumb', seg), sel = $('.mb-seg__item.is-selected', seg);
    if (!thumb || !sel) return;
    thumb.style.left = sel.offsetLeft + 'px';
    thumb.style.width = sel.offsetWidth + 'px';
  }

  /* ---------------------------------------------------- filtro e busca */
  var state = { filter: 'all', query: '', view: 'cards' };
  var MATCH = {
    all: function () { return true; },
    action: function (s) { return s === 'err' || s === 'miss'; },
    err: function (s) { return s === 'err'; },
    miss: function (s) { return s === 'miss'; },
    ok: function (s) { return s === 'ok'; },
    off: function () { return false; }
  };

  function terms() { return state.query.toLowerCase().split(/\s+/).filter(Boolean); }
  function hit(el, ts) {
    if (!ts.length) return true;
    var q = el.dataset.q || '';
    for (var i = 0; i < ts.length; i++) if (q.indexOf(ts[i]) < 0) return false;
    return true;
  }

  function apply(animate) {
    var ts = terms(), ok = MATCH[state.filter] || MATCH.all, shown = 0, revealed = [];
    $$('.rp-view--cards .v').forEach(function (v) {
      var on = ok(v.dataset.s) && hit(v, ts);
      v.hidden = !on; if (on) shown++;
    });
    $$('.rp-card').forEach(function (card) {
      var on = !!$('.v:not([hidden])', card);
      if (on && card.hidden) revealed.push(card);
      card.hidden = !on;
      $$('.rp-col', card).forEach(function (col) { col.hidden = !$('.v:not([hidden])', col); });
    });
    $$('.rp-section').forEach(function (sec) {
      var n = $$('.v:not([hidden])', sec).length;
      sec.hidden = n === 0;
      var link = $('.rp-nav a[href="#' + sec.id + '"]');
      if (link) {
        link.classList.toggle('is-empty', n === 0);
        var c = $('.mb-count', link); if (c) c.textContent = String(n);
      }
    });
    $$('.rp-table tbody tr').forEach(function (tr) { tr.hidden = !(ok(tr.dataset.s) && hit(tr, ts)); });

    var extras = $('#fora-da-spec');
    if (extras) {
      var showExtras = state.filter === 'all' || state.filter === 'off';
      var visibleRows = 0, visibleExtras = 0;
      $$('.rp-mini tbody tr', extras).forEach(function (tr) {
        tr.hidden = !hit(tr, ts);
        if (tr.hidden) return;
        visibleRows++;
        if (tr.dataset.k === 'extra') visibleExtras++;
      });
      extras.hidden = !showExtras || (ts.length > 0 && visibleRows === 0);
      if (state.filter === 'off') shown = visibleExtras;
    }

    var total = $$('.rp-view--cards .v').length;
    var counter = $('.rp-result-count');
    if (counter) {
      counter.textContent = state.filter === 'off'
        ? shown + (shown === 1 ? ' evento fora da spec' : ' eventos fora da spec')
        : (shown === total ? total + ' validações' : shown + ' de ' + total + ' validações');
    }
    var empty = $('.rp-empty');
    if (empty) empty.hidden = shown > 0 || !!(extras && !extras.hidden);

    $$('.rp-filter .mb-seg__item').forEach(function (b) {
      var on = b.dataset.filter === state.filter;
      b.classList.toggle('is-selected', on);
      b.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
    $$('.rp-tile').forEach(function (t) { t.classList.toggle('is-active', t.dataset.filter === state.filter && state.filter !== 'all'); });
    placeThumb($('.rp-filter'));

    if (animate && revealed.length) {
      anim(revealed.slice(0, 12), { opacity: [0, 1], y: [8, 0] }, Object.assign({ delay: stagger(0.035) }, SNAPPY));
    }
  }

  function setFilter(f) { state.filter = f; apply(true); }

  /* --------------------------------------------------------- visões */
  function setView(view) {
    if (state.view === view) return;
    state.view = view;
    var cards = $('.rp-view--cards'), table = $('.rp-view--table');
    cards.hidden = view !== 'cards';
    table.hidden = view !== 'table';
    $$('.rp-viewseg .mb-seg__item').forEach(function (b) {
      var on = b.dataset.view === view;
      b.classList.toggle('is-selected', on);
      b.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
    placeThumb($('.rp-viewseg'));
    anim(view === 'cards' ? cards : table, { opacity: [0, 1], y: [6, 0] }, SNAPPY);
  }

  function goToCard(id) {
    setView('cards');
    var card = document.getElementById(id);
    if (!card) return;
    if (card.hidden) { state.filter = 'all'; apply(false); }
    card.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' });
    card.classList.remove('is-flash');
    void card.offsetWidth;
    card.classList.add('is-flash');
  }

  /* ---------------------------------------------------- tabela */
  function sortBy(th) {
    var table = th.closest('table'), tbody = table.tBodies[0];
    var idx = Array.prototype.indexOf.call(th.parentNode.children, th);
    var dir = th.getAttribute('aria-sort') === 'ascending' ? 'descending' : 'ascending';
    $$('th', table).forEach(function (h) { h.removeAttribute('aria-sort'); });
    th.setAttribute('aria-sort', dir);
    var numeric = th.dataset.type === 'num';
    var rows = $$('tr', tbody);
    rows.sort(function (a, b) {
      var x = a.children[idx], y = b.children[idx];
      var vx = x.dataset.sort || x.textContent, vy = y.dataset.sort || y.textContent;
      var r = numeric ? (parseFloat(vx) || 0) - (parseFloat(vy) || 0) : vx.localeCompare(vy, 'pt-BR', { numeric: true });
      return dir === 'ascending' ? r : -r;
    });
    rows.forEach(function (r) { tbody.appendChild(r); });
    anim(rows.filter(function (r) { return !r.hidden; }).slice(0, 30), { opacity: [0.35, 1] }, { duration: 0.25, delay: stagger(0.008) });
  }

  /* ------------------------------------------------- copiar e aviso */
  var toastTimer = null;
  function toast(msg) {
    var t = $('.rp-toast');
    if (!t) return;
    $('span', t).textContent = msg;
    clearTimeout(toastTimer);
    if (M) anim(t, { opacity: [0, 1], y: [10, 0] }, SNAPPY); else t.style.opacity = '1';
    toastTimer = setTimeout(function () {
      if (M) M.animate(t, { opacity: 0 }, { duration: 0.15 }); else t.style.opacity = '0';
    }, 1600);
  }
  function copy(text) {
    var done = function () { toast('Copiado'); };
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(done, function () { legacyCopy(text) && done(); });
    } else if (legacyCopy(text)) { done(); }
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

  function toggleBlock(v, force) {
    var pre = $('.v__block', v), btn = $('[data-act="block"]', v);
    if (!pre) return;
    var open = force === undefined ? pre.hidden : force;
    if (open === !pre.hidden) return;
    pre.hidden = !open;
    if (btn) btn.setAttribute('aria-expanded', open ? 'true' : 'false');
    if (open) anim(pre, { opacity: [0, 1], y: [-4, 0] }, SNAPPY);
  }
  var allOpen = false;
  function toggleAllBlocks() {
    allOpen = !allOpen;
    $$('.rp-view--cards .v').forEach(function (v) { toggleBlock(v, allOpen); });
    var b = $('[data-act="blocks"]');
    if (b) {
      b.setAttribute('aria-pressed', allOpen ? 'true' : 'false');
      $('span', b).textContent = allOpen ? 'Recolher Blocos' : 'Expandir Blocos';
    }
  }

  /* ------------------------------------------------ print ampliado */
  var dlg = $('.rp-lightbox');
  function openPrint(btn) {
    if (!dlg || !dlg.showModal) return;
    var img = $('img', btn);
    $('img', dlg).src = img.src;
    $('img', dlg).alt = img.alt;
    $('.rp-lightbox__bar span', dlg).textContent = btn.dataset.title || '';
    dlg.showModal();
    anim($('.rp-lightbox__frame', dlg), { opacity: [0, 1], scale: [0.95, 1] }, SMOOTH);
  }
  function closePrint() {
    if (!dlg || !dlg.open) return;
    var a = M && !reduce ? M.animate($('.rp-lightbox__frame', dlg), { opacity: 0, scale: 0.97 }, { duration: 0.15 }) : null;
    if (a && a.then) a.then(function () { dlg.close(); }); else dlg.close();
  }

  /* ------------------------------------------------------ entrada */
  function intro() {
    var ring = $('.rp-ring');
    if (ring) {
      var segs = $$('.rp-ring__seg', ring), C = parseFloat(ring.dataset.c);
      var value = $('.rp-ring__value', ring), target = parseFloat(ring.dataset.rate) || 0;
      var draw = function (p) {
        segs.forEach(function (s) {
          var len = parseFloat(s.dataset.len) * p, start = parseFloat(s.dataset.start) * p;
          s.setAttribute('stroke-dasharray', len + ' ' + C);
          s.setAttribute('stroke-dashoffset', String(-start));
        });
        if (value) value.textContent = fmtPct(target * p);
      };
      if (M && !reduce) {
        draw(0);
        settle(M.animate(0, 1, { duration: 1.1, ease: [0.2, 0.8, 0.2, 1], delay: 0.15, onUpdate: draw }));
      }
    }
    anim($$('.rp-tile'), { opacity: [0, 1], y: [10, 0] }, Object.assign({ delay: stagger(0.045, 0.1) }, SNAPPY));
    anim($$('.rp-hero__title, .rp-hero__meta'), { opacity: [0, 1], y: [6, 0] }, Object.assign({ delay: stagger(0.06) }, SMOOTH));

    if (!M || reduce || !M.inView) return;
    var vh = window.innerHeight;
    $$('.rp-card, .rp-extras .mb-card').forEach(function (card) {
      if (card.getBoundingClientRect().top < vh) {
        anim(card, { opacity: [0, 1], y: [12, 0] }, Object.assign({ delay: 0.2 }, SMOOTH));
        return;
      }
      card.style.opacity = '0';
      M.inView(card, function () {
        settle(M.animate(card, { opacity: [0, 1], y: [16, 0] }, SMOOTH));
      }, { amount: 0.08 });
    });
  }

  /* ------------------------------------------------ barra lateral */
  function spy() {
    if (!('IntersectionObserver' in window)) return;
    var links = $$('.rp-nav a');
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        links.forEach(function (l) { l.classList.toggle('is-current', l.getAttribute('href') === '#' + e.target.id); });
      });
    }, { rootMargin: '-130px 0px -65% 0px' });
    $$('.rp-section, #fora-da-spec, #resumo').forEach(function (s) { io.observe(s); });
  }

  /* --------------------------------------------------------- eventos */
  function typing(e) { var t = e.target; return t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable); }

  document.addEventListener('click', function (e) {
    if (dlg && e.target === dlg) { closePrint(); return; }
    var el = e.target.closest('[data-filter], [data-view], [data-pick-theme], [data-act], .rp-print, .rp-table th, .rp-table tbody tr, .rp-nav a');
    if (!el) return;
    if (el.matches('.rp-print')) { openPrint(el); return; }
    if (el.matches('.rp-table th')) { sortBy(el); return; }
    if (el.matches('.rp-table tbody tr')) { goToCard(el.dataset.target); return; }
    if (el.matches('.rp-nav a')) {
      var target = $(el.getAttribute('href'));
      if (target) {
        e.preventDefault();
        if (target.classList.contains('rp-section')) setView('cards');
        target.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' });
      }
      return;
    }
    if (el.dataset.filter !== undefined) { setFilter(el.dataset.filter); return; }
    if (el.dataset.view !== undefined) { setView(el.dataset.view); return; }
    if (el.dataset.pickTheme !== undefined) {
      try { localStorage.setItem(THEME_KEY, el.dataset.pickTheme); } catch (err) { /* sem armazenamento: vale só nesta aba */ }
      applyTheme(el.dataset.pickTheme);
      return;
    }
    switch (el.dataset.act) {
      case 'block': toggleBlock(el.closest('.v')); break;
      case 'copy': copy($('.v__block', el.closest('.v')).textContent); break;
      case 'blocks': toggleAllBlocks(); break;
      case 'close': closePrint(); break;
      case 'clear': setSearch(''); break;
      case 'all': state.query = ''; $('#rp-q').value = ''; setFilter('all'); break;
    }
  });

  var search = $('#rp-q'), searchTimer = null;
  function setSearch(v) { search.value = v; state.query = v; apply(true); }
  if (search) {
    search.addEventListener('input', function () {
      clearTimeout(searchTimer);
      searchTimer = setTimeout(function () { state.query = search.value.trim(); apply(true); }, 90);
    });
    search.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') { setSearch(''); search.blur(); }
    });
  }
  if (dlg) dlg.addEventListener('cancel', function (e) { e.preventDefault(); closePrint(); });

  var FILTER_KEYS = { '1': 'all', '2': 'action', '3': 'err', '4': 'miss', '5': 'ok', '6': 'off' };
  document.addEventListener('keydown', function (e) {
    if (e.metaKey || e.ctrlKey || e.altKey || typing(e)) return;
    if (e.key === '/') { e.preventDefault(); search && search.focus(); return; }
    if (FILTER_KEYS[e.key]) { setFilter(FILTER_KEYS[e.key]); return; }
    if (e.key === 'b') { toggleAllBlocks(); return; }
    if (e.key === 't') { setView(state.view === 'cards' ? 'table' : 'cards'); }
  });

  var toolbar = $('.rp-toolbar'), ticking = false;
  window.addEventListener('scroll', function () {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(function () { toolbar.classList.toggle('is-scrolled', window.scrollY > 4); ticking = false; });
  }, { passive: true });
  window.addEventListener('resize', function () { $$('.mb-seg').forEach(placeThumb); });

  applyTheme(root.dataset.themePref || 'auto');
  apply(false);
  $$('.mb-seg').forEach(placeThumb);
  spy();
  intro();
})();
