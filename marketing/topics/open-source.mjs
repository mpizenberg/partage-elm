export default {
  id: "open-source",
  template: "topic",
  slug: { en: "open-source-bill-splitting", fr: "application-libre-partage-de-frais" },
  en: {
    title: "Open-source bill splitting — Partage",
    description:
      "Partage is an open-source, local-first bill-splitting app: an Elm PWA under MPL-2.0 and a small Node, Hono, and SQLite relay under Apache-2.0.",
    heading: "Open-source bill splitting",
    tagline: "A private, local-first app for shared expenses, built in public and open to new ideas and contributors.",
    open: "Open Partage",
    home: "Home",
    feedback: "Send feedback",
    label: "Open source and self-hosting",
    sections: [
      {
        id: "made-for-real-groups",
        title: "Made for real groups",
        body: `<p>Partage helps friends, families, and roommates keep track of who paid for what and settle up, without making everyone create another account. The hosted app is free, has no ads or individual tracking, and works offline. The <a href="/en/">short product tour</a> shows what using it looks like.</p>
<p>The first prototype was written in JavaScript. As the rules around splits, history, and offline edits grew, I restarted it in Elm. For an app that keeps track of people’s shared expenses, I wanted the domain to be boring in the best way: explicit, deterministic, and easy to test.</p>`,
      },
      {
        id: "architecture",
        title: "How the pieces fit together",
        body: `<p>The frontend is Elm 0.19.1, with the interface built in <a href="https://github.com/mpizenberg/partage-elm/tree/main/vendor/elm-ui" rel="noreferrer"><code>elm-ui</code> 2.0</a>. The browser is not a thin client: each device keeps the group’s encrypted history in IndexedDB, works from that local copy, and synchronizes when a connection is available.</p>
<ul>
<li><strong>The domain is a fold.</strong> A group is an append-only log of signed events. <a href="https://github.com/mpizenberg/partage-elm/blob/main/src/Domain/GroupState.elm" rel="noreferrer"><code>Domain.GroupState.applyEvents</code></a> replays that log into the current members, entries, balances, settlement plan, and activity. Devices with the same valid events derive the same state, so offline edits converge without a server-side merge.</li>
<li><strong>Effects stay at the edges.</strong> Web Crypto, IndexedDB, HTTP, and compression flow through typed <code>elm-concurrent-task</code> tasks in <a href="https://github.com/mpizenberg/partage-elm/tree/main/src/Infra" rel="noreferrer"><code>src/Infra</code></a>, backed by small vendored browser bindings. <a href="https://github.com/mpizenberg/partage-elm/blob/main/public/index.js" rel="noreferrer"><code>public/index.js</code></a> contains the remaining startup and custom-element glue rather than domain logic.</li>
<li><strong>The relay is deliberately small.</strong> The <a href="https://github.com/mpizenberg/partage-elm/blob/main/packages/relay/src/app.js" rel="noreferrer">Hono application</a> stores opaque encrypted records in SQLite and tells connected clients when new records arrive. Clients remain the source of truth and can restore history that the relay has lost.</li>
</ul>
<p>This split keeps the business rules pure and testable while the replaceable edges handle browsers, storage, and transport. The <a href="https://github.com/mpizenberg/partage-elm#architecture" rel="noreferrer">README architecture overview</a> is a good map before going deeper.</p>`,
      },
      {
        id: "use-it-on-your-terms",
        title: "Use it on your terms",
        body: `<p>The app and relay live in <a href="https://github.com/mpizenberg/partage-elm" rel="noreferrer">one public GitHub repository</a>. The Elm PWA, including the local ledger and browser-side encryption, is licensed under <a href="https://github.com/mpizenberg/partage-elm/blob/main/LICENSE" rel="noreferrer">MPL-2.0</a>. The Node, Hono, and SQLite relay has its own <a href="https://github.com/mpizenberg/partage-elm/blob/main/packages/relay/LICENSE" rel="noreferrer">Apache-2.0 licence</a>.</p>
<p>The standard self-hosted deployment puts the static PWA and relay in one container and keeps SQLite on a persistent volume. Push notifications and the feedback form are optional. The <a href="https://github.com/mpizenberg/partage-elm/blob/main/docs/DEPLOY.md" rel="noreferrer">deployment guide</a> covers builds, configuration, backups, reverse proxies, quotas, retention, and the operator dashboard.</p>`,
      },
      {
        id: "ways-to-contribute",
        title: "There are several ways in",
        body: `<p>You do not need to understand the whole synchronization protocol before helping. Useful contributions can start in many places:</p>
<ul>
<li>try the app on a browser or device I may have missed, and report confusing behaviour, accessibility gaps, or PWA rough edges;</li>
<li>work on the Elm domain, the <code>elm-ui</code> interface, or the tests that connect them;</li>
<li>review the cryptography, event replay, relay boundary, or self-hosting documentation; or</li>
<li>translate Partage into another language, or improve the documentation and existing English or French wording.</li>
</ul>
<p>I currently maintain Partage, so a precise question or a small focused contribution is genuinely useful; it does not have to arrive as a finished redesign. The <a href="https://github.com/mpizenberg/partage-elm#getting-started" rel="noreferrer">README gets the local stack running</a>, CI checks formatting, <code>elm-review</code>, and the test suites, and bugs, questions, and pull requests are welcome in the <a href="https://github.com/mpizenberg/partage-elm/issues" rel="noreferrer">issue tracker</a>.</p>`,
      },
      {
        id: "clear-limits",
        title: "Open, with clear limits",
        body: `<p>Publishing code does not make a privacy claim true by itself, but it makes the boundary inspectable. <a href="/en/how-partage-encryption-works/">The encryption page</a> documents what the relay can still observe and the limits of a web app. <a href="/en/bill-splitting-without-an-account/">The no-account page</a> explains device identity and recovery.</p>
<p>The <a href="https://github.com/mpizenberg/partage-elm/blob/main/docs/SPECIFICATION.md" rel="noreferrer">canonical specification</a> records the intended behaviour and security boundaries. The cryptographic design has not been independently audited, and an operator serving modified web code could read data entered through that version of the app. If threat modelling is your thing, careful criticism here is especially welcome.</p>`,
      },
    ],
  },
  fr: {
    title: "Application libre de partage de frais — Partage",
    description:
      "Partage est une application libre et local-first de partage de frais : une PWA Elm sous MPL-2.0 et un petit relais Node, Hono et SQLite sous Apache-2.0.",
    heading: "Une application libre de partage de frais",
    tagline: "Une application privée et local-first pour les dépenses partagées, développée publiquement et ouverte aux idées comme aux contributions.",
    open: "Ouvrir Partage",
    home: "Accueil",
    feedback: "Envoyer un retour",
    label: "Logiciel libre et auto-hébergement",
    sections: [
      {
        id: "pensee-pour-de-vrais-groupes",
        title: "Pensée pour de vrais groupes",
        body: `<p>Partage aide les amis, les familles et les colocataires à noter qui a payé quoi et à régler les comptes, sans imposer la création d’un énième compte à tout le monde. L’application hébergée est gratuite, sans publicité ni suivi individuel, et fonctionne hors ligne. La <a href="/fr/">courte présentation du produit</a> montre à quoi elle ressemble en pratique.</p>
<p>Le premier prototype était écrit en JavaScript. À mesure que les règles de répartition, l’historique et les modifications hors ligne ont grandi, j’ai préféré repartir de zéro en Elm. Pour une application qui tient les comptes d’un groupe, je voulais un domaine sans surprise : explicite, déterministe et facile à tester.</p>`,
      },
      {
        id: "architecture",
        title: "Comment l’ensemble fonctionne",
        body: `<p>Le frontend est écrit en Elm 0.19.1 et toute l’interface utilise <a href="https://github.com/mpizenberg/partage-elm/tree/main/vendor/elm-ui" rel="noreferrer"><code>elm-ui</code> 2.0</a>. Le navigateur n’est pas une simple façade : chaque appareil conserve l’historique chiffré du groupe dans IndexedDB, travaille depuis cette copie locale et se synchronise lorsqu’une connexion est disponible.</p>
<ul>
<li><strong>Le domaine est un <i>fold</i>.</strong> Un groupe est un journal d’événements signés qui ne fait que s’allonger. <a href="https://github.com/mpizenberg/partage-elm/blob/main/src/Domain/GroupState.elm" rel="noreferrer"><code>Domain.GroupState.applyEvents</code></a> le rejoue pour reconstruire les membres, les dépenses, les soldes, le plan de remboursement et l’activité. Deux appareils qui possèdent les mêmes événements valides obtiennent le même état : les modifications hors ligne convergent sans fusion côté serveur.</li>
<li><strong>Les effets restent aux frontières.</strong> Web Crypto, IndexedDB, HTTP et la compression passent par des tâches <code>elm-concurrent-task</code> typées dans <a href="https://github.com/mpizenberg/partage-elm/tree/main/src/Infra" rel="noreferrer"><code>src/Infra</code></a>, appuyées par de petites bibliothèques navigateur intégrées au dépôt. <a href="https://github.com/mpizenberg/partage-elm/blob/main/public/index.js" rel="noreferrer"><code>public/index.js</code></a> contient le reste du démarrage et des éléments personnalisés, plutôt que de la logique métier.</li>
<li><strong>Le relais reste volontairement simple.</strong> <a href="https://github.com/mpizenberg/partage-elm/blob/main/packages/relay/src/app.js" rel="noreferrer">L’application Hono</a> stocke des enregistrements chiffrés opaques dans SQLite et prévient les clients connectés lorsqu’il en arrive de nouveaux. Les clients restent la source de vérité et peuvent restaurer un historique perdu par le relais.</li>
</ul>
<p>Cette séparation garde les règles métier pures et testables, tandis que les frontières remplaçables s’occupent du navigateur, du stockage et du transport. La <a href="https://github.com/mpizenberg/partage-elm#architecture" rel="noreferrer">vue d’ensemble du README</a> offre un plan global du dépot avant d’aller plus loin.</p>`,
      },
      {
        id: "utiliser-selon-ses-besoins",
        title: "À utiliser selon vos besoins",
        body: `<p>L’application et le relais se trouvent dans <a href="https://github.com/mpizenberg/partage-elm" rel="noreferrer">un dépôt GitHub public</a>. La PWA Elm, y compris le registre local et le chiffrement dans le navigateur, est placée sous <a href="https://github.com/mpizenberg/partage-elm/blob/main/LICENSE" rel="noreferrer">MPL-2.0</a>. Le relais Node, Hono et SQLite possède sa propre <a href="https://github.com/mpizenberg/partage-elm/blob/main/packages/relay/LICENSE" rel="noreferrer">licence Apache-2.0</a>.</p>
<p>Le déploiement auto-hébergé standard réunit la PWA statique et le relais dans un même conteneur, avec SQLite sur un volume persistant. Les notifications push et le formulaire de retour sont facultatifs. Le <a href="https://github.com/mpizenberg/partage-elm/blob/main/docs/DEPLOY.md" rel="noreferrer">guide de déploiement</a> couvre la compilation, la configuration, les sauvegardes, le proxy inverse, les quotas, la rétention et le tableau de bord opérateur.</p>`,
      },
      {
        id: "plusieurs-portes-entree",
        title: "Plusieurs portes d’entrée",
        body: `<p>Il n’est pas nécessaire de comprendre tout le protocole de synchronisation avant de contribuer. Une aide utile peut commencer à bien des endroits :</p>
<ul>
<li>tester l’application sur un navigateur ou un appareil qui m’a échappé, puis signaler un comportement déroutant, un problème d’accessibilité ou un défaut d’intégration de la PWA ;</li>
<li>travailler sur le domaine Elm, l’interface <code>elm-ui</code> ou les tests qui les relient ;</li>
<li>relire le chiffrement, le rejeu des événements, la frontière du relais ou la documentation d’auto-hébergement ;</li>
<li>traduire Partage dans une nouvelle langue, ou améliorer la documentation et les textes français ou anglais existants.</li>
</ul>
<p>Je maintiens actuellement Partage : une question précise ou une petite contribution ciblée est donc réellement utile, sans devoir arriver sous la forme d’une refonte complète. Le <a href="https://github.com/mpizenberg/partage-elm#getting-started" rel="noreferrer">README permet de lancer l’environnement local</a>, l’intégration continue vérifie le formatage, <code>elm-review</code> et les suites de tests, et les bugs, questions et pull requests sont les bienvenus dans le <a href="https://github.com/mpizenberg/partage-elm/issues" rel="noreferrer">gestionnaire de tickets</a>.</p>`,
      },
      {
        id: "limites-claires",
        title: "Ouvert, sans cacher ses limites",
        body: `<p>Publier le code ne suffit pas à rendre vraie une promesse de confidentialité, mais ça permet d’examiner concrètement où se trouve la frontière. <a href="/fr/comment-partage-chiffre-vos-donnees/">La page sur le chiffrement</a> détaille ce que le relais peut encore observer et les limites d’une application web. <a href="/fr/partage-de-frais-sans-compte/">La page sur l’absence de compte</a> explique l’identité des appareils et la récupération.</p>
<p>La <a href="https://github.com/mpizenberg/partage-elm/blob/main/docs/SPECIFICATION.md" rel="noreferrer">spécification de référence</a> consigne le comportement attendu et les frontières de sécurité. La conception cryptographique n’a pas fait l’objet d’un audit indépendant, et un opérateur qui servirait un code web modifié pourrait lire les données saisies dans cette version de l’application. Si la modélisation des menaces vous intéresse, les critiques attentives sont particulièrement bienvenues ici.</p>`,
      },
    ],
  },
};
