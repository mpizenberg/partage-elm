export default {
  id: "open-source",
  template: "topic",
  slug: { en: "open-source-bill-splitting", fr: "application-libre-partage-de-frais" },
  en: {
    title: "Open-source bill splitting — Partage",
    description:
      "Partage is an open-source, local-first bill-splitting app: an Elm PWA under MPL-2.0 and a small Node, Hono, and SQLite relay under Apache-2.0.",
    heading: "Open-source bill splitting",
    tagline: "The app and its encrypted sync relay are public, inspectable, and self-hostable.",
    open: "Open Partage",
    home: "Home",
    feedback: "Send feedback",
    label: "Open source and self-hosting",
    sections: [
      {
        id: "one-repository-two-licences",
        title: "One repository, two licences",
        body: `<p>Partage is developed in <a href="https://github.com/mpizenberg/partage-elm" rel="noreferrer">one public GitHub repository</a>. The Elm PWA, including the local ledger and browser-side encryption, is licensed under <a href="https://github.com/mpizenberg/partage-elm/blob/main/LICENSE" rel="noreferrer">MPL-2.0</a>. The small Node, Hono, and SQLite relay has its own <a href="https://github.com/mpizenberg/partage-elm/blob/main/packages/relay/LICENSE" rel="noreferrer">Apache-2.0 licence</a>.</p>`,
      },
      {
        id: "source-and-trust",
        title: "The source is part of the trust model",
        body: `<p>Publishing code does not make a privacy claim true by itself. It makes the boundary inspectable: group state is rebuilt from signed events on each participating device, while the relay stores and forwards encrypted records.</p>
<p><a href="/en/how-partage-encryption-works/">The encryption page documents what the relay can still observe and the limits of a web app</a>. <a href="/en/bill-splitting-without-an-account/">The no-account page explains device identity and recovery</a>.</p>`,
      },
      {
        id: "self-hosting",
        title: "Run your own deployment",
        body: `<p>The standard deployment puts the static PWA and relay in one container and keeps SQLite on a persistent volume. Push notifications and the feedback form are optional services, so a deployment can leave either out.</p>
<p>The <a href="https://github.com/mpizenberg/partage-elm/blob/main/docs/DEPLOY.md" rel="noreferrer">self-hosting guide</a> covers the production build, container configuration, backups, reverse-proxy requirements, quotas, retention, and operator dashboard.</p>`,
      },
      {
        id: "review-welcome",
        title: "Review is welcome",
        body: `<p>The <a href="https://github.com/mpizenberg/partage-elm/blob/main/docs/SPECIFICATION.md" rel="noreferrer">canonical specification</a> records the intended behaviour and security boundaries. The cryptographic design has not been independently audited, and an operator serving modified web code could read data entered through that version of the app.</p>
<p>Bug reports, architecture questions, focused pull requests, and scrutiny of those boundaries are welcome in the <a href="https://github.com/mpizenberg/partage-elm/issues" rel="noreferrer">GitHub issue tracker</a>.</p>`,
      },
    ],
  },
  fr: {
    title: "Application libre de partage de frais — Partage",
    description:
      "Partage est une application libre et local-first de partage de frais : une PWA Elm sous MPL-2.0 et un petit relais Node, Hono et SQLite sous Apache-2.0.",
    heading: "Une application libre de partage de frais",
    tagline: "L’application et son relais de synchronisation chiffré sont publics, vérifiables et auto-hébergeables.",
    open: "Ouvrir Partage",
    home: "Accueil",
    feedback: "Envoyer un retour",
    label: "Logiciel libre et auto-hébergement",
    sections: [
      {
        id: "un-depot-deux-licences",
        title: "Un dépôt, deux licences",
        body: `<p>Partage est développé dans <a href="https://github.com/mpizenberg/partage-elm" rel="noreferrer">un dépôt GitHub public</a>. La PWA Elm, y compris le registre local et le chiffrement dans le navigateur, est placée sous <a href="https://github.com/mpizenberg/partage-elm/blob/main/LICENSE" rel="noreferrer">MPL-2.0</a>. Le petit relais Node, Hono et SQLite possède sa propre <a href="https://github.com/mpizenberg/partage-elm/blob/main/packages/relay/LICENSE" rel="noreferrer">licence Apache-2.0</a>.</p>`,
      },
      {
        id: "code-et-confiance",
        title: "Le code source fait partie du modèle de confiance",
        body: `<p>Publier le code ne suffit pas à rendre vraie une promesse de confidentialité. Cela rend la frontière vérifiable : l’état d’un groupe est reconstruit sur chaque appareil participant à partir d’événements signés, tandis que le relais stocke et retransmet des enregistrements chiffrés.</p>
<p><a href="/fr/comment-partage-chiffre-vos-donnees/">La page sur le chiffrement détaille ce que le relais peut encore observer et les limites d’une application web</a>. <a href="/fr/partage-de-frais-sans-compte/">La page sur l’absence de compte explique l’identité des appareils et la récupération</a>.</p>`,
      },
      {
        id: "auto-hebergement",
        title: "Exploiter son propre déploiement",
        body: `<p>Le déploiement standard réunit la PWA statique et le relais dans un même conteneur, avec SQLite sur un volume persistant. Les notifications push et le formulaire de retour sont des services facultatifs : un déploiement peut se passer de l’un comme de l’autre.</p>
<p>Le <a href="https://github.com/mpizenberg/partage-elm/blob/main/docs/DEPLOY.md" rel="noreferrer">guide d’auto-hébergement</a> couvre la compilation de production, la configuration du conteneur, les sauvegardes, le proxy inverse, les quotas, la rétention et le tableau de bord opérateur.</p>`,
      },
      {
        id: "relecture-bienvenue",
        title: "Les relectures sont bienvenues",
        body: `<p>La <a href="https://github.com/mpizenberg/partage-elm/blob/main/docs/SPECIFICATION.md" rel="noreferrer">spécification de référence</a> consigne le comportement attendu et les frontières de sécurité. La conception cryptographique n’a pas fait l’objet d’un audit indépendant, et un opérateur qui servirait un code web modifié pourrait lire les données saisies dans cette version de l’application.</p>
<p>Les signalements de bugs, questions d’architecture, propositions ciblées et examens critiques de ces frontières sont bienvenus dans le <a href="https://github.com/mpizenberg/partage-elm/issues" rel="noreferrer">gestionnaire de tickets GitHub</a>.</p>`,
      },
    ],
  },
};
