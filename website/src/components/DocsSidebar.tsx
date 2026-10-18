"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { DOCS } from "@/lib/docs-list";

export default function DocsSidebar() {
  const path = usePathname();
  const groups = Array.from(new Set(DOCS.map((d) => d.group)));
  return (
    <aside className="lg:sticky lg:top-24 lg:self-start">
      <details className="lg:hidden">
        <summary className="cursor-pointer rounded-lg border border-line px-3 py-2 text-[14px] font-medium">Documentation menu</summary>
        <Nav groups={groups} path={path} />
      </details>
      <div className="hidden lg:block"><Nav groups={groups} path={path} /></div>
    </aside>
  );
}

function Nav({ groups, path }: { groups: string[]; path: string }) {
  return (
    <nav className="mt-3 space-y-6 lg:mt-0">
      {groups.map((g) => (
        <div key={g}>
          <div className="mb-2 text-[11.5px] font-semibold uppercase tracking-[.08em] text-fg-3">{g}</div>
          <ul className="space-y-0.5 border-l border-line">
            {DOCS.filter((d) => d.group === g).map((d) => {
              const href = `/docs/${d.slug}`;
              const on = path === href || (d.slug === "introduction" && path === "/docs");
              return (
                <li key={d.slug}>
                  <Link href={href} className={`-ml-px block border-l py-1 pl-3.5 text-[14px] transition-colors ${on ? "border-fg font-medium text-fg" : "border-transparent text-fg-2 hover:border-line-2 hover:text-fg"}`}>{d.title}</Link>
                </li>
              );
            })}
          </ul>
        </div>
      ))}
      <a href="/GUIDE.md" className="block text-[13px] text-fg-3 hover:text-fg">Single-file guide (Markdown) ↗</a>
    </nav>
  );
}
