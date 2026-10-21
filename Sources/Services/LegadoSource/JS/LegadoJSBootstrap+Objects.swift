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
            // Đăng nhập (spec §10.5–§10.6): chưa có ⇒ `null` (U39); bản `Map` chưa có ⇒ map rỗng.
            getLoginInfo: function () { return callJSON('loginInfoGet', []); },
            getLoginInfoMap: function () { return L.map(callJSON('loginInfoMap', []) || {}); },
            putLoginInfo: function (v) { call('loginInfoPut', [textArg(v)]); return true; },
            putLoginInfoMap: function (v) { call('loginInfoPut', [textArg(v)]); return true; },
            removeLoginInfo: function () { call('loginInfoRemove', []); },
            getLoginHeader: function () { return callJSON('loginHeaderGet', []); },
            getLoginHeaderMap: function () { return L.map(callJSON('loginHeaderMap', []) || {}); },
            putLoginHeader: function (v) { call('loginHeaderPut', [textArg(v)]); },
            removeLoginHeader: function () { call('loginHeaderRemove', []); },
            getHeaderMap: function (withLogin) { return L.map(callJSON('sourceHeaders', [!!withLogin]) || {}); },
            login: function () { call('sourceLogin', []); },
            refreshExplore: function () { call('refreshExplore', []); },
            refreshJSLib: function () {},
            putConcurrent: function () {},
            getSource: function () { return source; }
          };
          function textArg(v) {
            if (v === undefined || v === null) { return ''; }
            if (typeof v === 'string' || v instanceof String) { return String(v); }
            try { return JSON.stringify(v); } catch (e) { return String(v); }
          }
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
                set: function (v) { overrides[f] = v; call(kind + '.set', [f, v === undefined ? null : v]); }
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
            // `setReverseToc(b)`, `setUseReplaceRule(b)` (spec §13.5): ghi nhận trên ngữ cảnh Swift để luồng áp dụng.
            (deferredSetters || []).forEach(function (name) {
              L.defineHidden(o, name, function (v) {
                call(kind + '.set', [name, v === undefined ? null : v]);
                overrides['__' + name] = v;
              });
            });
            L.defineHidden(o, '__lgReset', function () { overrides = {}; });
            L.defineHidden(o, 'toString', function () { return '[' + kind + ']'; });
            return o;
          }

          var book = contextObject('book', [
            'name', 'author', 'kind', 'coverUrl', 'intro', 'bookUrl', 'tocUrl', 'origin', 'originName', 'type',
            'latestChapterTitle', 'lastChapter', 'wordCount', 'durChapterIndex', 'durChapterTitle', 'durChapterPos',
            'totalChapterNum', 'customIntro', 'customTag', 'customCoverUrl', 'canUpdate', 'order', 'variable', 'group', 'imageStyle'
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
            removeCookie: function (url) { call('cookieRemove', [String(url)]); },
            // Map cookie (vd `response.cookies()`) → chuỗi `k=v; k2=v2` (spec §14.5).
            mapToCookie: function (map) {
              if (!map) { return ''; }
              return Object.keys(map).filter(function (k) { return typeof map[k] !== 'function'; })
                .map(function (k) { return k + '=' + map[k]; }).join('; ');
            },
            cookieToMap: function (text) {
              var out = {};
              String(text || '').split(';').forEach(function (part) {
                var i = part.indexOf('=');
                if (i > 0) { out[part.slice(0, i).trim()] = part.slice(i + 1).trim(); }
              });
              return L.map(out);
            }
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
          g.infoMap = L.infoMap();
          g.book = null;
          g.chapter = null;
        })(this);
        """#
}
