"use client";
import { useEffect, useState } from "react";
import { useTheme } from "next-themes";

export default function ThemeToggle() {
  const { theme, setTheme } = useTheme();
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);
  const opts: [string, string][] = [["light", "Light"], ["dark", "Dark"], ["system", "Auto"]];
  return (
    <div role="radiogroup" aria-label="Colour theme" className="flex rounded-lg border border-line bg-surface p-0.5 text-[12px] font-medium">
      {opts.map(([v, l]) => {
        const on = mounted && theme === v;
        return (
          <button key={v} role="radio" aria-checked={on} onClick={() => setTheme(v)}
            className={`rounded-md px-2.5 py-1 transition-colors ${on ? "bg-bg text-fg shadow-sm" : "text-fg-3 hover:text-fg"}`}>
            {l}
          </button>
        );
      })}
    </div>
  );
}
