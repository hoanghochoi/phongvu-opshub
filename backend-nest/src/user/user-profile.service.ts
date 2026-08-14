import { BadRequestException, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { UploadService } from '../upload/upload.service';

export type UserProfileDtoAdapter = {
  include: () => Prisma.UserInclude;
  toDto: (user: any) => any;
};

export class UserProfileService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly uploadService: UploadService,
    private readonly dto: UserProfileDtoAdapter,
  ) {}

  async getProfile(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      include: this.dto.include(),
    });
    if (!user) throw new NotFoundException('Không tìm thấy người dùng');
    return this.dto.toDto(user);
  }

  async updateProfile(
    userId: string,
    body: { firstName?: string; lastName?: string },
  ) {
    const firstName = body.firstName?.trim();
    if (!firstName) {
      throw new BadRequestException('Tên không được để trống');
    }
    const user = await this.prisma.user.update({
      where: { id: userId },
      data: {
        firstName,
        lastName: body.lastName?.trim() || null,
      },
      include: this.dto.include(),
    });
    return this.dto.toDto(user);
  }

  async updateAvatar(userId: string, file?: Express.Multer.File) {
    if (!file) {
      throw new BadRequestException('Vui lòng chọn ảnh đại diện');
    }
    const previous = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { avatarUrl: true },
    });
    const avatarUrl = await this.uploadService.saveUserAvatar(userId, file);
    let user: any;
    try {
      user = await this.prisma.user.update({
        where: { id: userId },
        data: { avatarUrl },
        include: this.dto.include(),
      });
    } catch (error) {
      await this.uploadService.discardPrivateMedia([avatarUrl]);
      throw error;
    }
    if (previous?.avatarUrl && previous.avatarUrl !== avatarUrl) {
      await this.uploadService.discardPrivateMedia([previous.avatarUrl]);
    }
    return this.dto.toDto(user);
  }
}
