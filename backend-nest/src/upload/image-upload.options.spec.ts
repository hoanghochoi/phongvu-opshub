import {
  IMAGE_UPLOAD_MAX_FILES,
  imageUploadOptions,
} from './image-upload.options';

describe('imageUploadOptions', () => {
  it('allows up to twenty images per upload request', () => {
    expect(IMAGE_UPLOAD_MAX_FILES).toBe(20);
    expect(imageUploadOptions.limits?.files).toBe(IMAGE_UPLOAD_MAX_FILES);
  });
});
