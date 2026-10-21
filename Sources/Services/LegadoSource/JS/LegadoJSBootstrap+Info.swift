import Foundation

extension LegadoJSBootstrap {
    /// `infoMap` của khám phá động (spec §11.3): Proxy đọc/ghi thẳng kho `infoMap` của nguồn qua native, nên mọi đoạn JS
    /// lồng nhau (`exploreUrl`, `action`, hàm `jsLib`) thấy cùng giá trị. Ngoài ngữ cảnh khám phá native trả rỗng và bỏ qua
    /// lệnh ghi ⇒ "map rỗng chỉ đọc". Hỗ trợ `infoMap[k]`, `infoMap.get(k)`, `infoMap[k] = v`, `infoMap.put(k, v)`,
    /// `infoMap.save()`, `Object.keys(infoMap)`, `JSON.stringify(infoMap)`.
    static let info = #"""
        (function (g) {
          var L = g.__lg, call = L.call, callJSON = L.callJSON;
          L.infoMap = function () {
            var methods = {
              get: function (k) { var v = callJSON('infoGet', [String(k)]); return v === null ? null : v; },
              put: function (k, v) { call('infoSet', [String(k), v == null ? null : String(v)]); return v; },
              remove: function (k) { call('infoSet', [String(k), null]); },
              containsKey: function (k) { return callJSON('infoGet', [String(k)]) !== null; },
              save: function () {},
              keySet: function () { return L.list(callJSON('infoKeys', []) || []); },
              size: function () { return (callJSON('infoKeys', []) || []).length; },
              isEmpty: function () { return (callJSON('infoKeys', []) || []).length === 0; },
              toJSON: function () { return callJSON('infoAll', []) || {}; },
              toString: function () { return JSON.stringify(callJSON('infoAll', []) || {}); }
            };
            return new Proxy({}, {
              get: function (t, k) {
                if (typeof k !== 'string') { return undefined; }
                if (Object.prototype.hasOwnProperty.call(methods, k)) { return methods[k]; }
                var v = callJSON('infoGet', [k]);
                return v === null ? undefined : v;
              },
              set: function (t, k, v) {
                if (typeof k === 'string') { call('infoSet', [k, v == null ? null : String(v)]); }
                return true;
              },
              has: function (t, k) { return typeof k === 'string' && callJSON('infoGet', [k]) !== null; },
              deleteProperty: function (t, k) {
                if (typeof k === 'string') { call('infoSet', [k, null]); }
                return true;
              },
              ownKeys: function () { return callJSON('infoKeys', []) || []; },
              getOwnPropertyDescriptor: function (t, k) {
                var v = typeof k === 'string' ? callJSON('infoGet', [k]) : null;
                return v === null ? undefined : { value: v, writable: true, enumerable: true, configurable: true };
              }
            });
          };
        })(this);
        """#
}
