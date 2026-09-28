// Public configuration only. Provider credentials remain on the existing API.
const base = (import.meta.env.VITE_API_URL || "").replace(/\/$/, "");
let sessionToken: string | null = null;
export function setSessionToken(token: string | null) {
  sessionToken = token;
}
export async function api<T>(
  path: string,
  body?: unknown,
  signal?: AbortSignal,
  idempotencyKey?: string,
): Promise<T> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "X-Request-Id": crypto.randomUUID(),
  };
  if (idempotencyKey) headers["Idempotency-Key"] = idempotencyKey;
  if (sessionToken) headers.Authorization = `Bearer ${sessionToken}`;
  else if (import.meta.env.DEV) headers.Authorization = "Dev traveler-web";
  let response: Response;
  try {
    response = await fetch(base + path, {
      method: body === undefined ? "GET" : "POST",
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: signal
        ? AbortSignal.any([signal, AbortSignal.timeout(60000)])
        : AbortSignal.timeout(60000),
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError")
      throw error;
    throw new Error(
      "The travel service is unavailable. Your saved trip is still here. Try again when the service is connected.",
    );
  }
  const data = await response.json().catch(() => null);
  if (!response.ok)
    throw new Error(
      typeof data?.detail === "string"
        ? data.detail
        : (data?.detail?.message ??
            data?.message ??
            "The travel service could not complete that request. Please try again."),
    );
  if (data === null)
    throw new Error(
      "The travel service returned an empty response. Please try again.",
    );
  return data as T;
}
