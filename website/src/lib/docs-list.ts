export type DocPage = { slug: string; title: string; group: string; description: string };

export const DOCS: DocPage[] = [
  { slug: "introduction", title: "Introduction", group: "Getting started", description: "What Dolly is, how it works, and what it is not." },
  { slug: "install", title: "Install", group: "Getting started", description: "Download the disk image, move Dolly to Applications, first launch." },
  { slug: "permissions", title: "Permissions", group: "Getting started", description: "Screen Recording, Microphone and Camera: what is asked, when, and how to fix it." },
  { slug: "recording", title: "Recording", group: "Using Dolly", description: "Full screen, area, window, webcam and audio-only; pause, draw, schedule." },
  { slug: "auto-zoom", title: "Auto-Zoom polish", group: "Using Dolly", description: "Turn a raw recording into a produced video automatically." },
  { slug: "dashboard", title: "Dashboard", group: "Using Dolly", description: "Browse, play, trim, export and share everything you have captured." },
  { slug: "screenshots", title: "Screenshots", group: "Using Dolly", description: "Capture a screen, an area or a window; what happens after." },
  { slug: "editor", title: "Screenshot editor", group: "Using Dolly", description: "Annotate, blur, crop, OCR, style with a macOS frame, export in six formats." },
  { slug: "settings", title: "Settings", group: "Reference", description: "Every option in the five Settings tabs." },
  { slug: "hotkeys", title: "Hotkeys", group: "Reference", description: "Default shortcuts and how to change them." },
  { slug: "troubleshooting", title: "Troubleshooting", group: "Reference", description: "Black recordings, missing audio, hotkeys that do nothing, logs." },
  { slug: "faq", title: "FAQ", group: "Reference", description: "Pricing, privacy, platforms, roadmap." },
];
