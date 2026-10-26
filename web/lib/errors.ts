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

export const GENERIC_ERROR_MESSAGE = 'Something went wrong. Please try again.';

/**
 * Returns text that is safe to show in the browser: the human text of a MODVAULT error,
 * otherwise a generic message. Non-MODVAULT errors (raw Postgres text, stacks) are only logged.
 */
export function formatErrorMessage(error: unknown): string {
  const parsed = parseModvaultError(error);
  if (parsed) {
    return parsed.message;
  }
  console.error(error);
  return GENERIC_ERROR_MESSAGE;
}
