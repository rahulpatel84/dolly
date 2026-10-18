// Comparison data. Values: "yes" | "no" | "part" | free text. Verified against
// public product pages in October 2026; corrections welcome via GitHub issues.
export type Cell = "yes" | "no" | "part" | string;
export type Product = { id: string; name: string; tagline: string; pricing: string; platforms: string; notes: string[] };

export const PRODUCTS: Product[] = [
  { id: "dolly", name: "Dolly", tagline: "Record, auto-polish, annotate — locally", pricing: "Free, open source", platforms: "macOS 14+",
    notes: ["Auto-Zoom from cursor telemetry, re-polishable at any time.", "Screenshot editor with OCR, macOS frame styling and six export formats.", "No account, no cloud, no telemetry leaves the Mac.", "Not notarised; scrolling capture, keystroke overlay and Windows are not shipped yet."] },
  { id: "movavi", name: "Movavi Screen Recorder", tagline: "Mainstream recorder with scheduling and webcam overlay", pricing: "Paid (subscription or lifetime licence)", platforms: "macOS, Windows",
    notes: ["Scheduled recording, keystroke and mouse display, draw-while-recording, webcam overlay.", "Screenshot tool with basic annotations; GIF export.", "No automatic zoom or silence removal; editing is in a separate Movavi product.", "Free trial adds a watermark."] },
  { id: "loom", name: "Loom", tagline: "Cloud-first async video messaging", pricing: "Free tier (limits), paid per seat", platforms: "macOS, Windows, Chrome, iOS, Android",
    notes: ["Instant shareable links, comments, viewer analytics, team workspaces.", "AI features on paid plans: filler-word and silence removal, titles, summaries.", "Recordings live in Loom's cloud; the free tier caps count and length.", "No automatic zoom; webcam bubble rather than composited PiP."] },
  { id: "cleanshot", name: "CleanShot X", tagline: "The reference screenshot tool for Mac", pricing: "Paid (one-time), optional cloud", platforms: "macOS",
    notes: ["Best-in-class screenshots: scrolling capture, OCR, pinning, annotation, backgrounds.", "Screen recording to MP4/GIF with trimming.", "No automatic zoom or silence removal; no webcam PiP composition.", "Cloud upload is optional and paid."] },
  { id: "screen-studio", name: "Screen Studio", tagline: "Beautiful auto-zoomed demos", pricing: "Paid (licence)", platforms: "macOS",
    notes: ["The product that popularised automatic zoom, cursor smoothing and background framing.", "Rich manual editing timeline for zoom and speed.", "Video only — no screenshot tooling.", "Rendering is slower on long recordings; export resolution up to 4K."] },
  { id: "shottr", name: "Shottr", tagline: "Fast, free screenshots with OCR", pricing: "Free (donation)", platforms: "macOS",
    notes: ["Scrolling capture, OCR, measurements, pinning, quick annotations.", "No video recording at all.", "Extremely light and fast."] },
  { id: "obs", name: "OBS Studio", tagline: "Open-source streaming and recording", pricing: "Free, open source", platforms: "macOS, Windows, Linux",
    notes: ["Scenes, sources, streaming, unlimited configurability.", "No editing, no screenshots, no automatic polish — raw capture.", "Significant setup for simple screen recording."] },
  { id: "quicktime", name: "QuickTime Player", tagline: "Built into macOS", pricing: "Free (included)", platforms: "macOS",
    notes: ["Zero install; basic screen and area recording; trim.", "No system audio without a third-party driver; no screenshots editor; no polish."] },
];

export type Row = { feature: string; group: string; values: Record<string, Cell> };
const yes = "yes", no = "no", part = "part";

