// www/tooltips.js — Bootstrap 5 tooltip initialisation
// ============================================================
// Tooltips are attached to clickable question-mark icons (tooltip-icon class).
// Each icon carries data-bs-trigger="click" so the tooltip opens/closes on
// click rather than hover.  Clicking anywhere outside an open tooltip
// dismisses it.
//
// Popovers are handled natively by bslib::popover() — no JS needed here.

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
}

// Dismiss any open click-triggered tooltip when the user clicks outside
document.addEventListener('click', function (e) {
  document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(function (el) {
    var instance = bootstrap.Tooltip.getInstance(el);
    if (instance && !el.contains(e.target)) {
      instance.hide();
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

// Prevent mouse-wheel changes on numeric inputs while scrolling through
// large Shiny forms like the effect-size panel. Without this, hovering a
// numericInput can change its value instead of scrolling the page, which
// makes the review pane feel jumpy and unstable.
if (!window.__numericWheelGuardBound) {
  document.addEventListener('wheel', function (e) {
    var el = e.target;
    if (el && el.matches && el.matches('input[type="number"]')) {
      el.blur();
    }
  }, { capture: true, passive: true });

  window.__numericWheelGuardBound = true;
}
