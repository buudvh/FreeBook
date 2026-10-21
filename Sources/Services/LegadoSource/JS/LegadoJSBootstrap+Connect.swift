import Foundation

extension LegadoJSBootstrap {
    /// `org.jsoup.Jsoup.connect(url)` (spec §13.9): `Connection` gọi nối (`ignoreContentType`, `ignoreHttpErrors`,
    /// `header(s)`, `userAgent`, `referrer`, `cookie(s)`, `data`, `requestBody`, `method`, `timeout`, `followRedirects`,
    /// `maxBodySize`), `get()`/`post()` → Document, `execute()` → Response (`body`, `bodyAsBytes`, `statusCode`,
    /// `statusMessage`, `header(s)`, `cookies`, `url`, `parse`). Cùng client HTTP của engine (kho cookie,
    /// `concurrentRate`); header = UA mặc định, **không** gắn header nguồn (U55). Mã ≥ 400 mà không
    /// `ignoreHttpErrors(true)` ⇒ ném lỗi như jsoup.
    static let connect = #"""
        (function (g) {
          var L = g.__lg, callJSON = L.callJSON;
          function findHeader(headers, name) {
            var lower = String(name).toLowerCase();
            for (var k in headers) { if (k.toLowerCase() === lower) { return headers[k]; } }
            return null;
          }
          function jsoupResponse(r) {
            return {
              body: function () { return r.body; },
              bodyAsBytes: function () { return L.hexToBytes(r.hex || ''); },
              statusCode: function () { return r.code; },
              statusMessage: function () { return r.message; },
              header: function (name) { return findHeader(r.headers, name); },
              hasHeader: function (name) { return findHeader(r.headers, name) !== null; },
              headers: function () { return L.map(Object.assign({}, r.headers)); },
              cookies: function () { return L.map(Object.assign({}, r.cookies)); },
              cookie: function (name) { var v = r.cookies[name]; return v === undefined ? null : v; },
              url: function () { return r.url; },
              contentType: function () { return findHeader(r.headers, 'Content-Type'); },
              parse: function () { return g.__lgJsoup.parse(r.body, r.url); },
              toString: function () { return r.body; }
            };
          }
          function connection(url) {
            var req = { url: String(url), method: 'GET', headers: {}, cookies: {}, data: [], body: null,
              ignoreHttpErrors: false, timeout: null, followRedirects: true, wantBytes: false };
            var c = {};
            function chain(fn) { return function () { fn.apply(null, arguments); return c; }; }
            function each(map, fn) {
              if (!map) { return; }
              Object.keys(map).forEach(function (k) { if (typeof map[k] !== 'function') { fn(k, map[k]); } });
            }
            c.url = chain(function (u) { req.url = String(u); });
            c.ignoreContentType = chain(function () {});
            c.ignoreHttpErrors = chain(function (b) { req.ignoreHttpErrors = !!b; });
            c.header = chain(function (k, v) { req.headers[String(k)] = v == null ? '' : String(v); });
            c.headers = chain(function (m) { each(m, function (k, v) { req.headers[k] = String(v); }); });
            c.userAgent = chain(function (s) { req.headers['User-Agent'] = String(s); });
            c.referrer = chain(function (s) { req.headers.Referer = String(s); });
            c.cookie = chain(function (k, v) { req.cookies[String(k)] = v == null ? '' : String(v); });
            c.cookies = chain(function (m) { each(m, function (k, v) { req.cookies[k] = String(v); }); });
            c.data = chain(function (k, v) {
              if (v === undefined && k && typeof k === 'object') { each(k, function (kk, vv) { req.data.push([kk, String(vv)]); }); }
              else { req.data.push([String(k), v == null ? '' : String(v)]); }
            });
            c.requestBody = chain(function (s) { req.body = s == null ? null : String(s); });
            c.method = chain(function (m) { req.method = String(m && typeof m.name === 'function' ? m.name() : m).toUpperCase(); });
            c.timeout = chain(function (ms) { req.timeout = Number(ms); });
            c.followRedirects = chain(function (b) { req.followRedirects = !!b; });
            c.maxBodySize = chain(function () {});
            c.validateTLSCertificates = chain(function () {});
            c.proxy = chain(function () {});
            function run() {
              var r = callJSON('jsoupConnect', [req]) || { code: 0, message: '', url: req.url, headers: {}, cookies: {}, body: '' };
              if (r.code === 0) { throw new Error('Lỗi mạng khi tải ' + req.url + (r.message ? ': ' + r.message : '')); }
              if (r.code >= 400 && !req.ignoreHttpErrors) {
                throw new Error('HTTP error fetching URL. Status=' + r.code + ', URL=' + r.url);
              }
              return r;
            }
            c.get = function () { req.method = 'GET'; req.wantBytes = false; var r = run(); return g.__lgJsoup.parse(r.body, r.url); };
            c.post = function () { req.method = 'POST'; req.wantBytes = false; var r = run(); return g.__lgJsoup.parse(r.body, r.url); };
            c.execute = function () { req.wantBytes = true; return jsoupResponse(run()); };
            return c;
          }
          g.__lgJsoup.connect = connection;
        })(this);
        """#
}
