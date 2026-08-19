// Decrypt and localize push notifications.
//
// The wire payload is constant apart from an AES-256-GCM blob in
// n.data.{iv,ct}, encrypted with a group key. The plaintext carries the group
// name (t), a phrase key (k), its parameters (p, actor included), an optional
// amount (a: {v, sym, prec}), the recipient's own share of it (s, same
// shape), an optional count of further events in the batch (n) and the
// target url (u). The Elm app stores a bundle in IndexedDB
// (identity/notificationTranslations) holding phrase templates (t) and the
// locale's number formatting (n: {decimal, group, pos}), so all wording, word
// order and locale knowledge stays in Elm and the Fluent files; this code
// only substitutes and formats.
//
// Trial-decrypts against every stored group key (a device holds few). Any
// failure keeps the constant cleartext fallback, and the whole transform is
// bounded by a timeout so a stalled IndexedDB read degrades to that fallback
// instead of showing nothing.
// eslint-disable-next-line no-unused-vars
var SW_TRANSFORM_NOTIFICATION = (function () {
  function fromBase64(base64) {
    return Uint8Array.from(atob(base64), function (c) {
      return c.charCodeAt(0);
    });
  }

  function request(req) {
    return new Promise(function (resolve, reject) {
      req.onsuccess = function () {
        resolve(req.result);
      };
      req.onerror = function () {
        reject(req.error);
      };
    });
  }

  async function readStores() {
    var db = await request(indexedDB.open("partage"));
    try {
      var tx = db.transaction(["identity", "groupKeys"], "readonly");
      var keyStore = tx.objectStore("groupKeys");
      var bundleReq = request(tx.objectStore("identity").get("notificationTranslations"));
      var idsReq = request(keyStore.getAllKeys());
      var keysReq = request(keyStore.getAll());
      var bundle = await bundleReq;
      var groupIds = await idsReq;
      var groupKeys = await keysReq;
      return { bundle: bundle, groupIds: groupIds, groupKeys: groupKeys };
    } finally {
      db.close();
    }
  }

  // Record that a group has unseen activity, for the home screen's markers:
  // keyed by group id when the payload decrypted, by the raw topic otherwise.
  // Best-effort — the store only exists once the app has opened on a schema
  // that defines it, and a failed write costs a marker, not the notification.
  async function writeMarker(key) {
    if (!key) return;
    var db = await request(indexedDB.open("partage"));
    try {
      if (!db.objectStoreNames.contains("activityMarkers")) return;
      var tx = db.transaction("activityMarkers", "readwrite");
      tx.objectStore("activityMarkers").put(true, key);
      await new Promise(function (resolve, reject) {
        tx.oncomplete = resolve;
        tx.onerror = function () {
          reject(tx.error);
        };
      });
    } finally {
      db.close();
    }
  }

  async function decryptPayload(stores, data) {
    var iv = fromBase64(data.iv);
    var ct = fromBase64(data.ct);
    for (var i = 0; i < stores.groupKeys.length; i++) {
      try {
        var key = await crypto.subtle.importKey(
          "raw",
          fromBase64(stores.groupKeys[i]),
          { name: "AES-GCM" },
          false,
          ["decrypt"],
        );
        var buf = await crypto.subtle.decrypt({ name: "AES-GCM", iv: iv }, key, ct);
        return {
          plain: JSON.parse(new TextDecoder().decode(buf)),
          groupId: stores.groupIds[i],
        };
      } catch (e) {
        // Wrong key or corrupted blob: try the next group.
      }
    }
    return null;
  }

  function fill(template, params) {
    return Object.keys(params).reduce(function (acc, name) {
      return acc.replaceAll("{" + name + "}", params[name]);
    }, template);
  }

  // Mirrors Elm's Format.formatCentsWithCurrency with the locale config
  // shipped in the bundle: a {v, sym, prec} amount to a localized string.
  function formatAmount(a, num) {
    var sign = a.v < 0 ? "-" : "";
    var digits = String(Math.abs(a.v));
    var whole = digits;
    var frac = "";
    if (a.prec > 0) {
      digits = digits.padStart(a.prec + 1, "0");
      whole = digits.slice(0, -a.prec);
      frac = num.decimal + digits.slice(-a.prec);
    }
    var grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, num.group);
    if (num.pos === "suffix") {
      return sign + grouped + frac + "\u00a0" + a.sym;
    }
    return sign + a.sym + grouped + frac;
  }

  function composeBody(plain, bundle) {
    var t = bundle.t || {};
    var template = t[plain.k];
    var body;
    if (template) {
      var phrase = fill(template, plain.p || {});
      if (plain.a && bundle.n) {
        phrase = fill(t.activityAmountSuffix || "{text} ({amount})", {
          text: phrase,
          amount: formatAmount(plain.a, bundle.n),
        });
      }
      body = fill(t.notificationLine || "{actor} {phrase}", {
        actor: (plain.p && plain.p.actor) || "",
        phrase: phrase,
      });
    } else {
      // A phrase this bundle does not know (newer sender): generic body.
      body = t.notificationGeneric;
    }
    if (!body) return null;
    if (plain.n > 0) body = body + " +" + plain.n;
    if (body.length > 120) body = body.slice(0, 119) + "…";
    if (plain.s && bundle.n && t.notificationYourShare) {
      body += "\n" + fill(t.notificationYourShare, { amount: formatAmount(plain.s, bundle.n) });
    }
    return body;
  }

  async function transform(n) {
    var stores = await readStores();
    var decrypted = await decryptPayload(stores, n.data);
    try {
      await writeMarker(decrypted ? decrypted.groupId : n.tag);
    } catch (e) {
      // Marker write failed; the notification itself still shows.
    }
    if (!decrypted) return null;
    var plain = decrypted.plain;
    n.title = plain.t || n.title;
    var body = stores.bundle ? composeBody(plain, stores.bundle) : null;
    if (body) n.body = body;
    n.data.url = plain.u || "/";
    return n;
  }

  return async function (n) {
    if (!n.data || !n.data.ct || !n.data.iv) return n;
    var attempt = transform(n).catch(function () {
      return null;
    });
    var timeout = new Promise(function (resolve) {
      setTimeout(resolve, 3000, null);
    });
    var result = await Promise.race([attempt, timeout]);
    return result || n;
  };
})();
