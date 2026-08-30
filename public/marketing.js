import { openFeedback } from "./feedback.js";

// The relay substitutes the project id into the page it serves. An unconfigured
// deployment leaves it empty and a build served without that substitution leaves
// the placeholder, so the control stays hidden for both rather than offering a
// form that cannot open.
const PLACEHOLDER = "__FEEDBACK_PROJECT_ID__";

const slot = document.querySelector("[data-feedback-project]");
const projectId = slot?.getAttribute("data-feedback-project") ?? "";

if (slot && projectId && projectId !== PLACEHOLDER) {
  slot.hidden = false;
  slot.querySelector("button").addEventListener("click", () => {
    openFeedback({ projectId: projectId });
  });
}
