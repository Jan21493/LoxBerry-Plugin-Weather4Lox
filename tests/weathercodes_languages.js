function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function runTests() {
  new Function(pageScript);
  const makePage = new Function('fetch', 'document', 'console',
    "const pluginBase = '/plugins/weather4lox'; let lang = {};\n" + languageSource +
    "\nreturn { load: loadLang, options: loadLanguageOptions, strings: function() { return lang; } };");
  let count = 0;
  for (const scenario of [
    { code: 'pl', effective: 'pl' },
    { code: 'pt-BR', effective: 'pt-BR' },
    { code: '../private', effective: 'en' },
    { code: null, effective: 'en' },
    { code: 'zz', effective: 'en', missing: true },
    { code: 'pl', effective: 'en', malformed: true },
    { code: 'pl', effective: 'en', network: true },
    { code: 'en', error: true, missing: true }
  ]) {
    const select = { options: [], appendChild: function(option) { this.options.push(option); } };
    const document = {
      documentElement: { lang: 'en' },
      getElementById: function() { return select; },
      createElement: function() { return {}; }
    };
    const urls = [], warnings = [];
    const page = makePage(async function(url, options) {
      urls.push(url);
      if (url.endsWith('languages.cgi')) {
        assert(options.cache === 'no-store', 'Language discovery must not be cached');
        return { ok: true, json: async function() {
          return [{ code: 'cs', language: 'Čeština' }, { code: 'en', language: 'English' },
            { code: 'pl', language: 'Polski' }, { code: 'pt-BR', language: 'Português' },
            { code: '../bad', language: 'Invalid' }];
        } };
      }
      const first = urls.length === 2;
      if (scenario.network && first) throw new Error('Offline');
      return {
        ok: !(scenario.missing && first), status: 404, url: url,
        json: async function() {
          if (scenario.malformed && first) throw new SyntaxError('Invalid JSON');
          return { language: 'Native name', weathercodes_title: 'Translated title' };
        }
      };
    }, document, { warn: function(message) { warnings.push(message); } });
    await page.options();
    assert(select.options.map(function(option) { return option.textContent; }).join('|') ===
      'Čeština|English|Polski|Português', 'Names must come from discovered files');
    let failed = false;
    try {
      await page.load(scenario.code);
    } catch (err) {
      failed = true;
      assert(scenario.error && err.message.includes('HTTP 404'), 'Unexpected language failure');
    }
    assert(failed === !!scenario.error, 'English errors must propagate');
    if (!scenario.error) {
      assert(select.value === scenario.effective, 'Selector must reflect loaded language');
      assert(document.documentElement.lang === scenario.effective, 'Document language must match');
      assert(page.strings().weathercodes_title === 'Translated title', 'Translations must be applied');
      assert(urls[urls.length - 1].endsWith('/lang-' + scenario.effective + '.json'), 'Effective file');
    }
    assert(!urls.some(function(url) { return url.includes('../'); }), 'No traversal');
    assert(warnings.length === (urls.length > 2 ? 1 : 0), 'Fallback must log a warning');
    count++;
  }
  for (const brokenList of [true, false]) {
    const select = { options: [], appendChild: function(option) { this.options.push(option); } };
    const document = { documentElement: {}, getElementById: function() { return select; },
      createElement: function() { return {}; } };
    const warnings = [];
    const page = makePage(async function(url) {
      if (url.endsWith('languages.cgi')) {
        if (brokenList) throw new Error('Unavailable endpoint');
        return { ok: true, json: async function() { return {}; } };
      }
      return { ok: true, json: async function() { return { language: 'Polski' }; } };
    }, document, { warn: function(message) { warnings.push(message); } });
    await page.options();
    await page.load('pl');
    assert(select.value === 'pl' && select.options[0].textContent === 'Polski',
      'URL language must work when discovery fails');
    assert(warnings.length === 1, 'Discovery failure must be logged');
    count++;
  }
  return count;
}
