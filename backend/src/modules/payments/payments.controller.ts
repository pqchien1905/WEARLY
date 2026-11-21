import {
  Body,
  Controller,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  Req,
  Res,
} from '@nestjs/common';
import { Request, Response } from 'express';
import { Public, CurrentUser, Identity } from '../../common/decorators/auth';
import { PaymentsService } from './payments.service';
import { ChangeOrderPaymentDto } from '../orders/dto/order.dto';
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
  @Patch('orders/:id/method') changeMethod(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ChangeOrderPaymentDto,
  ) {
    return this.service.changeMethod(u.id, id, dto.paymentMethod);
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
  @Public() @Get('vnpay/return') async returned(
    @Query() query: Record<string, unknown>,
    @Res() res: Response,
  ) {
    res.setHeader('Cache-Control', 'no-store');
    res.redirect(302, await this.service.returnUrl(query));
  }
  /** MoMo expects 204 once handled; any other status makes it retry. */
  @Public() @Post('momo/ipn') async momoIpn(
    @Body() body: unknown,
    @Res() res: Response,
  ) {
    const result = await this.service.walletNotification('momo', body);
    res.status(result === null ? 400 : result === '99' ? 500 : 204).end();
  }
  /** ZaloPay: return_code 1 = handled, -1 = invalid MAC, 0 = retry later. */
  @Public() @Post('zalopay/callback') @HttpCode(200) async zalopayCallback(
    @Body() body: unknown,
  ) {
    const result = await this.service.walletNotification('zalopay', body);
    if (result === null)
      return { return_code: -1, return_message: 'mac not equal' };
    if (result === '99') return { return_code: 0, return_message: 'retry' };
    return { return_code: 1, return_message: 'success' };
  }
  @Public() @Get(['momo/return', 'zalopay/return']) async walletReturned(
    @Query() query: Record<string, unknown>,
    @Res() res: Response,
  ) {
    res.setHeader('Cache-Control', 'no-store');
    res.redirect(302, await this.service.walletReturnUrl(query));
  }
}
