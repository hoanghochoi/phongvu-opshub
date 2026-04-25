import 'dotenv/config';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { getPort, validateRuntimeEnv } from './config/env';

async function bootstrap() {
  validateRuntimeEnv();
  const app = await NestFactory.create(AppModule);
  await app.listen(getPort());
}
bootstrap();
