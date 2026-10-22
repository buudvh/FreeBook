import Foundation

extension LegadoJSBootstrap {
    /// `java.lang.System.getProperties()`/`nanoTime()` và `java.util.concurrent` tối thiểu (spec §6.9), đủ cho bộ giới hạn
    /// nhịp mà nguồn viết bằng lớp Java: `System.getProperties().computeIfAbsent(khoá, k => new AtomicLong(0))`, vòng
    /// `get`/`compareAndSet` theo `System.nanoTime()`, rồi `LockSupport.parkNanos`. Bảng thuộc tính là của từng ngữ cảnh,
    /// nhưng `AtomicLong`/`AtomicInteger` đặt vào bảng được gắn với ô dùng chung toàn tiến trình (lệnh native `javaCell`),
    /// vì mỗi tác vụ một `JSContext`. Phần `System` được gộp vào `java.lang.System` ở script `packages` (nạp sau script này).
    static let concurrent = #"""
        (function (g) {
          var L = g.__lg, call = L.call;
          L.classes = L.classes || {};
          function register(full, cls) { L.defineHidden(cls, '__lgName', full.split('.').pop()); L.classes[full] = cls; return cls; }
          function cell(args) { return call('javaCell', args); }
          function num(text) { return text === '' ? null : Number(text); }
          function toLong(v) { var n = Number(v); return isFinite(n) ? Math.trunc(n) : 0; }
          function toInt(v) { return Number(v) | 0; }

          // Ô nguyên tử: giá trị cục bộ `__lgValue`, hoặc (sau khi vào bảng thuộc tính) ô dùng chung `__lgCell` — mọi
          // thao tác đọc-sửa-ghi khi đó là một lệnh native có khoá.
          function atomicClass(coerce) {
            function Atomic(v) { L.defineHidden(this, '__lgValue', coerce(v === undefined ? 0 : v)); }
            function shared(self) { return self.__lgCell !== undefined; }
            function change(self, delta) {
              delta = coerce(delta);
              if (shared(self)) { return JSON.parse(cell(['add', self.__lgCell, delta])); }
              var old = self.__lgValue;
              self.__lgValue = coerce(old + delta);
              return [old, self.__lgValue];
            }
            var p = Atomic.prototype;
            p.get = function () {
              if (shared(this)) { var v = num(cell(['get', this.__lgCell])); if (v !== null) { return v; } }
              return this.__lgValue;
            };
            p.set = function (v) {
              v = coerce(v);
              if (shared(this)) { cell(['set', this.__lgCell, v]); } else { this.__lgValue = v; }
            };
            p.lazySet = p.set;
            p.compareAndSet = function (expect, update) {
              expect = coerce(expect);
              update = coerce(update);
              if (shared(this)) { return cell(['cas', this.__lgCell, expect, update]) === '1'; }
              if (this.__lgValue !== expect) { return false; }
              this.__lgValue = update;
              return true;
            };
            p.weakCompareAndSet = p.compareAndSet;
            p.getAndSet = function (v) {
              v = coerce(v);
              if (shared(this)) { return Number(cell(['swap', this.__lgCell, v])); }
              var old = this.__lgValue;
              this.__lgValue = v;
              return old;
            };
            p.addAndGet = function (d) { return change(this, d)[1]; };
            p.getAndAdd = function (d) { return change(this, d)[0]; };
            p.incrementAndGet = function () { return change(this, 1)[1]; };
            p.getAndIncrement = function () { return change(this, 1)[0]; };
            p.decrementAndGet = function () { return change(this, -1)[1]; };
            p.getAndDecrement = function () { return change(this, -1)[0]; };
            p.longValue = p.get;
            p.intValue = p.get;
            p.doubleValue = p.get;
            p.valueOf = p.get;
            p.toString = function () { return String(this.get()); };
            return Atomic;
          }
          var AtomicLong = register('java.util.concurrent.atomic.AtomicLong', atomicClass(toLong));
          var AtomicInteger = register('java.util.concurrent.atomic.AtomicInteger', atomicClass(toInt));

          // Gắn ô nguyên tử vừa vào bảng với ô dùng chung cùng khoá (`replace` = `put`; bảng native đầy ⇒ giữ cục bộ).
          function bindShared(key, value, replace) {
            if (!(value instanceof AtomicLong || value instanceof AtomicInteger) || value.__lgCell !== undefined) { return value; }
            if (num(cell(['bind', key, value.__lgValue, !!replace])) !== null) { L.defineHidden(value, '__lgCell', key); }
            return value;
          }

          // `System.getProperties()`: cùng một bảng cho mọi lần gọi trong ngữ cảnh. Khoá vắng mặt mà ô dùng chung có (do
          // ngữ cảnh khác đặt) ⇒ dựng `AtomicLong` gắn với ô đó, không gọi lại hàm tạo của nguồn.
          var table = null;
          function properties() {
            if (table) { return table; }
            var local = {};
            function lookup(k) {
              k = String(k);
              if (Object.prototype.hasOwnProperty.call(local, k)) { return local[k]; }
              if (num(cell(['peek', k])) === null) { return undefined; }
              var atomic = new AtomicLong(0);
              L.defineHidden(atomic, '__lgCell', k);
              local[k] = atomic;
              return atomic;
            }
            function orNull(v) { return v === undefined ? null : v; }
            table = {
              get: function (k) { return orNull(lookup(k)); },
              containsKey: function (k) { var v = lookup(k); return v !== undefined && v !== null; },
              put: function (k, v) { var old = lookup(k); local[String(k)] = bindShared(String(k), v, true); return orNull(old); },
              putIfAbsent: function (k, v) {
                var old = lookup(k);
                if (old !== undefined && old !== null) { return old; }
                table.put(k, v);
                return null;
              },
              computeIfAbsent: function (k, fn) {
                var old = lookup(k);
                if (old !== undefined && old !== null) { return old; }
                var made = typeof fn === 'function' ? fn(k) : (fn && typeof fn.apply === 'function' ? fn.apply(k) : null);
                if (made === undefined || made === null) { return null; }
                local[String(k)] = bindShared(String(k), made, false);
                return local[String(k)];
              },
              remove: function (k) { var old = lookup(k); delete local[String(k)]; return orNull(old); },
              getProperty: function (k, def) {
                var v = lookup(k);
                return v === undefined || v === null ? (def === undefined ? null : def) : String(v);
              },
              setProperty: function (k, v) { var old = table.put(k, v == null ? null : String(v)); return old === null ? null : String(old); },
              keySet: function () { return L.list(Object.keys(local)); },
              size: function () { return Object.keys(local).length; },
              isEmpty: function () { return Object.keys(local).length === 0; }
            };
            return table;
          }

          L.system = {
            nanoTime: function () { return Number(call('nanoTime', [])); },
            getProperties: properties,
            getProperty: function (k, def) { return properties().getProperty(k, def); },
            setProperty: function (k, v) { return properties().setProperty(k, v); },
            clearProperty: function (k) { var old = properties().remove(k); return old === null ? null : String(old); },
            lineSeparator: function () { return '\n'; }
          };

          // `parkNanos([blocker,] nanos)` / `parkUntil([blocker,] mốc ms)` ⇒ lệnh `sleep` (giới hạn 5 giây, huỷ được).
          register('java.util.concurrent.locks.LockSupport', {
            parkNanos: function (a, b) { var n = Number(b === undefined ? a : b); if (n > 0) { call('sleep', [n / 1e6]); } },
            parkUntil: function (a, b) { var ms = Number(b === undefined ? a : b) - Date.now(); if (ms > 0) { call('sleep', [ms]); } },
            park: function () {},
            unpark: function () {}
          });
        })(this);
        """#
}
