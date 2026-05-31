export function resetPasswordPageHtml(): string {
  return `<!doctype html>
<html lang="vi">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Doi mat khau OpsHub</title>
  <style>
    :root { color-scheme: light; font-family: Inter, Arial, sans-serif; }
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      background: linear-gradient(135deg, #0f766e, #2563eb);
      color: #111827;
    }
    main {
      width: min(420px, calc(100vw - 32px));
      background: #ffffff;
      border-radius: 8px;
      padding: 28px;
      box-shadow: 0 24px 70px rgba(15, 23, 42, 0.28);
    }
    h1 { margin: 0 0 8px; font-size: 24px; line-height: 1.2; }
    p { margin: 0 0 20px; color: #4b5563; line-height: 1.45; }
    label { display: block; margin: 14px 0 6px; font-weight: 700; }
    input {
      width: 100%;
      box-sizing: border-box;
      border: 1px solid #d1d5db;
      border-radius: 8px;
      padding: 12px;
      font: inherit;
    }
    input:focus { outline: 3px solid rgba(37, 99, 235, 0.18); border-color: #2563eb; }
    button {
      width: 100%;
      margin-top: 18px;
      border: 0;
      border-radius: 8px;
      padding: 13px 16px;
      background: #0f766e;
      color: #ffffff;
      font-weight: 800;
      cursor: pointer;
    }
    button:disabled { opacity: 0.65; cursor: progress; }
    .status { margin-top: 14px; min-height: 22px; font-weight: 700; }
    .error { color: #b91c1c; }
    .success { color: #047857; }
    .hint { font-size: 13px; margin-top: 16px; }
  </style>
</head>
<body>
  <main>
    <h1>Doi mat khau OpsHub</h1>
    <p>Nhap mat khau moi cho tai khoan cua ban. Link chi dung mot lan va se het han sau thoi gian quy dinh.</p>
    <form id="reset-form">
      <label for="password">Mat khau moi</label>
      <input id="password" name="password" type="password" autocomplete="new-password" required minlength="8" />
      <label for="confirm-password">Nhap lai mat khau moi</label>
      <input id="confirm-password" name="confirm-password" type="password" autocomplete="new-password" required minlength="8" />
      <button id="submit-button" type="submit">Doi mat khau</button>
      <div id="status" class="status" role="status" aria-live="polite"></div>
    </form>
    <p class="hint">Mat khau can co it nhat 8 ky tu, 1 chu HOA, 1 so va 1 ky tu dac biet.</p>
  </main>
  <script>
    const token = new URLSearchParams(window.location.search).get('token') || '';
    const form = document.getElementById('reset-form');
    const statusEl = document.getElementById('status');
    const button = document.getElementById('submit-button');

    function setStatus(message, className) {
      statusEl.textContent = message;
      statusEl.className = 'status ' + className;
    }

    async function postReset(endpoint, payload) {
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });
      if (response.status === 404) return { retry: true };
      const body = await response.json().catch(() => ({}));
      if (!response.ok) {
        const message = Array.isArray(body.message) ? body.message.join('\n') : body.message;
        throw new Error(message || 'Khong doi duoc mat khau.');
      }
      return { ok: true };
    }

    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      if (!token) {
        setStatus('Link doi mat khau khong hop le.', 'error');
        return;
      }
      const newPassword = document.getElementById('password').value;
      const confirmPassword = document.getElementById('confirm-password').value;
      if (newPassword !== confirmPassword) {
        setStatus('Mat khau nhap lai chua khop.', 'error');
        return;
      }
      button.disabled = true;
      setStatus('Dang doi mat khau...', '');
      try {
        const payload = { token, newPassword };
        const primary = await postReset('/api/auth/reset-password', payload);
        if (primary.retry) await postReset('/auth/reset-password', payload);
        setStatus('Da doi mat khau. Ban co the quay lai ung dung de dang nhap.', 'success');
        form.reset();
      } catch (error) {
        setStatus(error.message || 'Khong doi duoc mat khau.', 'error');
      } finally {
        button.disabled = false;
      }
    });
  </script>
</body>
</html>`;
}
