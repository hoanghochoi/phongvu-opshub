import {
  BadRequestException,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { createHash, randomBytes } from 'node:crypto';

export type SalesReportErpOrderItem = {
  sku: string | null;
  sellerSku: string | null;
  name: string | null;
  brandCode: string | null;
  brandName: string | null;
  productTypeCode: string | null;
  productTypeName: string | null;
  productGroupId: string | null;
  productGroupName: string | null;
  quantity: number | null;
  sellPrice: number | null;
  finalSellPrice: number | null;
  rowTotal: number | null;
  raw: Record<string, unknown>;
};

export type SalesReportErpPayment = {
  paymentMethod: string | null;
  amount: number | null;
  paidAt: Date | null;
  transactionCode: string | null;
  partnerTransactionCode: string | null;
  raw: Record<string, unknown>;
};

export type SalesReportErpOrder = {
  orderCode: string;
  erpOrderId: string | null;
  erpExternalOrderRef: string | null;
  erpOrderCreatedAt: Date | null;
  erpPaymentStatus: string | null;
  erpConfirmationStatus: string | null;
  erpFulfillmentStatus: string | null;
  erpTerminalName: string | null;
  erpGrandTotal: number | null;
  erpPlatformId: number | null;
  erpConsultantCustomId: string | null;
  erpConsultantName: string | null;
  customerNeed: string | null;
  categoryCandidates: string[];
  items: SalesReportErpOrderItem[];
  payments: SalesReportErpPayment[];
  sanitizedSnapshot: Record<string, unknown>;
  fetchedAt: Date;
};

type CachedToken = {
  accessToken: string;
  expiresAt: number;
};

const DEFAULT_ERP_SCOPE =
  'openid profile read:permissions sellers om catalog ppm page_builder wms as fms seller-gateway ps-v2 us tenant:management notification-management-apis apl staff-bff user-segment-bff rebate-staff-bff merchant-bff ons-bff uns-bff-api ticket-bff dca payment-staff-bff lo marketing-automation-bff-api rebate-admin shopping-cart:order shopping-cart:write teko:marketing-automation-bff-api terra-staff-bff terra-staff-bff:loyalty user-segment-v2 loyalty-staff-bff loyalty-management-bff';

@Injectable()
export class SalesReportErpService {
  private readonly logger = new Logger(SalesReportErpService.name);
  private cachedToken: CachedToken | null = null;

  async lookupOrder(orderCodeInput: string, storeCode?: string | null) {
    const orderCode = this.normalizeOrderCode(orderCodeInput);
    if (!orderCode) {
      throw new BadRequestException('Vui lòng nhập mã đơn hàng.');
    }
    const startedAt = Date.now();
    this.logger.log(
      `Sales report ERP lookup started: orderLength=${orderCode.length} store=${storeCode || 'none'}`,
    );
    try {
      const accessToken = await this.getAccessToken();
      const order = await this.fetchOrder(orderCode, accessToken);
      const items = await this.normalizeItems(
        order,
        accessToken,
        storeCode ?? null,
      );
      const payments = this.normalizePayments(order?.payments);
      const result = this.normalizeOrder(orderCode, order, items, payments);
      this.logger.log(
        `Sales report ERP lookup succeeded: orderLength=${orderCode.length} itemCount=${items.length} paymentCount=${payments.length} durationMs=${Date.now() - startedAt}`,
      );
      return result;
    } catch (error) {
      if (
        error instanceof BadRequestException ||
        error instanceof ServiceUnavailableException
      ) {
        throw error;
      }
      this.logger.error(
        `Sales report ERP lookup failed: orderLength=${orderCode.length} durationMs=${Date.now() - startedAt} error=${String(error)}`,
      );
      throw new ServiceUnavailableException(
        'Chưa kiểm tra được mã đơn hàng. Vui lòng thử lại sau ít phút.',
      );
    }
  }

  private async fetchOrder(orderCode: string, accessToken: string) {
    const baseUrl = this.env(
      'ERP_STAFF_BFF_BASE_URL',
      'https://staff-bff.tekoapis.com',
    ).replace(/\/$/, '');
    const url = `${baseUrl}/api/v2/staff-admin/orders/${encodeURIComponent(
      orderCode,
    )}?thousandSeparator=%2C&decimalSeparator=.`;
    const response = await this.fetchWithTimeout(url, {
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: 'application/json',
      },
    });
    if (response.status === 404) {
      throw new BadRequestException('Không tìm thấy mã đơn hàng trên ERP.');
    }
    if (!response.ok) {
      this.logger.warn(
        `Sales report ERP order endpoint failed: status=${response.status}`,
      );
      throw new ServiceUnavailableException(
        'Chưa kiểm tra được mã đơn hàng. Vui lòng thử lại sau ít phút.',
      );
    }
    const body = (await response.json()) as any;
    const order = body?.data?.order;
    if (!order?.orderId) {
      throw new BadRequestException('Không tìm thấy mã đơn hàng trên ERP.');
    }
    return order;
  }

  private async normalizeItems(
    order: any,
    accessToken: string,
    storeCode: string | null,
  ): Promise<SalesReportErpOrderItem[]> {
    const rawItems: any[] = Array.isArray(order?.orderCaptureLineItems)
      ? order.orderCaptureLineItems
      : [];
    const productBySku = await this.fetchProducts(
      rawItems
        .map((item: any) => this.optionalText(item?.sellerSku))
        .filter((sku: string | null): sku is string => Boolean(sku)),
      accessToken,
      storeCode,
    );
    return rawItems.map((item: any) => {
      const sellerSku = this.optionalText(item?.sellerSku);
      const product = sellerSku ? productBySku.get(sellerSku) : null;
      const brand = product?.brand;
      const productType = product?.productType;
      const productGroup = product?.productGroup;
      return {
        sku: this.optionalText(product?.sku) ?? sellerSku,
        sellerSku,
        name: this.optionalText(item?.name) ?? this.optionalText(product?.name),
        brandCode: this.optionalText(brand?.code ?? brand?.id),
        brandName: this.optionalText(brand?.name ?? brand?.displayName),
        productTypeCode: this.optionalText(
          productType?.code ?? productType?.id,
        ),
        productTypeName: this.optionalText(
          productType?.name ?? productType?.displayName,
        ),
        productGroupId: this.optionalText(
          productGroup?.id ?? productGroup?.code,
        ),
        productGroupName: this.optionalText(
          productGroup?.name ?? productGroup?.displayName,
        ),
        quantity: this.toInt(item?.quantity),
        sellPrice: this.toInt(item?.sellPrice),
        finalSellPrice: this.toInt(item?.finalSellPrice),
        rowTotal: this.toInt(item?.rowTotal),
        raw: this.sanitizeItemRaw(item, product),
      };
    });
  }

  private async fetchProducts(
    sellerSkus: string[],
    accessToken: string,
    storeCode: string | null,
  ) {
    const uniqueSkus = Array.from(new Set(sellerSkus)).slice(0, 50);
    const result = new Map<string, any>();
    if (uniqueSkus.length === 0) return result;
    const baseUrl = this.env(
      'ERP_LISTING_BASE_URL',
      'https://listing.tekoapis.com',
    ).replace(/\/$/, '');
    const url = new URL(`${baseUrl}/api/products/`);
    url.searchParams.set(
      'channel',
      this.env('ERP_LISTING_CHANNEL', 'pv_showroom'),
    );
    url.searchParams.set(
      'terminal',
      storeCode || this.env('ERP_LISTING_TERMINAL', '{storeCode}'),
    );
    url.searchParams.set('skus', uniqueSkus.join(','));
    try {
      const response = await this.fetchWithTimeout(url.toString(), {
        headers: {
          Authorization: `Bearer ${accessToken}`,
          Accept: 'application/json',
        },
      });
      if (!response.ok) {
        this.logger.warn(
          `Sales report ERP product lookup skipped: status=${response.status}`,
        );
        return result;
      }
      const body = (await response.json()) as any;
      const products = Array.isArray(body?.result?.products)
        ? body.result.products
        : [];
      for (const product of products) {
        const sku = this.optionalText(product?.sku);
        if (sku) result.set(sku, product);
      }
    } catch (error) {
      this.logger.warn(
        `Sales report ERP product lookup failed but order lookup continues: error=${String(error)}`,
      );
    }
    return result;
  }

  private normalizePayments(value: unknown): SalesReportErpPayment[] {
    const payments = Array.isArray(value) ? value : [];
    return payments.map((payment) => ({
      paymentMethod: this.optionalText((payment as any)?.paymentMethod),
      amount: this.toInt((payment as any)?.amount),
      paidAt: this.parseDate((payment as any)?.paidAt),
      transactionCode: this.optionalText((payment as any)?.transactionCode),
      partnerTransactionCode: this.optionalText(
        (payment as any)?.partnerTransactionCode,
      ),
      raw: {
        paymentMethod: this.optionalText((payment as any)?.paymentMethod),
        amount: this.toInt((payment as any)?.amount),
        paidAt: this.optionalText((payment as any)?.paidAt),
      },
    }));
  }

  private normalizeOrder(
    orderCode: string,
    order: any,
    items: SalesReportErpOrderItem[],
    payments: SalesReportErpPayment[],
  ): SalesReportErpOrder {
    const fetchedAt = new Date();
    const customerNeed = items
      .map((item) => item.name)
      .filter((name): name is string => Boolean(name))
      .slice(0, 5)
      .join('; ');
    const categoryCandidates = Array.from(
      new Set(
        items
          .flatMap((item) => [
            item.productGroupId,
            item.productGroupName,
            item.productTypeName,
            item.name,
          ])
          .filter((value): value is string => Boolean(value)),
      ),
    );
    return {
      orderCode,
      erpOrderId: this.optionalText(order?.orderId),
      erpExternalOrderRef: this.optionalText(order?.externalOrderRef),
      erpOrderCreatedAt: this.parseDate(order?.createdAt),
      erpPaymentStatus: this.optionalText(order?.paymentStatus),
      erpConfirmationStatus: this.optionalText(order?.confirmationStatus),
      erpFulfillmentStatus: this.optionalText(order?.fulfillmentStatus),
      erpTerminalName: this.optionalText(order?.terminalName),
      erpGrandTotal: this.toInt(order?.grandTotal),
      erpPlatformId: this.toInt(order?.platformId),
      erpConsultantCustomId: this.optionalText(order?.consultant?.customId),
      erpConsultantName: this.optionalText(order?.consultant?.name),
      customerNeed: customerNeed || null,
      categoryCandidates,
      items,
      payments,
      sanitizedSnapshot: {
        orderId: this.optionalText(order?.orderId),
        createdAt: this.optionalText(order?.createdAt),
        paymentStatus: this.optionalText(order?.paymentStatus),
        confirmationStatus: this.optionalText(order?.confirmationStatus),
        fulfillmentStatus: this.optionalText(order?.fulfillmentStatus),
        terminalName: this.optionalText(order?.terminalName),
        createdFromSiteDisplayName: this.optionalText(
          order?.createdFromSiteDisplayName,
        ),
        externalOrderRef: this.optionalText(order?.externalOrderRef),
        grandTotal: this.toInt(order?.grandTotal),
        platformId: this.toInt(order?.platformId),
        consultant: {
          customId: this.optionalText(order?.consultant?.customId),
          name: this.optionalText(order?.consultant?.name),
        },
        itemCount: items.length,
        paymentCount: payments.length,
        items: items.map((item) => ({
          sku: item.sku,
          sellerSku: item.sellerSku,
          name: item.name,
          quantity: item.quantity,
          finalSellPrice: item.finalSellPrice,
          rowTotal: item.rowTotal,
          productGroupId: item.productGroupId,
          productGroupName: item.productGroupName,
        })),
        payments: payments.map((payment) => ({
          paymentMethod: payment.paymentMethod,
          amount: payment.amount,
          paidAt: payment.paidAt?.toISOString() ?? null,
        })),
      },
      fetchedAt,
    };
  }

  private async getAccessToken() {
    const staticToken = process.env.ERP_ACCESS_TOKEN?.trim();
    if (staticToken) return staticToken;
    const now = Date.now();
    if (this.cachedToken && this.cachedToken.expiresAt > now) {
      return this.cachedToken.accessToken;
    }
    const username = process.env.ERP_USERNAME?.trim();
    const password = process.env.ERP_PASSWORD?.trim();
    if (!username || !password) {
      throw new ServiceUnavailableException(
        'Chưa cấu hình tài khoản ERP để kiểm tra đơn hàng.',
      );
    }
    const token = await this.loginWithPassword(username, password);
    this.cachedToken = token;
    return token.accessToken;
  }

  private async loginWithPassword(
    username: string,
    password: string,
  ): Promise<CachedToken> {
    const clientId = this.env(
      'ERP_CLIENT_ID',
      '04409baea81b46e1a53e64efe0de16a5',
    );
    const redirectUri = this.env('ERP_REDIRECT_URI', 'https://erp.phongvu.vn');
    const oauthBase = this.env(
      'ERP_OAUTH_BASE_URL',
      'https://oauth-merchant.phongvu.vn',
    ).replace(/\/$/, '');
    const identityBase = this.env(
      'ERP_IDENTITY_BASE_URL',
      'https://identity.tekoapis.com',
    ).replace(/\/$/, '');
    const state = this.base64Url(randomBytes(12));
    const nonce = this.base64Url(randomBytes(12));
    const codeVerifier = this.base64Url(randomBytes(32));
    const codeChallenge = this.base64Url(
      createHash('sha256').update(codeVerifier).digest(),
    );
    const scope = this.env('ERP_SCOPE', DEFAULT_ERP_SCOPE);

    const challengeUrl = this.authorizeUrl(oauthBase, {
      clientId,
      redirectUri,
      state,
      nonce,
      scope,
      codeChallenge,
    });
    const challengeResponse = await this.fetchWithTimeout(challengeUrl, {
      redirect: 'manual',
    });
    const challengeLocation =
      challengeResponse.headers.get('location') ?? challengeResponse.url;
    const challenge = this.urlParam(challengeLocation, 'challenge');
    if (!challenge) {
      throw new ServiceUnavailableException(
        'Chưa lấy được phiên đăng nhập ERP.',
      );
    }

    const loginResponse = await this.fetchWithTimeout(
      `${identityBase}/api/v1/users/login`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
        },
        body: JSON.stringify({
          challenge,
          username,
          password,
          client_id: clientId,
        }),
      },
    );
    if (!loginResponse.ok) {
      this.logger.warn(
        `Sales report ERP login failed: status=${loginResponse.status}`,
      );
      throw new ServiceUnavailableException(
        'Tài khoản ERP chưa đăng nhập được. Vui lòng kiểm tra cấu hình.',
      );
    }
    const loginBody = (await loginResponse.json().catch(() => ({}))) as any;
    const loginVerifier =
      loginBody?.data?.login_verifier ??
      loginBody?.login_verifier ??
      loginBody?.data?.loginVerifier ??
      loginBody?.loginVerifier ??
      loginBody?.data?.verifier ??
      loginBody?.verifier;
    if (!loginVerifier) {
      throw new ServiceUnavailableException(
        'ERP chưa trả phiên xác thực hợp lệ.',
      );
    }

    const codeResponse = await this.fetchWithTimeout(
      this.authorizeUrl(oauthBase, {
        clientId,
        redirectUri,
        state,
        nonce,
        scope,
        codeChallenge,
        loginVerifier: String(loginVerifier),
      }),
      { redirect: 'manual' },
    );
    const codeLocation =
      codeResponse.headers.get('location') ?? codeResponse.url;
    const code = this.urlParam(codeLocation, 'code');
    if (!code) {
      throw new ServiceUnavailableException('ERP chưa trả mã xác thực hợp lệ.');
    }

    const tokenResponse = await this.fetchWithTimeout(
      `${oauthBase}/oauth/token`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          Accept: 'application/json',
        },
        body: new URLSearchParams({
          code,
          grant_type: 'authorization_code',
          redirect_uri: redirectUri,
          client_id: clientId,
          code_verifier: codeVerifier,
        }),
      },
    );
    if (!tokenResponse.ok) {
      this.logger.warn(
        `Sales report ERP token exchange failed: status=${tokenResponse.status}`,
      );
      throw new ServiceUnavailableException(
        'ERP chưa cấp được token kiểm tra đơn hàng.',
      );
    }
    const tokenBody = (await tokenResponse.json()) as any;
    const accessToken = String(tokenBody?.access_token || '').trim();
    if (!accessToken) {
      throw new ServiceUnavailableException('ERP chưa trả token hợp lệ.');
    }
    const expiresIn = Number(tokenBody?.expires_in || 3600);
    const safetySeconds = Number(
      process.env.ERP_TOKEN_TTL_SAFETY_SECONDS || 60,
    );
    return {
      accessToken,
      expiresAt:
        Date.now() +
        Math.max(60, expiresIn - Math.max(0, safetySeconds)) * 1000,
    };
  }

  private authorizeUrl(
    oauthBase: string,
    input: {
      clientId: string;
      redirectUri: string;
      state: string;
      nonce: string;
      scope: string;
      codeChallenge: string;
      loginVerifier?: string;
    },
  ) {
    const url = new URL(`${oauthBase}/oauth/authorize`);
    url.searchParams.set('client_id', input.clientId);
    url.searchParams.set('redirect_uri', input.redirectUri);
    url.searchParams.set('response_type', 'code');
    url.searchParams.set('state', input.state);
    url.searchParams.set('scope', input.scope);
    url.searchParams.set('code_challenge', input.codeChallenge);
    url.searchParams.set('code_challenge_method', 'S256');
    url.searchParams.set('nonce', input.nonce);
    if (input.loginVerifier) {
      url.searchParams.set('login_verifier', input.loginVerifier);
    }
    return url.toString();
  }

  private async fetchWithTimeout(
    url: string,
    init: RequestInit = {},
  ): Promise<Response> {
    const timeoutMs = Number(process.env.ERP_ORDER_TIMEOUT_MS || 10_000);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      return await fetch(url, { ...init, signal: controller.signal });
    } finally {
      clearTimeout(timer);
    }
  }

  private sanitizeItemRaw(item: any, product: any) {
    return {
      sellerSku: this.optionalText(item?.sellerSku),
      name: this.optionalText(item?.name),
      sellerName: this.optionalText(item?.sellerName),
      quantity: this.toInt(item?.quantity),
      sellPrice: this.toInt(item?.sellPrice),
      finalSellPrice: this.toInt(item?.finalSellPrice),
      rowTotal: this.toInt(item?.rowTotal),
      productGroup: product?.productGroup
        ? {
            id: this.optionalText(product.productGroup?.id),
            code: this.optionalText(product.productGroup?.code),
            name: this.optionalText(product.productGroup?.name),
          }
        : null,
      productType: product?.productType
        ? {
            id: this.optionalText(product.productType?.id),
            code: this.optionalText(product.productType?.code),
            name: this.optionalText(product.productType?.name),
          }
        : null,
    };
  }

  private parseDate(value: unknown) {
    const text = String(value || '').trim();
    if (!text) return null;
    const date = new Date(text);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  private toInt(value: unknown) {
    const number = Number(value);
    if (!Number.isFinite(number)) return null;
    return Math.trunc(number);
  }

  private optionalText(value: unknown) {
    const text = String(value ?? '').trim();
    return text ? text.slice(0, 500) : null;
  }

  private normalizeOrderCode(value: unknown) {
    return String(value || '')
      .trim()
      .toUpperCase()
      .replace(/\s+/g, '');
  }

  private env(key: string, fallback: string) {
    return process.env[key]?.trim() || fallback;
  }

  private base64Url(buffer: Buffer) {
    return buffer
      .toString('base64')
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/g, '');
  }

  private urlParam(url: string, key: string) {
    try {
      return new URL(url).searchParams.get(key);
    } catch {
      return null;
    }
  }
}
