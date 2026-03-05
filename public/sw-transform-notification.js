// Transform push notification body using translations stored in IndexedDB.
// The Elm app saves a { key: translatedTemplate, ... } map to the "identity"
// store under the "notificationTranslations" key each time the language changes.
// The notification body is expected to be a JSON string like:
//   {"key":"expense_added","name":"Alice"}
// This function looks up the template for "key", substitutes {param} placeholders
// with the remaining fields, and returns the modified notification object.
// eslint-disable-next-line no-unused-vars
var SW_TRANSFORM_NOTIFICATION = async function (n) {
  if (!n.body) return n;
  var msg;
  try {
    msg = JSON.parse(n.body);
  } catch (e) {
    return n; // Not JSON, use body as-is
  }
  if (!msg.key) return n;
  try {
    var db = await new Promise(function (resolve, reject) {
      var req = indexedDB.open("partage");
      req.onsuccess = function () {
        resolve(req.result);
      };
      req.onerror = function () {
        reject(req.error);
      };
    });
    var tx = db.transaction("identity", "readonly");
    var store = tx.objectStore("identity");
    var translations = await new Promise(function (resolve, reject) {
      var req = store.get("notificationTranslations");
      req.onsuccess = function () {
        resolve(req.result);
      };
      req.onerror = function () {
        reject(req.error);
      };
    });
    db.close();
    if (translations && translations[msg.key]) {
      var body = translations[msg.key];
      Object.keys(msg).forEach(function (k) {
        if (k !== "key") body = body.replaceAll("{" + k + "}", msg[k]);
      });
      n.body = body;
    } else {
      n.body = msg.key;
    }
  } catch (e) {
    n.body = msg.key;
  }
  return n;
};
