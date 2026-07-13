import {
  HttpResponseTooLargeError,
  readBoundedHttpResponse,
} from './bounded-http-response';

describe('readBoundedHttpResponse', () => {
  it('returns a response body within the configured limit', async () => {
    const response = new Response('hello');

    await expect(readBoundedHttpResponse(response, 5)).resolves.toEqual(
      Buffer.from('hello'),
    );
  });

  it('rejects a declared response that is too large before reading it', async () => {
    const response = new Response('ignored', {
      headers: { 'content-length': '100' },
    });

    await expect(readBoundedHttpResponse(response, 10)).rejects.toBeInstanceOf(
      HttpResponseTooLargeError,
    );
  });

  it('rejects a chunked response once the streamed limit is exceeded', async () => {
    const response = new Response(
      new ReadableStream({
        start(controller) {
          controller.enqueue(new Uint8Array([1, 2, 3]));
          controller.enqueue(new Uint8Array([4, 5, 6]));
          controller.close();
        },
      }),
    );

    await expect(readBoundedHttpResponse(response, 5)).rejects.toMatchObject({
      name: 'HttpResponseTooLargeError',
      maxBytes: 5,
    });
  });
});
