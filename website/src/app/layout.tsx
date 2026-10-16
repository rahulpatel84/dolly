import type { Metadata } from "next";
import { ThemeProvider } from "next-themes";
import "./globals.css";

const FONTS = "https://fonts.googleapis.com/css2?family=Familjen+Grotesk:wght@500;600;700&family=Source+Sans+3:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap";

export const metadata: Metadata = {
  title: "Dolly · The screen recorder that follows you",
  description: "Dolly is a macOS screen recorder that records clean and polishes afterwards: auto-zoom, click rings, webcam picture-in-picture, silence removal, and a screenshot editor with OCR. By Rahul Patel.",
  openGraph: { title: "Dolly · The screen recorder that follows you", description: "Record clean. Polish after.", images: ["/assets/polish.png"] },
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
