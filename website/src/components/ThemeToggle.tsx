"use client";
import { useTheme } from "next-themes";
import { useEffect, useState } from "react";

const options = [
  { key: "light", label: "Light", icon: "☀" },
  { key: "dark", label: "Dark", icon: "☾" },
  { key: "system", label: "Auto", icon: "◐" },
] as const;

export default function ThemeToggle() {
  const { theme, setTheme } = useTheme();
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);
  const current = mounted ? theme ?? "system" : "system";
  return (
    <div role="radiogroup" aria-label="Colour theme" className="inline-flex rounded-lg border border-line/60 bg-black/10 p-0.5 text-xs font-mono">
      {options.map((o) => (
        <button
          key={o.key}
          role="radio"
          aria-checked={current === o.key}
          onClick={() => setTheme(o.key)}
          className={`rounded-md px-2.5 py-1 transition-colors focus-visible:outline-2 focus-visible:outline-accent ${current === o.key ? "bg-card text-fg shadow-sm" : "text-hero-muted hover:text-hero-fg"}`}
          title={o.label}
        >
          <span aria-hidden="true" className="mr-1">{o.icon}</span>{o.label}
        </button>
      ))}
    </div>
  );
}
