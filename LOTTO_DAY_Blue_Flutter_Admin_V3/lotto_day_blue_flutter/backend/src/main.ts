import 'reflect-metadata';
import { INestApplication, Logger, ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import helmet from 'helmet';
import { jwtSecret } from './common/auth';
import { AppModule } from './module';

/** Shared app configuration (also used by e2e tests). */
export function configureApp(app: INestApplication) {
  app.setGlobalPrefix('api/v1');
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }));
  // CSP disabled: Flutter web (CanvasKit) needs wasm + inline bootstrap; other helmet protections stay on.
  app.use(helmet({ contentSecurityPolicy: false, crossOriginEmbedderPolicy: false }));
  const origins = (process.env.CORS_ORIGINS || 'http://localhost:3001,http://localhost:8080,http://localhost:5000').split(',').map((s) => s.trim()).filter(Boolean);
  app.enableCors({ origin: origins, methods: 'GET,POST,PATCH,DELETE', allowedHeaders: 'Content-Type,Authorization' });
  return app;
}

async function bootstrap() {
  jwtSecret(); // fail fast in production without a secret
  const app = await NestFactory.create<NestExpressApplication>(AppModule);
  app.set('trust proxy', 1);
  configureApp(app);
  app.enableShutdownHooks();
  const host = process.env.HOST || (process.env.NODE_ENV === 'production' ? '0.0.0.0' : '127.0.0.1');
  const port = Number(process.env.PORT || 3000);
  await app.listen(port, host);
  new Logger('Bootstrap').log(`LOTTO DAY API on http://${host}:${port}/api/v1 (DEMO mode — real-money features locked)`);
}
if (require.main === module) bootstrap();
