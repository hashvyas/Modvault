import type { NextConfig } from "next";
import path from "path";

// Next only reads .env files from web/, but this project keeps its .env in the repo root.
// Loading it here makes JWT_SECRET visible to the Edge middleware too. Existing variables win.
try {
  process.loadEnvFile(path.resolve(process.cwd(), "../.env"));
} catch {
  // No root .env (CI, Docker): rely on the real environment.
}

const nextConfig: NextConfig = {
  output: "standalone",
  serverExternalPackages: ["@huggingface/transformers"],
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "X-Frame-Options", value: "DENY" },
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
        ],
      },
    ];
  },
};

export default nextConfig;
