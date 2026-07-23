import { json, type RequestHandler, urlencoded } from 'express';

type MiddlewareRegistrar = {
  use: (...handlers: RequestHandler[]) => unknown;
};

export function registerRequestBodyParsers(
  app: MiddlewareRegistrar,
  limit: string,
): void {
  const jsonParser = json({ limit });
  const urlencodedParser = urlencoded({ extended: true, limit });

  app.use(jsonParser);
  app.use(urlencodedParser);
}
