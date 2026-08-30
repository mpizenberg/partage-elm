import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";

const marketingCss = readFileSync("public/marketing.css", "utf8");
const changelog = JSON.parse(readFileSync("changelog.json", "utf8"));
const origin = "__CANONICAL_ORIGIN__";
const fundingUrl = "https://github.com/sponsors/mpizenberg";
const sourceUrl = "https://github.com/mpizenberg/partage-elm";

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

const pages = {
  en: {
    flag: "🇬🇧",
    name: "English",
    title: "Partage — Private, local-first bill splitting",
    description:
      "Partage is a free, open-source bill-splitting app. End-to-end encrypted, works offline, no account needed.",
    heading: "Welcome to Partage",
    tagline: "Private, encrypted bill splitting that works offline — no account needed.",
    open: "Open Partage",
    whyTitle: "Why Partage",
    whyBody:
      "Splitting bills with friends should be simple, and stay between you and your friends. Partage is end-to-end encrypted, works offline, and syncs across devices when you want.",
    featuresTitle: "Features",
    features: [
      ["lock", "End-to-end encrypted"],
      ["key", "No account or password"],
      ["wifi-off", "Works offline, syncs when online"],
      ["git-merge", "Smart settle-up with fewer transactions"],
      ["globe", "Multiple currencies in one group"],
      ["clock", "Full activity and edit history"],
      ["smartphone", "Installable on any device"],
      ["heart", "Open source, no ads, no user tracking"],
    ],
    screenshotsTitle: "A look inside",
    screenshots: [
      ["screenshot-balance.webp", "Balances and smart settle-up"],
      ["screenshot-multicurrency.webp", "Add expenses in any currency"],
      ["screenshot-activity.webp", "Full activity log with edit history"],
      ["screenshot-invite.webp", "Invite by link or QR code"],
    ],
    detailsTitle: "Details that matter",
    details: [
      ["filter", "Filter by person, category, currency, or date"],
      ["download", "Free CSV export and complete JSON backup"],
      ["credit-card", "Payment hints for common payment methods"],
      ["users", "Virtual members, merging, and retirement without lost history"],
      ["trending-up", "Expenses, transfers, and income"],
      ["rotate-ccw", "Soft deletion with restore and field-level edit history"],
      ["user-check", "Per-member settle-up preferences"],
      ["gift", "No daily limits, caps, or ads"],
    ],
    howTitle: "How it works",
    howBody:
      "Your expenses stay on your device and are encrypted before syncing. Only group members with the shared key can read them. The relay never receives the key or decrypted content.",
    fundingTitle: "Open source and funding",
    fundingBody:
      "Partage is free, open source, and ad-free. Running the sync relay costs a few cents per active user each month. If Partage helps you, please consider supporting it.",
    fundingCta: "Support Partage",
    about: "App information and local usage",
    source: "Source code",
    feedback: "Send feedback",
    whatsNew: "What’s new",
    changelogTitle: "Partage changelog — What’s new",
    changelogDescription:
      "New features and improvements in Partage, the private, offline-capable bill-splitting app — updated with every release.",
    changelogTagline: "Every new feature and improvement, newest first.",
    suggestTitle: "What should we build next?",
    suggestButton: "Send an idea",
    home: "Home",
  },
  fr: {
    flag: "🇫🇷",
    name: "Français",
    title: "Partage — Partage de frais privé et local-first",
    description:
      "Partage est une application libre et gratuite de partage de frais. Chiffrée de bout en bout, hors-ligne et sans compte.",
    heading: "Bienvenue sur Partage",
    tagline: "Le partage de frais privé et chiffré qui fonctionne hors-ligne — sans compte.",
    open: "Ouvrir Partage",
    whyTitle: "Pourquoi Partage",
    whyBody:
      "Partager les frais entre amis doit rester simple, et entre vous. Partage est chiffré de bout en bout, fonctionne hors-ligne et se synchronise entre appareils quand vous le souhaitez.",
    featuresTitle: "Fonctionnalités",
    features: [
      ["lock", "Chiffrement de bout en bout"],
      ["key", "Sans compte ni mot de passe"],
      ["wifi-off", "Hors-ligne, synchronisé en ligne"],
      ["git-merge", "Remboursements optimisés"],
      ["globe", "Plusieurs devises dans un groupe"],
      ["clock", "Journal complet des modifications"],
      ["smartphone", "Installable sur tout appareil"],
      ["heart", "Open source, sans pub ni suivi individuel"],
    ],
    screenshotsTitle: "Aperçu de l’application",
    screenshots: [
      ["screenshot-balance.webp", "Soldes et remboursements optimisés"],
      ["screenshot-multicurrency.webp", "Ajouter une dépense dans n’importe quelle devise"],
      ["screenshot-activity.webp", "Journal complet avec historique des modifications"],
      ["screenshot-invite.webp", "Inviter par lien ou QR code"],
    ],
    detailsTitle: "Les détails qui comptent",
    details: [
      ["filter", "Filtrer par personne, catégorie, devise ou date"],
      ["download", "Export CSV gratuit et sauvegarde JSON complète"],
      ["credit-card", "Raccourcis pour les moyens de remboursement courants"],
      ["users", "Membres virtuels, fusion et retrait sans perte d’historique"],
      ["trending-up", "Dépenses, transferts et revenus"],
      ["rotate-ccw", "Suppression réversible et historique détaillé"],
      ["user-check", "Préférences de remboursement par membre"],
      ["gift", "Sans limite journalière, plafond ni publicité"],
    ],
    howTitle: "Comment ça marche",
    howBody:
      "Vos dépenses restent sur votre appareil et sont chiffrées avant synchronisation. Seuls les membres ayant la clé du groupe peuvent les lire. Le relais ne reçoit jamais la clé ni le contenu déchiffré.",
    fundingTitle: "Open source et financement",
    fundingBody:
      "Partage est gratuit, open source et sans publicité. Le relais de synchronisation coûte quelques centimes par utilisateur actif chaque mois. Si Partage vous aide, vous pouvez le soutenir.",
    fundingCta: "Soutenir Partage",
    about: "Informations sur l’app et usage local",
    source: "Code source",
    feedback: "Envoyer un retour",
    whatsNew: "Nouveautés",
    changelogTitle: "Changelog de Partage — Nouveautés",
    changelogDescription:
      "Nouvelles fonctionnalités et améliorations de Partage, l’application privée de partage de frais — mis à jour à chaque version.",
    changelogTagline: "Toutes les nouveautés et améliorations, les plus récentes en premier.",
    suggestTitle: "On construit quoi ensuite ?",
    suggestButton: "Proposer une idée",
    home: "Accueil",
  },
};

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

