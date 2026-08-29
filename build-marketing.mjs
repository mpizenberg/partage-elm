import { mkdirSync, writeFileSync } from "node:fs";

const origin = (process.env.CANONICAL_ORIGIN || "__CANONICAL_ORIGIN__").replace(/\/$/, "");
const fundingUrl = "https://github.com/sponsors/mpizenberg";
const sourceUrl = "https://github.com/mpizenberg/partage-elm";

const pages = {
  en: {
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
      "End-to-end encrypted",
      "No account or password",
      "Works offline, syncs when online",
      "Smart settle-up with fewer transactions",
      "Multiple currencies in one group",
      "Full activity and edit history",
      "Installable on any device",
      "Open source, no ads, no user tracking",
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
      "Filter by person, category, currency, or date",
      "Free CSV export and complete JSON backup",
      "Payment hints for common payment methods",
      "Virtual members, merging, and retirement without lost history",
      "Expenses, transfers, and income",
      "Soft deletion with restore and field-level edit history",
      "Per-member settle-up preferences",
      "No daily limits, caps, or ads",
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
  },
  fr: {
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
      "Chiffrement de bout en bout",
      "Sans compte ni mot de passe",
      "Hors-ligne, synchronisé en ligne",
      "Remboursements optimisés",
      "Plusieurs devises dans un groupe",
      "Journal complet des modifications",
      "Installable sur tout appareil",
      "Open source, sans pub ni suivi individuel",
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
      "Filtrer par personne, catégorie, devise ou date",
      "Export CSV gratuit et sauvegarde JSON complète",
      "Raccourcis pour les moyens de remboursement courants",
      "Membres virtuels, fusion et retrait sans perte d’historique",
      "Dépenses, transferts et revenus",
      "Suppression réversible et historique détaillé",
      "Préférences de remboursement par membre",
      "Sans limite journalière, plafond ni publicité",
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
  },
};

function list(items) {
  return items.map((item) => `                    <li>${item}</li>`).join("\n");
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

function render(language, page) {
  return `<!doctype html>
<html lang="${language}">
    <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <meta name="theme-color" content="#E8725C" />
        <title>${page.title}</title>
        <meta name="description" content="${page.description}" />
        <link rel="canonical" href="${origin}/${language}/" />
        <link rel="alternate" hreflang="en" href="${origin}/en/" />
        <link rel="alternate" hreflang="fr" href="${origin}/fr/" />
        <link rel="alternate" hreflang="x-default" href="${origin}/" />
        <meta property="og:type" content="website" />
        <meta property="og:title" content="${page.title}" />
        <meta property="og:description" content="${page.description}" />
        <meta property="og:image" content="${origin}/icon-512.png" />
        <meta property="og:url" content="${origin}/${language}/" />
        <meta name="twitter:card" content="summary" />
        <meta name="twitter:title" content="${page.title}" />
        <meta name="twitter:description" content="${page.description}" />
        <meta name="twitter:image" content="${origin}/icon-512.png" />
        <link rel="icon" href="/favicon.svg" type="image/svg+xml" />
        <link rel="stylesheet" href="/marketing.css" />
    </head>
    <body>
        <main class="page">
            <header class="hero">
                <img class="logo" src="/icon.svg" width="96" height="96" alt="" />
                <h1>${page.heading}</h1>
                <p class="tagline">${page.tagline}</p>
                <a class="button" href="/groups">${page.open}</a>
                <nav class="languages" aria-label="Language · Langue">
                    <a href="/en/"${language === "en" ? ' aria-current="page"' : ""}>English</a>
                    ·
                    <a href="/fr/"${language === "fr" ? ' aria-current="page"' : ""}>Français</a>
                </nav>
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
                <a class="button" href="${fundingUrl}" rel="noreferrer">${page.fundingCta}</a>
            </section>
            <footer>
                <a href="/about">${page.about}</a>
                ·
                <a href="${sourceUrl}" rel="noreferrer">${page.source}</a>
            </footer>
        </main>
    </body>
</html>
`;
}

for (const [language, page] of Object.entries(pages)) {
  const directory = `dist/${language}`;
  mkdirSync(directory, { recursive: true });
  writeFileSync(`${directory}/index.html`, render(language, page));
}
