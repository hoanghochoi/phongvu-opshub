# ZXing web runtime

`zxing-library-0.21.3.min.js` is the pinned UMD bundle loaded by
`mobile_scanner` on Flutter web. OpsHub serves it from the same origin so the
camera scanner works with the production `script-src 'self'` policy and does
not depend on a third-party CDN at runtime.

- Package: `@zxing/library@0.21.3`
- Source: `https://unpkg.com/@zxing/library@0.21.3/umd/index.min.js`
- SHA-256: `d7cc8f69dd70bdcf3ac00c9ae572bf2acb9f4132ba379c72df842e4db918652d`
- License: Apache-2.0; see `zxing-LICENSE.txt`
