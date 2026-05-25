// Applies the saved (or system) theme before first paint to avoid a flash.
(function () {
  try {
    var t = localStorage.getItem("menustat-theme");
    if (!t) {
      t = window.matchMedia("(prefers-color-scheme: light)").matches
        ? "light"
        : "dark";
    }
    document.documentElement.dataset.theme = t;
  } catch (e) {
    document.documentElement.dataset.theme = "dark";
  }
})();
