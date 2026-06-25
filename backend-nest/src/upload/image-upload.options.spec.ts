import {
  avatarUploadOptions,
  getAvatarUploadMaxBytes,
  getImageUploadMaxBytes,
  IMAGE_UPLOAD_MAX_FILES,
  imageUploadOptions,
} from './image-upload.options';

describe('imageUploadOptions', () => {
  const megabyte = 1024 * 1024;

  it('allows up to twenty images per upload request', () => {
    expect(IMAGE_UPLOAD_MAX_FILES).toBe(20);
    expect(imageUploadOptions.limits?.files).toBe(IMAGE_UPLOAD_MAX_FILES);
  });

  it('defaults warranty and feedback images to ten MiB per file', () => {
    expect(getImageUploadMaxBytes({})).toBe(10 * megabyte);
  });

  it('defaults avatars to two MiB per file', () => {
    expect(getAvatarUploadMaxBytes({})).toBe(2 * megabyte);
  });

  it('wires upload options to their current environment limits', () => {
    expect(imageUploadOptions.limits?.fileSize).toBe(getImageUploadMaxBytes());
    expect(avatarUploadOptions.limits?.fileSize).toBe(
      getAvatarUploadMaxBytes(),
    );
  });
});
