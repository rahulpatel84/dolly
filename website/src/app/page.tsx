import Image from "next/image";
import ThemeToggle from "@/components/ThemeToggle";

const features = [
  ["⌃⌘R · ⌃⇧⌘R · window picker", "Record screen, area, or window", "Full display at native Retina resolution, a dragged region, or any window — and “record last area again” for repeat takes."],
  ["automatic", "Auto-Zoom", "The camera follows your cursor, pushes in where you work, pulls back when you roam. Smoothed both directions so it never trails or jumps."],
  ["from telemetry", "Cursor halo and click rings", "A soft highlight on the pointer and an expanding ring on every click, composited in source space so they zoom with the content."],
  ["system + mic", "Audio on separate tracks", "System audio always, microphone when you want it, each on its own track. Silence removal cuts dead air with padding so speech is never clipped."],
  ["picture-in-picture", "Webcam without burning it in", "Recorded to its own file on the same clock, shown as a circular inset by Auto-Zoom. Leave it out of any export with one switch."],
  ["⌃⌘P", "Pause and resume", "The gap is removed from the file, not frozen into it — one timeline shared by every track."],
  ["⌃⌘D", "Draw on screen while recording", "Sketch arrows over anything mid-take. This is the one effect that is recorded into the video, on purpose."],
  ["lossless", "Trim, or cut a section out", "Keep a range or remove one from the middle; the halves join. No re-encode, and the telemetry follows the cut."],
  ["MOV · MP4 · GIF · M4A", "Export and share", "Muted MP4, compressed 1080p, audio-only M4A, animated GIF. Share sheet to AirDrop, Messages, Mail. Up to 4K output."],
  ["canvas", "Framed background", "Inset the recording on a gradient or solid canvas with rounded corners and a soft shadow — the produced look, in one setting."],
  ["unattended", "Schedule and auto-stop", "Start at a time, stop after a length. Or set a maximum duration so a forgotten recording ends itself."],
  ["audio · webcam only", "Other modes", "Record just system audio and voice to M4A, or just the camera — same menu, same folder."],
];

const compare: [string, string, "y" | "n" | "p", string, "y" | "n" | "p"][] = [
  ["Full screen, area, window capture", "Yes", "y", "Yes", "y"],
  ["System audio + microphone, separate tracks", "Yes", "y", "Yes", "y"],
  ["Automatic cursor-following zoom", "Yes, after capture, re-runnable", "y", "No", "n"],
  ["Cursor and click effects", "Applied after capture", "y", "Burned in at capture", "y"],
  ["Webcam", "Separate file, PiP at render", "y", "Overlay at capture", "y"],
  ["Draw on screen while recording", "Yes", "y", "Yes", "y"],
  ["Silence removal", "Yes", "y", "No", "n"],
  ["Background framing", "Yes", "y", "No", "n"],
  ["Screenshot editor with OCR, blur, pin", "Yes", "y", "Basic", "p"],
  ["Scrolling screenshot", "No", "n", "Yes", "y"],
  ["Keystroke display", "Not yet", "n", "Yes", "y"],
  ["Upload to YouTube / Drive", "No — share sheet instead", "n", "Yes", "y"],
  ["Scheduled recording, auto-stop", "Yes", "y", "Yes", "y"],
  ["Export", "MOV, MP4, GIF, M4A, up to 4K", "y", "MP4, MOV, MKV, AVI, GIF, MP3", "y"],
  ["Windows version", "In progress", "p", "Yes", "y"],
  ["Price", "Free", "y", "Subscription, trial watermark", "n"],
];

const faq = [
  ["Does it upload my recordings anywhere?", "No. There is no account and no server. Sharing uses the macOS share sheet, which sends files only where you point it."],
  ["Why does it keep the webcam and cursor effects separate?", "Because once an effect is burned into the pixels it can never be adjusted. Keeping the telemetry and webcam as sidecar files costs nothing during capture and lets every effect be re-rendered with different settings later."],
  ["What does “zero dropped frames” mean?", "The encoder keeps up with capture. Every recording reports frames written and dropped when it ends, so you see the number rather than discovering a stutter later."],
  ["What if macOS stops the capture on its own?", "Whatever was captured is finalised and playable, and the app tells you why it ended. Quitting mid-recording finishes the file too."],
  ["Will there be a Windows version?", "The zoom engine is already ported and tested; the Windows capture layer compiles but has not been run on Windows yet."],
];

