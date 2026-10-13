// Keep the live icon's proportions and move existing cards without duplicating IDs.
(function setupCoastalHero() {
  var hero = document.querySelector('.hero');
  var icon = document.getElementById('heroIcon');
  var side = document.querySelector('.side-stats');
  var inset = document.createElement('div');
  inset.className = 'hero-inline-stats';
  hero.appendChild(inset);
  var precipitation = document.getElementById('statPrecip').closest('.glass');
  var wind = document.querySelector('.wind-card');
  var windAnchor = document.createComment('coastal wind position');
  wind.before(windAnchor);
  inset.appendChild(precipitation);
  function updateAspect() {
    if (icon.naturalWidth && icon.naturalHeight) {
      hero.style.setProperty('--weather-aspect', icon.naturalWidth / icon.naturalHeight);
    }
  }
  icon.addEventListener('load', updateAspect);
  updateAspect();
  var panel = hero.querySelector('.hero-row > div:first-child');
  function syncReadingEdges() {
    var heroBox = hero.getBoundingClientRect();
    var panelBox = panel.getBoundingClientRect();
    var borderRight = parseFloat(getComputedStyle(hero).borderRightWidth) || 0;
    inset.style.setProperty('--inset-reading-width', panelBox.width + 'px');
    inset.style.right = (heroBox.right - panelBox.right - borderRight) + 'px';
  }
  function syncReadingHeights() {
    syncReadingEdges();
    var style = getComputedStyle(hero);
    var insetHeight = inset.getBoundingClientRect().height;
    var insetBottom = parseFloat(getComputedStyle(inset).bottom);
    hero.style.paddingBottom = Math.ceil(insetHeight + insetBottom + 20) + 'px';
    hero.style.setProperty('--coastal-min-height',
      Math.ceil(panel.getBoundingClientRect().height + insetHeight +
        parseFloat(style.paddingTop) + insetBottom + 20) + 'px');
  }
  var readingObserver = new ResizeObserver(syncReadingHeights);
  readingObserver.observe(panel);
  readingObserver.observe(precipitation.querySelector('.stat-content'));
  readingObserver.observe(wind.querySelector('.stat-content'));
  readingObserver.observe(inset);
  new ResizeObserver(function() {
    syncReadingEdges();
    var ratio = Number(getComputedStyle(hero).getPropertyValue('--weather-aspect')) || 1;
    var moveInside = window.matchMedia('(orientation: landscape)').matches ||
      window.innerWidth < 750 ||
      hero.getBoundingClientRect().width / ratio * 0.7 >= 500;
    if (hero.classList.contains('hero-with-wind') === moveInside) return;
    hero.classList.toggle('hero-with-wind', moveInside);
    side.classList.toggle('hero-stats-moved', moveInside);
    if (moveInside) inset.appendChild(wind);
    else windAnchor.after(wind);
    syncReadingHeights();
  }).observe(hero);
})();

(function setupCoastalHours() {
  var layout = document.querySelector('.cur-layout');
  var rail = document.createElement('div');
  rail.className = 'coastal-hour-rail';
  var landscape = window.matchMedia('(orientation: landscape)');
  var entries = ['heute', 'morgen'].map(function(tab) {
    var panel = document.getElementById('panel-' + tab);
    var wrap = panel.querySelector('.hour-strip-wrap');
    var anchor = document.createComment('coastal hours position');
    wrap.before(anchor);
    wrap.classList.add('coastal-hours-' + tab);
    return { panel: panel, wrap: wrap, anchor: anchor };
  });
  function syncTab() {
    var active = document.querySelector('.tab-panel.active');
    rail.dataset.activeTab = active ? active.id.replace('panel-', '') : '';
  }
  function syncLayout() {
    if (landscape.matches) {
      layout.appendChild(rail);
      entries.forEach(function(entry) { rail.appendChild(entry.wrap); });
    } else {
      entries.forEach(function(entry) { entry.anchor.after(entry.wrap); });
      rail.remove();
    }
    syncTab();
  }
  var observer = new MutationObserver(syncTab);
  entries.forEach(function(entry) {
    observer.observe(entry.panel, { attributes: true, attributeFilter: ['class'] });
    var strip = entry.wrap.querySelector('.hour-strip');
    strip.addEventListener('wheel', function(event) {
      if (landscape.matches) event.stopImmediatePropagation();
    }, { capture: true, passive: true });
    strip.addEventListener('mousedown', function(event) {
      if (!landscape.matches || event.button !== 0) return;
      event.stopImmediatePropagation();
      event.preventDefault();
      dragStrip = strip;
      dragStart = event.clientY;
      scrollStart = strip.scrollTop;
      dragged = false;
    }, true);
    strip.addEventListener('click', function(event) {
      if (dragged) {
        event.stopImmediatePropagation();
        dragged = false;
      }
    }, true);
  });
  var dragStrip = null, dragStart = 0, scrollStart = 0, dragged = false;
  document.addEventListener('mousemove', function(event) {
    if (!dragStrip) return;
    if (Math.abs(event.clientY - dragStart) > 5) dragged = true;
    if (dragged) dragStrip.scrollTop = scrollStart - (event.clientY - dragStart);
  });
  document.addEventListener('mouseup', function() { dragStrip = null; });
  landscape.addEventListener('change', syncLayout);
  syncLayout();
})();
