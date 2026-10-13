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
