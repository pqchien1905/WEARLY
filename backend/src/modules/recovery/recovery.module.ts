import { Module } from '@nestjs/common';
import { RecoveryService } from './recovery.service';
import { RecoveryMailer } from './recovery.mailer';
@Module({
  providers: [RecoveryService, RecoveryMailer],
  exports: [RecoveryService],
})
export class RecoveryModule {}
