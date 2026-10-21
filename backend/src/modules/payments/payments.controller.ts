import {
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  Req,
  Res,
} from '@nestjs/common';
import { Request, Response } from 'express';
import { Public, CurrentUser, Identity } from '../../common/decorators/auth';
import { PaymentsService } from './payments.service';
@Controller('payments')
export class PaymentsController {
  constructor(private readonly service: PaymentsService) {}
  @Public() @Get('methods') methods() {
    return this.service.methods();
  }
  @Post('orders/:id/start') start(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
  ) {
    return this.service.start(u.id, id, req.ip ?? '127.0.0.1');
  }
  @Post('orders/:id/reconcile') reconcile(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.service.reconcile(u.id, id);
  }
  @Public() @Get('vnpay/ipn') ipn(@Query() query: Record<string, unknown>) {
    return this.service.ipn(query);
  }
  @Public() @Get('vnpay/return') returned(
    @Query() query: Record<string, unknown>,
    @Res() res: Response,
  ) {
    res.setHeader('Cache-Control', 'no-store');
    res.redirect(302, this.service.returnUrl(query));
  }
}