// The subPath distinguishes the localized homes ("") from deeper localized
// pages ("changelog/"); x-default points at the language-negotiating URL.
function head(language, subPath, { title, description }) {
  return `    <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <meta name="theme-color" content="#E8725C" />
        <title>${title}</title>
        <meta name="description" content="${description}" />
        <link rel="canonical" href="${origin}/${language}/${subPath}" />
        <link rel="alternate" hreflang="en" href="${origin}/en/${subPath}" />
        <link rel="alternate" hreflang="fr" href="${origin}/fr/${subPath}" />
        <link rel="alternate" hreflang="x-default" href="${origin}/${subPath.replace(/\/$/, "")}" />
        <meta property="og:type" content="website" />
        <meta property="og:title" content="${title}" />
        <meta property="og:description" content="${description}" />
        <meta property="og:image" content="${origin}/icon-512.png" />
        <meta property="og:url" content="${origin}/${language}/${subPath}" />
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

function languageNav(current, subPath) {
  const links = Object.entries(pages).map(
    ([language, page]) =>
      `<a href="/${language}/${subPath}"${language === current ? ' aria-current="page"' : ""}>` +
      `<span aria-hidden="true">${page.flag}</span> ${page.name}</a>`,
  );
  return `<nav class="languages" aria-label="Language · Langue">
                    ${links.join("\n                    ·\n                    ")}
                </nav>`;
}

function render(language, page) {
  return `<!doctype html>
<html lang="${language}">
${head(language, "", page)}
    <body>
        <main class="page">
            <header class="hero">
                <img class="logo" src="/icon.svg" width="96" height="96" alt="" />
                <h1>${page.heading}</h1>
                <p class="tagline">${page.tagline}</p>
                <a class="button" href="/groups">${page.open}</a>
                ${languageNav(language, "")}
            </header>
            <section aria-labelledby="why">
                <h2 id="why">${page.whyTitle}</h2>
                <div class="card"><p>${page.whyBody}</p></div>
            </section>
            <section aria-labelledby="features">
                <h2 id="features">${page.featuresTitle}</h2>
                <ul class="feature-list">
${list(page.features)}
                </ul>
            </section>
            <section aria-labelledby="screenshots">
                <h2 id="screenshots">${page.screenshotsTitle}</h2>
                <div class="screenshots">
${screenshots(page.screenshots)}
                </div>
            </section>
            <section aria-labelledby="details">
                <h2 id="details">${page.detailsTitle}</h2>
                <ul class="feature-list">
${list(page.details)}
                </ul>
            </section>
            <section aria-labelledby="how">
                <h2 id="how">${page.howTitle}</h2>
                <div class="card"><p>${page.howBody}</p></div>
            </section>
            <section class="card support" aria-labelledby="funding">
                <h2 id="funding">${page.fundingTitle}</h2>
                <p>${page.fundingBody}</p>
                <a class="button" href="${fundingUrl}" rel="noreferrer">${featherIcon("heart")}${page.fundingCta}</a>
            </section>
            <footer>
                <a href="/${language}/changelog/">${featherIcon("gift")}${page.whatsNew}</a>
                ·
                <a href="/about">${featherIcon("info")}${page.about}</a>
                ·
                <a href="${sourceUrl}" rel="noreferrer">${featherIcon("github")}${page.source}</a>
                <span class="feedback" data-feedback-project="__FEEDBACK_PROJECT_ID__" hidden>
                    <button type="button">${featherIcon("message-square")}${page.feedback}</button>
                </span>
            </footer>
        </main>
        <script src="/marketing.js" defer></script>
    </body>
</html>
`;
}

function entryArticles(language) {
  const label = new Intl.DateTimeFormat(language, { dateStyle: "long", timeZone: "UTC" });
  return changelog
    .map(
      (entry) => `                <article class="entry" id="${entry.date}">
                    <h2>${escapeHtml(entry[language].title)}</h2>
                    <p><time datetime="${entry.date}">${label.format(new Date(entry.date))}</time></p>
                    <p>${escapeHtml(entry[language].body)}</p>
                </article>`,
    )
    .join("\n");
}

function renderChangelog(language, page) {
  return `<!doctype html>
<html lang="${language}">
${head(language, "changelog/", { title: page.changelogTitle, description: page.changelogDescription })}
    <body>
        <main class="page">
            <header class="hero">
                <img class="logo" src="/icon.svg" width="96" height="96" alt="" />
                <h1>${page.whatsNew}</h1>
                <p class="tagline">${page.changelogTagline}</p>
                <a class="button" href="/groups">${page.open}</a>
                ${languageNav(language, "changelog/")}
            </header>
            <section class="card support" data-feedback-project="__FEEDBACK_PROJECT_ID__" hidden>
                <h2>${page.suggestTitle}</h2>
                <button type="button" class="button">${page.suggestButton}</button>
            </section>
            <section class="entries">
${entryArticles(language)}
            </section>
            <footer>
                <a href="/${language}/">${featherIcon("home")}${page.home}</a>
                ·
                <a href="${sourceUrl}" rel="noreferrer">${featherIcon("github")}${page.source}</a>
            </footer>
        </main>
        <script src="/marketing.js" defer></script>
    </body>
</html>
`;
}

function sitemap() {
  const url = (path, lastmod) =>
    ["  <url>", `    <loc>${origin}${path}</loc>`]
      .concat(lastmod ? [`    <lastmod>${lastmod}</lastmod>`] : [])
      .concat(["  </url>"])
      .join("\n");
  const newest = changelog[0].date;
  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${["/en/", "/fr/"]
  .map((path) => url(path))
  .concat(["/en/changelog/", "/fr/changelog/"].map((path) => url(path, newest)))
  .join("\n")}
</urlset>
`;
}

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
    "${changelog[0].date}"
`;
if (!existsSync("src/Changelog/Latest.elm") || readFileSync("src/Changelog/Latest.elm", "utf8") !== latestModule) {
  mkdirSync("src/Changelog", { recursive: true });
  writeFileSync("src/Changelog/Latest.elm", latestModule);
}

for (const [language, page] of Object.entries(pages)) {
  mkdirSync(`dist/${language}/changelog`, { recursive: true });
  writeFileSync(`dist/${language}/index.html`, render(language, page));
  writeFileSync(`dist/${language}/changelog/index.html`, renderChangelog(language, page));
}
writeFileSync("dist/sitemap.xml", sitemap());
