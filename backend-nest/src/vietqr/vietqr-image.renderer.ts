import { existsSync, readFileSync } from 'fs';
import { resolve } from 'path';
import QRCode from 'qrcode';
import sharp from 'sharp';
import type { VietQrResponse } from './vietqr.service';

export interface RenderedVietQrImage {
  buffer: Buffer;
  fileName: string;
  mimeType: 'image/png';
}

export class VietQrImageRenderer {
  private readonly width = 1080;
  private readonly height = 1560;
  private fontFaceCache?: string;

  async renderPng(transfer: VietQrResponse): Promise<RenderedVietQrImage> {
    const [qrBuffer, logoBuffer] = await Promise.all([
      this.qrPng(transfer.qrPayload),
      this.logoPlatePng(),
    ]);
    const buffer = await sharp(Buffer.from(this.buildBaseSvg(transfer)))
      .composite([
        { input: qrBuffer, left: 195, top: 230 },
        { input: logoBuffer, left: 447, top: 482 },
      ])
      .png()
      .toBuffer();
    return {
      buffer,
      fileName: this.fileNameFor(transfer),
      mimeType: 'image/png',
    };
  }

  private buildBaseSvg(transfer: VietQrResponse): string {
    const fontFamily =
      '&quot;OpsHubSans&quot;, &quot;SF Pro Display&quot;, &quot;DejaVu Sans&quot;, Arial, Helvetica, sans-serif';
    const titleStyle =
      `font-family: ${fontFamily}; font-size: 58px; font-weight: 700; fill: #1238C8;`;
    const labelStyle =
      `font-family: ${fontFamily}; font-size: 32px; font-weight: 400; fill: #5F6673;`;
    const valueStyle =
      `font-family: ${fontFamily}; font-size: 38px; font-weight: 700; fill: #1F2430;`;
    const rows = [
      ['Ngân hàng', transfer.bankName],
      ['Số tài khoản', transfer.accountNumber],
      ['Chủ tài khoản', transfer.accountName],
      ['Số tiền', this.amountLabel(transfer.amount)],
      ['Nội dung', this.contentLabel(transfer.transferContent)],
    ];

    return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${this.width}" height="${this.height}" viewBox="0 0 ${this.width} ${this.height}">
  ${this.svgStyle()}
  <rect width="${this.width}" height="${this.height}" fill="#FFFFFF"/>
  <text x="72" y="111" style="${titleStyle}">PhongVu OpsHub</text>
  <text x="72" y="168" style="${labelStyle}">Mã chuyển khoản VietQR</text>
  ${rows.map((row, index) => this.infoRow(row[0], row[1], 1030 + index * 96, labelStyle, valueStyle)).join('\n')}
</svg>`;
  }

  private async qrPng(payload: string): Promise<Buffer> {
    return QRCode.toBuffer(payload, {
      errorCorrectionLevel: 'H',
      type: 'png',
      width: 690,
      margin: 0,
      color: { dark: '#000000ff', light: '#ffffffff' },
    });
  }

  private async logoPlatePng(): Promise<Buffer> {
    const plateSize = 186;
    const iconSize = 150;
    const inset = Math.round((plateSize - iconSize) / 2);
    const logo = await this.roundedLogoPng(iconSize);
    const plateSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="${plateSize}" height="${plateSize}" viewBox="0 0 ${plateSize} ${plateSize}">
      <rect width="${plateSize}" height="${plateSize}" rx="24" ry="24" fill="#FFFFFF"/>
    </svg>`;
    return sharp(Buffer.from(plateSvg))
      .composite([{ input: logo, left: inset, top: inset }])
      .png()
      .toBuffer();
  }

  private async roundedLogoPng(size: number): Promise<Buffer> {
    const logo = await sharp(this.logoSourceBuffer())
      .resize(size, size, { fit: 'cover' })
      .png()
      .toBuffer();
    const mask = Buffer.from(
      `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}"><rect width="${size}" height="${size}" rx="20" ry="20" fill="#FFFFFF"/></svg>`,
    );
    return sharp(logo)
      .composite([{ input: mask, blend: 'dest-in' }])
      .png()
      .toBuffer();
  }

