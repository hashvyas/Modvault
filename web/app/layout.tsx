import type { Metadata } from "next";
import "./globals.css";
import { JetBrains_Mono } from "next/font/google";
import { cn } from "@/lib/utils";
import { Navbar } from "@/components/navbar";

const mono = JetBrains_Mono({ subsets: ["latin"], weight: "400", variable: "--font-sans" });

export const metadata: Metadata = {
  title: "ModVault",
  description: "Pre-flight mod compatibility checks and hybrid search for Skyrim SE, Fallout 4 and Stardew Valley.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={cn("dark font-sans", mono.variable)} style={{ colorScheme: "dark" }}>
      <body className="min-h-screen bg-background text-foreground antialiased flex flex-col">
        <Navbar />
        <div className="flex-1">{children}</div>
      </body>
    </html>
  );
}
