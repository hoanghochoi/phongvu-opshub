import fs from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import path from 'node:path';
import tls from 'node:tls';
import { fileURLToPath } from 'node:url';

const port = Number(process.env.PORT || 8765);
const host = process.env.HOST || '127.0.0.1';
const upstreamHost = process.env.OPSHUB_SMOKE_HOST || 'opshub.hoanghochoi.com';
const upstreamProtocol = process.env.OPSHUB_SMOKE_PROTOCOL || 'https:';
const upstreamPort = Number(
  process.env.OPSHUB_SMOKE_PORT || (upstreamProtocol === 'https:' ? 443 : 80),
);
const workspace = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const webRoot = path.join(workspace, 'build', 'web');

const contentTypes = new Map([
  ['.css', 'text/css; charset=utf-8'],
  ['.html', 'text/html; charset=utf-8'],
  ['.ico', 'image/x-icon'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.json', 'application/json; charset=utf-8'],
  ['.png', 'image/png'],
  ['.svg', 'image/svg+xml'],
  ['.wasm', 'application/wasm'],
  ['.webmanifest', 'application/manifest+json'],
  ['.woff2', 'font/woff2'],
]);

function upstreamHeaders(request) {
  const hostHeader =
    (upstreamProtocol === 'https:' && upstreamPort === 443) ||
    (upstreamProtocol === 'http:' && upstreamPort === 80)
      ? upstreamHost
      : `${upstreamHost}:${upstreamPort}`;
  const headers = { ...request.headers, host: hostHeader };
  delete headers.origin;
  delete headers.referer;
  return headers;
}

function proxyApi(request, response) {
  const client = upstreamProtocol === 'https:' ? https : http;
  const upstream = client.request(
    {
      hostname: upstreamHost,
      port: upstreamPort,
      path: request.url,
      method: request.method,
      headers: upstreamHeaders(request),
    },
    (upstreamResponse) => {
      response.writeHead(upstreamResponse.statusCode || 502, upstreamResponse.headers);
      upstreamResponse.pipe(response);
    },
  );
  upstream.on('error', (error) => {
    response.writeHead(502, { 'content-type': 'application/json; charset=utf-8' });
    response.end(JSON.stringify({ message: 'Proxy request failed', error: error.message }));
  });
  request.pipe(upstream);
}

function serveWeb(request, response) {
  const url = new URL(request.url, `http://${host}:${port}`);
  const relativePath = decodeURIComponent(url.pathname).replace(/^\/+/, '');
  let filePath = path.resolve(webRoot, relativePath || 'index.html');
  const relativeToRoot = path.relative(webRoot, filePath);
  if (relativeToRoot.startsWith('..') || path.isAbsolute(relativeToRoot)) {
    response.writeHead(403).end('Forbidden');
    return;
  }
  if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    filePath = path.join(webRoot, 'index.html');
  }
  response.writeHead(200, {
    'cache-control': 'no-store',
    'content-type': contentTypes.get(path.extname(filePath)) || 'application/octet-stream',
  });
  fs.createReadStream(filePath).pipe(response);
}

function proxyWebSocket(request, socket, head) {
  const upstreamSocket =
    upstreamProtocol === 'https:'
      ? tls.connect(upstreamPort, upstreamHost, { servername: upstreamHost })
      : net.connect(upstreamPort, upstreamHost);

  const readyEvent = upstreamProtocol === 'https:' ? 'secureConnect' : 'connect';
  upstreamSocket.once(readyEvent, () => {
    const headers = upstreamHeaders(request);
    const headerLines = Object.entries(headers)
      .filter(([, value]) => value !== undefined)
      .flatMap(([name, value]) =>
        Array.isArray(value)
          ? value.map((item) => `${name}: ${item}`)
          : [`${name}: ${value}`],
      );
    upstreamSocket.write(
      [`GET ${request.url} HTTP/1.1`, ...headerLines, '', ''].join('\r\n'),
    );
    if (head.length > 0) {
      upstreamSocket.write(head);
    }
    upstreamSocket.pipe(socket);
    socket.pipe(upstreamSocket);
  });

  upstreamSocket.on('error', () => socket.destroy());
  socket.on('error', () => upstreamSocket.destroy());
}

if (!fs.existsSync(webRoot)) {
  console.error(
    `Missing ${webRoot}. Run flutter build web with API_BASE_URL=http://${host}:${port}/api first.`,
  );
  process.exit(1);
}

const server = http.createServer((request, response) => {
  if (request.url?.startsWith('/api/')) {
    proxyApi(request, response);
    return;
  }
  serveWeb(request, response);
});

server.on('upgrade', (request, socket, head) => {
  if (request.url?.startsWith('/ws')) {
    proxyWebSocket(request, socket, head);
    return;
  }
  socket.destroy();
});

server.listen(port, host, () => {
  process.stdout.write(
    `OpsHub web smoke proxy listening on http://${host}:${port} -> ${upstreamHost}\n`,
  );
});
