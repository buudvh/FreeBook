import Foundation

/// Mã JS dựng môi trường của nguồn Legado trong `JSContext` riêng của engine (spec §6).
///
/// Swift chỉ cài **một** hàm native `__lgNative(lệnh, đối-số-JSON) -> chuỗi`; mọi đối tượng nguồn thấy được (`java`,
/// `source`, `book`, `chapter`, `cookie`, `cache`, `org.jsoup`, `Packages`…) được dựng bằng JS ở đây. Giá trị qua ranh
/// giới dùng "descriptor" JSON: chuỗi/số/bool giữ nguyên, `{"$el": id}` = phần tử HTML (handle trong runtime),
/// `{"$arr": [...]}` = danh sách, `{"$json": v}` = object/mảng JS, `{"$bytes": "hex"}` = mảng byte.
///
/// Thứ tự nạp: `core` → `info` → `objects` → `java` → `javaExtra` → `classes` → `concurrent` → `jsoup` → `connect` →
/// `packages`.
enum LegadoJSBootstrap {
    static var scripts: [String] {
        [core, info, objects, java, javaExtra, classes, concurrent, jsoup, connect, packages]
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
          // Danh sách kiểu Java `List`/jsoup `Elements` (spec §6.3, §6.8): mảng JS thật gắn thêm phương thức **ẩn** (không
          // enumerable, để `for (i in ds)` chỉ thấy chỉ số). Phương thức dùng chung một bảng, đọc `this`.
          function isElement(x) { return x !== null && x !== undefined && x.__lgEl !== undefined; }
          function nullable(v) { return v === undefined ? null : v; }
          // Chỉ số kiểu Java `int` (cắt phần lẻ); ngoài `[0, độ dài)` (hoặc `[0, độ dài]` khi `inclusive`) ⇒ ném lỗi.
          function listIndex(list, i, inclusive) {
            var n = Math.trunc(Number(i));
            if (!(n >= 0 && (inclusive ? n <= list.length : n < list.length))) {
              throw new RangeError('Chỉ số ' + i + ' ngoài khoảng (độ dài ' + list.length + ')');
            }
            return n;
          }
          // Dạng có chỉ số `f(i, x)` của Java: đúng 2 đối số và đối số đầu là số (gọi qua `forEach(ds.add, ds)` thì không).
          function indexedCall(args) { return args.length === 2 && (typeof args[0] === 'number' || args[0] instanceof Number); }
          function collectionItems(c) {
            if (c === undefined || c === null) { return []; }
            if (!Array.isArray(c) && typeof c.toArray === 'function') { c = c.toArray(); }
            return Array.prototype.slice.call(c);
          }
          var listMethods = {
            size: function () { return this.length; },
            get: function (i) { return nullable(this[i]); },
            toArray: function () { return Array.prototype.slice.call(this); },
            isEmpty: function () { return this.length === 0; },
            first: function () { return this.length ? this[0] : null; },
            last: function () { return this.length ? this[this.length - 1] : null; },
            // `add(x)` thêm cuối; `add(i, x)` chèn tại chỉ số.
            add: function (a, b) {
              if (indexedCall(arguments)) { this.splice(listIndex(this, a, true), 0, b); return; }
              this.push(a);
              return true;
            },
            addAll: function (a, b) {
              var indexed = indexedCall(arguments), items = collectionItems(indexed ? b : a);
              if (indexed) {
                Array.prototype.splice.apply(this, [listIndex(this, a, true), 0].concat(items));
              } else {
                for (var i = 0; i < items.length; i++) { this.push(items[i]); }
              }
              return items.length > 0;
            },
            set: function (i, v) { var at = listIndex(this, i, false), old = this[at]; this[at] = v; return nullable(old); },
            clear: function () { this.length = 0; },
            contains: function (x) { return this.indexOf(x) >= 0; },
            // `remove()` = `Elements.remove()` (gỡ mọi phần tử khỏi DOM, trả chính danh sách); `remove(số)` = bỏ phần tử
            // ở chỉ số đó khỏi danh sách, trả phần tử; `remove(đối tượng)` = bỏ lần xuất hiện đầu, trả `true`/`false`.
            remove: function (x) {
              if (arguments.length === 0) {
                this.forEach(function (e) { if (e && typeof e.remove === 'function') { e.remove(); } });
                return this;
              }
              if (typeof x === 'number' || x instanceof Number) {
                var at = listIndex(this, x, false), old = this[at];
                this.splice(at, 1);
                return nullable(old);
              }
              var found = this.indexOf(x);
              if (found < 0) { return false; }
              this.splice(found, 1);
              return true;
            },
            // Bản sao `[from, to)`; chỉ `clear()` ghi ngược (bỏ đoạn đó khỏi danh sách gốc), cách dùng duy nhất của corpus.
            // Danh sách gốc đổi sau khi tạo (độ dài hoặc phần tử trong đoạn khác đi) ⇒ `clear()` ném lỗi như Java
            // `ConcurrentModificationException`, thay vì bỏ nhầm đoạn.
            subList: function (from, to) {
              var parent = this, start = Math.trunc(Number(from)), end = Math.trunc(Number(to));
              if (!(start >= 0 && end <= parent.length && start <= end)) {
                throw new RangeError('subList(' + from + ', ' + to + ') ngoài khoảng (độ dài ' + parent.length + ')');
              }
              var sub = javaList(Array.prototype.slice.call(parent, start, end));
              var range = Array.prototype.slice.call(sub), expected = parent.length;
              defineHidden(sub, 'clear', function () {
                var same = parent.length === expected;
                for (var i = 0; same && i < range.length; i++) { same = Object.is(parent[start + i], range[i]); }
                if (!same) { throw new Error('ConcurrentModificationException: danh sách gốc đã đổi sau subList()'); }
                parent.splice(start, range.length);
                range = [];
                expected = parent.length;
                this.length = 0;
              });
              return sub;
            },
            iterator: function () {
              var self = this, next = 0, last = -1;
              return {
                hasNext: function () { return next < self.length; },
                next: function () {
                  if (next >= self.length) { throw new RangeError('Hết phần tử'); }
                  last = next;
                  return self[next++];
                },
                remove: function () {
                  if (last < 0) { throw new Error('iterator.remove() khi chưa gọi next()'); }
                  self.splice(last, 1);
                  next = last;
                  last = -1;
                }
              };
            },
            text: function () {
              return this.map(function (x) { return x && typeof x.text === 'function' ? x.text() : String(x); })
                .filter(function (s) { return s.length > 0; }).join(' ');
            },
            html: function () {
              return this.map(function (x) { return x && typeof x.html === 'function' ? x.html() : String(x); }).join('\n');
            },
            outerHtml: function () {
              return this.map(function (x) { return x && typeof x.outerHtml === 'function' ? x.outerHtml() : String(x); }).join('\n');
            },
            // Danh sách phần tử ⇒ `outerHtml` nối bằng `\n` như jsoup (để `Jsoup.parse(ds)` đúng); còn lại như mảng JS.
            toString: function () {
              if (this.length > 0 && this.every(isElement)) { return this.outerHtml(); }
              return Array.prototype.toString.call(this);
            },
            attr: function (k) {
              for (var i = 0; i < this.length; i++) {
                var x = this[i];
                if (x && typeof x.hasAttr === 'function' && x.hasAttr(k)) { return x.attr(k); }
              }
              return '';
            },
            eachText: function () {
              return javaList(this.map(function (x) { return x && typeof x.text === 'function' ? x.text() : String(x); })
                .filter(function (s) { return s.length > 0; }));
            },
            eachAttr: function (k) {
              var out = [];
              this.forEach(function (x) { if (x && typeof x.hasAttr === 'function' && x.hasAttr(k)) { out.push(x.attr(k)); } });
              return javaList(out);
            },
            select: function (css) {
              var out = [];
              this.forEach(function (x) { if (x && typeof x.select === 'function') { out.push.apply(out, x.select(css)); } });
              return javaList(out);
            },
            // `eq(i)` = danh sách chỉ gồm phần tử thứ i (ngoài khoảng ⇒ rỗng).
            eq: function (i) {
              var n = Math.trunc(Number(i));
              return javaList(n >= 0 && n < this.length ? [this[n]] : []);
            },
            // Tổ tiên của mọi phần tử, bỏ trùng theo định danh, giữ thứ tự gặp.
            parents: function () {
              var out = [];
              this.forEach(function (x) {
                if (!x || typeof x.parents !== 'function') { return; }
                x.parents().forEach(function (p) { if (out.indexOf(p) < 0) { out.push(p); } });
              });
              return javaList(out);
            }
          };
          var listMethodNames = Object.keys(listMethods);
          function javaList(arr) {
            for (var i = 0; i < listMethodNames.length; i++) { defineHidden(arr, listMethodNames[i], listMethods[listMethodNames[i]]); }
            return arr;
          }
          // Một cặp của `Map.entrySet()`: `getKey()`, `getValue()`, `setValue(v)` (ghi ngược vào map), `toString()` = `k=v`.
          function mapEntry(map, key) {
            var entry = {}, value = map[key];
            defineHidden(entry, 'getKey', function () { return key; });
            defineHidden(entry, 'getValue', function () { return nullable(value); });
            defineHidden(entry, 'setValue', function (v) { var old = value; value = v; map[key] = v; return nullable(old); });
            defineHidden(entry, 'toString', function () { return key + '=' + (value === undefined ? null : value); });
            return entry;
          }
          var mapMethods = {
            get: function (k) { return nullable(this[k]); },
            put: function (k, v) { this[k] = v; return v; },
            containsKey: function (k) { return Object.prototype.hasOwnProperty.call(this, k); },
            remove: function (k) { var v = this[k]; delete this[k]; return nullable(v); },
            keySet: function () { return javaList(Object.keys(this)); },
            values: function () { var self = this; return javaList(Object.keys(this).map(function (k) { return self[k]; })); },
            entrySet: function () { var self = this; return javaList(Object.keys(this).map(function (k) { return mapEntry(self, k); })); },
            size: function () { return Object.keys(this).length; },
            isEmpty: function () { return Object.keys(this).length === 0; }
          };
          var mapMethodNames = Object.keys(mapMethods);
          function javaMap(obj) {
            obj = obj || {};
            for (var i = 0; i < mapMethodNames.length; i++) { defineHidden(obj, mapMethodNames[i], mapMethods[mapMethodNames[i]]); }
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
          // Mảng byte kiêm luồng đọc kiểu `InputStream` (`read()` → byte kế hoặc -1, `read(buf[, off, len])`).
          function byteStream(bytes) {
            var pos = 0;
            defineHidden(bytes, 'read', function (buf, off, len) {
              if (buf === undefined || buf === null) { return pos < bytes.length ? bytes[pos++] : -1; }
              off = off || 0;
              len = len === undefined ? buf.length - off : len;
              if (pos >= bytes.length) { return -1; }
              var n = Math.min(len, bytes.length - pos);
              for (var i = 0; i < n; i++) { buf[off + i] = bytes[pos++]; }
              return n;
            });
            defineHidden(bytes, 'available', function () { return bytes.length - pos; });
            defineHidden(bytes, 'readBytes', function () { var out = bytes.slice(pos); pos = bytes.length; return out; });
            defineHidden(bytes, 'readAllBytes', function () { var out = bytes.slice(pos); pos = bytes.length; return out; });
            defineHidden(bytes, 'reset', function () { pos = 0; });
            defineHidden(bytes, 'close', function () {});
            return bytes;
          }
          g.__lg.byteStream = byteStream;
          defineHidden(g, '__lgMakeMap', function (text) { return javaMap(JSON.parse(text)); });
          defineHidden(g, '__lgMakeBytes', function (hex) { return byteStream(hexToBytes(hex)); });
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
