import type { Metadata } from "next";
import SiteHeader from "@/components/SiteHeader";
import SiteFooter from "@/components/SiteFooter";
import { PRODUCTS, ROWS, type Cell } from "@/lib/compare";
import { DMG_URL } from "@/lib/site";

export const metadata: Metadata = {
  title: "Compare Dolly with Movavi, Loom, CleanShot X, Screen Studio, Shottr, OBS and QuickTime",
  description: "Feature-by-feature comparison of macOS screen recorders and screenshot tools, including what Dolly does not do.",
};

function CellView({ v }: { v: Cell }) {
  if (v === "yes") return <span className="yes" aria-label="Yes">✓</span>;
  if (v === "no") return <span className="no" aria-label="No">—</span>;
  if (v === "part") return <span className="part" aria-label="Partial" title="Partial or limited">◐</span>;
  return <span className="text-[12.5px] text-fg-2">{v}</span>;
}

export default function ComparePage() {
  const groups = Array.from(new Set(ROWS.map((r) => r.group)));
  const dollyYes = ROWS.filter((r) => r.values.dolly === "yes").length;
  return (
    <>
      <SiteHeader active="Compare" />
      <main className="mx-auto max-w-[1200px] px-5 py-14">
        <div className="max-w-[760px]">
          <div className="text-[12.5px] font-semibold uppercase tracking-[.08em] text-fg-3">Comparison</div>
          <h1 className="mt-3 text-[40px] leading-[1.1]">How Dolly compares</h1>
          <p className="mt-4 text-[17px] leading-relaxed text-fg-2">
            Eight tools people actually use for screen recording and screenshots on a Mac, across {ROWS.length} capabilities. Dolly covers {dollyYes} of them. The gaps are listed too — scrolling capture, keystroke overlay, cloud links and Windows are things other tools do today and Dolly does not.
          </p>
          <p className="mt-3 text-[13px] text-fg-3">Compiled from public product pages and our own use, October 2026. ✓ included · ◐ partial or limited · — not offered. Found an error? <a className="underline" href="https://github.com/rahulpatel84/dolly/issues">Open an issue</a>.</p>
        </div>

        <div className="mt-10 overflow-x-auto rounded-xl border border-line">
          <table className="matrix min-w-[980px]">
            <thead>
              <tr>
                <th className="w-[260px]">Capability</th>
                {PRODUCTS.map((p) => <th key={p.id} className={p.id === "dolly" ? "dolly" : ""}>{p.name}</th>)}
              </tr>
            </thead>
            <tbody>
              {groups.map((g) => (
                <GroupRows key={g} group={g} />
              ))}
            </tbody>
          </table>
        </div>

        <section className="mt-16 grid gap-6 md:grid-cols-2">
          {PRODUCTS.map((p) => (
            <article key={p.id} id={p.id} className={`rounded-2xl border p-6 ${p.id === "dolly" ? "border-accent/40 bg-surface" : "border-line"}`}>
              <div className="flex items-baseline justify-between gap-4">
                <h2 className="text-[20px]">{p.name}</h2>
                <span className="text-[12.5px] text-fg-3">{p.platforms}</span>
              </div>
              <p className="mt-1 text-[14.5px] text-fg-2">{p.tagline}</p>
              <p className="mt-3 inline-block rounded-md bg-surface-2 px-2 py-0.5 text-[12.5px] font-medium">{p.pricing}</p>
              <ul className="mt-4 space-y-1.5 text-[14.5px] text-fg-2">
                {p.notes.map((n) => <li key={n} className="flex gap-2"><span className="mt-[9px] h-1 w-1 shrink-0 rounded-full bg-fg-3" />{n}</li>)}
              </ul>
            </article>
          ))}
        </section>

        <section className="mt-16 rounded-2xl bg-ink px-8 py-10 text-ink-fg">
          <h2 className="text-[26px]">When to pick something else</h2>
          <div className="mt-5 grid gap-6 text-[15px] leading-relaxed text-ink-muted md:grid-cols-3">
            <p><strong className="text-ink-fg">You need a share link in seconds.</strong> Loom's whole model is cloud-first. Dolly gives you a file and the share sheet.</p>
            <p><strong className="text-ink-fg">Scrolling screenshots are your daily work.</strong> CleanShot X and Shottr do this well; Dolly does not yet.</p>
            <p><strong className="text-ink-fg">You want a manual zoom timeline.</strong> Screen Studio lets you keyframe every move. Dolly plans zoom automatically and exposes strength and smoothing only.</p>
          </div>
          <a href={DMG_URL} className="mt-8 inline-flex rounded-lg bg-ink-fg px-4 py-2.5 text-[14px] font-semibold text-ink">Otherwise, download Dolly — it's free</a>
        </section>
      </main>
      <SiteFooter />
    </>
  );
}

function GroupRows({ group }: { group: string }) {
  return (
    <>
      <tr className="group"><td colSpan={PRODUCTS.length + 1}>{group}</td></tr>
      {ROWS.filter((r) => r.group === group).map((r) => (
        <tr key={r.feature}>
          <td>{r.feature}</td>
          {PRODUCTS.map((p) => <td key={p.id} className={p.id === "dolly" ? "dolly" : ""}><CellView v={r.values[p.id] ?? "no"} /></td>)}
        </tr>
      ))}
    </>
  );
}
