/* The GDScript / JavaScript selector.
 *
 * A mod is written in either language and they are the same API, so every entry in the reference
 * carries both signatures. Showing them stacked doubles the length of a 300-function reference and
 * makes the reader skip half of every entry; a selector shows the one they are actually writing in
 * and remembers it. (the user, 2026-09-23: "possible to do a selector")
 *
 * **It upgrades the Markdown rather than depending on markup.** The generated pages are the source of
 * truth and are meant to read as plain Markdown in the repository, so they contain an `h3` holding
 * the GDScript signature and a paragraph beginning "JavaScript:" - and this finds those two and turns
 * them into one switchable block. Nothing here is required for the page to make sense; with the
 * script absent you get both signatures, which is the honest fallback. */

(function () {
  var KEY = 'quarrowen.lang';
  var langs = { gdscript: 'GDScript', javascript: 'JavaScript' };

  function remembered() {
    try {
      var v = localStorage.getItem(KEY);
      return langs[v] ? v : 'gdscript';
    } catch (e) {
      return 'gdscript';  // private windows and blocked site data both throw here
    }
  }

  function remember(v) {
    try { localStorage.setItem(KEY, v); } catch (e) { /* a preference, not data - losing it is fine */ }
  }

  function strip(el, label) {
    var first = el.firstChild;
    if (first && first.nodeType === 3 && first.nodeValue.indexOf(label) === 0) {
      first.nodeValue = first.nodeValue.slice(label.length).replace(/^\s+/, '');
    }
  }

  var current = remembered();
  var entries = [];

  function build() {
    var paras = document.querySelectorAll('.doc p');
    for (var i = 0; i < paras.length; i++) {
      var gdP = paras[i];
      if (gdP.textContent.indexOf('GDScript:') !== 0) continue;
      var jsP = gdP.nextElementSibling;
      if (!jsP || jsP.tagName !== 'P' || jsP.textContent.indexOf('JavaScript:') !== 0) continue;

      var unavailable = /not available/i.test(jsP.textContent);
      // The label is redundant once there is a tab above saying the same word - but it stays in the
      // Markdown, where there are no tabs and the line has to say which language it is.
      strip(gdP, 'GDScript:');
      strip(jsP, 'JavaScript:');
      gdP.classList.add('sigline');
      jsP.classList.add('sigline');
      if (unavailable) jsP.classList.add('unavailable');

      var tabs = document.createElement('div');
      tabs.className = 'langtabs';
      Object.keys(langs).forEach(function (id) {
        var b = document.createElement('button');
        b.type = 'button';
        b.className = 'langtab';
        b.dataset.lang = id;
        b.textContent = langs[id];
        b.addEventListener('click', function () { choose(id); });
        tabs.appendChild(b);
      });

      gdP.parentNode.insertBefore(tabs, gdP);
      entries.push({ gd: gdP, js: jsP, tabs: tabs });
    }
  }

  function apply() {
    entries.forEach(function (e) {
      e.gd.hidden = current !== 'gdscript';
      e.js.hidden = current !== 'javascript';
      var b = e.tabs.querySelectorAll('.langtab');
      for (var i = 0; i < b.length; i++) {
        var on = b[i].dataset.lang === current;
        b[i].classList.toggle('on', on);
        b[i].setAttribute('aria-pressed', on ? 'true' : 'false');
      }
    });
  }

  function choose(id) {
    if (!langs[id]) return;
    current = id;
    remember(id);
    apply();
  }

  build();
  if (entries.length) apply();
})();
