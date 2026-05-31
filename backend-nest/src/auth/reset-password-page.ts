type ResetPasswordPageOptions = {
  token?: string;
  status?: 'error' | 'success';
  message?: string;
  showForm?: boolean;
};

export function resetPasswordPageHtml(
  options: ResetPasswordPageOptions = {},
): string {
  const token = escapeHtml(options.token || '');
  const message = options.message ? escapeHtml(options.message) : '';
  const statusClass = options.status ? ` status-${options.status}` : '';
  const showForm = options.showForm ?? Boolean(options.token);

  return `<!doctype html>
<html lang="vi">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Đổi mật khẩu OpsHub</title>
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
    .status { margin: 16px 0 0; min-height: 22px; font-weight: 700; }
    .status-error { color: #b91c1c; }
    .status-success { color: #047857; }
    .hint { font-size: 13px; margin-top: 16px; }
  </style>
</head>
<body>
  <main>
    <h1>Đổi mật khẩu OpsHub</h1>
    <p>Nhập mật khẩu mới cho tài khoản của bạn. Link chỉ dùng một lần và sẽ hết hạn sau thời gian quy định.</p>
    ${message ? `<p class="status${statusClass}" role="status">${message}</p>` : ''}
    ${
      showForm
        ? `<form method="post" action="/reset-password" autocomplete="off">
      <input type="hidden" name="token" value="${token}" />
      <label for="newPassword">Mật khẩu mới</label>
      <input id="newPassword" name="newPassword" type="password" autocomplete="new-password" required minlength="8" />
      <label for="confirmPassword">Nhập lại mật khẩu mới</label>
      <input id="confirmPassword" name="confirmPassword" type="password" autocomplete="new-password" required minlength="8" />
      <button type="submit">Đổi mật khẩu</button>
    </form>
    <p class="hint">Mật khẩu cần có ít nhất 8 ký tự, 1 chữ HOA, 1 số và 1 ký tự đặc biệt.</p>`
        : ''
    }
  </main>
</body>
</html>`;
}

function escapeHtml(value: string) {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
