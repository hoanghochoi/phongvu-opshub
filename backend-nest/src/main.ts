import 'dotenv/config';
import { Logger, ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import helmet from 'helmet';
import { randomUUID } from 'crypto';
import { AppModule } from './app.module';
import {
  getPort,
  getRequestBodyLimit,
  isCorsOriginAllowed,
  validateRuntimeEnv,
} from './config/env';
import { registerRequestBodyParsers } from './request-body-parsers';
import { requestPathForLog } from './request-log';

async function bootstrap() {
  validateRuntimeEnv();
  const app = await NestFactory.create<NestExpressApplication>(AppModule);
  const requestLogger = new Logger('HttpRequest');

  // The API is reached through exactly one trusted Caddy reverse-proxy hop.
  app.set('trust proxy', 1);
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
  registerRequestBodyParsers(app, getRequestBodyLimit());
  app.enableCors({
    credentials: false,
    origin: (
      origin: string | undefined,
      callback: (error: Error | null, allow?: boolean) => void,
    ) => {
      if (isCorsOriginAllowed(origin)) {
        callback(null, true);
        return;
      }
      callback(null, false);
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
