import { readFileSync } from "node:fs";

const entries = JSON.parse(readFileSync("changelog.json", "utf8"));

export default {
  id: "changelog",
  template: "changelog",
  negotiate: "/changelog",
  slug: { en: "changelog", fr: "changelog" },
  entries,
  lastmod: entries[0].date,
  en: {
    title: "Partage changelog — What’s new",
    description:
      "New features and improvements in Partage, the private, offline-capable bill-splitting app — updated with every release.",
    heading: "What’s new",
    tagline: "Every new feature and improvement, newest first.",
    open: "Open Partage",
    suggestTitle: "What should we build next?",
    suggestButton: "Send an idea",
    home: "Home",
    source: "Source code",
  },
  fr: {
    title: "Changelog de Partage — Nouveautés",
    description:
      "Nouvelles fonctionnalités et améliorations de Partage, l’application privée de partage de frais — mis à jour à chaque version.",
    heading: "Nouveautés",
    tagline: "Toutes les nouveautés et améliorations, les plus récentes en premier.",
    open: "Ouvrir Partage",
    suggestTitle: "On construit quoi ensuite ?",
    suggestButton: "Proposer une idée",
    home: "Accueil",
    source: "Code source",
  },
};
