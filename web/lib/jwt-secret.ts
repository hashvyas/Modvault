// Shared by lib/session.ts (Node) and middleware.ts (Edge), so it must stay free of Node-only imports.
export function getJwtSecretKey(): Uint8Array {
  const secret = process.env.JWT_SECRET;
  if (!secret || secret.length < 32) {
    throw new Error(
      'JWT_SECRET is unset or shorter than 32 characters. Set it in the environment (generate one with: openssl rand -hex 32).'
    );
  }
  return new TextEncoder().encode(secret);
}
