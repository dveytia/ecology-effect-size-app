// www/tooltips.js — Bootstrap 5 tooltip + popover initialisation
// ============================================================
// Tooltips are attached to clickable question-mark icons (tooltip-icon class).
// Each icon carries data-bs-trigger="click" so the tooltip opens/closes on
// click rather than hover.  Clicking anywhere outside an open tooltip
// dismisses it.
//
// Popovers are used for rich HTML content (value definitions).

// Initialise all Bootstrap tooltips present in the DOM
function initTooltips() {
  var tooltipTriggerList = [].slice.call(
    document.querySelectorAll('[data-bs-toggle="tooltip"]')
  );
  tooltipTriggerList.forEach(function (el) {
    // Avoid double-initialisation
    if (!bootstrap.Tooltip.getInstance(el)) {
      new bootstrap.Tooltip(el);
    }
  });

  // Initialise Bootstrap popovers (rich HTML tooltips)
  var popoverTriggerList = [].slice.call(
    document.querySelectorAll('[data-bs-toggle="popover"]')
  );
  popoverTriggerList.forEach(function (el) {
    if (!bootstrap.Popover.getInstance(el)) {
      new bootstrap.Popover(el, {
        html: true,
        sanitize: false,
        trigger: 'click',
        placement: 'top'
      });
    }
  });
}

// Dismiss any open click-triggered tooltip or popover when the user clicks outside
document.addEventListener('click', function (e) {
  // Dismiss tooltips
  document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(function (el) {
    var instance = bootstrap.Tooltip.getInstance(el);
    if (instance && !el.contains(e.target)) {
      instance.hide();
    }
  });
  // Dismiss popovers
  document.querySelectorAll('[data-bs-toggle="popover"]').forEach(function (el) {
    var instance = bootstrap.Popover.getInstance(el);
    if (instance && !el.contains(e.target)) {
      // Don't dismiss if clicking inside the popover content itself
      var popoverEl = document.querySelector('.popover');
      if (!popoverEl || !popoverEl.contains(e.target)) {
        instance.hide();
      }
    }
  });
}, true);

// Run on initial page load
document.addEventListener('DOMContentLoaded', function () {
  initTooltips();
});

// Re-run after Shiny re-renders dynamic UI (debounced to prevent excessive calls)
var _tooltipTimer = null;
$(document).on('shiny:value', function () {
  if (_tooltipTimer) clearTimeout(_tooltipTimer);
  _tooltipTimer = setTimeout(initTooltips, 500);
});

// Allow server to trigger re-initialisation explicitly
Shiny.addCustomMessageHandler('reinit_tooltips', function (msg) {
  initTooltips();
});
