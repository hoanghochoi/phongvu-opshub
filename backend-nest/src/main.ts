import 'dotenv/config';
import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { json, urlencoded } from 'express';
import helmet from 'helmet';
import { AppModule } from './app.module';
import {
  getPort,
  getRequestBodyLimit,
  isCorsOriginAllowed,
  validateRuntimeEnv,
} from './config/env';

async function bootstrap() {
  validateRuntimeEnv();
  const app = await NestFactory.create(AppModule);

  app.use(helmet());
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
