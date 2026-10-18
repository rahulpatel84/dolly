import Link from "next/link";
import ThemeToggle from "./ThemeToggle";
import { DMG_URL, GITHUB, NAV, VERSION } from "@/lib/site";

export default function SiteHeader({ active }: { active?: string }) {
  return (
    <header className="sticky top-0 z-30 border-b border-line bg-bg/85 backdrop-blur-md">
      <div className="mx-auto flex h-16 max-w-[1200px] items-center justify-between px-5">
        <div className="flex items-center gap-8">
          <Link href="/" className="flex items-center gap-2.5 font-semibold tracking-tight">
            <img src="/icon.png" alt="" width={28} height={28} className="rounded-[7px]" />
            <span>Dolly</span>
            <span className="hidden rounded-md border border-line px-1.5 py-0.5 font-mono text-[11px] font-medium text-fg-3 sm:inline">v{VERSION}</span>
          </Link>
          <nav className="hidden items-center gap-1 md:flex">
            {NAV.map((n) => (
              <Link key={n.href} href={n.href}
                className={`rounded-md px-3 py-1.5 text-[14px] font-medium transition-colors hover:bg-surface ${active === n.label ? "text-fg" : "text-fg-2 hover:text-fg"}`}>
                {n.label}
              </Link>
            ))}
            <a href={GITHUB} className="rounded-md px-3 py-1.5 text-[14px] font-medium text-fg-2 transition-colors hover:bg-surface hover:text-fg">GitHub</a>
          </nav>
        </div>
        <div className="flex items-center gap-2">
          <ThemeToggle />
          <a href={DMG_URL} style={{ background: "var(--fg)", color: "var(--bg)" }} className="hidden rounded-lg px-3.5 py-2 text-[14px] font-semibold transition-opacity hover:opacity-90 sm:inline-flex">
            Download for Mac
          </a>
        </div>
      </div>
    </header>
  );
}
