export function isSupportChatEnabled(
  env: Record<string, string | undefined> = process.env,
) {
  return env.SUPPORT_CHAT_ENABLED?.trim().toLowerCase() === 'true';
}
