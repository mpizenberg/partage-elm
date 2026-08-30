export default {
  id: "encryption",
  template: "topic",
  slug: { en: "how-partage-encryption-works", fr: "comment-partage-chiffre-vos-donnees" },
  en: {
    title: "How Partage’s encryption works",
    description:
      "What end-to-end encryption means in Partage: AES-256 group keys that never leave your devices, exactly what the sync relay can and cannot see, and the honest limits.",
    heading: "How Partage’s encryption works",
    tagline: "What “end-to-end encrypted” means here, and what the server can still see.",
    open: "Open Partage",
    home: "Home",
    feedback: "Send feedback",
    label: "How encryption works",
    sections: [
      {
        id: "what-is-encrypted",
        title: "What is encrypted, and where the key lives",
        body: `<p>Every group has its own key: a random 256-bit AES-GCM key, generated on your device by the browser’s built-in cryptography. There is no account the key is attached to and no password it is derived from. The key itself is the membership.</p>
<p>Everything a group contains, such as expenses, transfers, members, categories, and every edit in the history, is encrypted on your device before it syncs. What leaves the device is ciphertext, and what the server stores and forwards is ciphertext.</p>
<p>The key travels only when you invite someone, and only inside the invite link, as described below. It never reaches the server.</p>`,
      },
      {
        id: "what-the-relay-sees",
        title: "What the relay can see, and what it cannot",
        body: `<p>The sync relay sees:</p>
<ul>
<li>encrypted records: their size, when they arrive, and the random group identifier they belong to;</li>
<li>a random per-device identifier on each record — this is how your devices sync without accounts;</li>
<li>the IP address of each connection, like every server on the internet;</li>
<li>aggregate counts for these public pages: visitors per day, the top referring sites, and which page was served. There is no cookie, and no per-visitor identifier.</li>
</ul>
<p>It can’t see amounts, titles, categories, currencies, member names, balances, or who owes whom. The relay never receives the key: a device proves its access with a hash of the key, and the server stores only a hash of that hash. A full copy of the server’s database reveals no expense to anyone.</p>
<p>The relay also keeps nothing forever: a group untouched by any member for twelve months is deleted from the server, while each member’s device keeps its own full copy.</p>`,
      },
      {
        id: "invitations",
        title: "Invitations: the key travels in the fragment",
        body: `<p>An invite link carries the group key after the <code>#</code>. Browsers never send that part of a URL to any server, so the link opens the join page without the relay ever learning the key. A QR code invitation is the same link.</p>
<p>One thing to keep in mind: anyone who has the link has the key. Share it responsibly, directly with the people you mean to let in. Prefer direct QR code scans, or end-to-end encrypted messaging groups.</p>`,
      },
      {
        id: "honest-limits",
        title: "The honest limits",
        body: `<ul>
<li>The cryptography has not been independently audited. The design uses standard primitives from the browser’s WebCrypto API, and the <a href="https://github.com/mpizenberg/partage-elm" rel="noreferrer">source is public</a>, but nobody has been paid to break it.</li>
<li>Partage is a web app, so the code that encrypts is delivered by the server. An operator serving malicious code could read your data. This is the tradeoff every encrypted web app makes. Open source and an installable app soften this but do not remove it.</li>
<li>Encryption hides content, not shape. Sizes and timing of encrypted records are visible to the relay, as listed above.</li>
</ul>`,
      },
    ],
  },
  fr: {
    title: "Comment Partage chiffre vos données",
    description:
      "Ce que « chiffré de bout en bout » veut dire dans Partage : des clés AES-256 qui ne quittent jamais vos appareils, ce que le relais peut voir et ne peut pas voir, et les limites honnêtes.",
    heading: "Comment Partage chiffre vos données",
    tagline: "Ce que « chiffré de bout en bout » veut dire ici, et ce que le serveur voit encore.",
    open: "Ouvrir Partage",
    home: "Accueil",
    feedback: "Envoyer un retour",
    label: "Comment vos données sont chiffrées",
    sections: [
      {
        id: "ce-qui-est-chiffre",
        title: "Ce qui est chiffré, et où vit la clé",
        body: `<p>Chaque groupe a sa propre clé : une clé AES-GCM de 256 bits, tirée au hasard sur votre appareil par la cryptographie intégrée du navigateur. Aucun compte ne la porte, aucun mot de passe ne la génère. La clé est l’appartenance au groupe.</p>
<p>Tout le contenu d’un groupe, comme les dépenses, les remboursements, les membres, les catégories et chaque modification de l’historique, est chiffré sur votre appareil avant la synchronisation. Ce qui quitte l’appareil est du chiffré, et ce que le serveur stocke et retransmet est du chiffré.</p>
<p>La clé ne voyage que lorsque vous invitez quelqu’un, et uniquement dans le lien d’invitation, comme décrit plus bas. Elle n’atteint jamais le serveur.</p>`,
      },
      {
        id: "ce-que-voit-le-relais",
        title: "Ce que le relais voit, et ce qu’il ne peut pas voir",
        body: `<p>Le relais de synchronisation voit :</p>
<ul>
<li>des enregistrements chiffrés : leur taille, leur heure d’arrivée, et l’identifiant aléatoire du groupe auquel ils appartiennent ;</li>
<li>un identifiant aléatoire par appareil sur chaque enregistrement — c’est ainsi que vos appareils se synchronisent sans compte ;</li>
<li>l’adresse IP de chaque connexion, comme tout serveur sur Internet ;</li>
<li>des compteurs agrégés pour ces pages publiques : visiteurs par jour, principaux sites référents, et quelle page a été servie. Pas de cookie, pas d’identifiant de visiteur.</li>
</ul>
<p>Il ne peut voir ni montants, ni intitulés, ni catégories, ni devises, ni noms de membres, ni soldes, ni qui doit quoi à qui. Le relais ne reçoit jamais la clé : un appareil prouve son accès avec un condensat de la clé, et le serveur ne stocke qu’un condensat de ce condensat. Une copie complète de la base du serveur ne révèle aucune dépense à personne.</p>
<p>Le relais ne garde d’ailleurs rien pour toujours : un groupe qu’aucun membre n’a touché depuis douze mois est supprimé du serveur, chaque appareil membre conservant sa copie complète.</p>`,
      },
      {
        id: "invitations",
        title: "Invitations : la clé voyage dans le fragment",
        body: `<p>Un lien d’invitation porte la clé du groupe après le <code>#</code>. Les navigateurs n’envoient jamais cette partie de l’URL à un serveur : le lien ouvre la page d’invitation sans que le relais n’apprenne la clé. Une invitation par QR code est le même lien.</p>
<p>Une chose à garder en tête : qui a le lien a la clé. Partagez-le avec soin, directement aux personnes que vous voulez faire entrer. Privilégiez un scan direct du QR code, ou un groupe de messagerie chiffrée de bout en bout.</p>`,
      },
      {
        id: "limites-honnetes",
        title: "Les limites honnêtes",
        body: `<ul>
<li>La cryptographie n’a pas fait l’objet d’un audit indépendant. La conception s’appuie sur les primitives standard de l’API WebCrypto du navigateur, et le <a href="https://github.com/mpizenberg/partage-elm" rel="noreferrer">code source est public</a>, mais personne n’a été payé pour la casser.</li>
<li>Partage est une application web : le code qui chiffre est livré par le serveur. Un opérateur servant du code malveillant pourrait lire vos données. C’est le compromis de toute application web chiffrée. Le code ouvert et l’installation en application l’atténuent sans le supprimer.</li>
<li>Le chiffrement cache le contenu, pas la forme. Les tailles et les horaires des enregistrements chiffrés restent visibles du relais, comme listé ci-dessus.</li>
</ul>`,
      },
    ],
  },
};
