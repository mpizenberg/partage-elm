// Transform push notification body using translations stored in IndexedDB.
// The Elm app saves a { key: translatedTemplate, ... } map to the "identity"
// store under the "notificationTranslations" key each time the language changes.
// Template data (key, name, etc.) is carried in n.data alongside the url field.
// The body already contains a readable English fallback, which is replaced
// with the localized version if translations are available.
// eslint-disable-next-line no-unused-vars
var SW_TRANSFORM_NOTIFICATION = async function (n) {
  if (!n.data || !n.data.key) return n;
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
    if (translations && translations[n.data.key]) {
      var body = translations[n.data.key];
      Object.keys(n.data).forEach(function (k) {
        if (k !== "key" && k !== "url")
          body = body.replaceAll("{" + k + "}", n.data[k]);
      });
      n.body = body;
    }
  } catch (e) {
    // Transform failed, keep the English fallback body
  }
  return n;
};
