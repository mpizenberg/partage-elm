import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import changelog from "./marketing/changelog.mjs";
import home from "./marketing/home.mjs";

const marketingCss = readFileSync("public/marketing.css", "utf8");
const origin = "__CANONICAL_ORIGIN__";
const fundingUrl = "https://github.com/sponsors/mpizenberg";
const sourceUrl = "https://github.com/mpizenberg/partage-elm";

const pages = [home, changelog];

const languages = {
  en: { flag: "🇬🇧", name: "English" },
  fr: { flag: "🇫🇷", name: "Français" },
};

// Feather icon shapes (MIT), inlined so the pages carry no icon runtime.
// Same set the app uses through elm-feather.
const icons = {
  "lock":
    '<rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>',
  "key":
    '<path d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0l3 3L22 7l-3-3m-3.5 3.5L19 4"/>',
  "wifi-off":
    '<line x1="1" y1="1" x2="23" y2="23"/><path d="M16.72 11.06A10.94 10.94 0 0 1 19 12.55"/><path d="M5 12.55a10.94 10.94 0 0 1 5.17-2.39"/><path d="M10.71 5.05A16 16 0 0 1 22.58 9"/><path d="M1.42 9a15.91 15.91 0 0 1 4.7-2.88"/><path d="M8.53 16.11a6 6 0 0 1 6.95 0"/><line x1="12" y1="20" x2="12.01" y2="20"/>',
  "git-merge":
    '<circle cx="18" cy="18" r="3"/><circle cx="6" cy="6" r="3"/><path d="M6 21V9a9 9 0 0 0 9 9"/>',
  "globe":
    '<circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/>',
  "clock": '<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>',
  "smartphone":
    '<rect x="5" y="2" width="14" height="20" rx="2" ry="2"/><line x1="12" y1="18" x2="12.01" y2="18"/>',
  "heart":
    '<path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"/>',
  "filter": '<polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3"/>',
  "download":
    '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/>',
  "credit-card":
    '<rect x="1" y="4" width="22" height="16" rx="2" ry="2"/><line x1="1" y1="10" x2="23" y2="10"/>',
  "users":
    '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
  "trending-up": '<polyline points="23 6 13.5 15.5 8.5 10.5 1 18"/><polyline points="17 6 23 6 23 12"/>',
  "rotate-ccw": '<polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10"/>',
  "user-check":
    '<path d="M16 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="8.5" cy="7" r="4"/><polyline points="17 11 19 13 23 9"/>',
  "github":
    '<path d="M9 19c-5 1.5-5-2.5-7-3m14 6v-3.87a3.37 3.37 0 0 0-.94-2.61c3.14-.35 6.44-1.54 6.44-7A5.44 5.44 0 0 0 20 4.77 5.07 5.07 0 0 0 19.91 1S18.73.65 16 2.48a13.38 13.38 0 0 0-7 0C6.27.65 5.09 1 5.09 1A5.07 5.07 0 0 0 5 4.77a5.44 5.44 0 0 0-1.5 3.78c0 5.42 3.3 6.61 6.44 7A3.37 3.37 0 0 0 9 18.13V22"/>',
  "home":
    '<path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/>',
  "info":
    '<circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/>',
  "message-square": '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>',
  "gift":
    '<polyline points="20 12 20 22 4 22 4 12"/><rect x="2" y="7" width="20" height="5"/><line x1="12" y1="22" x2="12" y2="7"/><path d="M12 7H7.5a2.5 2.5 0 0 1 0-5C11 2 12 7 12 7z"/><path d="M12 7h4.5a2.5 2.5 0 0 0 0-5C13 2 12 7 12 7z"/>',
};

function featherIcon(name) {
  const shape = icons[name];
  if (!shape) throw new Error(`unknown icon: ${name}`);
  return `<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${shape}</svg>`;
}

function pagePath(page, language) {
  return "/" + [language, page.slug[language]].filter(Boolean).join("/") + "/";
}

function list(items) {
  return items.map(([icon, label]) => `                    <li>${featherIcon(icon)}${label}</li>`).join("\n");
}

