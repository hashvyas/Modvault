export interface AppError {
  code: string;
  message: string;
}

const MODVAULT_ERROR_REGEX = /^MODVAULT:([A-Z_]+): (.*)$/;

/**
 * Parses PostgreSQL errors matching the MODVAULT:<CODE>: <message> convention.
 */
export function parseModvaultError(error: unknown): AppError | null {
  if (!error) return null;
  const message =
    typeof error === 'string'
      ? error
      : (error as { message?: string }).message || String(error);

  const match = message.match(MODVAULT_ERROR_REGEX);
  if (match) {
    return {
      code: match[1],
      message: match[2],
    };
  }
  return null;
}

/**
 * Returns a human-friendly error message, extracting the human text from MODVAULT errors when present.
 */
export function formatErrorMessage(error: unknown): string {
  const parsed = parseModvaultError(error);
  if (parsed) {
    return parsed.message;
  }
  if (error instanceof Error) {
    return error.message;
  }
  if (typeof error === 'string') {
    return error;
  }
  return 'An unexpected error occurred.';
}
