import { AppVersionService } from './app-version.service';

describe('AppVersionService', () => {
  const service = new AppVersionService();

  it('returns configured update metadata', () => {
    expect(
      service.getVersion({
        APP_VERSION: '1.2.3',
        APP_BUILD_NUMBER: '42',
        APP_MIN_SUPPORTED_BUILD: '40',
        APP_UPDATE_URL: 'https://opshub.hoanghochoi.com/downloads/app.apk',
        APP_RELEASE_NOTES: 'Fixes',
        APP_FORCE_UPDATE: 'true',
      }),
    ).toEqual({
      latestVersion: '1.2.3',
      latestBuild: 42,
      minSupportedBuild: 40,
      updateUrl: 'https://opshub.hoanghochoi.com/downloads/app.apk',
      releaseNotes: 'Fixes',
      forceUpdate: true,
    });
  });

  it('falls back to safe defaults for missing or invalid values', () => {
    expect(
      service.getVersion({
        APP_BUILD_NUMBER: 'abc',
        APP_MIN_SUPPORTED_BUILD: '-1',
      }),
    ).toEqual({
      latestVersion: '1.0.0',
      latestBuild: 1,
      minSupportedBuild: 1,
      updateUrl: '',
      releaseNotes: '',
      forceUpdate: false,
    });
  });
});
