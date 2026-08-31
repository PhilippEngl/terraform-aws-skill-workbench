// The browser reaches S3 only through the proxy, so there is deliberately no bucket
// name or prefix here — it needs neither.
//
// Every value here is baked into the bundle at build time by Vite, which is why
// `make frontend` needs the stack applied at least once — see the ordering note in
// README.md. scripts/frontend-env.sh writes these from Terraform outputs and fails
// loudly if one is missing.
export const config = {
  userPoolId: import.meta.env.VITE_USER_POOL_ID,
  userPoolClientId: import.meta.env.VITE_USER_POOL_CLIENT_ID,
  identityPoolId: import.meta.env.VITE_IDENTITY_POOL_ID,
  proxyFunctionName: import.meta.env.VITE_PROXY_FUNCTION_NAME,

  // A placeholder, not a default. It only applies to a build made with no .env.local
  // at all, which cannot work anyway because the pool IDs above would be undefined
  // too — it exists so the AWS SDK constructor gets a string rather than undefined.
  // Every real build gets the deployed region from scripts/frontend-env.sh or from
  // the Amplify environment variables Terraform sets.
  region: import.meta.env.VITE_AWS_REGION || 'us-east-1',

  // The picker's options. The proxy independently rejects anything outside its own
  // enum, so this list is a convenience rather than a control — shipping a stale
  // bundle produces a clear rejection rather than a silent model substitution.
  modelIds: (import.meta.env.VITE_MODEL_IDS || '')
    .split(',')
    .map((m: string) => m.trim())
    .filter(Boolean),
};
