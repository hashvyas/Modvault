import type { Metadata } from "next";
import "./globals.css";
import { Geist } from "next/font/google";
import { cn } from "@/lib/utils";
import { Navbar } from "@/components/navbar";

const geist = Geist({ subsets: ["latin"], variable: "--font-sans" });

export const metadata: Metadata = {
  title: "ModVault - Mod Compatibility Intelligence",
  description:
    "Pre-flight mod compatibility checker and semantic discovery for Skyrim SE, Fallout 4, and Stardew Valley.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={cn("dark font-sans", geist.variable)} style={{ colorScheme: "dark" }}>
      <body className="min-h-screen bg-background text-foreground antialiased flex flex-col">
        <Navbar />
        <div className="flex-1">{children}</div>
      </body>
    </html>
  );
}
