import type { Metadata } from "next";
import { Bricolage_Grotesque, JetBrains_Mono } from "next/font/google";
import Script from "next/script";
import { Analytics } from "@vercel/analytics/react";
import "./globals.css";

const display = Bricolage_Grotesque({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700", "800"],
  variable: "--font-display",
  display: "swap"
});

const mono = JetBrains_Mono({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  variable: "--font-mono",
  display: "swap"
});

export const metadata: Metadata = {
  title: "MenuStat — Watch your Mac think",
  description:
    "A native macOS menu-bar monitor for Apple Silicon. CPU, unified memory, GPU, memory pressure, and fan RPM — read straight off the silicon, drawn in one panel. No dock icon. No window.",
  metadataBase: new URL("https://menustat.app"),
  openGraph: {
    title: "MenuStat — Watch your Mac think",
    description:
      "CPU, memory, GPU, pressure, and fans in a fast native macOS menu-bar panel. Built for Apple Silicon.",
    images: ["/menustat-panel.png"]
  }
};

export default function RootLayout({
  children
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${display.variable} ${mono.variable}`}
      suppressHydrationWarning
    >
      <body>
        {/* Set theme before first paint to avoid a flash of the wrong theme. */}
        <Script src="/theme-init.js" strategy="beforeInteractive" />
        {children}
        <Analytics />
      </body>
    </html>
  );
}
