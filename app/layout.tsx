import type { Metadata } from "next";
import "@fontsource/ibm-plex-serif/400.css";
import "@fontsource/ibm-plex-serif/500.css";
import "@fontsource-variable/inter";
import "./globals.css";
import "./evertally.css";
import "./evertally-community-design.css";

export const metadata: Metadata = {
  title: "Evertally — dungeon history, world atlas and rankings for WoW Forever",
  description: "Track your dungeon runs, build a shared world atlas and compare results with other WoW Forever players. The addon works on its own; the website is opt-in.",
  icons: {
    icon: "/favicon.svg",
    shortcut: "/favicon.svg",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
