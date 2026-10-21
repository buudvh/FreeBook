import Foundation

extension LegadoJSBootstrap {
    /// `Packages`, `JavaImporter`, `importPackage`/`importClass`, `org.jsoup`, và `java.lang`/`java.util`… trỏ cùng bộ
    /// giả lập (spec §6.9). Giả lập sẵn: `java.lang.String(bytes|str[, charset])`, `java.lang.Thread.sleep` (≤ 5 giây),
    /// `java.util.Base64`, `android.util.Base64`, `java.util.UUID`. Lớp khác ⇒ gọi/khởi tạo là ném lỗi "chưa hỗ trợ".
    static let packages = #"""
        (function (g) {
          var L = g.__lg, call = L.call;
          function isBytes(v) { return v instanceof Uint8Array || v instanceof Int8Array || (Array.isArray(v) && v.length > 0 && typeof v[0] === 'number'); }
          function named(fn, name) { L.defineHidden(fn, '__lgName', name); return fn; }
          function unsupportedClass(full) {
            var short = full.split('.').pop();
            var thrower = named(function () { call('unsupported', ['Lớp Java ' + full]); }, short);
            return new Proxy(thrower, {
              get: function (target, prop) {
                if (typeof prop !== 'string') { return undefined; }
                if (prop === '__lgName') { return short; }
                if (prop === 'then' || prop === 'toJSON' || prop.indexOf('__') === 0) { return undefined; }
                if (prop === 'prototype' || prop === 'name' || prop === 'length') { return target[prop]; }
                return function () { call('unsupported', ['Lớp Java ' + full + '.' + prop]); };
              }
            });
          }
          // Lớp giả lập đăng ký ở `__lg.classes` (script `classes`) được gắn vào gói chứa nó, để `JavaImporter`/
          // `importPackage` (đọc khoá của gói) thấy được.
          function namespace(path, known) {
            known = known || {};
            Object.keys(L.classes || {}).forEach(function (full) {
              var dot = full.lastIndexOf('.');
              var name = full.slice(dot + 1);
              if (dot > 0 && full.slice(0, dot) === path && !Object.prototype.hasOwnProperty.call(known, name)) {
                known[name] = L.classes[full];
              }
            });
            return new Proxy(known, {
              get: function (target, prop) {
                if (typeof prop !== 'string') { return undefined; }
                if (Object.prototype.hasOwnProperty.call(target, prop)) { return target[prop]; }
                if (prop === 'then' || prop === 'toJSON' || prop === 'valueOf' || prop === 'constructor' || prop.indexOf('__') === 0) {
                  return undefined;
                }
                if (prop === 'toString') { return function () { return '[JavaPackage ' + path + ']'; }; }
                var full = path ? path + '.' + prop : prop;
                return /^[A-Z]/.test(prop) ? unsupportedClass(full) : namespace(full);
              }
            });
          }

          var JString = named(function (a, cs) {
            var s;
            if (a === undefined || a === null) { s = ''; }
            else if (isBytes(a)) { s = call('bytesToStr', [a, cs === undefined ? 'UTF-8' : String(cs)]); }
            else { s = String(a); }
            return new.target ? new String(s) : s;
          }, 'String');
          JString.valueOf = function (v) { return String(v); };
          var JThread = named({ sleep: function (ms) { call('sleep', [Number(ms)]); } }, 'Thread');
          var JInteger = named({
            parseInt: function (s, radix) { return parseInt(s, radix || 10); },
            valueOf: function (s, radix) { return parseInt(s, radix || 10); },
            toHexString: function (n) { return (n >>> 0).toString(16); },
            MAX_VALUE: 2147483647, MIN_VALUE: -2147483648
          }, 'Integer');
          var JSystem = named({ currentTimeMillis: function () { return Date.now(); } }, 'System');
          function base64Encode(bytes, flags) { return call('b64enc', [bytes, flags === undefined ? 2 : flags]); }
          function base64Decode(text, flags) { return L.hexToBytes(call('b64decBytes', [text, flags === undefined ? null : flags])); }
          var JBase64 = named({
            getEncoder: function () { return { encodeToString: function (b) { return base64Encode(b, 2); }, encode: function (b) { return L.hexToBytes(call('strToBytes', [base64Encode(b, 2), 'UTF-8'])); } }; },
            getDecoder: function () { return { decode: function (s) { return base64Decode(s, 0); } }; },
            getUrlEncoder: function () { return { encodeToString: function (b) { return base64Encode(b, 10); } }; },
            getUrlDecoder: function () { return { decode: function (s) { return base64Decode(s, 8); } }; },
            getMimeEncoder: function () { return { encodeToString: function (b) { return base64Encode(b, 0); } }; },
            getMimeDecoder: function () { return { decode: function (s) { return base64Decode(s, 0); } }; }
          }, 'Base64');
          var AndroidBase64 = named({
            DEFAULT: 0, NO_PADDING: 1, NO_WRAP: 2, CRLF: 4, URL_SAFE: 8, NO_CLOSE: 16,
            encodeToString: function (b, flags) { return base64Encode(b, flags === undefined ? 0 : flags); },
            encode: function (b, flags) { return L.hexToBytes(call('strToBytes', [base64Encode(b, flags === undefined ? 0 : flags), 'UTF-8'])); },
            decode: function (s, flags) { return base64Decode(s, flags === undefined ? 0 : flags); }
          }, 'Base64');
          var JUUID = named({
            randomUUID: function () { var u = call('uuid', []); return { toString: function () { return u; } }; }
          }, 'UUID');

          var javaLang = namespace('java.lang', { String: JString, Thread: JThread, Integer: JInteger, System: JSystem, Math: Math });
          var javaUtil = namespace('java.util', { Base64: JBase64, UUID: JUUID });
          var javaRoot = namespace('java', { lang: javaLang, util: javaUtil });
          var androidRoot = namespace('android', { util: namespace('android.util', { Base64: AndroidBase64 }) });
          var orgRoot = namespace('org', { jsoup: namespace('org.jsoup', { Jsoup: g.__lgJsoup }) });
          var Packages = namespace('', { java: javaRoot, javax: namespace('javax'), android: androidRoot, org: orgRoot });

          function importInto(target, pkg) {
            if (!pkg) { return; }
            if (pkg.__lgName) { target[pkg.__lgName] = pkg; return; }
            Object.keys(pkg).forEach(function (k) { target[k] = pkg[k]; });
          }
          g.Packages = Packages;
          g.org = orgRoot;
          g.JavaImporter = function () {
            var importer = {};
            L.defineHidden(importer, 'importPackage', function () {
              for (var i = 0; i < arguments.length; i++) { importInto(importer, arguments[i]); }
            });
            L.defineHidden(importer, 'importClass', function () {
              for (var i = 0; i < arguments.length; i++) { importInto(importer, arguments[i]); }
            });
            for (var i = 0; i < arguments.length; i++) { importInto(importer, arguments[i]); }
            return importer;
          };
          g.importPackage = function () {
            for (var i = 0; i < arguments.length; i++) {
              var pkg = arguments[i];
              if (pkg && !pkg.__lgName) { Object.keys(pkg).forEach(function (k) { if (k !== 'String' && k !== 'Math') { g[k] = pkg[k]; } }); }
            }
          };
          g.importClass = function () {
            for (var i = 0; i < arguments.length; i++) {
              var cls = arguments[i];
              if (cls && cls.__lgName && cls.__lgName !== 'String') { g[cls.__lgName] = cls; }
            }
          };
          ['lang', 'util', 'io', 'net', 'security', 'math', 'text', 'nio', 'time'].forEach(function (name) {
            g.java[name] = javaRoot[name];
          });
        })(this);
        """#
}
