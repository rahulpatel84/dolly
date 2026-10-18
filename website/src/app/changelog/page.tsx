import type { Metadata } from "next";
import SiteHeader from "@/components/SiteHeader";
import SiteFooter from "@/components/SiteFooter";
import { RELEASES } from "@/lib/site";

export const metadata: Metadata = { title: "Changelog", description: "What changed in each Dolly release." };

const RELEASES_LOG = [
  { v: "0.2.2", date: "17 Oct 2026", items: [
    "Appearance setting: match system, light or dark.",
    "End-to-end feature audit (`--selftest-features`) exercises every menu action, dashboard operation, export format and editor tool against a demo library; shipped builds must pass it.",
    "Editor: size readout no longer wraps in narrow toolbars; OCR reports errors instead of staying busy.",
    "Demo library generator and window-capture mode used for the documentation screenshots." ] },
  { v: "0.2.1", date: "16 Oct 2026", items: [
    "Screenshot styles: six gradient backgrounds, padding and corner sliders, shadow, macOS window frame with title.",
    "Export screenshots as PNG, JPEG, HEIC, WebP, TIFF or PDF with a quality slider and live size estimate.",
    "Pixel-sharp Retina preview; instant hover hints on every editor control.",
    "Hotkeys: recording a new shortcut now works for combinations already in use; conflicts flagged; per-field and reset-all.",
    "User Guide in Help menu, in the disk image and on the website." ] },
  { v: "0.2.0", date: "15 Oct 2026", items: [
    "Renamed to Dolly with a new icon.",
    "Performance: polish 76 s → 14–21 s per minute of video; OCR 69 s → 0.14 s; blur 1.8 s → 30 ms; clipboard 4.6 s → 1 s.",
    "Webcam recording with picture-in-picture, audio-only and webcam-only modes, scheduled recording, auto-stop, launch at login.",
    "Dashboard with sidebar, search, sort, grid/list, inspector; trim and remove-section; six export formats; share sheet.",
    "Shottr-style screenshot editor with arrows, shapes, highlighter, blur, text, numbers, crop, colour picker, OCR, pin, zoom.",
    "Stable code signing so Screen Recording permission survives updates." ] },
];

export default function Changelog() {
  return (
    <>
      <SiteHeader active="Changelog" />
      <main className="mx-auto max-w-[820px] px-5 py-14">
        <div className="text-[12.5px] font-semibold uppercase tracking-[.08em] text-fg-3">Changelog</div>
        <h1 className="mt-3 text-[40px] leading-[1.1]">Releases</h1>
        <p className="mt-3 text-fg-2">Disk images for every version are on <a className="underline" href={RELEASES}>GitHub Releases</a>.</p>
        <ol className="mt-10 space-y-10 border-l border-line pl-8">
          {RELEASES_LOG.map((r) => (
            <li key={r.v} className="relative">
              <span className="absolute -left-[41px] top-1.5 h-4 w-4 rounded-full border-4 border-bg bg-fg" />
              <div className="flex flex-wrap items-baseline gap-3"><h2 className="text-[22px]">Dolly {r.v}</h2><span className="text-[13px] text-fg-3">{r.date}</span></div>
              <ul className="mt-3 space-y-1.5 text-[15px] text-fg-2">{r.items.map((i) => <li key={i} className="flex gap-2"><span className="mt-[10px] h-1 w-1 shrink-0 rounded-full bg-fg-3" />{i}</li>)}</ul>
            </li>
          ))}
        </ol>
      </main>
      <SiteFooter />
    </>
  );
}
