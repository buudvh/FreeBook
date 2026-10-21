import Foundation

extension LegadoJSBootstrap {
    /// Đối tượng `java` (spec §6.4) — mọi hàm **đồng bộ** đối với script. Hàm hoãn (§6.11) là stub ném lỗi có tên hàm;
    /// cố ý **không** định nghĩa `java.qread`, `java.deviceID`, `java.reLoginView`, `java.getUserAgent` (§6.10).
    static let java = #"""
        (function (g) {
          var L = g.__lg, call = L.call, callJSON = L.callJSON;
          function headerArg(h) {
            if (h === undefined || h === null) { return null; }
            if (typeof h === 'string') { return h; }
            try { return JSON.stringify(h); } catch (e) { return String(h); }
          }
          function response(r) {
            r = r || { url: '', code: 0, message: '', headers: {}, cookies: {}, body: '' };
            function findHeader(name) {
              var lower = String(name).toLowerCase();
              for (var k in r.headers) { if (k.toLowerCase() === lower) { return r.headers[k]; } }
              return null;
            }
            var res = {
              body: function () { return r.body; },
              code: function () { return r.code; },
              statusCode: function () { return r.code; },
              message: function () { return r.message; },
              statusMessage: function () { return r.message; },
              isSuccessful: function () { return r.code >= 200 && r.code < 300; },
              headers: function () { return L.map(Object.assign({}, r.headers)); },
              header: function (name) { return findHeader(name); },
              cookies: function () { return L.map(Object.assign({}, r.cookies)); },
              cookie: function (name) { var v = r.cookies[name]; return v === undefined ? null : v; },
              url: function () { return r.url; },
              raw: function () {
                return {
                  request: function () { return { url: function () { return r.url; } }; },
                  code: function () { return r.code; },
                  message: function () { return r.message; },
                  headers: function () { return L.map(Object.assign({}, r.headers)); },
                  header: function (name) { return findHeader(name); }
                };
              },
              toString: function () { return r.body; }
            };
            L.defineHidden(res, '__lgResp', r);
            L.defineHidden(res, '__lgString', function () { return { $resp: r }; });
            return res;
          }
          L.response = response;
          L.defineHidden(g, '__lgMakeResponse', function (text) { return response(JSON.parse(text)); });
          L.defineHidden(g, '__lgClassify', function (v) {
            if (v === undefined || v === null) { return '{"k":"none"}'; }
            if (typeof v === 'object' && v.__lgResp) { return JSON.stringify({ k: 'resp', r: v.__lgResp }); }
            if (typeof v === 'string' || v instanceof String) { return JSON.stringify({ k: 'str', s: String(v) }); }
            return '{"k":"none"}';
          });
          function symmetric(transformation, key, iv) {
            function run(op, data, output) { return call('sym', [op, String(transformation), key, iv === undefined ? null : iv, data, output]); }
            return {
              decrypt: function (d) { return L.hexToBytes(run('dec', d, 'hex')); },
              decryptStr: function (d) { return run('dec', d, 'str'); },
              encrypt: function (d) { return L.hexToBytes(run('enc', d, 'hex')); },
              encryptBase64: function (d) { return run('enc', d, 'b64'); },
              encryptHex: function (d) { return run('enc', d, 'hex'); }
            };
          }
          var java = {
            ajax: function (url, timeout) { return call('ajax', [String(url), timeout === undefined ? null : Number(timeout)]); },
            ajaxAll: function (urls) {
              var list = Array.prototype.slice.call(urls || []).map(String);
              return L.list((callJSON('ajaxAll', [list]) || []).map(response));
            },
            connect: function (url, headers) { return response(callJSON('connect', [String(url), headerArg(headers)])); },
            get: function (a, b) {
              if (arguments.length >= 2) { return response(callJSON('httpGet', [String(a), headerArg(b)])); }
              return call('getVar', [String(a)]);
            },
            post: function (url, body, headers) {
              return response(callJSON('httpPost', [String(url), body == null ? '' : String(body), headerArg(headers)]));
            },
            head: function (url, headers) { return response(callJSON('httpHead', [String(url), headerArg(headers)])); },
            webView: function (html, url, js) {
              return call('webView', [html == null ? null : String(html), url == null ? null : String(url), js == null ? null : String(js)]);
            },
            getString: function (rule, content, isUrl) {
              return call('getString', [String(rule), content === undefined ? null : content, !!isUrl]);
            },
            getStringList: function (rule, content, isUrl) {
              return L.list(callJSON('getStringList', [String(rule), content === undefined ? null : content, !!isUrl]) || []);
            },
            getElements: function (rule) { return L.dec(callJSON('getElements', [String(rule)])) || L.list([]); },
            getElement: function (rule) { var l = java.getElements(rule); return l.length ? l[0] : null; },
            setContent: function (content, baseUrl) { call('setContent', [content, baseUrl == null ? null : String(baseUrl)]); },
            put: function (k, v) { call('putVar', [String(k), String(v)]); return v; },
            toNumChapter: function (s) { return call('toNumChapter', [s == null ? '' : String(s)]); },
            md5Encode: function (s) { return call('md5', [s]); },
            md5Encode16: function (s) { return call('md5_16', [s]); },
            base64Encode: function (s, flags) { return call('b64enc', [s, flags === undefined ? null : flags]); },
            base64Decode: function (s, cs) { return call('b64dec', [s == null ? '' : String(s), cs === undefined ? null : cs]); },
            base64DecodeToByteArray: function (s, flags) {
              return L.hexToBytes(call('b64decBytes', [s == null ? '' : String(s), flags === undefined ? null : flags]));
            },
            hexDecodeToString: function (hex) { return call('hexDecStr', [String(hex)]); },
            hexDecodeToByteArray: function (hex) { return L.hexToBytes(String(hex).replace(/[^0-9a-fA-F]/g, '')); },
            hexEncodeToString: function (s) { return call('hexEnc', [s]); },
            strToBytes: function (s, cs) { return L.hexToBytes(call('strToBytes', [String(s), cs === undefined ? 'UTF-8' : String(cs)])); },
            bytesToStr: function (b, cs) { return call('bytesToStr', [b, cs === undefined ? 'UTF-8' : String(cs)]); },
            encodeURI: function (s, enc) { return call('encodeURI', [s == null ? '' : String(s), enc === undefined ? 'UTF-8' : String(enc)]); },
            createSymmetricCrypto: function (t, key, iv) { return symmetric(t, key, iv); },
            aesBase64DecodeToString: function (data, key, t, iv) { return symmetric(t, key, iv).decryptStr(data); },
            digestHex: function (data, alg) { return call('digest', [data, String(alg), 'hex']); },
            digestBase64Str: function (data, alg) { return call('digest', [data, String(alg), 'b64']); },
            HMacHex: function (data, alg, key) { return call('hmac', [data, String(alg), key, 'hex']); },
            HMacBase64: function (data, alg, key) { return call('hmac', [data, String(alg), key, 'b64']); },
            log: function (msg) { call('log', [typeof msg === 'string' ? msg : (function () { try { return JSON.stringify(msg); } catch (e) { return String(msg); } })()]); return msg; },
            logType: function (v) { call('log', [Object.prototype.toString.call(v) + ' / ' + typeof v]); },
            toast: function (msg) { call('toast', [String(msg)]); },
            longToast: function (msg) { call('toast', [String(msg), true]); },
            timeFormat: function (ms) { return call('timeFormat', [Number(ms)]); },
            timeFormatUTC: function (ms, fmt, sh) { return call('timeFormatUTC', [Number(ms), String(fmt), sh === undefined ? 0 : Number(sh)]); },
            t2s: function (s) { return call('t2s', [s == null ? '' : String(s)]); },
            s2t: function (s) { return call('s2t', [s == null ? '' : String(s)]); },
            htmlFormat: function (s) { return call('htmlFormat', [s == null ? '' : String(s)]); },
            randomUUID: function () { return call('uuid', []); },
            androidId: function () { return call('androidId', []); },
            getWebViewUA: function () { return call('webViewUA', []); },
            getCookie: function (url, key) { return call('cookieGet', [String(url), key === undefined || key === null ? null : String(key)]); }
          };
          // Hoãn hẳn / UI của ứng dụng gốc (spec §13.11, §14.5): stub ném "Chưa hỗ trợ …". Các hàm đợt 2/3 khác nằm ở
          // `LegadoJSBootstrap+JavaExtra`. Cố ý KHÔNG định nghĩa: `showBrowser`, `showReadingBrowser`, `openWeb`
          // (nguồn bọc `try` rồi rơi về `startBrowser`), `upLoginData`/`reLoginView` (chỉ có trong form đăng nhập), `readFile`.
          ['open', 'openVideoPlayer', 'addBook'].forEach(function (name) { java[name] = L.unsupported('java.' + name); });
          g.java = java;
        })(this);
        """#
}
