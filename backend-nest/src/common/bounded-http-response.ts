export class HttpResponseTooLargeError extends Error {
  constructor(
    readonly maxBytes: number,
    readonly receivedBytes?: number,
  ) {
    super(
      receivedBytes === undefined
        ? `HTTP response exceeds the ${maxBytes}-byte limit`
        : `HTTP response exceeds the ${maxBytes}-byte limit (${receivedBytes} bytes received)`,
    );
    this.name = 'HttpResponseTooLargeError';
  }
}

export async function readBoundedHttpResponse(
  response: Response,
  maxBytes: number,
): Promise<Buffer> {
  if (!Number.isSafeInteger(maxBytes) || maxBytes <= 0) {
    throw new Error('maxBytes must be a positive safe integer');
  }

  const declaredLength = Number(response.headers?.get?.('content-length'));
  if (Number.isFinite(declaredLength) && declaredLength > maxBytes) {
    throw new HttpResponseTooLargeError(maxBytes, declaredLength);
  }

  const reader = response.body?.getReader();
  if (!reader) {
    const responseLike = response as Response & {
      arrayBuffer?: () => Promise<ArrayBuffer>;
      text?: () => Promise<string>;
    };
    const buffer = responseLike.arrayBuffer
      ? Buffer.from(await responseLike.arrayBuffer())
      : responseLike.text
        ? Buffer.from(await responseLike.text())
        : Buffer.alloc(0);
    if (buffer.length > maxBytes) {
      throw new HttpResponseTooLargeError(maxBytes, buffer.length);
    }
    return buffer;
  }

  const chunks: Buffer[] = [];
  let totalBytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value?.byteLength) continue;

      totalBytes += value.byteLength;
      if (totalBytes > maxBytes) {
        await reader.cancel().catch(() => undefined);
        throw new HttpResponseTooLargeError(maxBytes, totalBytes);
      }
      chunks.push(Buffer.from(value));
    }
  } finally {
    reader.releaseLock();
  }

  return Buffer.concat(chunks, totalBytes);
}
