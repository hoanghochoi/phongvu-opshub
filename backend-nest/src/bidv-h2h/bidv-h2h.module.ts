import { Module } from '@nestjs/common';
import { FeatureModule } from '../feature/feature.module';
import { PaymentNotificationsModule } from '../payment-notifications/payment-notifications.module';
import { PrismaModule } from '../prisma/prisma.module';
import { BidvH2hAdminService } from './bidv-h2h-admin.service';
import { BidvH2hCryptoService } from './bidv-h2h-crypto.service';
import {
  BidvH2hAdminController,
  BidvH2hController,
} from './bidv-h2h.controller';
import { BidvH2hIngressService } from './bidv-h2h-ingress.service';
import { BidvH2hOauthService } from './bidv-h2h-oauth.service';
import { BidvH2hParser } from './bidv-h2h-parser';
import { BidvH2hProjectionWorker } from './bidv-h2h-projection.worker';
import { BidvH2hOperatingPolicy } from './bidv-h2h-operating-policy';

@Module({
  imports: [PrismaModule, FeatureModule, PaymentNotificationsModule],
  controllers: [BidvH2hController, BidvH2hAdminController],
  providers: [
    BidvH2hAdminService,
    BidvH2hCryptoService,
    BidvH2hIngressService,
    BidvH2hOauthService,
    BidvH2hParser,
    BidvH2hProjectionWorker,
    BidvH2hOperatingPolicy,
  ],
})
export class BidvH2hModule {}
