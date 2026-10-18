import type { Metadata } from "next";
import { ThemeProvider } from "next-themes";
import "./globals.css";

const FONTS = "https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap";

export const metadata: Metadata = {
  metadataBase: new URL("https://screen-recorder-site.vercel.app"),
  title: { default: "Dolly — Screen recorder for macOS with automatic zoom", template: "%s · Dolly" },
  description: "Dolly records your Mac screen, system audio, mic and webcam, then polishes the result automatically: smooth zoom to where you work, cursor emphasis, silence removal. Screenshots with a full annotation editor. Free and open source.",
  openGraph: { title: "Dolly — Screen recorder for macOS", description: "Record, polish automatically, annotate, export. Free and open source.", type: "website" },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link rel="stylesheet" href={FONTS} />
      </head>
      <body>
        <ThemeProvider attribute="class" defaultTheme="system" enableSystem disableTransitionOnChange>
          {children}
        </ThemeProvider>
      </body>
    </html>
  );
}
