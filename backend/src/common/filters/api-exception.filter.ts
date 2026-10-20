import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  Logger,
} from '@nestjs/common';
import { Request, Response } from 'express';
import { Prisma } from '../../generated/prisma/client';
import { isTransactionConflict } from '../transaction';
@Catch()
export class ApiExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger('HTTP');
  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp(),
      request = ctx.getRequest<Request>(),
      response = ctx.getResponse<Response>();
    let status = 500,
      code = 'INTERNAL_ERROR',
      message: string | string[] = 'Unable to complete the request';
    if (exception instanceof HttpException) {
      status = exception.getStatus();
      const data = exception.getResponse();
      const body =
        typeof data === 'object'
          ? (data as { message?: string | string[]; code?: string })
          : { message: data };
      code =
        body.code ??
        {
          400: 'VALIDATION_ERROR',
          401: 'AUTH_REQUIRED',
          403: 'FORBIDDEN',
          404: 'NOT_FOUND',
          409: 'CONFLICT',
          413: 'PAYLOAD_TOO_LARGE',
          429: 'RATE_LIMITED',
          503: 'SERVICE_UNAVAILABLE',
        }[status] ??
        'REQUEST_FAILED';
      // Nest wraps JSON parser SyntaxError as an un-coded BadRequestException.
      // Its message may contain request bytes (including a submitted password).
      // Keep structured validation arrays and explicit application codes, but
      // never echo an unstructured 400 message from middleware.
      message =
        status === 400 && !body.code && typeof body.message === 'string'
          ? 'Invalid request data'
          : (body.message ?? 'Request failed');
    } else if (
      exception instanceof Error &&
      'type' in exception &&
      exception.type === 'entity.too.large' &&
      'status' in exception &&
      exception.status === 413
    ) {
      // Express body-parser errors occur before controller validation. Do not
      // echo their message/body or treat an arbitrary error.status as trusted.
      status = 413;
      code = 'PAYLOAD_TOO_LARGE';
      message = 'Request body exceeds the allowed size';
    } else if (isTransactionConflict(exception)) {
      status = 409;
      code = 'VERSION_CONFLICT';
      message = 'Please retry the operation';
    } else if (exception instanceof Prisma.PrismaClientKnownRequestError) {
      if (exception.code === 'P2003') {
        status = 400;
        code = 'INVALID_REFERENCE';
        message = 'A referenced record does not exist or is still in use';
      }
      if (exception.code === 'P2002') {
        status = 409;
        code = 'CONFLICT';
        message = 'A record already exists';
      }
      if (exception.code === 'P2025') {
        status = 404;
        code = 'NOT_FOUND';
        message = 'Record not found';
      }
    }
    const requestId = response.getHeader('x-request-id');
    if (status >= 500)
      this.logger.error(
        JSON.stringify({
          requestId,
          status,
          type: exception instanceof Error ? exception.name : 'UnknownError',
        }),
      );
    response.status(status).json({
      error: {
        code,
        message,
        retryable: status >= 500 || status === 429,
        requestId,
      },
      path: request.path,
    });
  }
}
