import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { Response } from 'express';
import { RuleError } from './rules';

/** Maps domain/Prisma errors to consistent JSON: { statusCode, message, error }. */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly log = new Logger('Exceptions');
  catch(exception: unknown, host: ArgumentsHost) {
    const res = host.switchToHttp().getResponse<Response>();
    let status = HttpStatus.INTERNAL_SERVER_ERROR;
    let message: string | string[] = 'เกิดข้อผิดพลาดภายในระบบ';
    if (exception instanceof HttpException) {
      status = exception.getStatus();
      const body = exception.getResponse();
      message = typeof body === 'string' ? body : ((body as { message?: string | string[] }).message ?? exception.message);
    } else if (exception instanceof RuleError) {
      status = exception.kind === 'conflict' ? 409 : exception.kind === 'forbidden' ? 403 : 400;
      message = exception.message;
    } else if (exception instanceof Prisma.PrismaClientKnownRequestError) {
      if (exception.code === 'P2002') { status = 409; message = 'ข้อมูลซ้ำกับที่มีอยู่แล้ว (duplicate)'; }
      else if (exception.code === 'P2025') { status = 404; message = 'ไม่พบข้อมูล'; }
      else this.log.error(exception);
    } else {
      this.log.error(exception);
    }
    res.status(status).json({ statusCode: status, message, error: HttpStatus[status] ?? 'Error' });
  }
}
