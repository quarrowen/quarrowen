/* Search, written rather than installed.
 *
 * MkDocs builds `search/search_index.json` (1700-odd sections) but with `search_index_only` it ships
 * no script to read it - that belongs to the themes we are not using. This is that script, and it is
 * short because the job is narrow: somebody types a function name and wants the page it is on.
 *
 * Deliberately not a fuzzy ranked full-text engine. The thing being searched is a reference whose
 * headings *are* the identifiers, so an exact substring of the title beats anything cleverer, and a
 * body match is the fallback. Every term must appear, which is what makes two words useful.
 * (2026-09-23) */

(function () {
  var box = document.getElementById('q');
  var panel = document.getElementById('results');
  var list = document.getElementById('results-list');
  var article = document.getElementById('article');
  if (!box || !panel || !list || !article) return;

  var docs = null, loading = false;
  var base = (function () {
    // The site can be served from a subdirectory, so work the root out from this script's own src
    // rather than assuming "/".
    var s = document.querySelector('script[src$="search/main.js"]');
    return s ? s.getAttribute('src').replace(/search\/main\.js$/, '') : '';
  })();

  function load(then) {
    if (docs) { then(); return; }
    if (loading) return;
    loading = true;
    fetch(base + 'search/search_index.json')
      .then(function (r) { return r.json(); })
      .then(function (d) { docs = d.docs || []; loading = false; then(); })
      .catch(function () { loading = false; });
  }

  function search(q) {
    var terms = q.toLowerCase().split(/\s+/).filter(Boolean);
    if (!terms.length) return [];
    var out = [];
    for (var i = 0; i < docs.length; i++) {
      var d = docs[i];
      if (!d.title) continue;
      var title = d.title.toLowerCase();
      var text = (d.text || '').toLowerCase();
      var score = 0, ok = true;
      for (var t = 0; t < terms.length; t++) {
        var inTitle = title.indexOf(terms[t]) !== -1;
        var inText = text.indexOf(terms[t]) !== -1;
        if (!inTitle && !inText) { ok = false; break; }
        // A hit in the heading is what the reader almost always meant; an exact heading, more so.
        score += inTitle ? (title === terms[t] ? 100 : 10) : 1;
      }
      if (ok) out.push({ d: d, score: score + Math.max(0, 40 - title.length) / 40 });
    }
    out.sort(function (a, b) { return b.score - a.score; });
    return out.slice(0, 40);
  }

  function render(hits, q) {
    list.innerHTML = '';
    if (!hits.length) {
      var li = document.createElement('li');
      li.textContent = 'Nothing matches "' + q + '".';
      list.appendChild(li);
    }
    hits.forEach(function (h) {
      var li = document.createElement('li');
      var a = document.createElement('a');
      a.href = base + h.d.location;
      a.textContent = h.d.title;
      var p = document.createElement('p');
      p.textContent = (h.d.text || '').slice(0, 150) + ((h.d.text || '').length > 150 ? '…' : '');
      li.appendChild(a); li.appendChild(p);
      list.appendChild(li);
    });
    panel.hidden = false;
    article.hidden = true;
  }

  function clear() {
    panel.hidden = true;
    article.hidden = false;
  }

  var timer = 0;
  box.addEventListener('input', function () {
    var q = box.value.trim();
    clearTimeout(timer);
    if (q.length < 2) { clear(); return; }
    timer = setTimeout(function () {
      load(function () { render(search(q), q); });
    }, 120);
  });

  // Loading 1.3MB on the first keystroke shows as a pause, so start as soon as the box is touched.
  box.addEventListener('focus', function () { load(function () {}); });

  box.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') { box.value = ''; clear(); box.blur(); }
  });

  // "/" focuses search, the way every reference site a modder already uses does.
  document.addEventListener('keydown', function (e) {
    if (e.key === '/' && document.activeElement !== box &&
        !/^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName)) {
      e.preventDefault();
      box.focus();
    }
  });
})();
