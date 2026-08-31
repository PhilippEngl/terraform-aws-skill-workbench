import { LambdaClient, InvokeCommand } from '@aws-sdk/client-lambda';
import { fetchAuthSession } from 'aws-amplify/auth';
import { config } from '../config';
import type { ProxyResponse } from '../types';

/**
 * Credentials from the Cognito identity pool. Forced refresh on failure rather than
 * on every call, so an expired session recovers without a sign-out.
 */
async function credentials() {
  let session = await fetchAuthSession({ forceRefresh: false });
  if (!session.credentials) {
    session = await fetchAuthSession({ forceRefresh: true });
  }
  if (!session.credentials) {
    throw new Error('Not signed in');
  }
  return session.credentials;
}

/**
 * Invoke the proxy and unwrap its response.
 *
 * Two distinct failure modes are collapsed into thrown errors here: a Lambda-level
 * failure (`FunctionError`, meaning the handler raised) and an application-level
 * rejection (`ok: false`, meaning the handler refused on purpose). Callers only need
 * to render the message.
 */
export async function callProxy<T>(payload: Record<string, unknown>): Promise<T> {
  const client = new LambdaClient({ region: config.region, credentials: await credentials() });

  const response = await client.send(
    new InvokeCommand({
      FunctionName: config.proxyFunctionName,
      Payload: new TextEncoder().encode(JSON.stringify(payload)),
    })
  );

  if (!response.Payload) {
    throw new Error('Empty response from the proxy');
  }

  const decoded = new TextDecoder().decode(response.Payload);

  if (response.FunctionError) {
    throw new Error(`Proxy failed: ${decoded}`);
  }

  const parsed = JSON.parse(decoded) as ProxyResponse<T>;

  if (!parsed.ok) {
    throw new Error(parsed.error || 'The proxy rejected the request');
  }

  return parsed as unknown as T;
}
