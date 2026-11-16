/* Mo baile no navegador: cliente do servidor local (python -m mobaile.web).
   Só fala com a própria origem. O token vem no fragmento da URL, sai da barra
   de endereço logo na carga e vai em cabeçalho em cada chamada. Texto vindo de
   spec ou log entra só por textContent, nunca por innerHTML. */
(function () {
  "use strict";

  var TOKEN_KEY = "mobaile-web-token";
  var STATUS_LABEL = { ok: "OK", error: "Divergente", missing: "Não disparada" };
  var KIND_LABEL = { html: "Baixar HTML", markdown: "Baixar Markdown", tsv: "Baixar TSV", board: "Baixar board (Excalidraw)" };
  var token = readToken();
  var seq = 0;
  var analytics = null;

  function $(id) { return document.getElementById(id); }

  function readToken() {
    var found = /(?:^#|&)t=([A-Za-z0-9_-]+)/.exec(location.hash);
    var value = found ? found[1] : null;
    try {
      if (value) { sessionStorage.setItem(TOKEN_KEY, value); } else { value = sessionStorage.getItem(TOKEN_KEY); }
    } catch (err) { /* sem armazenamento: vale só nesta carga */ }
    if (found) { history.replaceState(null, "", location.pathname); }
    return value;
  }

  function el(tag, text, className) {
    var node = document.createElement(tag);
    if (text !== undefined && text !== null) { node.textContent = String(text); }
    if (className) { node.className = className; }
    return node;
  }

  function request(path, options) {
    options.headers = options.headers || {};
    options.headers["X-Mobaile-Token"] = token;
    options.cache = "no-store";
    options.credentials = "omit";
    return fetch(path, options);
  }

  function post(path, body, type) {
    return request(path, { method: "POST", body: body, headers: { "Content-Type": type } }).then(function (resp) {
      return resp.text().then(function (text) {
        var data = {};
        try { data = JSON.parse(text); } catch (err) { /* resposta sem JSON */ }
        if (!resp.ok) { throw new Error(data.error || ("O servidor respondeu " + resp.status + ".")); }
        return data;
      });
    });
  }

  function rpc(method, params) {
    var envelope = { jsonrpc: "2.0", id: ++seq, method: method, params: params || {} };
    return post("/rpc", JSON.stringify(envelope), "application/json").then(function (msg) {
      if (msg.error) { throw new Error(msg.error.message); }
      return msg.result;
    });
  }

  function upload(kind, file) {
    return post("/upload?kind=" + kind, file, "application/octet-stream").then(function (data) { return data.path; });
  }

  function save(blob, name) {
    var url = URL.createObjectURL(blob);
    var link = el("a");
    link.href = url;
    link.download = name;
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 2000);
  }

  function setStatus(id, text, isError) {
    var node = $(id);
    node.textContent = text;
    node.classList.toggle("status--erro", Boolean(isError));
  }

  function busy(form, on) {
    Array.prototype.forEach.call(form.elements, function (field) { field.disabled = on; });
    form.setAttribute("aria-busy", on ? "true" : "false");
  }

  /* ----------------------------------------------------------- Relatório */

  function percent(value) { return value.toFixed(1).replace(".", ",") + "%"; }

  function renderSummary(result) {
    var s = result.summary;
    var tiles = [["Validações", s.total, ""], ["OK", s.ok, "ok"], ["Divergentes", s.divergent, "erro"],
      ["Não disparadas", s.missing, "aviso"], ["Conformidade", percent(s.compliance_rate), ""],
      ["Fora da spec", s.extras, ""], ["Alertas", s.alerts, ""]];
    var list = $("resumo");
    list.replaceChildren();
    tiles.forEach(function (tile) {
      var box = el("div", null, "tile" + (tile[2] ? " tile--" + tile[2] : ""));
      box.append(el("dt", tile[0]), el("dd", tile[1]));
      list.append(box);
    });
    var st = result.log_stats;
    $("log-stats").textContent = "Projeto " + result.spec.projeto + " · " + result.platform.toUpperCase() + " · " +
      st.total_lidos + " eventos lidos, " + st.da_plataforma + " da plataforma, " + st.duplicados + " duplicados, " +
      st.uteis + " usados na auditoria.";
    var pend = $("pendencias");
    pend.replaceChildren();
    var issues = result.results.filter(function (r) { return r.status !== "ok"; });
    issues.slice(0, 100).forEach(function (r) {
      var item = el("li");
      item.append(el("span", STATUS_LABEL[r.status] || r.status, "selo selo--" + r.status),
        el("strong", r.event), el("span", " · " + (r.variation || r.section)));
      if (r.divergences) { item.append(el("p", r.divergences, "divergencia")); }
      pend.append(item);
    });
    if (!issues.length) { pend.append(el("li", "Nenhuma: todas as variações estão OK.")); }
    if (issues.length > 100) { pend.append(el("li", "E mais " + (issues.length - 100) + ". Veja o relatório completo abaixo.")); }
  }

  function renderDownloads(files) {
    var box = $("downloads");
    box.replaceChildren();
    files.forEach(function (file) {
      var button = el("button", KIND_LABEL[file.kind] || file.name, "mb-btn mb-btn--large");
      button.type = "button";
      button.addEventListener("click", function () { download(file); });
      box.append(button);
    });
  }

  function download(file) {
    request("/download/" + encodeURIComponent(file.id), { method: "GET" })
      .then(function (resp) {
        if (!resp.ok) { throw new Error("Não foi possível baixar " + file.name + "."); }
        return resp.blob();
      })
      .then(function (blob) { save(blob, file.name); })
      .catch(function (err) { setStatus("status-relatorio", err.message, true); });
  }

  function showReport(files) {
    var html = files.filter(function (f) { return f.kind === "html"; })[0];
    if (!html) { return Promise.resolve(); }
    return post("/ticket", JSON.stringify({ id: html.id }), "application/json").then(function (data) {
      $("visor").src = "/view/" + encodeURIComponent(data.view);
    });
  }

  function onAudit(event) {
    event.preventDefault();
    var form = event.currentTarget;
    var spec = $("spec").files[0];
    var log = $("log").files[0];
    if (!spec || !log) { setStatus("status-relatorio", "Escolha a spec e o log.", true); return; }
    busy(form, true);
    setStatus("status-relatorio", "Enviando os arquivos e auditando…");
    Promise.all([upload("spec", spec), upload("log", log)])
      .then(function (paths) {
        var params = { spec_path: paths[0], log_path: paths[1], source: "file" };
        if ($("plataforma").value) { params.platform = $("plataforma").value; }
        return rpc("report.audit", params);
      })
      .then(function (result) {
        renderSummary(result);
        $("resultado").hidden = false;
        setStatus("status-relatorio", "Auditoria concluída. Gerando os arquivos…");
        return rpc("report.export", {});
      })
      .then(function (exported) {
        renderDownloads(exported.files);
        return showReport(exported.files);
      })
      .then(function () { setStatus("status-relatorio", "Pronto. O relatório completo está abaixo."); })
      .catch(function (err) { setStatus("status-relatorio", err.message, true); })
      .then(function () { busy(form, false); });
  }

  /* ----------------------------------------------------------- Analytics */

  function paramsText(params) {
    return Object.keys(params).map(function (key) {
      var value = params[key];
      return key + ": " + (typeof value === "string" ? value : JSON.stringify(value));
    }).join(", ");
  }

  function renderEvents(data) {
    var body = $("linhas");
    body.replaceChildren();
    data.events.forEach(function (ev) {
      var row = el("tr");
      row.append(el("td", ev.time_str || "", "mb-tabular"), el("td", ev.event_name), el("td", ev.origin || ""),
        el("td", paramsText(ev.params || {}), "parametros"));
      body.append(row);
    });
    var st = data.stats;
    $("legenda-eventos").textContent = data.events.length + " eventos do Firebase (" + st.total_lidos +
      " lidos, " + st.duplicados + " duplicados descartados).";
    $("eventos").hidden = false;
  }

  function onAnalytics(event) {
    event.preventDefault();
    var form = event.currentTarget;
    var file = $("logcat").files[0];
    if (!file) { setStatus("status-analytics", "Escolha o logcat salvo.", true); return; }
    busy(form, true);
    setStatus("status-analytics", "Lendo os eventos…");
    post("/analytics", file, "application/octet-stream")
      .then(function (data) {
        analytics = data;
        renderEvents(data);
        setStatus("status-analytics", data.events.length ? "Pronto." : "Nenhum evento do Firebase neste arquivo.");
      })
      .catch(function (err) { setStatus("status-analytics", err.message, true); })
      .then(function () { busy(form, false); });
  }

  /* ---------------------------------------------------------------- Abas */

  function selectTab(tab, focus) {
    document.querySelectorAll("[role=tab]").forEach(function (other) {
      var on = other === tab;
      other.setAttribute("aria-selected", on ? "true" : "false");
      other.tabIndex = on ? 0 : -1;
      $(other.getAttribute("aria-controls")).hidden = !on;
    });
    if (focus) { tab.focus(); }
  }

  function onTabKey(event) {
    var tabs = Array.prototype.slice.call(document.querySelectorAll("[role=tab]"));
    var index = tabs.indexOf(event.currentTarget);
    var next = { ArrowRight: index + 1, ArrowLeft: index - 1, Home: 0, End: tabs.length - 1 }[event.key];
    if (next === undefined) { return; }
    event.preventDefault();
    selectTab(tabs[(next + tabs.length) % tabs.length], true);
  }

  function applyTheme() {
    var dark = window.matchMedia && matchMedia("(prefers-color-scheme: dark)").matches;
    document.documentElement.dataset.theme = dark ? "dark" : "light";
  }

  document.addEventListener("DOMContentLoaded", function () {
    applyTheme();
    if (window.matchMedia) { matchMedia("(prefers-color-scheme: dark)").addEventListener("change", applyTheme); }
    document.querySelectorAll("[role=tab]").forEach(function (tab) {
      tab.addEventListener("click", function () { selectTab(tab, false); });
      tab.addEventListener("keydown", onTabKey);
    });
    $("form-relatorio").addEventListener("submit", onAudit);
    $("form-analytics").addEventListener("submit", onAnalytics);
    $("baixar-tsv").addEventListener("click", function () {
      if (analytics) { save(new Blob([analytics.tsv], { type: "text/tab-separated-values;charset=utf-8" }), "eventos_analytics.tsv"); }
    });
    $("baixar-json").addEventListener("click", function () {
      if (analytics) { save(new Blob([JSON.stringify(analytics.events, null, 2)], { type: "application/json" }), "eventos_analytics.json"); }
    });
    if (!token) {
      $("sem-chave").hidden = false;
      document.querySelectorAll("form").forEach(function (form) { busy(form, true); });
    }
  });
})();
