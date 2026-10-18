import Link from "next/link";
import { DMG_URL, GITHUB, RELEASES, VERSION } from "@/lib/site";

const cols = [
  { h: "Product", links: [["Overview", "/#product"], ["Auto-Zoom", "/docs/auto-zoom"], ["Screenshots", "/docs/screenshots"], ["Download", DMG_URL]] },
  { h: "Documentation", links: [["Install", "/docs/install"], ["Permissions", "/docs/permissions"], ["Hotkeys", "/docs/hotkeys"], ["Troubleshooting", "/docs/troubleshooting"]] },
  { h: "Compare", links: [["vs Movavi", "/compare#movavi"], ["vs Loom", "/compare#loom"], ["vs CleanShot X", "/compare#cleanshot"], ["vs Screen Studio", "/compare#screen-studio"]] },
  { h: "Project", links: [["GitHub", GITHUB], ["Releases", RELEASES], ["Changelog", "/changelog"], ["Report an issue", `${GITHUB}/issues`]] },
];

export default function SiteFooter() {
  return (
    <footer className="border-t border-line bg-surface">
      <div className="mx-auto grid max-w-[1200px] gap-10 px-5 py-14 md:grid-cols-[1.4fr_repeat(4,1fr)]">
        <div>
          <div className="flex items-center gap-2.5 font-semibold"><img src="/icon.png" alt="" width={24} height={24} className="rounded-md" /> Dolly</div>
          <p className="mt-3 max-w-[260px] text-[13.5px] leading-relaxed text-fg-2">The screen recorder that follows you. Native macOS, no account, nothing leaves your Mac.</p>
          <p className="mt-4 font-mono text-[12px] text-fg-3">v{VERSION} · macOS 14+ · Apple silicon &amp; Intel</p>
        </div>
        {cols.map((c) => (
          <div key={c.h}>
            <div className="text-[12px] font-semibold uppercase tracking-[.08em] text-fg-3">{c.h}</div>
            <ul className="mt-3 space-y-2">
              {c.links.map(([t, h]) => (
                <li key={t}>{h.startsWith("/") ? <Link href={h} className="text-[14px] text-fg-2 hover:text-fg">{t}</Link> : <a href={h} className="text-[14px] text-fg-2 hover:text-fg">{t}</a>}</li>
              ))}
            </ul>
          </div>
        ))}
      </div>
      <div className="border-t border-line">
        <div className="mx-auto flex max-w-[1200px] flex-wrap items-center justify-between gap-3 px-5 py-5 text-[13px] text-fg-3">
          <span>© 2026 Rahul Patel. Open source under the terms in the repository.</span>
          <span>macOS, Finder and QuickTime are trademarks of Apple Inc. Other product names are trademarks of their owners.</span>
        </div>
      </div>
    </footer>
  );
}