  private logoSourceBuffer(): Buffer {
    const explicitPath = process.env.VIETQR_LOGO_PATH?.trim();
    const candidates = [
      explicitPath,
      resolve(
        process.cwd(),
        '..',
        'assets',
        'icon',
        'source',
        'app_icon_master.png',
      ),
      resolve(process.cwd(), 'assets', 'icon', 'source', 'app_icon_master.png'),
    ].filter((value): value is string => Boolean(value));

    for (const candidate of candidates) {
      if (!existsSync(candidate)) continue;
      return readFileSync(candidate);
    }

    const fallback = `<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
      <defs><linearGradient id="g" x1="0" x2="1" y1="0" y2="1"><stop stop-color="#05164F"/><stop offset="1" stop-color="#0E46F5"/></linearGradient></defs>
      <rect width="512" height="512" rx="86" fill="url(#g)"/>
      <path d="M142 174h228M256 174v164M142 338h228" stroke="#65E9FF" stroke-width="18" stroke-linecap="round"/>
      <circle cx="142" cy="174" r="48" fill="#39D5F4" stroke="#B8FBFF" stroke-width="10"/>
      <circle cx="370" cy="174" r="48" fill="#39D5F4" stroke="#B8FBFF" stroke-width="10"/>
      <circle cx="142" cy="338" r="48" fill="#39D5F4" stroke="#B8FBFF" stroke-width="10"/>
      <rect x="322" y="290" width="96" height="96" rx="18" fill="#39D5F4" stroke="#B8FBFF" stroke-width="10"/>
      <path d="M256 220c18 42 36 60 78 78-42 18-60 36-78 78-18-42-36-60-78-78 42-18 60-36 78-78z" fill="#FFFFFF"/>
    </svg>`;
    return Buffer.from(fallback);
  }

  private svgStyle(): string {
    const fontFaces = this.fontFaceCss();
    if (!fontFaces) return '';
    return `<style type="text/css"><![CDATA[
${fontFaces}
]]></style>`;
  }

  private fontFaceCss(): string {
    if (this.fontFaceCache !== undefined) return this.fontFaceCache;

    const faces = [
      { fileName: 'SF-Pro-Display-Regular.otf', weight: 400 },
      { fileName: 'SF-Pro-Display-Semibold.otf', weight: 600 },
      { fileName: 'SF-Pro-Display-Bold.otf', weight: 700 },
    ]
      .map((face) => {
        const font = this.fontSourceBuffer(face.fileName);
        if (!font) return '';
        const dataUrl = `data:font/otf;base64,${font.toString('base64')}`;
        return `@font-face { font-family: 'OpsHubSans'; src: url('${dataUrl}') format('opentype'); font-weight: ${face.weight}; font-style: normal; }`;
      })
      .filter(Boolean)
      .join('\n');

    this.fontFaceCache = faces;
    return this.fontFaceCache;
  }

  private fontSourceBuffer(fileName: string): Buffer | null {
    const explicitDir = process.env.VIETQR_FONT_DIR?.trim();
    const candidates = [
      explicitDir ? resolve(explicitDir, fileName) : null,
      resolve(process.cwd(), 'fonts', fileName),
      resolve(process.cwd(), '..', 'fonts', fileName),
    ].filter((value): value is string => Boolean(value));

    for (const candidate of candidates) {
      if (!existsSync(candidate)) continue;
      return readFileSync(candidate);
    }

    return null;
  }

  private infoRow(
    label: string,
    value: string,
    y: number,
    labelStyle: string,
    valueStyle: string,
  ): string {
    const lines = this.wrapValue(value, 27);
    const tspans = lines
      .map((line, index) => {
        const dy = index === 0 ? 0 : 44;
        return `<tspan x="360" dy="${dy}">${this.escapeXml(line)}</tspan>`;
      })
      .join('');
    return `<text x="72" y="${y}" style="${labelStyle}">${this.escapeXml(label)}</text>
  <text x="360" y="${y - 4}" style="${valueStyle}">${tspans}</text>`;
  }

  private wrapValue(value: string, maxChars: number): string[] {
    const normalized = value.trim() || ' ';
    if (normalized.length <= maxChars) return [normalized];

    const words = normalized.split(/\s+/);
    const lines: string[] = [''];
    for (const word of words) {
      const last = lines[lines.length - 1];
      const next = last ? `${last} ${word}` : word;
      if (!last && word.length > maxChars) {
        lines[lines.length - 1] = `${word.slice(0, maxChars - 3)}...`;
        continue;
      }
      if (next.length <= maxChars || lines.length === 2) {
        lines[lines.length - 1] = next;
        continue;
      }
      lines.push(word);
    }

    if (lines.length > 2) {
      lines.length = 2;
    }
    if (lines[1]?.length > maxChars) {
      lines[1] = `${lines[1].slice(0, Math.max(0, maxChars - 3)).trim()}...`;
    }
    return lines.slice(0, 2);
  }

  private amountLabel(amount: number | null): string {
    if (amount === null) return 'Người chuyển nhập';
    return `${new Intl.NumberFormat('vi-VN').format(amount)} VND`;
  }

  private contentLabel(transferContent: string): string {
    return transferContent.trim() || 'Người chuyển nhập';
  }

  private fileNameFor(transfer: VietQrResponse): string {
    const seed =
      transfer.transferContent || transfer.id || Date.now().toString();
    return `vietqr_${seed.replace(/[^A-Z0-9_-]/g, '_')}.png`;
  }

  private escapeXml(value: string): string {
    return value
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&apos;');
  }
}
