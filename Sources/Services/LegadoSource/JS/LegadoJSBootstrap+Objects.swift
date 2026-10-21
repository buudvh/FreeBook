import Foundation

extension LegadoJSBootstrap {
    /// `source`, `book`, `chapter`, `cookie`, `cache` (spec §6.5–§6.7). Biến môi trường là **thuộc tính của đối tượng toàn
    /// cục** (hàm `jsLib` đọc `this.source`, §5.8). `book`/`chapter` được gắn lại trước mỗi lần chạy JS bằng
    /// `__lgBindContexts(idSách, idChương)`: không có ngữ cảnh ⇒ `null` (nguồn kiểm `book ? … : …`, §3.6).
    static let objects = #"""
        (function (g) {
          var L = g.__lg, call = L.call, callJSON = L.callJSON;
          function cap(s) { return s.charAt(0).toUpperCase() + s.slice(1); }

          var raw = callJSON('sourceInfo', []) || {};
          var source = {};
          Object.keys(raw).forEach(function (k) { source[k] = raw[k]; });
          source.key = raw.bookSourceUrl;
          Object.keys(raw).forEach(function (k) {
            var getter = 'get' + cap(k);
            if (!(getter in source)) { L.defineHidden(source, getter, function () { return raw[k]; }); }
          });
          var sourceMethods = {
            getKey: function () { return raw.bookSourceUrl; },
            getTag: function () { return raw.bookSourceName; },
            getVariable: function () { return call('sourceGetVar', []); },
            setVariable: function (v) { call('sourceSetVar', [v == null ? '' : String(v)]); },
            putVariable: function (v) { call('sourceSetVar', [v == null ? '' : String(v)]); },
            put: function (k, v) { call('sourcePut', [String(k), v == null ? '' : String(v)]); return v; },
            get: function (k) { var v = callJSON('sourceGet', [String(k)]); return v === null ? '' : v; },
            getLoginInfo: function () { return ''; },
            getLoginInfoMap: function () { return L.map({}); },
            getLoginHeader: function () { return ''; },
            getLoginHeaderMap: function () { return L.map({}); },
            getHeaderMap: function () { return L.map(callJSON('sourceHeaders', []) || {}); },
            refreshExplore: function () {},
            refreshJSLib: function () {},
            putConcurrent: function () {},
            getSource: function () { return source; },
            putLoginHeader: L.unsupported('source.putLoginHeader'),
            removeLoginHeader: L.unsupported('source.removeLoginHeader'),
            putLoginInfo: L.unsupported('source.putLoginInfo'),
            removeLoginInfo: L.unsupported('source.removeLoginInfo'),
            login: L.unsupported('source.login')
          };
          Object.keys(sourceMethods).forEach(function (k) { L.defineHidden(source, k, sourceMethods[k]); });

          function contextObject(kind, fields, deferredSetters) {
            var o = {}, overrides = {};
            fields.forEach(function (f) {
              Object.defineProperty(o, f, {
                enumerable: true, configurable: true,
                get: function () {
                  if (Object.prototype.hasOwnProperty.call(overrides, f)) { return overrides[f]; }
                  return callJSON(kind + '.get', [f]);
                },
                set: function (v) { overrides[f] = v; }
              });
              L.defineHidden(o, 'get' + cap(f), function () { return o[f]; });
              L.defineHidden(o, 'set' + cap(f), function (v) { o[f] = v; });
            });
            L.defineHidden(o, 'getVariable', function (k) {
              if (k === undefined) { return o.variable; }
              return call(kind + '.getVar', [String(k)]);
            });
            L.defineHidden(o, 'putVariable', function (k, v) {
              call(kind + '.putVar', [String(k), v == null ? null : String(v)]);
              return v;
            });
            (deferredSetters || []).forEach(function (name) {
              L.defineHidden(o, name, function (v) { call('deferredNoop', [kind + '.' + name]); overrides['__' + name] = v; });
            });
            L.defineHidden(o, '__lgReset', function () { overrides = {}; });
            L.defineHidden(o, 'toString', function () { return '[' + kind + ']'; });
            return o;
          }

          var book = contextObject('book', [
            'name', 'author', 'kind', 'coverUrl', 'intro', 'bookUrl', 'tocUrl', 'origin', 'originName', 'type',
            'latestChapterTitle', 'lastChapter', 'wordCount', 'durChapterIndex', 'durChapterTitle', 'durChapterPos',
            'totalChapterNum', 'customIntro', 'customTag', 'customCoverUrl', 'canUpdate', 'order', 'variable', 'group'
          ], ['setReverseToc', 'setUseReplaceRule']);
          var chapter = contextObject('chapter', [
            'title', 'index', 'url', 'baseUrl', 'bookUrl', 'tag', 'isVip', 'isVolume', 'isPay', 'variable', 'resourceUrl'
          ], []);

          var bound = { book: null, chapter: null };
          L.defineHidden(g, '__lgBindContexts', function (bookId, chapterId) {
            if (bookId !== bound.book) { book.__lgReset(); bound.book = bookId; }
            if (chapterId !== bound.chapter) { chapter.__lgReset(); bound.chapter = chapterId; }
            g.book = bookId === null ? null : book;
            g.chapter = chapterId === null ? null : chapter;
          });

          var cookie = {
            getCookie: function (url, key) {
              return call('cookieGet', [String(url), key === undefined || key === null ? null : String(key)]);
            },
            getKey: function (url, key) { return call('cookieGet', [String(url), String(key)]); },
            setCookie: function (url, value) { call('cookieSet', [String(url), value == null ? '' : String(value), false]); },
            replaceCookie: function (url, value) { call('cookieSet', [String(url), value == null ? '' : String(value), true]); },
            removeCookie: function (url) { call('cookieRemove', [String(url)]); }
          };

          var cache = {
            put: function (key, value, saveTime) {
              call('cachePut', [String(key), value == null ? '' : String(value), saveTime === undefined ? null : Number(saveTime)]);
            },
            get: function (key) { return callJSON('cacheGet', [String(key)]); },
            'delete': function (key) { call('cacheDelete', [String(key)]); },
            putFile: function (key, value, saveTime) { cache.put(key, value, saveTime); },
            getFile: function (key) { return cache.get(key); },
            deleteFile: function (key) { cache['delete'](key); },
            putMemory: function (key, value) {
              var text;
              try { text = JSON.stringify(value === undefined ? null : value); } catch (e) { text = JSON.stringify(String(value)); }
              call('memPut', [String(key), text]);
            },
            getFromMemory: function (key) { var t = call('memGet', [String(key)]); return t === '' ? null : JSON.parse(t); },
            deleteMemory: function (key) { call('memDelete', [String(key)]); }
          };

          g.source = source;
          g.cookie = cookie;
          g.cache = cache;
          g.book = null;
          g.chapter = null;
        })(this);
        """#
}
