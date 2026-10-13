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
    var moveInside = window.innerWidth < 750 ||
      hero.getBoundingClientRect().width / ratio * 0.7 >= 500;
    if (hero.classList.contains('hero-with-wind') === moveInside) return;
    hero.classList.toggle('hero-with-wind', moveInside);
    side.classList.toggle('hero-stats-moved', moveInside);
    if (moveInside) inset.appendChild(wind);
    else windAnchor.after(wind);
    syncReadingHeights();
  }).observe(hero);
})();
