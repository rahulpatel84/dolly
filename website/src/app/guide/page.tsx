import fs from "node:fs";
import path from "node:path";
import type { Metadata } from "next";
import ThemeToggle from "@/components/ThemeToggle";
import { renderMarkdown } from "./markdown";

export const metadata: Metadata = {
  title: "Dolly User Guide",
  description: "Every Dolly feature, hotkey and setting: recording, Auto-Zoom, the dashboard, screenshots and the editor.",
};

export default function GuidePage() {
  const md = fs.readFileSync(path.join(process.cwd(), "public", "GUIDE.md"), "utf8");
  const html = renderMarkdown(md);
  return (
    <main className="min-h-screen">
      <header className="sticky top-0 z-20 border-b border-line bg-bg/85 backdrop-blur">
        <div className="mx-auto flex max-w-[860px] items-center justify-between px-4 py-3">
          <a href="/" className="flex items-center gap-2.5 font-display text-lg font-semibold">
            <img src="/icon.png" alt="" width={28} height={28} className="rounded-md" /> Dolly
          </a>
          <nav className="flex items-center gap-4 text-sm">
            <a href="/" className="hover:underline">Home</a>
            <a href="https://github.com/rahulpatel84/dolly" className="hover:underline">GitHub</a>
            <a href="/GUIDE.md" className="hover:underline">Markdown</a>
            <ThemeToggle />
          </nav>
        </div>
      </header>
      <article className="guide mx-auto max-w-[860px] px-4 py-10" dangerouslySetInnerHTML={{ __html: html }} />
      <footer className="mx-auto max-w-[860px] px-4 pb-12 text-sm text-fg-2">
        Dolly 0.2.1 · Rahul Patel · <a href="/" className="underline">screen-recorder-site.vercel.app</a>
      </footer>
    </main>
  );
}
