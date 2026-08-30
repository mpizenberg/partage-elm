export default {
  id: "no-account",
  template: "topic",
  slug: { en: "bill-splitting-without-an-account", fr: "partage-de-frais-sans-compte" },
  en: {
    title: "Bill splitting without an account",
    description:
      "Split bills with no signup, no email, and no password: in Partage the group key on your device is the membership. What that means, and exactly how recovery works if a device is lost.",
    heading: "Bill splitting without an account",
    tagline: "No signup, no email, no password. What “no account” actually means — and what happens if you lose your phone.",
    open: "Open Partage",
    home: "Home",
    feedback: "Send feedback",
    label: "Splitting bills without an account",
    sections: [
      {
        id: "what-no-account-means",
        title: "What “no account” means exactly",
        body: `<p>There is nothing to register. No email to confirm, no password to invent, no profile to fill in. You open Partage, create a group, and share its invite link; whoever opens the link is in.</p>
<p>This is not an anonymous mode bolted onto a normal app. There is no server-side identity to be anonymous <em>from</em>: your membership is a cryptographic key held on your device, and <a href="/en/how-partage-encryption-works/">the server only ever stores data encrypted with it</a>. It cannot attach your expenses to you, because it never learns who you are.</p>
<p>The absence is also the security model. No password means no password to phish, no reset flow to hijack, and no “forgot email” support queue — the classic account attack surface simply is not there.</p>`,
      },
      {
        id: "losing-a-device",
        title: "What if I lose my phone?",
        body: `<p>The question “no account” raises immediately — and the one this page will not dodge. There are three ways back, and all of them exist today:</p>
<ul>
<li><strong>Another device you already use.</strong> Open a group on a second device — your desktop browser next to your phone — and link it to your existing member with “This is me — link my device”. From then on each device holds its own full copy of the group. Losing one loses nothing.</li>
<li><strong>An exported backup.</strong> Every group can be exported to a file that carries what is needed to restore it; import brings it back on any device. The app itself nudges you to export groups you care about.</li>
<li><strong>An invite link.</strong> Kept in your password manager — or simply asked from any other member of the group, who can share it again. The group key travels inside the link, which is why a link is enough.</li>
</ul>
<p>And the honest limit: with no second device, no backup, and no other member, there is nothing to recover from — because nobody else holds the key. That is not a gap in the design; it is what “the server cannot read your data” costs, and the three routes above are how you make sure it never bites.</p>`,
      },
      {
        id: "thirty-seconds",
        title: "Started in thirty seconds",
        body: `<p>No account also means no onboarding. Create a group, add the first expense, show the QR code to the person across the table. It runs in the browser, installs as an app if you want it to, <a href="/en/split-expenses-with-friends/">works offline on a trip</a>, and is free with no ads — the fastest path from “let’s just split this” to actually splitting it.</p>`,
      },
    ],
  },
  fr: {
    title: "Partage de frais sans compte",
    description:
      "Partager les frais sans inscription, sans e-mail et sans mot de passe : dans Partage, la clé du groupe sur votre appareil tient lieu de compte. Ce que ça veut dire, et comment récupérer un groupe si un appareil disparaît.",
    heading: "Partage de frais sans compte",
    tagline: "Sans inscription, sans e-mail, sans mot de passe. Ce que « sans compte » veut vraiment dire — et ce qui se passe si vous perdez votre téléphone.",
    open: "Ouvrir Partage",
    home: "Accueil",
    feedback: "Envoyer un retour",
    label: "Partager les frais sans compte",
    sections: [
      {
        id: "ce-que-sans-compte-veut-dire",
        title: "Ce que « sans compte » veut dire exactement",
        body: `<p>Il n’y a rien à créer. Pas d’e-mail à confirmer, pas de mot de passe à inventer, pas de profil à remplir. Vous ouvrez Partage, créez un groupe et partagez son lien d’invitation ; qui ouvre le lien en fait partie.</p>
<p>Ce n’est pas un mode anonyme greffé sur une application classique. Il n’y a pas d’identité côté serveur dont il faudrait être anonyme : votre appartenance au groupe est une clé cryptographique détenue par votre appareil, et <a href="/fr/comment-partage-chiffre-vos-donnees/">le serveur ne stocke que des données chiffrées avec elle</a>. Il ne peut pas rattacher vos dépenses à vous, puisqu’il ne sait jamais qui vous êtes.</p>
<p>Cette absence est aussi le modèle de sécurité. Pas de mot de passe, donc pas de mot de passe à hameçonner, pas de procédure de réinitialisation à détourner — la surface d’attaque classique des comptes n’existe tout simplement pas.</p>`,
      },
      {
        id: "perdre-un-appareil",
        title: "Et si je perds mon téléphone ?",
        body: `<p>La question que « sans compte » soulève immédiatement — et que cette page ne va pas esquiver. Il y a trois chemins de retour, et tous existent déjà :</p>
<ul>
<li><strong>Un autre appareil que vous utilisez déjà.</strong> Ouvrez un groupe sur un second appareil — votre navigateur de bureau à côté du téléphone — et reliez-le à votre membre avec « C’est moi — lier mon appareil ». Chaque appareil détient dès lors sa copie complète du groupe. En perdre un ne perd rien.</li>
<li><strong>Une sauvegarde exportée.</strong> Chaque groupe peut être exporté vers un fichier qui contient ce qu’il faut pour le restaurer ; l’import le fait revenir sur n’importe quel appareil. L’application elle-même vous incite à exporter les groupes qui comptent.</li>
<li><strong>Un lien d’invitation.</strong> Conservé dans votre gestionnaire de mots de passe — ou simplement redemandé à n’importe quel autre membre du groupe, qui peut le repartager. La clé du groupe voyage dans le lien : c’est pourquoi un lien suffit.</li>
</ul>
<p>Et la limite honnête : sans second appareil, sans sauvegarde et sans autre membre, il n’y a rien à récupérer — parce que personne d’autre ne détient la clé. Ce n’est pas un trou dans la conception ; c’est le prix de « le serveur ne peut pas lire vos données », et les trois chemins ci-dessus servent à ce qu’il ne vous coûte jamais rien.</p>`,
      },
      {
        id: "trente-secondes",
        title: "Lancé en trente secondes",
        body: `<p>Sans compte, c’est aussi sans parcours d’inscription. Créez un groupe, ajoutez la première dépense, montrez le QR code à la personne en face. Ça tourne dans le navigateur, s’installe en application si vous le souhaitez, <a href="/fr/partager-les-frais-entre-amis/">fonctionne hors-ligne en voyage</a>, et c’est gratuit et sans publicité — le chemin le plus court entre « on n’a qu’à partager » et le partage fait.</p>`,
      },
    ],
  },
};
