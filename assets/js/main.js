/* Kamruzzaman Akib | Portfolio scripts (no external libraries) */
(function () {
  'use strict';
  var root = document.documentElement;
  root.classList.add('js');

  /* Light / dark mode toggle (remembers the choice) */
  var themeBtn = document.getElementById('theme-toggle');
  if (themeBtn) {
    themeBtn.addEventListener('click', function () {
      var next = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
      root.setAttribute('data-theme', next);
      try { localStorage.setItem('theme', next); } catch (e) {}
    });
  }

  /* Mobile menu */
  var nav = document.getElementById('site-nav');
  var navBtn = document.getElementById('nav-toggle');
  if (nav && navBtn) {
    navBtn.addEventListener('click', function () {
      var open = nav.classList.toggle('open');
      navBtn.setAttribute('aria-expanded', open ? 'true' : 'false');
      navBtn.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
    });
    nav.addEventListener('click', function (e) {
      if (e.target.tagName === 'A') {
        nav.classList.remove('open');
        navBtn.setAttribute('aria-expanded', 'false');
        navBtn.setAttribute('aria-label', 'Open menu');
      }
    });
  }

  /* Email link is assembled here so spam bots can't read it from the page source */
  document.querySelectorAll('.js-email').forEach(function (a) {
    var addr = a.getAttribute('data-user') + '@' + a.getAttribute('data-domain');
    a.setAttribute('href', 'mailto:' + addr);
    a.setAttribute('title', addr);
  });

  /* Hide any link that still contains the REPLACE-ME placeholder */
  document.querySelectorAll('[data-optional-link]').forEach(function (a) {
    if ((a.getAttribute('href') || '').indexOf('REPLACE-ME') !== -1) { a.remove(); }
  });

  /* On GitHub Pages, point the GitHub button at the site owner's profile automatically */
  var host = window.location.hostname;
  if (/\.github\.io$/i.test(host)) {
    var user = host.split('.')[0];
    document.querySelectorAll('.js-github').forEach(function (a) {
      a.setAttribute('href', 'https://github.com/' + user);
    });
  }

  /* Footer year */
  var year = document.getElementById('year');
  if (year) { year.textContent = new Date().getFullYear(); }

  /* Fade sections in as they scroll into view */
  var items = document.querySelectorAll('.reveal');
  if ('IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          io.unobserve(entry.target);
        }
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
    items.forEach(function (el) { io.observe(el); });
  } else {
    items.forEach(function (el) { el.classList.add('is-visible'); });
  }

  /* Screenshot viewer: click a screenshot to see it at full size.
     Click the picture to switch between "fit to screen" and "actual size". */
  var shots = document.querySelectorAll('a[data-lightbox]');
  if (shots.length && typeof HTMLDialogElement === 'function') {
    var box = document.createElement('dialog');
    box.className = 'lightbox';
    box.setAttribute('aria-label', 'Screenshot at full size');
    box.innerHTML = '<div class="lightbox-bar"><p></p><button type="button" data-size>Fit to screen</button><button type="button" data-close>Close</button></div>' +
      '<div class="lightbox-scroll"><img alt=""></div><p class="lightbox-hint">Click the picture to zoom. Press Esc to close.</p>';
    document.body.appendChild(box);
    var big = box.querySelector('img');
    var cap = box.querySelector('.lightbox-bar p');
    var sizeBtn = box.querySelector('[data-size]');
    function setFit(fit) {
      big.classList.toggle('fit', fit);
      sizeBtn.textContent = fit ? 'Actual size' : 'Fit to screen';
    }
    shots.forEach(function (a) {
      a.addEventListener('click', function (e) {
        if (e.ctrlKey || e.metaKey || e.shiftKey || e.button === 1) { return; }
        e.preventDefault();
        var img = a.querySelector('img');
        big.src = a.getAttribute('href');
        big.alt = img ? img.alt : '';
        cap.textContent = img ? img.alt : '';
        var w = img ? parseInt(img.getAttribute('width'), 10) : 0;
        setFit(w > window.innerWidth - 32);
        box.showModal();
        box.querySelector('.lightbox-scroll').scrollTo(0, 0);
      });
    });
    big.addEventListener('click', function (e) { e.stopPropagation(); setFit(!big.classList.contains('fit')); });
    sizeBtn.addEventListener('click', function () { setFit(!big.classList.contains('fit')); });
    box.querySelector('[data-close]').addEventListener('click', function () { box.close(); });
    box.querySelector('.lightbox-scroll').addEventListener('click', function (e) { if (e.target === this) { box.close(); } });
    box.addEventListener('close', function () { big.removeAttribute('src'); });
  }

  /* Highlight the menu item for the section on screen */
  var links = document.querySelectorAll('.site-nav a[href^="#"]');
  var sections = [];
  links.forEach(function (l) {
    var s = document.querySelector(l.getAttribute('href'));
    if (s) { sections.push({ link: l, el: s }); }
  });
  function spy() {
    var pos = window.scrollY + 120;
    var current = null;
    sections.forEach(function (s) { if (s.el.offsetTop <= pos) { current = s; } });
    links.forEach(function (l) { l.classList.remove('active'); });
    if (current) { current.link.classList.add('active'); }
  }
  window.addEventListener('scroll', spy, { passive: true });
  spy();
})();
