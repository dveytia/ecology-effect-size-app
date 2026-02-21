// www/tooltips.js — Bootstrap 5 tooltip initialisation
// ============================================================
// Called automatically on page load (and re-triggered by Shiny
// after each renderUI via the Shiny.addCustomMessageHandler below).

// Initialise all Bootstrap tooltips present in the DOM
function initTooltips() {
  var tooltipTriggerList = [].slice.call(
    document.querySelectorAll('[data-bs-toggle="tooltip"]')
  );
  tooltipTriggerList.forEach(function (el) {
    // Avoid double-initialisation
    if (!el._tippy && !el._tooltip) {
      new bootstrap.Tooltip(el, { trigger: 'hover focus' });
    }
  });
}

// Run on initial page load
document.addEventListener('DOMContentLoaded', function () {
  initTooltips();
});

// Re-run after Shiny re-renders dynamic UI
$(document).on('shiny:value', function () {
  setTimeout(initTooltips, 200);
});

// Allow server to trigger re-initialisation explicitly
Shiny.addCustomMessageHandler('reinit_tooltips', function (msg) {
  initTooltips();
});