export const ROWS: Row[] = [
  { feature: "Price", group: "Basics", values: { dolly: "Free", movavi: "Paid", loom: "Freemium", cleanshot: "Paid", "screen-studio": "Paid", shottr: "Free", obs: "Free", quicktime: "Free" } },
  { feature: "Open source", group: "Basics", values: { dolly: yes, movavi: no, loom: no, cleanshot: no, "screen-studio": no, shottr: no, obs: yes, quicktime: no } },
  { feature: "Works fully offline, no account", group: "Basics", values: { dolly: yes, movavi: yes, loom: no, cleanshot: yes, "screen-studio": yes, shottr: yes, obs: yes, quicktime: yes } },
  { feature: "Native macOS app", group: "Basics", values: { dolly: yes, movavi: yes, loom: yes, cleanshot: yes, "screen-studio": yes, shottr: yes, obs: yes, quicktime: yes } },
  { feature: "Windows", group: "Basics", values: { dolly: "In progress", movavi: yes, loom: yes, cleanshot: no, "screen-studio": no, shottr: no, obs: yes, quicktime: no } },

  { feature: "Full screen / area / window", group: "Recording", values: { dolly: yes, movavi: yes, loom: yes, cleanshot: yes, "screen-studio": yes, shottr: no, obs: yes, quicktime: part } },
  { feature: "System audio", group: "Recording", values: { dolly: yes, movavi: yes, loom: yes, cleanshot: yes, "screen-studio": yes, shottr: no, obs: yes, quicktime: no } },
  { feature: "Microphone", group: "Recording", values: { dolly: yes, movavi: yes, loom: yes, cleanshot: yes, "screen-studio": yes, shottr: no, obs: yes, quicktime: yes } },
  { feature: "Webcam", group: "Recording", values: { dolly: yes, movavi: yes, loom: yes, cleanshot: no, "screen-studio": yes, shottr: no, obs: yes, quicktime: no } },
  { feature: "4K · 60 fps · HEVC", group: "Recording", values: { dolly: yes, movavi: part, loom: part, cleanshot: part, "screen-studio": yes, shottr: no, obs: yes, quicktime: part } },
  { feature: "Pause / resume", group: "Recording", values: { dolly: yes, movavi: yes, loom: yes, cleanshot: no, "screen-studio": yes, shottr: no, obs: yes, quicktime: no } },
  { feature: "Draw on screen while recording", group: "Recording", values: { dolly: yes, movavi: yes, loom: yes, cleanshot: no, "screen-studio": no, shottr: no, obs: no, quicktime: no } },
  { feature: "Scheduled recording / auto-stop", group: "Recording", values: { dolly: yes, movavi: yes, loom: no, cleanshot: no, "screen-studio": no, shottr: no, obs: part, quicktime: no } },
  { feature: "Keystroke overlay", group: "Recording", values: { dolly: no, movavi: yes, loom: no, cleanshot: no, "screen-studio": yes, shottr: no, obs: no, quicktime: no } },

  { feature: "Automatic zoom to activity", group: "Polish", values: { dolly: yes, movavi: no, loom: no, cleanshot: no, "screen-studio": yes, shottr: no, obs: no, quicktime: no } },
  { feature: "Cursor highlight & click effects", group: "Polish", values: { dolly: yes, movavi: yes, loom: no, cleanshot: no, "screen-studio": yes, shottr: no, obs: no, quicktime: no } },
  { feature: "Silence removal", group: "Polish", values: { dolly: yes, movavi: no, loom: "Paid", cleanshot: no, "screen-studio": no, shottr: no, obs: no, quicktime: no } },
  { feature: "Background framing & padding", group: "Polish", values: { dolly: yes, movavi: no, loom: no, cleanshot: no, "screen-studio": yes, shottr: no, obs: no, quicktime: no } },
  { feature: "Webcam picture-in-picture composite", group: "Polish", values: { dolly: yes, movavi: yes, loom: part, cleanshot: no, "screen-studio": yes, shottr: no, obs: yes, quicktime: no } },
  { feature: "Re-polish without re-recording", group: "Polish", values: { dolly: yes, movavi: no, loom: no, cleanshot: no, "screen-studio": yes, shottr: no, obs: no, quicktime: no } },
  { feature: "Trim / remove section", group: "Polish", values: { dolly: yes, movavi: yes, loom: yes, cleanshot: yes, "screen-studio": yes, shottr: no, obs: no, quicktime: yes } },

  { feature: "Screenshot: screen / area / window", group: "Screenshots", values: { dolly: yes, movavi: yes, loom: part, cleanshot: yes, "screen-studio": no, shottr: yes, obs: no, quicktime: no } },
  { feature: "Annotation editor", group: "Screenshots", values: { dolly: yes, movavi: part, loom: part, cleanshot: yes, "screen-studio": no, shottr: yes, obs: no, quicktime: no } },
  { feature: "Blur / redact", group: "Screenshots", values: { dolly: yes, movavi: no, loom: no, cleanshot: yes, "screen-studio": no, shottr: yes, obs: no, quicktime: no } },
  { feature: "OCR (copy text from image)", group: "Screenshots", values: { dolly: yes, movavi: no, loom: no, cleanshot: yes, "screen-studio": no, shottr: yes, obs: no, quicktime: no } },
  { feature: "macOS-style frame & gradient background", group: "Screenshots", values: { dolly: yes, movavi: no, loom: no, cleanshot: yes, "screen-studio": no, shottr: part, obs: no, quicktime: no } },
  { feature: "Export PNG / JPEG / HEIC / WebP / PDF", group: "Screenshots", values: { dolly: yes, movavi: part, loom: part, cleanshot: part, "screen-studio": no, shottr: part, obs: no, quicktime: no } },
  { feature: "Pin on screen", group: "Screenshots", values: { dolly: yes, movavi: no, loom: no, cleanshot: yes, "screen-studio": no, shottr: yes, obs: no, quicktime: no } },
  { feature: "Scrolling capture", group: "Screenshots", values: { dolly: no, movavi: no, loom: no, cleanshot: yes, "screen-studio": no, shottr: yes, obs: no, quicktime: no } },

  { feature: "Library / dashboard", group: "Output", values: { dolly: yes, movavi: yes, loom: yes, cleanshot: part, "screen-studio": yes, shottr: no, obs: no, quicktime: no } },
  { feature: "MP4 / MOV / GIF / M4A export", group: "Output", values: { dolly: yes, movavi: yes, loom: part, cleanshot: yes, "screen-studio": yes, shottr: no, obs: part, quicktime: part } },
  { feature: "Instant share link (cloud)", group: "Output", values: { dolly: no, movavi: no, loom: yes, cleanshot: "Paid", "screen-studio": no, shottr: no, obs: no, quicktime: no } },
  { feature: "Share sheet (AirDrop, Messages, Mail…)", group: "Output", values: { dolly: yes, movavi: part, loom: part, cleanshot: yes, "screen-studio": yes, shottr: yes, obs: no, quicktime: yes } },
  { feature: "Configurable global hotkeys", group: "Output", values: { dolly: yes, movavi: yes, loom: yes, cleanshot: yes, "screen-studio": yes, shottr: yes, obs: yes, quicktime: no } },
];
