import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from '../app.module';
import { SupportChatRetentionWorker } from './support-chat-retention.worker';

const logger = new Logger('SupportChatPurgeCommand');
const MAX_BATCHES = 10_000;

async function main() {
  const app = await NestFactory.createApplicationContext(AppModule, {
    logger: ['error', 'warn', 'log'],
  });
  try {
    const worker = app.get(SupportChatRetentionWorker, { strict: false });
    for (let batch = 1; batch <= MAX_BATCHES; batch += 1) {
      const result = await worker.purgeExpired();
      if (!result) {
        throw new Error('support_chat_retention_lock_unavailable');
      }
      const changed =
        result.messageCount +
        result.auditCount +
        result.outboxCount +
        result.conversationCount +
        result.mediaIds.length;
      logger.log(
        `Support chat restore purge batch completed: batch=${batch} changed=${changed}`,
      );
      if (changed === 0) return;
    }
    throw new Error('support_chat_retention_batch_limit_exceeded');
  } finally {
    await app.close();
  }
}

void main().catch((error: unknown) => {
  logger.error(
    `Support chat restore purge failed: errorType=${
      error instanceof Error ? error.name : 'UnknownError'
    }`,
  );
  process.exitCode = 1;
});
