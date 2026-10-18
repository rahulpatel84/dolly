import Link from "next/link";
import SiteHeader from "@/components/SiteHeader";
import SiteFooter from "@/components/SiteFooter";
import Shot from "@/components/Shot";
import shots from "@/lib/shots.json";
import { DMG_URL, GITHUB, VERSION } from "@/lib/site";
import { PRODUCTS, ROWS } from "@/lib/compare";

type Dim = { w: number; h: number };
const S = shots as Record<string, Dim>;
const dim = (k: string): Dim => S[k] ?? { w: 1800, h: 1100 };

const STEPS = [
  { n: "01", t: "Record", d: "Full screen, an area, or one window. System audio, your mic and webcam if you want them. Pause, draw on screen, schedule, auto-stop.", shot: "settings-recording", alt: "Recording settings" },
  { n: "02", t: "Polish — automatically", d: "Auto-Zoom reads the cursor telemetry recorded beside every clip and plans the camera: in on clicks and typing, out when you pause. Cursor halo, click rings, silence removal, background framing. One click, re-runnable.", shot: "styled-export", alt: "Polished export on a gradient background" },
  { n: "03", t: "Share", d: "Play, trim, export to MOV, MP4, muted MP4, compressed H.264, M4A or GIF — then AirDrop, Messages, Mail or any app via the share sheet. Nothing is uploaded unless you do it.", shot: "player", alt: "Dolly player window" },
];

const FEATURES = [
  { t: "Auto-Zoom", d: "Camera moves planned from where you actually worked, with strength and smoothing presets.", href: "/docs/auto-zoom" },
  { t: "Screenshot editor", d: "Arrows, shapes, highlighter, blur, text, numbered steps, crop, colour picker, OCR. Opens the instant you capture.", href: "/docs/editor" },
  { t: "Styled exports", d: "macOS window frame, six gradients, padding, corners, shadow — applied to copy, save and export alike.", href: "/docs/editor#style" },
  { t: "Six image formats", d: "PNG, JPEG, HEIC, WebP, TIFF or PDF with a quality slider and live size estimate.", href: "/docs/editor#export" },
  { t: "Dashboard", d: "Library with search, sort, grid and list, an inspector with every action, player and trimmer.", href: "/docs/dashboard" },
  { t: "Hotkeys everywhere", d: "Eight configurable global shortcuts that need no Accessibility permission. Conflicts are flagged.", href: "/docs/hotkeys" },
  { t: "Webcam & audio modes", d: "Webcam sidecar composited as picture-in-picture; audio-only and webcam-only recordings.", href: "/docs/recording" },
  { t: "Private by design", d: "No account, no cloud, no analytics. Files live in ~/Movies. Open source.", href: "/docs/faq" },
];

const TEASER = ["Automatic zoom to activity", "Silence removal", "OCR (copy text from image)", "macOS-style frame & gradient background", "Works fully offline, no account", "Price"];

