/* SuperWebAdmin2 page script: theme toggle, mobile menu, confirmation dialogs and the
   list widget for the two-list pages. Every page works without it; this only makes
   them nicer to use. Loaded at the end of the body. */
(function () {
  var doc = document.documentElement;

  // ---- theme: dark by default, light when chosen (kept in this browser) ----
  var theme = document.getElementById('theme');
  // the button shows a sun in dark mode and a moon in light mode (CSS); only the label changes here
  function themeLabel() {
    var t = doc.getAttribute('data-theme') === 'light' ? 'Switch to dark mode' : 'Switch to light mode';
    theme.title = t;
    theme.setAttribute('aria-label', t);
  }
  if (theme) {
    theme.onclick = function () {
      var light = doc.getAttribute('data-theme') !== 'light';
      if (light) doc.setAttribute('data-theme', 'light'); else doc.removeAttribute('data-theme');
      try { localStorage.setItem('swa2-theme', light ? 'light' : 'dark'); } catch (e) { }
      themeLabel();
    };
    themeLabel();
  }

  // ---- mobile menu ----
  var nav = document.getElementById('nav'), menu = document.getElementById('menubtn');
  if (nav && menu) menu.onclick = function () { menu.setAttribute('aria-expanded', nav.classList.toggle('open')); };

  // ---- restart button of the info bar ----
  var restart = document.getElementById('restart'), restartDlg = document.getElementById('restartdlg');
  if (restart && restartDlg && restartDlg.showModal) {
    restart.onclick = function (e) { e.preventDefault(); restartDlg.showModal(); };
    document.getElementById('restartno').onclick = function () { restartDlg.close(); };
  }

  // ---- submit buttons with data-confirm="question" ask first ----
  var dlg = document.getElementById('confirmdlg');
  if (dlg && dlg.showModal) {
    var pending = null;
    document.addEventListener('click', function (e) {
      var b = e.target.closest ? e.target.closest('[data-confirm]') : null;
      if (!b || b.form == null) return;
      e.preventDefault();
      pending = b;
      document.getElementById('confirmtext').textContent = b.getAttribute('data-confirm');
      document.getElementById('confirmok').textContent = b.value;
      dlg.showModal();
    });
    document.getElementById('confirmno').onclick = function () { pending = null; dlg.close(); };
    document.getElementById('confirmok').onclick = function () {
      var b = pending; pending = null; dlg.close();
      if (!b) return;
      // submit with the name/value of the button that was pressed
      var h = document.createElement('input');
      h.type = 'hidden'; h.name = b.name; h.value = b.value;
      b.form.appendChild(h);
      b.form.submit();
    };
  }

  // ---- list widget: <select multiple class="lb"> shown as a list with tooltips and a
  // muted class name. The select stays the source of truth (it is what the form posts);
  // pages send it a 'change' event after changing its options. ----
  function listbox(sel) {
    var box = document.createElement('div'), last = -1;
    box.className = 'listbox';
    box.tabIndex = 0;
    box.setAttribute('role', 'listbox');
    box.setAttribute('aria-multiselectable', 'true');
    if (sel.getAttribute('aria-label')) box.setAttribute('aria-label', sel.getAttribute('aria-label'));
    sel.parentNode.insertBefore(box, sel);
    sel.hidden = true;

    function visible() { return Array.prototype.filter.call(sel.options, function (o) { return !o.hidden && o.value !== ''; }); }
    function render() {
      var keep = box.scrollTop;
      box.textContent = '';
      visible().forEach(function (o, i) {
        var d = document.createElement('div'), a = document.createElement('span');
        d.className = 'item' + (o.selected ? ' sel' : '');
        d.setAttribute('role', 'option');
        d.setAttribute('aria-selected', o.selected ? 'true' : 'false');
        d.title = o.title || o.textContent;
        a.className = 'tag';
        a.textContent = o.getAttribute('data-tag') || o.textContent;
        d.appendChild(a);
        if (o.getAttribute('data-cls')) {
          var c = document.createElement('span');
          c.className = 'cls';
          c.textContent = o.getAttribute('data-cls');
          d.appendChild(c);
        }
        d.onmousedown = function (e) { if (e.shiftKey) e.preventDefault(); };
        d.onclick = function (e) { pick(i, e.ctrlKey || e.metaKey, e.shiftKey); };
        d.ondblclick = function () {
          visible().forEach(function (x) { x.selected = false; });
          o.selected = true;
          sel.dispatchEvent(new Event('dblclick'));
        };
        box.appendChild(d);
      });
      if (!box.firstChild && sel.options.length && sel.options[0].value === '')
      {
        var none = document.createElement('div');
        none.className = 'empty';
        none.textContent = 'None';
        box.appendChild(none);
      }
      box.scrollTop = keep;
    }
    function pick(i, toggle, range) {
      var v = visible();
      if (range && last >= 0) {
        var a = Math.min(last, i), b = Math.max(last, i);
        if (!toggle) v.forEach(function (o) { o.selected = false; });
        for (var k = a; k <= b; k++) v[k].selected = true;
      } else if (toggle) {
        v[i].selected = !v[i].selected; last = i;
      } else {
        v.forEach(function (o) { o.selected = false; });
        v[i].selected = true; last = i;
      }
      render();
    }
    box.onkeydown = function (e) {
      var v = visible(), cur = last;
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        cur = Math.max(0, Math.min(v.length - 1, cur + (e.key === 'ArrowDown' ? 1 : -1)));
        if (v.length) { pick(cur, false, false); if (box.children[cur]) box.children[cur].scrollIntoView({ block: 'nearest' }); }
      } else if (e.key === 'Enter' && v.some(function (o) { return o.selected; })) {
        e.preventDefault();
        sel.dispatchEvent(new Event('dblclick'));
      }
    };
    sel.addEventListener('change', render);
    render();
  }
  Array.prototype.forEach.call(document.querySelectorAll('select.lb'), listbox);
})();
