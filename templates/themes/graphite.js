// Narrow portrait phones show wind as the first full-width card below the hero.
(function setupGraphiteWind() {
  var wind = document.querySelector('.hero .hero-wind-group');
  var side = document.querySelector('.side-stats');
  var anchor = document.createComment('graphite wind position');
  wind.before(anchor);
  var windCard = document.createElement('div');
  windCard.className = 'glass stat graphite-wind-card';
  var narrowPortrait = window.matchMedia('(orientation: portrait) and (max-width: 600px)');
  function syncWind() {
    if (narrowPortrait.matches) {
      windCard.appendChild(wind);
      side.prepend(windCard);
    } else {
      anchor.after(wind);
      windCard.remove();
    }
  }
  narrowPortrait.addEventListener('change', syncWind);
  syncWind();
})();

// German "Luftfeuchtigkeit" is shortened only when its label cannot fit on one line.
(function setupGraphiteHumidityLabel() {
  var label = document.getElementById('statHumidity').closest('.stat').querySelector('.stat-label');
  var shortText = 'Luftfeuchte';
  var probe = document.createElement('span');
  probe.setAttribute('aria-hidden', 'true');
  probe.style.cssText = 'position:absolute;visibility:hidden;white-space:nowrap;left:-9999px;top:0';
  document.body.appendChild(probe);
  function fitLabel() {
    var current = label.textContent;
    if (current !== shortText) label.dataset.fullText = current;
    var full = label.dataset.fullText || current;
    if (full.trim().toLowerCase() !== 'luftfeuchtigkeit') return;
    var style = getComputedStyle(label);
    ['font', 'letterSpacing', 'textTransform'].forEach(function(prop) { probe.style[prop] = style[prop]; });
    probe.textContent = full;
    var desired = probe.getBoundingClientRect().width > label.clientWidth ? shortText : full;
    if (label.textContent !== desired) label.textContent = desired;
    label.classList.remove('stat-label-tight');
    if (desired === shortText) {
      probe.style.font = getComputedStyle(label).font;
      probe.style.letterSpacing = getComputedStyle(label).letterSpacing;
      probe.textContent = shortText;
      label.classList.toggle('stat-label-tight', probe.getBoundingClientRect().width > label.clientWidth);
    }
  }
  new MutationObserver(fitLabel).observe(label, { childList: true, characterData: true, subtree: true });
  new ResizeObserver(fitLabel).observe(label.parentElement);
  fitLabel();
})();
