import 'dotenv/config';
import { Logger, ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { json, urlencoded } from 'express';
import helmet from 'helmet';
import { randomUUID } from 'crypto';
import { AppModule } from './app.module';
import {
  getPort,
  getRequestBodyLimit,
  isCorsOriginAllowed,
  validateRuntimeEnv,
} from './config/env';
import { requestPathForLog } from './request-log';

async function bootstrap() {
  validateRuntimeEnv();
  const app = await NestFactory.create(AppModule);
  const requestLogger = new Logger('HttpRequest');

  app.use(helmet());
  app.use((req: any, res: any, next: () => void) => {
    const requestId = req.headers['x-request-id']?.toString() || randomUUID();
    const startedAt = Date.now();
    req.requestId = requestId;
    res.setHeader('x-request-id', requestId);
    res.on('finish', () => {
      requestLogger.log(
        JSON.stringify({
          requestId,
          method: req.method,
          path: requestPathForLog(req),
          statusCode: res.statusCode,
          durationMs: Date.now() - startedAt,
        }),
      );
    });
    next();
  });
  app.use(json({ limit: getRequestBodyLimit() }));
  app.use(urlencoded({ extended: true, limit: getRequestBodyLimit() }));
  app.enableCors({
    credentials: true,
    origin: (
      origin: string | undefined,
      callback: (error: Error | null, allow?: boolean) => void,
    ) => {
      if (isCorsOriginAllowed(origin)) {
        callback(null, true);
        return;
      }
      callback(new Error('CORS origin not allowed'), false);
    },
  });
  app.useGlobalPipes(
    new ValidationPipe({
      forbidNonWhitelisted: true,
      transformOptions: { enableImplicitConversion: true },
      transform: true,
      whitelist: true,
    }),
  );

  await app.listen(getPort());
}
bootstrap();
