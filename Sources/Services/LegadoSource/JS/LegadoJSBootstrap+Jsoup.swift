import Foundation

extension LegadoJSBootstrap {
    /// Shim `org.jsoup` trên SwiftSoup (spec §6.8). Phần tử là đối tượng JS giữ handle số nguyên (registry của runtime);
    /// danh sách phần tử là mảng JS có thêm phương thức kiểu `Elements` (`size`, `get`, `text`, `select`…).
    static let jsoup = #"""
        (function (g) {
          var L = g.__lg, call = L.call, callJSON = L.callJSON;
          function JsoupElement(id) { L.defineHidden(this, '__lgEl', id); }
          function wrap(id) { return (id === null || id === undefined || id < 0) ? null : new JsoupElement(id); }
          function wrapList(ids) { return L.list((ids || []).map(function (id) { return new JsoupElement(id); })); }
          function idOf(el) { return el.__lgEl; }
          var P = JsoupElement.prototype;
          P.select = function (css) { return wrapList(callJSON('el.select', [idOf(this), String(css)])); };
          P.selectFirst = function (css) { var l = this.select(css); return l.length ? l[0] : null; };
          P.text = function () { return call('el.text', [idOf(this)]); };
          P.ownText = function () { return call('el.ownText', [idOf(this)]); };
          P.wholeText = function () { return call('el.wholeText', [idOf(this)]); };
          P.html = function () { return call('el.html', [idOf(this)]); };
          P.outerHtml = function () { return call('el.outerHtml', [idOf(this)]); };
          P.data = function () { return call('el.data', [idOf(this)]); };
          P.val = function () { return call('el.val', [idOf(this)]); };
          P.attr = function (k, v) {
            if (arguments.length > 1) { call('el.setAttr', [idOf(this), String(k), v == null ? '' : String(v)]); return this; }
            return call('el.attr', [idOf(this), String(k)]);
          };
          P.hasAttr = function (k) { return call('el.hasAttr', [idOf(this), String(k)]) === '1'; };
          P.absUrl = function (k) { return call('el.absUrl', [idOf(this), String(k)]); };
          P.hasClass = function (c) { return call('el.hasClass', [idOf(this), String(c)]) === '1'; };
          P.id = function () { return call('el.id', [idOf(this)]); };
          P.className = function () { return call('el.className', [idOf(this)]); };
          P.tagName = function () { return call('el.tagName', [idOf(this)]); };
          P.nodeName = P.tagName;
          P.children = function () { return wrapList(callJSON('el.children', [idOf(this)])); };
          P.child = function (i) { return wrap(callJSON('el.child', [idOf(this), Number(i)])); };
          P.parent = function () { return wrap(callJSON('el.parent', [idOf(this)])); };
          P.nextElementSibling = function () { return wrap(callJSON('el.next', [idOf(this)])); };
          P.previousElementSibling = function () { return wrap(callJSON('el.prev', [idOf(this)])); };
          P.getElementById = function (id) { return wrap(callJSON('el.byId', [idOf(this), String(id)])); };
          P.getElementsByTag = function (t) { return wrapList(callJSON('el.byTag', [idOf(this), String(t)])); };
          P.getElementsByClass = function (c) { return wrapList(callJSON('el.byClass', [idOf(this), String(c)])); };
          P.remove = function () { call('el.remove', [idOf(this)]); };
          P.body = function () { return wrap(callJSON('el.body', [idOf(this)])); };
          P.head = function () { return wrap(callJSON('el.head', [idOf(this)])); };
          P.title = function () { return call('el.title', [idOf(this)]); };
          P.toString = function () { return this.outerHtml(); };
          P.toJSON = function () { return this.outerHtml(); };
          L.wrapElement = wrap;

          var Jsoup = {
            parse: function (html, baseUri) {
              return wrap(callJSON('jsoup.parse', [html == null ? '' : String(html), baseUri == null ? '' : String(baseUri)]));
            },
            parseBodyFragment: function (html, baseUri) {
              return wrap(callJSON('jsoup.fragment', [html == null ? '' : String(html), baseUri == null ? '' : String(baseUri)]));
            },
            connect: L.unsupported('org.jsoup.Jsoup.connect')
          };
          L.defineHidden(g, '__lgJsoup', Jsoup);
        })(this);
        """#
}