function screenshots(items) {
  return items
    .map(
      ([src, caption]) => `                    <figure>
                        <img src="/${src}" width="280" height="623" loading="lazy" alt="${caption}" />
                        <figcaption>${caption}</figcaption>
                    </figure>`,
    )
    .join("\n");
}

function escapeHtml(text) {
  return text
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

// x-default belongs to the language-negotiating URL, so only pages declaring
// one carry it; pointing it at English instead would claim English is the
// right answer for every unmatched reader.
function head(page, language) {
  const { title, description } = page[language];
  const alternates = Object.keys(page.slug)
    .map(
      (alternate) =>
        `        <link rel="alternate" hreflang="${alternate}" href="${origin}${pagePath(page, alternate)}" />`,
    )
    .concat(
      page.negotiate
        ? [`        <link rel="alternate" hreflang="x-default" href="${origin}${page.negotiate}" />`]
        : [],
    );
  return `    <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <meta name="theme-color" content="#E8725C" />
        <title>${title}</title>
        <meta name="description" content="${description}" />
        <link rel="canonical" href="${origin}${pagePath(page, language)}" />
${alternates.join("\n")}
        <meta property="og:type" content="website" />
        <meta property="og:title" content="${title}" />
        <meta property="og:description" content="${description}" />
        <meta property="og:image" content="${origin}/icon-512.png" />
        <meta property="og:url" content="${origin}${pagePath(page, language)}" />
        <meta name="twitter:card" content="summary" />
        <meta name="twitter:title" content="${title}" />
        <meta name="twitter:description" content="${description}" />
        <meta name="twitter:image" content="${origin}/icon-512.png" />
        <link rel="icon" href="/favicon.svg" type="image/svg+xml" />
        <style>
${marketingCss}
        </style>
    </head>`;
}

function languageNav(page, current) {
  const links = Object.keys(page.slug).map(
    (language) =>
      `<a href="${pagePath(page, language)}"${language === current ? ' aria-current="page"' : ""}>` +
      `<span aria-hidden="true">${languages[language].flag}</span> ${languages[language].name}</a>`,
  );
  return `<nav class="languages" aria-label="Language · Langue">
                    ${links.join("\n                    ·\n                    ")}
                </nav>`;
}

function renderHome(page, language) {
  const text = page[language];
  return `<!doctype html>
<html lang="${language}">
${head(page, language)}
    <body>
        <main class="page">
            <header class="hero">
                <img class="logo" src="/icon.svg" width="96" height="96" alt="" />
                <h1>${text.heading}</h1>
                <p class="tagline">${text.tagline}</p>
                <a class="button" href="/groups">${text.open}</a>
                ${languageNav(page, language)}
            </header>
            <section aria-labelledby="why">
                <h2 id="why">${text.whyTitle}</h2>
                <div class="card"><p>${text.whyBody}</p></div>
            </section>
            <section aria-labelledby="features">
                <h2 id="features">${text.featuresTitle}</h2>
                <ul class="feature-list">
${list(text.features)}
                </ul>
            </section>
            <section aria-labelledby="screenshots">
                <h2 id="screenshots">${text.screenshotsTitle}</h2>
                <div class="screenshots">
${screenshots(text.screenshots)}
                </div>
            </section>
            <section aria-labelledby="details">
                <h2 id="details">${text.detailsTitle}</h2>
                <ul class="feature-list">
${list(text.details)}
                </ul>
            </section>
            <section aria-labelledby="how">
                <h2 id="how">${text.howTitle}</h2>
                <div class="card"><p>${text.howBody}</p></div>
            </section>
            <section class="card support" aria-labelledby="funding">
                <h2 id="funding">${text.fundingTitle}</h2>
                <p>${text.fundingBody}</p>
                <a class="button" href="${fundingUrl}" rel="noreferrer">${featherIcon("heart")}${text.fundingCta}</a>
            </section>
            <footer>
                <a href="/${language}/changelog/">${featherIcon("gift")}${text.whatsNew}</a>
                ·
                <a href="/about">${featherIcon("info")}${text.about}</a>
                ·
                <a href="${sourceUrl}" rel="noreferrer">${featherIcon("github")}${text.source}</a>
                <span class="feedback" data-feedback-project="__FEEDBACK_PROJECT_ID__" hidden>
                    <button type="button">${featherIcon("message-square")}${text.feedback}</button>
                </span>
            </footer>
        </main>
        <script src="/marketing.js" defer></script>
    </body>
</html>
`;
}

function entryArticles(entries, language) {
  const label = new Intl.DateTimeFormat(language, { dateStyle: "long", timeZone: "UTC" });
  return entries
    .map(
      (entry) => `                <article class="entry" id="${entry.date}">
                    <h2>${escapeHtml(entry[language].title)}</h2>
                    <p><time datetime="${entry.date}">${label.format(new Date(entry.date))}</time></p>
                    <p>${escapeHtml(entry[language].body)}</p>
                </article>`,
    )
    .join("\n");
}

function renderChangelog(page, language) {
  const text = page[language];
  return `<!doctype html>
<html lang="${language}">
${head(page, language)}
    <body>
        <main class="page">
            <header class="hero">
                <img class="logo" src="/icon.svg" width="96" height="96" alt="" />
                <h1>${text.heading}</h1>
                <p class="tagline">${text.tagline}</p>
                <a class="button" href="/groups">${text.open}</a>
                ${languageNav(page, language)}
            </header>
            <section class="card support" data-feedback-project="__FEEDBACK_PROJECT_ID__" hidden>
                <h2>${text.suggestTitle}</h2>
                <button type="button" class="button">${text.suggestButton}</button>
            </section>
            <section class="entries">
${entryArticles(page.entries, language)}
            </section>
            <footer>
                <a href="/${language}/">${featherIcon("home")}${text.home}</a>
                ·
                <a href="${sourceUrl}" rel="noreferrer">${featherIcon("github")}${text.source}</a>
            </footer>
        </main>
        <script src="/marketing.js" defer></script>
    </body>
</html>
`;
}

const templates = { home: renderHome, changelog: renderChangelog };

function sitemap() {
  const url = (path, lastmod) =>
    ["  <url>", `    <loc>${origin}${path}</loc>`]
      .concat(lastmod ? [`    <lastmod>${lastmod}</lastmod>`] : [])
      .concat(["  </url>"])
      .join("\n");
  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${pages
  .flatMap((page) => Object.keys(page.slug).map((language) => url(pagePath(page, language), page.lastmod)))
  .join("\n")}
</urlset>
`;
}

// The relay registers its static routes from this manifest at startup, so the
// routes, the sitemap, and the files all derive from the same value and
// cannot disagree.
const manifest = {
  pages: pages.map((page) => ({
    id: page.id,
    ...(page.negotiate && { negotiate: page.negotiate }),
    paths: Object.fromEntries(
      Object.keys(page.slug).map((language) => [language, pagePath(page, language)]),
    ),
  })),
};

// The app only needs the newest entry's date to raise its "what's new"
// banner; the entries themselves live on the static pages. Rewriting the
// module only when the date moves keeps watch builds from recompiling Elm on
// every page render.
const latestModule = `module Changelog.Latest exposing (date)

{-| Generated from changelog.json by build-marketing.mjs. Do not edit.
-}


{-| The date of the newest public changelog entry.
-}
date : String
date =
    "${changelog.entries[0].date}"
`;
if (!existsSync("src/Changelog/Latest.elm") || readFileSync("src/Changelog/Latest.elm", "utf8") !== latestModule) {
  mkdirSync("src/Changelog", { recursive: true });
  writeFileSync("src/Changelog/Latest.elm", latestModule);
}

for (const page of pages) {
  for (const language of Object.keys(page.slug)) {
    mkdirSync(`dist${pagePath(page, language)}`, { recursive: true });
    writeFileSync(`dist${pagePath(page, language)}index.html`, templates[page.template](page, language));
  }
}
writeFileSync("dist/sitemap.xml", sitemap());
writeFileSync("dist/pages.json", JSON.stringify(manifest, null, 2) + "\n");
