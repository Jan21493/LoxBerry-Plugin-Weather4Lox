// Portrait tablets show wind inside the hero; the card itself moves, so IDs stay unique.
(function setupDesertWind() {
  var hero = document.querySelector('.hero');
  var side = document.querySelector('.side-stats');
  var wind = document.querySelector('.wind-card');
  var anchor = document.createComment('desert wind position');
  wind.before(anchor);
  var portraitWide = window.matchMedia('(orientation: portrait) and (min-width: 701px)');
  function syncWind() {
    var inside = portraitWide.matches;
    hero.classList.toggle('desert-wind-inside', inside);
    side.classList.toggle('desert-wind-moved', inside);
    if (inside) hero.appendChild(wind);
    else anchor.after(wind);
  }
  portraitWide.addEventListener('change', syncWind);
  syncWind();
})();
