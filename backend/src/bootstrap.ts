import { INestApplication, Logger, ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { Request, Response, NextFunction } from 'express';
import { randomUUID } from 'node:crypto';
import helmet from 'helmet';
import { ApiExceptionFilter } from './common/filters/api-exception.filter';
export function configureApp(app: INestApplication) {
  const config = app.get(ConfigService);
  app.setGlobalPrefix('api/v1');
  app.use(helmet());
  app.enableCors({
    origin: config
      .getOrThrow<string>('CORS_ORIGINS')
      .split(',')
      .map((s) => s.trim()),
    allowedHeaders: [
      'Content-Type',
      'Authorization',
      'Idempotency-Key',
      'X-Wearly-Browser',
    ],
    exposedHeaders: ['X-Request-Id'],
    credentials: true,
  });
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );
  app.useGlobalFilters(new ApiExceptionFilter());
  const logger = new Logger('HTTP');
  app.use((req: Request, res: Response, next: NextFunction) => {
    const requestId = randomUUID(),
      start = Date.now();
    res.setHeader('x-request-id', requestId);
    res.on('finish', () =>
      logger.log(
        JSON.stringify({
          requestId,
          method: req.method,
          status: res.statusCode,
          durationMs: Date.now() - start,
        }),
      ),
    );
    next();
  });
  if (
    config.get('SWAGGER_ENABLED') === 'true' &&
    config.get('NODE_ENV') !== 'production'
  ) {
    const document = SwaggerModule.createDocument(
      app,
      new DocumentBuilder()
        .setTitle('Wearly API')
        .setVersion('1')
        .addBearerAuth()
        .build(),
    );
    SwaggerModule.setup('api/docs', app, document, {
      jsonDocumentUrl: '/api/docs-json',
    });
  }
  app.enableShutdownHooks();
}