export default function Home() {
  const teaserCols = ["dolly", "movavi", "loom", "cleanshot", "screen-studio"];
  return (
    <>
      <SiteHeader active="Product" />
      <main id="product">
        <section className="border-b border-line">
          <div className="mx-auto max-w-[1200px] px-5 pb-16 pt-20 md:pt-24">
            <div className="max-w-[780px]">
              <div className="inline-flex items-center gap-2 rounded-full border border-line bg-surface px-3 py-1 text-[12.5px] font-medium text-fg-2">
                <span className="h-1.5 w-1.5 rounded-full bg-good" /> Dolly {VERSION} · macOS 14+ · free and open source
              </div>
              <h1 className="mt-6 text-[44px] leading-[1.05] md:text-[60px]">Screen recordings that look produced. Automatically.</h1>
              <p className="mt-6 max-w-[640px] text-[18px] leading-relaxed text-fg-2">
                Dolly records your Mac, then does the editing: zooms to where you work, highlights the cursor, cuts the dead air and frames the result. Screenshots get a full annotation editor. Everything stays on your machine.
              </p>
              <div className="mt-8 flex flex-wrap items-center gap-3">
                <a href={DMG_URL} className="rounded-lg bg-accent px-5 py-3 text-[15px] font-semibold text-accent-ink hover:bg-accent-hover">Download for Mac</a>
                <Link href="/docs/install" className="rounded-lg border border-line-2 px-5 py-3 text-[15px] font-semibold hover:bg-surface">Installation guide</Link>
                <a href={GITHUB} className="px-2 py-3 text-[14px] font-medium text-fg-2 hover:text-fg">View source ↗</a>
              </div>
              <p className="mt-4 text-[13px] text-fg-3">1.4 MB disk image · Apple silicon and Intel · no account required</p>
            </div>
            <div className="mt-14">
              <Shot src="/shots/dashboard.png" alt="The Dolly dashboard showing a recordings library and inspector" {...dim("dashboard")} />
            </div>
          </div>
        </section>

        <section className="border-b border-line bg-surface">
          <div className="mx-auto grid max-w-[1200px] grid-cols-2 gap-6 px-5 py-8 md:grid-cols-4">
            {[["4K · 60 fps", "HEVC capture, system audio, mic and webcam"], ["≈ 1× realtime", "Auto-Zoom render speed on Apple silicon"], ["6 + 6 formats", "Video and image exports, no re-encode for MP4"], ["0 uploads", "No cloud, no telemetry, no account"]].map(([k, v]) => (
              <div key={k}><div className="text-[22px] font-semibold tracking-tight">{k}</div><div className="mt-1 text-[13.5px] text-fg-2">{v}</div></div>
            ))}
          </div>
        </section>

        <section className="mx-auto max-w-[1200px] px-5 py-20" id="how">
          <div className="max-w-[640px]">
            <div className="text-[12.5px] font-semibold uppercase tracking-[.08em] text-fg-3">How it works</div>
            <h2 className="mt-3 text-[34px] leading-tight">Record once. Polish any time.</h2>
            <p className="mt-4 text-fg-2">Effects are never burned into the pixels. Dolly keeps the clean recording and a small telemetry file, so a clip can be re-polished with different settings months later.</p>
          </div>
          <div className="mt-12 space-y-20">
            {STEPS.map((s, i) => (
              <div key={s.n} className={`grid items-center gap-10 md:grid-cols-2 ${i % 2 ? "md:[&>*:first-child]:order-2" : ""}`}>
                <div>
                  <div className="font-mono text-[13px] text-fg-3">{s.n}</div>
                  <h3 className="mt-2 text-[26px]">{s.t}</h3>
                  <p className="mt-3 text-[15.5px] leading-relaxed text-fg-2">{s.d}</p>
                </div>
                <Shot src={`/shots/${s.shot}.png`} alt={s.alt} {...dim(s.shot)} />
              </div>
            ))}
          </div>
        </section>

        <section className="border-y border-line bg-surface" id="editor">
          <div className="mx-auto max-w-[1200px] px-5 py-20">
            <div className="grid gap-10 md:grid-cols-[1fr_1.4fr] md:items-start">
              <div>
                <div className="text-[12.5px] font-semibold uppercase tracking-[.08em] text-fg-3">Screenshots</div>
                <h2 className="mt-3 text-[34px] leading-tight">An editor that opens before you can reach for one.</h2>
                <p className="mt-4 text-fg-2">Capture a screen, an area or a window at native resolution. The editor appears immediately with arrows, shapes, highlighter, blur, text, numbered steps and crop — plus a colour picker and on-device OCR.</p>
                <p className="mt-3 text-fg-2">Style it with a macOS window frame on a gradient and export as PNG, JPEG, HEIC, WebP, TIFF or PDF.</p>
                <Link href="/docs/editor" className="mt-6 inline-block text-[14.5px] font-semibold underline underline-offset-4">Editor documentation →</Link>
              </div>
              <div className="space-y-5">
                <Shot src="/shots/editor.png" alt="Screenshot editor with annotations" {...dim("editor")} />
                <Shot src="/shots/editor-styled.png" alt="Screenshot styled with a macOS window frame on a gradient" {...dim("editor-styled")} caption="Style: Midnight gradient, macOS window frame, title. Applied to copy, save, share and export." />
              </div>
            </div>
          </div>
        </section>

        <section className="mx-auto max-w-[1200px] px-5 py-20" id="features">
          <div className="text-[12.5px] font-semibold uppercase tracking-[.08em] text-fg-3">Capabilities</div>
          <h2 className="mt-3 text-[34px] leading-tight">Everything in the box</h2>
          <div className="mt-10 grid gap-px overflow-hidden rounded-2xl border border-line bg-line sm:grid-cols-2 lg:grid-cols-4">
            {FEATURES.map((f) => (
              <Link key={f.t} href={f.href} className="group bg-bg p-6 transition-colors hover:bg-surface">
                <div className="text-[16px] font-semibold">{f.t}</div>
                <p className="mt-2 text-[14px] leading-relaxed text-fg-2">{f.d}</p>
                <div className="mt-4 text-[13px] font-medium text-fg-3 group-hover:text-fg">Learn more →</div>
              </Link>
            ))}
          </div>
        </section>

        <section className="border-y border-line bg-surface">
          <div className="mx-auto grid max-w-[1200px] items-center gap-10 px-5 py-20 md:grid-cols-2">
            <Shot src="/shots/settings-hotkeys.png" alt="Hotkeys settings" {...dim("settings-hotkeys")} />
            <div>
              <div className="text-[12.5px] font-semibold uppercase tracking-[.08em] text-fg-3">Control</div>
              <h2 className="mt-3 text-[34px] leading-tight">Yours to configure, nothing to administer</h2>
              <p className="mt-4 text-fg-2">Five settings tabs cover frame rate and quality, microphone and webcam, Auto-Zoom presets, screenshot behaviour and every hotkey. Shortcuts that macOS or another app owns are flagged, and each has a one-click reset.</p>
              <ul className="mt-5 space-y-2 text-[14.5px] text-fg-2">
                {["Match system, light or dark appearance", "Launch at login, countdown, auto-stop", "Recordings folder of your choice", "Window-screenshot backgrounds: shadow, transparent, solid, gradient, trimmed"].map((i) => <li key={i} className="flex gap-2"><span className="mt-[9px] h-1 w-1 shrink-0 rounded-full bg-fg-3" />{i}</li>)}
              </ul>
              <Link href="/docs/settings" className="mt-6 inline-block text-[14.5px] font-semibold underline underline-offset-4">Settings reference →</Link>
            </div>
          </div>
        </section>

        <section className="mx-auto max-w-[1200px] px-5 py-20" id="compare">
          <div className="flex flex-wrap items-end justify-between gap-4">
            <div>
              <div className="text-[12.5px] font-semibold uppercase tracking-[.08em] text-fg-3">Compare</div>
              <h2 className="mt-3 text-[34px] leading-tight">Against the tools you already know</h2>
            </div>
            <Link href="/compare" className="text-[14.5px] font-semibold underline underline-offset-4">Full comparison, {ROWS.length} capabilities →</Link>
          </div>
          <div className="mt-8 overflow-x-auto rounded-xl border border-line">
            <table className="matrix min-w-[760px]">
              <thead><tr><th>Capability</th>{teaserCols.map((c) => <th key={c} className={c === "dolly" ? "dolly" : ""}>{PRODUCTS.find((p) => p.id === c)!.name}</th>)}</tr></thead>
              <tbody>
                {TEASER.map((f) => { const r = ROWS.find((x) => x.feature === f)!; return (
                  <tr key={f}><td>{f}</td>{teaserCols.map((c) => { const v = r.values[c]; return <td key={c} className={c === "dolly" ? "dolly" : ""}>{v === "yes" ? <span className="yes">✓</span> : v === "no" ? <span className="no">—</span> : v === "part" ? <span className="part">◐</span> : <span className="text-[12.5px] text-fg-2">{v}</span>}</td>; })}</tr>
                ); })}
              </tbody>
            </table>
          </div>
          <p className="mt-3 text-[13px] text-fg-3">Honest gaps: Dolly has no scrolling capture, no keystroke overlay and no cloud links. <Link href="/compare" className="underline">See where to pick something else.</Link></p>
        </section>

        <section className="border-t border-line bg-ink text-ink-fg" id="install">
          <div className="mx-auto grid max-w-[1200px] gap-10 px-5 py-20 md:grid-cols-[1fr_1fr] md:items-center">
            <div>
              <h2 className="text-[34px] leading-tight">Install in a minute</h2>
              <ol className="mt-6 space-y-3 text-[15px] text-ink-muted">
                {["Download the disk image and drag Dolly to Applications.", "Open it; confirm once in Privacy & Security → Open Anyway.", "Grant Screen Recording when asked, then relaunch.", "Press ⌃⌘S for your first screenshot, ⌃⌘R to record."].map((s, i) => <li key={s} className="flex gap-3"><span className="font-mono text-ink-fg">{i + 1}.</span>{s}</li>)}
              </ol>
              <div className="mt-8 flex flex-wrap gap-3">
                <a href={DMG_URL} style={{ background: "var(--ink-fg)", color: "var(--ink)" }} className="rounded-lg px-5 py-3 text-[15px] font-semibold">Download Dolly {VERSION}</a>
                <Link href="/docs/install" className="rounded-lg border border-ink-muted/40 px-5 py-3 text-[15px] font-semibold">Step-by-step guide</Link>
              </div>
            </div>
            <Shot src="/shots/install-dmg.png" alt="The Dolly disk image in Finder" {...dim("install-dmg")} />
          </div>
        </section>
      </main>
      <SiteFooter />
    </>
  );
}
