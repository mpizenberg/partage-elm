var languages = navigator.languages || [navigator.language || "en"];
var language = languages.find(function (candidate) {
  return /^(en|fr)(-|$)/i.test(candidate);
});
location.replace(/^fr(-|$)/i.test(language || "") ? "/fr/" : "/en/");