const tone = { y: "text-good font-semibold", n: "text-fg-2", p: "text-partial font-semibold" };

function SectionHead({ title, lede }: { title: string; lede: string }) {
  return (
    <div className="mb-9 grid gap-6 md:grid-cols-[minmax(0,1fr)_minmax(0,1.4fr)] md:items-end">
      <h2 className="text-[clamp(28px,3.4vw,40px)] font-semibold leading-[1.1]">{title}</h2>
      <p className="max-w-[40em] text-lg text-fg-2">{lede}</p>
    </div>
  );
}

export default function Home() {
  return (
    <>
      <header className="bg-hero text-hero-fg">
        <div className="mx-auto max-w-[1120px] px-5">
          <nav className="flex items-center justify-between gap-4 py-3.5">
            <a href="#top" className="flex items-center gap-2.5 font-display text-lg font-semibold">
              <Image src="/assets/icon.png" alt="" width={30} height={30} className="rounded-[7px]" />Dolly
            </a>
            <ul className="hidden gap-5 text-[15px] text-hero-muted md:flex">
              {[["#features", "Features"], ["#how", "How it works"], ["#editor", "Screenshots"], ["#compare", "Compare"], ["#install", "Install"], ["/guide", "Guide"], ["https://github.com/rahulpatel84/dolly", "GitHub"]].map(([h, t]) => (
                <li key={h}><a href={h} className="hover:text-hero-fg">{t}</a></li>
              ))}
            </ul>
            <ThemeToggle />
          </nav>
          <div id="top" className="grid items-center gap-10 py-12 pb-16 md:grid-cols-[minmax(0,1.05fr)_minmax(0,1fr)]">
            <div>
              <p className="font-mono text-xs uppercase tracking-[.08em] text-hero-muted">Dolly · macOS 14+ · Apple Silicon &amp; Intel</p>
              <h1 className="mt-3 text-[clamp(38px,5.6vw,66px)] font-bold leading-[1.02]">Record clean.<br />Polish <em className="not-italic text-accent">after.</em></h1>
              <p className="mt-4 max-w-[34em] text-[19px] text-hero-muted">The screen recorder that follows you. Dolly keeps your cursor telemetry beside the video, then zooms, frames and highlights clicks afterwards — so nothing is ever burned into the pixels, and any recording can be re-polished.</p>
              <div className="mt-7 flex flex-wrap gap-3">
                <a href="https://github.com/rahulpatel84/dolly/releases/download/v0.2.1/Dolly-0.2.1.dmg" className="rounded-lg bg-accent px-[18px] py-3 font-semibold text-accent-ink focus-visible:outline-2 focus-visible:outline-accent">Download for Mac · 0.2.1</a>
                <a href="#how" className="rounded-lg border border-current px-[18px] py-3 font-semibold">See how it works</a>
              </div>
              <div className="mt-4 flex flex-wrap gap-4 font-mono text-[12.5px] text-hero-muted">
                <span>0 dropped frames at 1080p60 in testing</span><span>HEVC, hardware encoded</span><span>No account, no upload</span>
              </div>
            </div>
            <figure className="relative m-0">
              <Image src="/assets/polish.png" alt="A polished recording: the screen inset on a gradient canvas with rounded corners, a soft cursor halo and a circular webcam inset" width={640} height={360} priority className="w-full rounded-xl shadow-[0_30px_60px_rgba(0,0,0,.45)]" />
              <figcaption className="absolute bottom-3.5 left-3.5 rounded-md bg-black/55 px-2 py-1 font-mono text-[11.5px] text-white">Auto-Zoom output · gradient frame · webcam picture-in-picture</figcaption>
            </figure>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-[1120px] px-5">
        <section id="features" className="py-16">
          <SectionHead title="Everything a screen recorder should do — and the one thing only Dolly does." lede="Capture, audio, webcam, pause, trim, export — the table stakes are all here. The difference is that the polish happens after you stop, from data captured while you recorded." />
          <div className="grid gap-[18px] sm:grid-cols-2 lg:grid-cols-3">
            {features.map(([k, h, p]) => (
              <div key={h} className="flex flex-col gap-2 rounded-[10px] border border-line bg-card p-5 pb-[22px]">
                <span className="font-mono text-xs text-fg-2">{k}</span>
                <h3 className="text-xl font-semibold">{h}</h3>
                <p className="text-[15.5px] text-fg-2">{p}</p>
              </div>
            ))}
          </div>
        </section>

        <section id="how" className="border-t border-line py-16">
          <SectionHead title="Why the polish can be redone forever" lede="Most recorders bake zoom and highlights into the pixels as they capture. Once there, they can never change. Dolly keeps them separate — hence the name: a dolly is the camera move that follows the action." />
          <div className="grid overflow-hidden rounded-xl border border-line bg-card md:grid-cols-3">
            {[
              ["01 · RECORD", "A clean stream, plus telemetry", "ScreenCaptureKit writes the raw screen to HEVC. Alongside it, the cursor position and clicks are sampled 60 times a second into a small sidecar file — no extra permission needed.", 'Recording 2026-10-14 at 12.45.16.mov\nRecording 2026-10-14 at 12.45.16.telemetry.json\n{ "t": 1.2218, "x": 2887.1, "y": 1148.6, "click": true }'],
              ["02 · PLAN", "A camera path, from arithmetic", "The timeline is bucketed into half-second windows. Tight cursor activity or a click pulls the camera in; roaming pushes it out. The path is smoothed forwards then backwards, which cancels the lag that makes auto-zoom feel seasick.", "window 0.5 s · zoom 1.3–3.0×\nsmoothing 0.5–3.0 s · click hold 1.0 s\nedge-clamped, never off-frame"],
              ["03 · RENDER", "Apply it, as often as you like", "Zoom, halo, click rings, webcam inset, background frame and silence removal are rendered into a new file. The original is untouched. Change a setting and run it again.", "5 s clip → 1.3 s render\noriginal: never modified"],
            ].map(([n, h, p, pre], i) => (
              <div key={n} className={`p-6 ${i > 0 ? "border-t border-line md:border-l md:border-t-0" : ""}`}>
                <span className="font-mono text-xs tracking-[.08em] text-accent">{n}</span>
                <h3 className="mt-2 text-xl font-semibold">{h}</h3>
                <p className="mt-2 text-[15.5px] text-fg-2">{p}</p>
                <pre className="mt-3.5 overflow-x-auto rounded-lg bg-code p-3 font-mono text-xs leading-normal text-code-fg">{pre}</pre>
              </div>
            ))}
          </div>
        </section>

        <section id="editor" className="border-t border-line py-16">
          <SectionHead title="Screenshots with an editor that opens itself" lede="Capture the screen, an area, or a window. The editor opens instantly — on a 31-megapixel Retina capture it takes 80 ms — with every tool a screenshot needs." />
          <div className="grid items-center gap-7 md:grid-cols-2">
            <Image src="/assets/editor.png" alt="The screenshot editor's output: an arrow, a rectangle, a highlight band, a pixelated blur region, a text label, a numbered step badge and an ellipse drawn over a capture" width={1600} height={1034} className="w-full rounded-[10px] border border-line" />
            <div className="min-w-0">
              <h3 className="text-xl font-semibold">Arrows, boxes, blur, text, numbers, crop</h3>
              <ul className="mt-3.5 grid gap-2 text-base text-fg-2 [&_li]:break-words [&_li::before]:mr-2 [&_li::before]:text-accent [&_li::before]:content-['—']">
                <li>Single-key tools: <kbd>A</kbd> arrow <kbd>R</kbd> rect <kbd>O</kbd> ellipse <kbd>B</kbd> blur <kbd>T</kbd> text <kbd>N</kbd> number <kbd>C</kbd> crop</li>
                <li><strong className="text-fg">Copy Text</strong> runs OCR over the whole screenshot</li>
                <li>Colour picker: click any pixel, its hex is copied</li>
                <li>Pin any screenshot above every window</li>
                <li>Window captures with a transparent, solid, gradient or trimmed background</li>
                <li>PNG or JPEG, any folder, optional 1× downscale of Retina captures</li>
                <li>Zoom ⌘+ / ⌘− / ⌘0 · <kbd>⏎</kbd> Done = save, copy to clipboard, close</li>
              </ul>
            </div>
          </div>
        </section>

        <section id="compare" className="border-t border-line py-16">
          <SectionHead title="Dolly against Movavi Screen Recorder" lede="An honest comparison. Movavi is a mature product with things this app doesn't have yet; the table says which." />
          <div className="overflow-x-auto rounded-[10px] border border-line">
            <table className="w-full min-w-[620px] border-collapse bg-card text-[15.5px]">
              <thead><tr>{["Capability", "Dolly", "Movavi Screen Recorder"].map((h) => <th key={h} className="border-b border-line px-3.5 py-3 text-left font-mono text-xs font-medium uppercase tracking-[.06em] text-fg-2">{h}</th>)}</tr></thead>
              <tbody>
                {compare.map(([c, a, at, b, bt]) => (
                  <tr key={c}>
                    <td className="border-b border-line px-3.5 py-3 align-top">{c}</td>
                    <td className={`border-b border-line px-3.5 py-3 align-top ${tone[at]}`}>{a}</td>
                    <td className={`border-b border-line px-3.5 py-3 align-top ${tone[bt]}`}>{b}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        <section id="install" className="border-t border-line py-16">
          <SectionHead title="Install in a minute" lede="Signed locally rather than notarised by Apple, so the first launch needs one extra click. Everything runs on your Mac; nothing is uploaded." />
          <div className="grid gap-7 md:grid-cols-2">
            <ol className="grid list-decimal gap-3 pl-5 text-[16.5px]">
              <li><strong><a href="https://github.com/rahulpatel84/dolly/releases/download/v0.2.1/Dolly-0.2.1.dmg" className="underline decoration-accent underline-offset-2">Download Dolly-0.2.1.dmg</a></strong> (1.3 MB), open it, and drag <strong>Dolly</strong> onto the Applications shortcut. If you launch it from Downloads instead, it offers to move itself.</li>
              <li><strong>First launch:</strong> right-click the app → <strong>Open</strong> → Open. Once.</li>
              <li><strong>Grant Screen Recording</strong> in System Settings → Privacy &amp; Security, then <strong>quit and reopen the app</strong> — macOS does not apply the grant to a running process.</li>
              <li>Press <kbd>⌃⌘R</kbd> to record, <kbd>⌃⌘S</kbd> for a screenshot, <kbd>⌘R</kbd> for the Recordings window.</li>
            </ol>
            <div>
              <div className="rounded-r-lg border-l-[3px] border-accent bg-card px-4 py-3 text-[15.5px] text-fg-2">Recordings and screenshots go to <code>~/Movies/Screen Recordings</code>. Uninstall by dragging the app to the Trash; your files stay.</div>
              <p className="mt-4 text-[15.5px] text-fg-2">Source and releases are on <a href="https://github.com/rahulpatel84/dolly" className="underline decoration-accent underline-offset-2">GitHub</a>. Build it yourself with <code>build.sh --release</code>; the Install Guide and the full <a href="/guide" className="underline decoration-accent underline-offset-2">User Guide</a> are included inside the image.</p>
            </div>
          </div>
        </section>

        <section id="faq" className="border-t border-line py-16">
          <h2 className="mb-6 text-[clamp(28px,3.4vw,40px)] font-semibold leading-[1.1]">Questions</h2>
          <div className="border-b border-line">
            {faq.map(([q, a], i) => (
              <details key={q} open={i === 0} className="group border-t border-line py-3.5">
                <summary className="flex cursor-pointer justify-between gap-3 font-display text-lg font-semibold after:font-mono after:text-accent after:content-['+'] group-open:after:content-['–']">{q}</summary>
                <p className="mt-2.5 max-w-[62em] text-fg-2">{a}</p>
              </details>
            ))}
          </div>
        </section>
      </main>
      <footer className="mx-auto flex max-w-[1120px] flex-wrap justify-between gap-4 border-t border-line px-5 py-9 text-[14.5px] text-fg-2">
        <span>Dolly 0.2.1 · Developed by Rahul Patel</span><span>macOS 14 Sonoma or later</span>
      </footer>
    </>
  );
}
