export default {
  id: "trips",
  template: "topic",
  slug: { en: "split-expenses-with-friends", fr: "partager-les-frais-entre-amis" },
  en: {
    title: "Split expenses with friends — trips, weekends, holidays",
    description:
      "One shared group for the whole trip: everyone adds what they paid, balances stay current, and settling up takes the fewest possible transfers. Works offline, any currency.",
    heading: "Split expenses with friends",
    tagline: "One group for the whole trip: who paid what, who owes whom, settled in the fewest transfers.",
    open: "Open Partage",
    home: "Home",
    feedback: "Send feedback",
    label: "Splitting trip expenses",
    sections: [
      {
        id: "the-trip-problem",
        title: "The trip problem",
        body: `<p>One person fronts the house. Someone else books the car. Everyone buys groceries, rounds of drinks, museum tickets, and by day three you’ve given up keeping a straight record of the tally.</p>
<p>Partage replaces the tally with one shared group. Each person adds what they paid from their own phone, says who it was for, and the balances update for everyone. Uneven splits, transfers between friends, and shared income like a refunded deposit all fit. Every entry keeps its history, so “wait, was the ferry 80 or 90?” is right there in the app.</p>`,
      },
      {
        id: "fewest-transfers",
        title: "Settle up in the fewest transfers",
        body: `<p>At the end of a trip nobody wants a chain of eight reimbursements. Partage computes the smallest set of transfers that settles the whole group, so five people who owe each other in circles become two or three payments and done.</p>
<p>Each member can note how they prefer to be paid back, and the settle-up screen shows those hints right where the payment happens.</p>`,
      },
      {
        id: "any-currency",
        title: "Several currencies, one group",
        body: `<p>The flight is in euros, the hotel in pounds, the street food in local cash. Add each expense in the currency you actually paid in. A conversion rate is fetched automatically, or you enter it by hand, and balances come out in the group’s currency. No need for a side spreadsheet of exchange rates.</p>`,
      },
      {
        id: "offline-normal",
        title: "Offline is the normal case",
        body: `<p>Connectivity can be tough on a trip: the plane, the mountain road, the foreign SIM that ran out of data. Partage works offline. Everything lives on your device, entries are added without a connection, and devices sync up whenever you’re back online.</p>
<p>And since groups are end-to-end encrypted with <a href="/en/bill-splitting-without-an-account/">no account to create</a>, your friend who “doesn’t install apps” can join from a browser with one link. What the trip cost, and who was on it, stays between you. <a href="/en/how-partage-encryption-works/">The server can’t read any of it</a>.</p>`,
      },
    ],
  },
  fr: {
    title: "Partager les frais entre amis — voyages et week-ends",
    description:
      "Un seul groupe pour tout le voyage : chacun ajoute ce qu’il a payé, les soldes restent à jour, et on se rembourse en un minimum de virements. Hors-ligne et multi-devises.",
    heading: "Partager les frais entre amis",
    tagline: "Un groupe pour tout le voyage : qui a payé quoi, qui doit quoi à qui, remboursé en un minimum de virements.",
    open: "Ouvrir Partage",
    home: "Accueil",
    feedback: "Envoyer un retour",
    label: "Partager les frais d’un voyage",
    sections: [
      {
        id: "le-probleme-du-voyage",
        title: "Le problème du voyage",
        body: `<p>Une personne avance la location. Une autre paie la voiture. Tout le monde achète des courses, des tournées, des billets d’entrée, et au troisième jour vous avez renoncé à tenir le compte proprement.</p>
<p>Partage remplace le récapitulatif par un groupe commun. Chacun ajoute ses dépenses depuis son propre téléphone, précise pour qui c’était, et les soldes se mettent à jour pour tout le monde. Répartitions inégales, remboursements entre amis, recettes partagées comme une caution rendue : tout y trouve sa place. Chaque entrée garde son historique, donc « attends, le ferry c’était 80 ou 90 ? » trouve sa réponse dans l’appli.</p>`,
      },
      {
        id: "minimum-de-virements",
        title: "Se rembourser en un minimum de virements",
        body: `<p>Personne ne veut finir un voyage sur une chaîne de huit remboursements. Partage calcule le plus petit ensemble de virements qui solde tout le groupe : cinq personnes qui se doivent de l’argent en boucle deviennent deux ou trois paiements, et c’est réglé.</p>
<p>Chaque membre peut indiquer comment il préfère être remboursé, et l’écran de remboursement affiche ces indications au moment du paiement.</p>`,
      },
      {
        id: "plusieurs-devises",
        title: "Plusieurs devises, un seul groupe",
        body: `<p>Le vol en euros, l’hôtel en livres, la cantine de rue en espèces locales. Ajoutez chaque dépense dans la devise réellement payée. Un taux de conversion est récupéré automatiquement, ou vous le saisissez à la main, et les soldes ressortent dans la devise du groupe. Pas besoin de tableur à côté pour les taux de change.</p>`,
      },
      {
        id: "hors-ligne-par-defaut",
        title: "Le hors-ligne est le cas normal",
        body: `<p>La connexion est vite capricieuse en voyage : l’avion, la route de montagne, la carte SIM étrangère à court de données. Partage fonctionne hors-ligne. Tout vit sur votre appareil, les dépenses s’ajoutent sans connexion, et les appareils se synchronisent dès que vous repassez en ligne.</p>
<p>Et comme les groupes sont chiffrés de bout en bout et <a href="/fr/partage-de-frais-sans-compte/">sans compte à créer</a>, votre ami qui « n’installe pas d’applis » rejoint depuis un navigateur avec un simple lien. Ce que le voyage a coûté, et qui en était, reste entre vous. <a href="/fr/comment-partage-chiffre-vos-donnees/">Le serveur ne peut rien en lire</a>.</p>`,
      },
    ],
  },
};
