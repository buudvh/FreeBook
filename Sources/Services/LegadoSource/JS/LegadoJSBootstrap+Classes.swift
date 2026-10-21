import Foundation

extension LegadoJSBootstrap {
    /// Lớp Java giả lập đợt 2/3 (spec §13.10, §14.3, §6.9, §10.7), đăng ký vào `__lg.classes` theo tên đầy đủ để
    /// `Packages.*`, `JavaImporter`, `importPackage`/`importClass` (script `packages`, nạp sau) tìm thấy:
    /// `javax.crypto.Cipher`/`Mac`/`spec.*`, `java.security.MessageDigest`/`KeyFactory`/`Signature`/`spec.*`,
    /// `java.io.ByteArray{Output,Input}Stream`, `java.util.HashMap`/`ArrayList`/`Arrays`, hàm dựng `StrResponse` của
    /// ngữ cảnh đăng nhập. Mảng byte là `Uint8Array` không dấu (U56).
    static let classes = #"""
        (function (g) {
          var L = g.__lg, call = L.call;
          L.classes = L.classes || {};
          function register(full, cls) { L.defineHidden(cls, '__lgName', full.split('.').pop()); L.classes[full] = cls; return cls; }
          function toBytes(v) {
            if (v === undefined || v === null) { return new Uint8Array(0); }
            if (v instanceof Uint8Array) { return v; }
            if (v instanceof Int8Array || Array.isArray(v)) { return Uint8Array.from(v, function (x) { return x & 0xff; }); }
            return L.hexToBytes(call('strToBytes', [String(v), 'UTF-8']));
          }
          function concat(chunks) {
            var n = 0; chunks.forEach(function (c) { n += c.length; });
            var out = new Uint8Array(n), p = 0;
            chunks.forEach(function (c) { out.set(c, p); p += c.length; });
            return out;
          }
          function keyBytes(k) {
            if (k === undefined || k === null) { return null; }
            if (k.__lgKeyBytes !== undefined) { return k.__lgKeyBytes; }
            if (typeof k.getEncoded === 'function') { return toBytes(k.getEncoded()); }
            return k;
          }

          // javax.crypto.spec / java.security.spec
          function SecretKeySpec(bytes, algorithm) {
            var key = toBytes(bytes);
            L.defineHidden(this, '__lgKeyBytes', key);
            this.getEncoded = function () { return key; };
            this.getAlgorithm = function () { return String(algorithm || ''); };
          }
          function IvParameterSpec(bytes) { var iv = toBytes(bytes); this.getIV = function () { return iv; }; L.defineHidden(this, '__lgIv', iv); }
          function GCMParameterSpec(tagBits, iv) {
            var nonce = toBytes(iv); this.getIV = function () { return nonce; }; this.getTLen = function () { return Number(tagBits); };
            L.defineHidden(this, '__lgIv', nonce); L.defineHidden(this, '__lgTagBits', Number(tagBits));
          }
          function EncodedKeySpec(kind) {
            return function (bytes) { var b = toBytes(bytes); L.defineHidden(this, '__lgKeyBytes', b); L.defineHidden(this, '__lgKind', kind); this.getEncoded = function () { return b; }; };
          }
          register('javax.crypto.spec.SecretKeySpec', SecretKeySpec);
          register('javax.crypto.spec.IvParameterSpec', IvParameterSpec);
          register('javax.crypto.spec.GCMParameterSpec', GCMParameterSpec);
          register('java.security.spec.X509EncodedKeySpec', EncodedKeySpec('public'));
          register('java.security.spec.PKCS8EncodedKeySpec', EncodedKeySpec('private'));

          function rsaKey(kind, bytes) {
            var k = { getEncoded: function () { return bytes; }, getAlgorithm: function () { return 'RSA'; }, getFormat: function () { return kind === 'public' ? 'X.509' : 'PKCS#8'; } };
            L.defineHidden(k, '__lgKeyBytes', bytes); L.defineHidden(k, '__lgRsaKind', kind);
            return k;
          }
          register('java.security.KeyFactory', {
            getInstance: function () {
              return {
                generatePublic: function (spec) { return rsaKey('public', keyBytes(spec)); },
                generatePrivate: function (spec) { return rsaKey('private', keyBytes(spec)); }
              };
            }
          });

          // javax.crypto.Cipher (§13.10): AES/DES/DESede qua lõi đối xứng, AES-GCM, RSA (§14.3).
          function Cipher(t) { this.t = t; this.mode = 1; this.key = null; this.spec = null; this.chunks = []; }
          Cipher.ENCRYPT_MODE = 1; Cipher.DECRYPT_MODE = 2;
          Cipher.getInstance = function (t) { return new Cipher(String(t)); };
          Cipher.prototype.init = function (mode, key, spec) { this.mode = Number(mode); this.key = key; this.spec = spec || null; this.chunks = []; };
          Cipher.prototype.update = function (b) { this.chunks.push(toBytes(b)); return new Uint8Array(0); };
          Cipher.prototype.getIV = function () { return this.spec && this.spec.__lgIv ? this.spec.__lgIv : null; };
          Cipher.prototype.getAlgorithm = function () { return this.t; };
          Cipher.prototype.doFinal = function (b) {
            if (b !== undefined && b !== null) { this.chunks.push(toBytes(b)); }
            var data = concat(this.chunks), op = this.mode === 2 ? 'dec' : 'enc';
            this.chunks = [];
            if (/^\s*rsa/i.test(this.t)) {
              var isPublic = !(this.key && this.key.__lgRsaKind === 'private');
              var kb = keyBytes(this.key);
              return L.hexToBytes(call('rsa', [op, this.t, isPublic ? kb : null, isPublic ? null : kb, isPublic, data, 'hex']));
            }
            var iv = this.spec && this.spec.__lgIv ? this.spec.__lgIv : null;
            if (this.spec && this.spec.__lgTagBits) {
              return L.hexToBytes(call('gcm', [op, keyBytes(this.key), iv, this.spec.__lgTagBits, data]));
            }
            return L.hexToBytes(call('sym', [op, this.t, keyBytes(this.key), iv, data, 'hex']));
          };
          register('javax.crypto.Cipher', Cipher);

          // javax.crypto.Mac, java.security.MessageDigest
          register('javax.crypto.Mac', {
            getInstance: function (alg) {
              var key = null, chunks = [];
              return {
                init: function (k) { key = keyBytes(k); chunks = []; },
                update: function (b) { chunks.push(toBytes(b)); },
                doFinal: function (b) {
                  if (b !== undefined && b !== null) { chunks.push(toBytes(b)); }
                  var data = concat(chunks); chunks = [];
                  return L.hexToBytes(call('hmac', [data, String(alg), key, 'hex']));
                },
                getAlgorithm: function () { return String(alg); }
              };
            }
          });
          register('java.security.MessageDigest', {
            getInstance: function (alg) {
              var chunks = [];
              return {
                update: function (b) { chunks.push(toBytes(b)); },
                digest: function (b) {
                  if (b !== undefined && b !== null) { chunks.push(toBytes(b)); }
                  var data = concat(chunks); chunks = [];
                  return L.hexToBytes(call('digest', [data, String(alg), 'hex']));
                },
                reset: function () { chunks = []; },
                getAlgorithm: function () { return String(alg); }
              };
            }
          });

          // RSA (§14.3): `java.createAsymmetricCrypto`, `java.createSign`, `java.security.Signature`.
          L.rsaCipher = function (t) {
            var pub = null, priv = null;
            function run(op, d, usePublic, out) {
              var data = (d instanceof Uint8Array || d instanceof Int8Array || Array.isArray(d)) ? toBytes(d) : String(d);
              return call('rsa', [op, t, pub, priv, usePublic === undefined ? true : !!usePublic, data, out]);
            }
            var o = {
              setPublicKey: function (k) { pub = keyBytes(k); return o; },
              setPrivateKey: function (k) { priv = keyBytes(k); return o; },
              decrypt: function (d, usePublic) { return L.hexToBytes(run('dec', d, usePublic, 'hex')); },
              decryptStr: function (d, usePublic) { return run('dec', d, usePublic, 'str'); },
              encrypt: function (d, usePublic) { return L.hexToBytes(run('enc', d, usePublic, 'hex')); },
              encryptBase64: function (d, usePublic) { return run('enc', d, usePublic, 'b64'); },
              encryptHex: function (d, usePublic) { return run('enc', d, usePublic, 'hex'); }
            };
            return o;
          };
          L.rsaSigner = function (alg) {
            var pub = null, priv = null;
            var o = {
              setPublicKey: function (k) { pub = keyBytes(k); return o; },
              setPrivateKey: function (k) { priv = keyBytes(k); return o; },
              sign: function (d) { return L.hexToBytes(call('rsaSign', [alg, priv, toBytes(d)])); },
              signHex: function (d) { return call('rsaSign', [alg, priv, toBytes(d)]); },
              verify: function (d, sig) { return call('rsaVerify', [alg, pub, toBytes(d), toBytes(sig)]) === '1'; }
            };
            return o;
          };
          register('java.security.Signature', {
            getInstance: function (alg) {
              var signer = L.rsaSigner(String(alg)), chunks = [];
              return {
                initSign: function (k) { signer.setPrivateKey(k); chunks = []; },
                initVerify: function (k) { signer.setPublicKey(k); chunks = []; },
                update: function (b) { chunks.push(toBytes(b)); },
                sign: function () { var d = concat(chunks); chunks = []; return signer.sign(d); },
                verify: function (sig) { var d = concat(chunks); chunks = []; return signer.verify(d, sig); }
              };
            }
          });

          // java.io (§6.9)
          function ByteArrayOutputStream() { this.buf = []; }
          ByteArrayOutputStream.prototype.write = function (b, off, len) {
            if (typeof b === 'number') { this.buf.push(b & 0xff); return; }
            var bytes = toBytes(b); off = off || 0; len = len === undefined ? bytes.length - off : len;
            for (var i = 0; i < len; i++) { this.buf.push(bytes[off + i] & 0xff); }
          };
          ByteArrayOutputStream.prototype.toByteArray = function () { return new Uint8Array(this.buf); };
          ByteArrayOutputStream.prototype.size = function () { return this.buf.length; };
          ByteArrayOutputStream.prototype.reset = function () { this.buf = []; };
          ByteArrayOutputStream.prototype.flush = function () {};
          ByteArrayOutputStream.prototype.close = function () {};
          ByteArrayOutputStream.prototype.toString = function (cs) {
            return call('bytesToStr', [new Uint8Array(this.buf), cs === undefined ? 'UTF-8' : String(cs)]);
          };
          register('java.io.ByteArrayOutputStream', ByteArrayOutputStream);
          register('java.io.ByteArrayInputStream', function (bytes) { return L.byteStream(Uint8Array.from(toBytes(bytes))); });

          // java.util tối thiểu
          register('java.util.HashMap', function () { return L.map({}); });
          register('java.util.LinkedHashMap', function () { return L.map({}); });
          register('java.util.ArrayList', function () { return L.list([]); });
          register('java.util.Arrays', {
            copyOfRange: function (a, from, to) { return Array.prototype.slice.call(a, from, to); },
            copyOf: function (a, n) { return Array.prototype.slice.call(a, 0, n); },
            asList: function () { return L.list(Array.prototype.slice.call(arguments)); },
            toString: function (a) { return '[' + Array.prototype.join.call(a, ', ') + ']'; }
          });

          // Phản hồi tự dựng trong loginCheckJs (§10.7, ngoại lệ duy nhất của lớp nội bộ ứng dụng gốc).
          register('io.legado.app.help.http.StrResponse', function (url, body) {
            return L.response({ url: url == null ? '' : String(url), code: 200, message: 'OK', headers: {}, cookies: {},
              body: body == null ? '' : String(body) });
          });
        })(this);
        """#
}
