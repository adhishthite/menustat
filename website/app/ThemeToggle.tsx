"use client";

import { Moon, Sun } from "lucide-react";
import { useEffect, useState } from "react";

type Theme = "dark" | "light";

function current(): Theme {
  return document.documentElement.dataset.theme === "light" ? "light" : "dark";
}

export default function ThemeToggle() {
  // Start undefined so the button does not render a wrong icon before we read
  // the theme the inline <head> script already applied.
  const [theme, setTheme] = useState<Theme | null>(null);

  useEffect(() => {
    setTheme(current());
  }, []);

  const toggle = () => {
    const next: Theme = current() === "light" ? "dark" : "light";
    document.documentElement.dataset.theme = next;
    try {
      localStorage.setItem("menustat-theme", next);
    } catch {
      // ignore storage failures (private mode, etc.)
    }
    setTheme(next);
  };

  return (
    <button
      type="button"
      className="themeToggle"
      onClick={toggle}
      aria-label="Toggle color theme"
      title="Toggle theme"
    >
      {theme === "light" ? <Moon size={16} /> : <Sun size={16} />}
    </button>
  );
}
