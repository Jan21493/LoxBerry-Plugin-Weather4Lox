function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function runTests() {
  var count = 0;
  return themeCases.reduce(function(chain, theme) {
    return chain.then(function() {
      theme.scripts.forEach(function(script) { new Function(script); });
      var createLoader = new Function('fetch', 'console', 'location', theme.source +
        '\nreturn { load: loadLanguage, language: function() { return currentLang; } };');
      var scenarios = [
        { lang: 'pl', expected: 'pl', urls: ['./lang-pl.json'] },
        { lang: 'cs', expected: 'cs', urls: ['./lang-cs.json'] },
        { lang: 'pt-BR', expected: 'pt-BR', urls: ['./lang-pt-BR.json'] },
        { lang: '', expected: 'en', urls: ['./lang-en.json'] },
        { lang: '../private', expected: 'en', urls: ['./lang-en.json'] },
        { lang: 'zz', expected: 'en', urls: ['./lang-zz.json', './lang-en.json'], missing: true },
        { lang: 'pl', expected: 'en', urls: ['./lang-pl.json', './lang-en.json'], malformed: true },
        { lang: 'pl', expected: 'en', urls: ['./lang-pl.json', './lang-en.json'], network: true },
        { lang: 'en', urls: ['./lang-en.json'], missing: true, error: true }
      ];
      return scenarios.reduce(function(sequence, scenario) {
        return sequence.then(function() {
          var urls = [];
          var warnings = [];
          var loader = createLoader(function(url) {
            urls.push(url);
            if (scenario.network && urls.length === 1) {
              return Promise.reject(new Error('Network error'));
            }
            return Promise.resolve({
              ok: !(scenario.missing && urls.length === 1),
              status: 404,
              url: url,
              json: function() {
                if (scenario.malformed && urls.length === 1) {
                  return Promise.reject(new SyntaxError('Invalid JSON'));
                }
                return Promise.resolve({ language: url });
              }
            });
          }, { warn: function(message) { warnings.push(message); } },
          { search: '?lang=' + encodeURIComponent(scenario.lang) });
          return loader.load().then(function(data) {
            assert(!scenario.error, theme.name + ': English failure must propagate');
            assert(loader.language() === scenario.expected, theme.name + ': effective language');
            assert(data.language === scenario.urls[scenario.urls.length - 1], theme.name + ': returned data');
          }, function(err) {
            assert(scenario.error && err.message.indexOf('HTTP 404') !== -1,
              theme.name + ': unexpected error: ' + err);
          }).then(function() {
            assert(JSON.stringify(urls) === JSON.stringify(scenario.urls), theme.name + ': fetched URLs');
            assert(warnings.length === (scenario.urls.length > 1 ? 1 : 0), theme.name + ': fallback warning');
            count++;
          });
        });
      }, Promise.resolve());
    });
  }, Promise.resolve()).then(function() { return count; });
}
