import Foundation

/// Mã JS dựng môi trường của nguồn Legado trong `JSContext` riêng của engine (spec §6).
///
/// Swift chỉ cài **một** hàm native `__lgNative(lệnh, đối-số-JSON) -> chuỗi`; mọi đối tượng nguồn thấy được (`java`,
/// `source`, `book`, `chapter`, `cookie`, `cache`, `org.jsoup`, `Packages`…) được dựng bằng JS ở đây. Giá trị qua ranh
/// giới dùng "descriptor" JSON: chuỗi/số/bool giữ nguyên, `{"$el": id}` = phần tử HTML (handle trong runtime),
/// `{"$arr": [...]}` = danh sách, `{"$json": v}` = object/mảng JS, `{"$bytes": "hex"}` = mảng byte.
///
/// Thứ tự nạp: `core` → `objects` → `java` → `jsoup` → `packages`.
enum LegadoJSBootstrap {
    static var scripts: [String] {
        [core, objects, java, jsoup, packages]
    }

    /// Lõi: mã hoá/giải mã descriptor, danh sách/map kiểu Java, hàm gọi native, xuất kết quả.
    static let core = #"""
        (function (g) {
          var N = g.__lgNative;
          function defineHidden(target, name, value) {
            Object.defineProperty(target, name, { value: value, enumerable: false, configurable: true, writable: true });
          }
          function hexToBytes(hex) {
            hex = String(hex || '');
            var n = hex.length >> 1, out = new Uint8Array(n);
            for (var i = 0; i < n; i++) { out[i] = parseInt(hex.substr(i * 2, 2), 16); }
            return out;
          }
          function bytesToHex(b) {
            var s = '';
            for (var i = 0; i < b.length; i++) { var x = b[i] & 0xff; s += (x < 16 ? '0' : '') + x.toString(16); }
            return s;
          }
          function isByteArray(v) {
            if (v instanceof Uint8Array || v instanceof Int8Array) { return true; }
            if (!Array.isArray(v) || v.length === 0) { return false; }
            for (var i = 0; i < v.length && i < 64; i++) { if (typeof v[i] !== 'number') { return false; } }
            return v.__lgBytes === true;
          }
          function enc(v) {
            if (v === undefined || v === null) { return null; }
            var t = typeof v;
            if (t === 'string' || t === 'boolean') { return v; }
            if (t === 'number') { return isFinite(v) ? v : String(v); }
            if (t === 'function' || t === 'symbol') { return null; }
            if (t === 'bigint') { return String(v); }
            if (v instanceof String || v instanceof Number || v instanceof Boolean) { return v.valueOf(); }
            if (v instanceof ArrayBuffer) { return { $bytes: bytesToHex(new Uint8Array(v)) }; }
            if (isByteArray(v)) { return { $bytes: bytesToHex(v) }; }
            if (v.__lgEl !== undefined) { return { $el: v.__lgEl }; }
            if (Array.isArray(v)) { return { $arr: v.map(enc) }; }
            if (typeof v.__lgString === 'function') { return v.__lgString(); }
            try { JSON.stringify(v); return { $json: v }; } catch (e) { return String(v); }
          }
          function dec(d) {
            if (d === null || d === undefined) { return null; }
            if (typeof d !== 'object') { return d; }
            if (Array.isArray(d)) { return javaList(d.map(dec)); }
            if (d.$el !== undefined) { return g.__lg.wrapElement(d.$el); }
            if (d.$arr !== undefined) { return javaList(d.$arr.map(dec)); }
            if (d.$json !== undefined) { return d.$json; }
            if (d.$bytes !== undefined) { return hexToBytes(d.$bytes); }
            return d;
          }
          function call(command, args) {
            return N(command, JSON.stringify((args || []).map(enc)));
          }
          function callJSON(command, args) {
            var raw = call(command, args);
            return raw === '' ? null : JSON.parse(raw);
          }
          function javaList(arr) {
            defineHidden(arr, 'size', function () { return this.length; });
            defineHidden(arr, 'get', function (i) { var v = this[i]; return v === undefined ? null : v; });
            defineHidden(arr, 'toArray', function () { return Array.prototype.slice.call(this); });
            defineHidden(arr, 'isEmpty', function () { return this.length === 0; });
            defineHidden(arr, 'first', function () { return this.length ? this[0] : null; });
            defineHidden(arr, 'last', function () { return this.length ? this[this.length - 1] : null; });
            defineHidden(arr, 'add', function (x) { this.push(x); return true; });
            defineHidden(arr, 'contains', function (x) { return this.indexOf(x) >= 0; });
            defineHidden(arr, 'text', function () {
              return this.map(function (x) { return x && typeof x.text === 'function' ? x.text() : String(x); })
                .filter(function (s) { return s.length > 0; }).join(' ');
            });
            defineHidden(arr, 'html', function () {
              return this.map(function (x) { return x && typeof x.html === 'function' ? x.html() : String(x); }).join('\n');
            });
            defineHidden(arr, 'outerHtml', function () {
              return this.map(function (x) { return x && typeof x.outerHtml === 'function' ? x.outerHtml() : String(x); }).join('\n');
            });
            defineHidden(arr, 'attr', function (k) {
              for (var i = 0; i < this.length; i++) {
                var x = this[i];
                if (x && typeof x.hasAttr === 'function' && x.hasAttr(k)) { return x.attr(k); }
              }
              return '';
            });
            defineHidden(arr, 'eachText', function () {
              return javaList(this.map(function (x) { return x && typeof x.text === 'function' ? x.text() : String(x); })
                .filter(function (s) { return s.length > 0; }));
            });
            defineHidden(arr, 'eachAttr', function (k) {
              var out = [];
              this.forEach(function (x) { if (x && typeof x.hasAttr === 'function' && x.hasAttr(k)) { out.push(x.attr(k)); } });
              return javaList(out);
            });
            defineHidden(arr, 'select', function (css) {
              var out = [];
              this.forEach(function (x) { if (x && typeof x.select === 'function') { out.push.apply(out, x.select(css)); } });
              return javaList(out);
            });
            defineHidden(arr, 'remove', function () {
              this.forEach(function (x) { if (x && typeof x.remove === 'function') { x.remove(); } });
              return this;
            });
            return arr;
          }
          function javaMap(obj) {
            obj = obj || {};
            defineHidden(obj, 'get', function (k) { var v = this[k]; return v === undefined ? null : v; });
            defineHidden(obj, 'put', function (k, v) { this[k] = v; return v; });
            defineHidden(obj, 'containsKey', function (k) { return Object.prototype.hasOwnProperty.call(this, k); });
            defineHidden(obj, 'remove', function (k) { var v = this[k]; delete this[k]; return v === undefined ? null : v; });
            defineHidden(obj, 'keySet', function () { return javaList(Object.keys(this)); });
            defineHidden(obj, 'values', function () { var self = this; return javaList(Object.keys(this).map(function (k) { return self[k]; })); });
            defineHidden(obj, 'size', function () { return Object.keys(this).length; });
            defineHidden(obj, 'isEmpty', function () { return Object.keys(this).length === 0; });
            return obj;
          }
          function unsupported(name) {
            return function () { call('unsupported', [name]); };
          }
          defineHidden(g, '__lg', {
            call: call, callJSON: callJSON, enc: enc, dec: dec, hexToBytes: hexToBytes, bytesToHex: bytesToHex,
            list: javaList, map: javaMap, unsupported: unsupported, defineHidden: defineHidden,
            wrapElement: function (id) { return null; }
          });
          defineHidden(g, '__lgExport', function (v) { return JSON.stringify(enc(v)); });
          defineHidden(g, '__lgImport', function (text) { return dec(JSON.parse(text)); });
          var stringPolyfills = {
            contains: function (s) { return String(this).indexOf(String(s)) >= 0; },
            equals: function (o) { return String(this) === String(o); },
            isEmpty: function () { return String(this).length === 0; },
            getBytes: function (cs) { return hexToBytes(call('strToBytes', [String(this), cs === undefined ? 'UTF-8' : String(cs)])); }
          };
          Object.keys(stringPolyfills).forEach(function (name) {
            if (!(name in String.prototype)) { defineHidden(String.prototype, name, stringPolyfills[name]); }
          });
          var log = function () {
            call('log', [Array.prototype.slice.call(arguments).map(function (x) {
              return typeof x === 'string' ? x : (function () { try { return JSON.stringify(x); } catch (e) { return String(x); } })();
            }).join(' ')]);
          };
          if (typeof g.console === 'undefined') { g.console = { log: log, info: log, warn: log, error: log, debug: log }; }
          if (typeof g.print === 'undefined') { g.print = log; }
        })(this);
        """#
}
