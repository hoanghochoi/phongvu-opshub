import express from 'express';
import request from 'supertest';
import { registerRequestBodyParsers } from './request-body-parsers';

function createEchoApp(limit = '1kb') {
  const app = express();
  registerRequestBodyParsers(app, limit);
  app.post('/echo', (req, res) => res.status(200).json(req.body));
  return app;
}

describe('request body parsers', () => {
  it('accepts valid JSON payloads', async () => {
    await request(createEchoApp())
      .post('/echo')
      .send({ message: 'xin chao' })
      .expect(200, { message: 'xin chao' });
  });

  it('accepts valid URL-encoded payloads', async () => {
    await request(createEchoApp())
      .post('/echo')
      .type('form')
      .send({ message: 'xin chao' })
      .expect(200, { message: 'xin chao' });
  });

  it.each([
    ['JSON', 'application/json', JSON.stringify({ message: 'too large' })],
    ['URL-encoded', 'application/x-www-form-urlencoded', 'message=too+large'],
  ])('rejects oversized %s payloads with HTTP 413', async (_, type, body) => {
    await request(createEchoApp('8b'))
      .post('/echo')
      .set('content-type', type)
      .send(body)
      .expect(413);
  });

  it('fails closed when the configured limit is invalid', () => {
    expect(() => createEchoApp('invalid')).toThrow(
      'option limit "invalid" is invalid',
    );
  });
});
