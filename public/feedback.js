// The feedback SDK replaces the global custom-element registry with its own
// implementation as soon as it runs, so it is fetched only once someone opens
// the form and never at all for the visitors who don't.
var sdk = null;
var mounted = false;

function loadSdk() {
  if (sdk === null) {
    sdk = new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = "/feedback-one.js";
      script.onload = resolve;
      script.onerror = reject;
      document.head.appendChild(script);
    }).catch((error) => {
      // Let a later click retry rather than leaving a dead button behind.
      sdk = null;
      throw error;
    });
  }
  return sdk;
}

/**
 * Open the hosted feedback form. The caller owns the trigger and supplies the
 * project id the relay reported.
 *
 * @param {Object} options
 * @param {string} options.projectId
 * @param {string} [options.email] Reporter address to prefill.
 * @param {string} [options.copyText] Report text to put on the clipboard.
 * @param {() => void} [options.onCopied] Called once `copyText` is on the clipboard.
 */
export function openFeedback({ projectId, email, copyText, onCopied }) {
  // The form's protocol carries no description, so a report reaches it through
  // the clipboard. Write before the dialog opens: the modal takes the top layer
  // and would hide the confirmation toast.
  if (copyText) {
    navigator.clipboard
      .writeText(copyText)
      .then(() => {
        if (onCopied) onCopied();
      })
      .catch(() => {});
  }
  return loadSdk()
    .then(() => {
      if (!mounted) {
        // The widget outlives no page, so the observer that would re-add it to
        // a wiped <body> stays off.
        window.FeedbackOne.init({
          projectId: projectId,
          showDefaultTrigger: false,
          persistent: false,
        });
        mounted = true;
      }
      // Both calls throw when the form's iframe has no window yet, and an
      // unusable reporter must not cost the user their report.
      try {
        if (email) {
          window.FeedbackOne.identify({ email: email });
        } else {
          window.FeedbackOne.unidentify();
        }
      } catch (_) {}
      window.FeedbackOne.show();
    })
    .catch(() => {});
}
