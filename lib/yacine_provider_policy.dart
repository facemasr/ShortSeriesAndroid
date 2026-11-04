/// A provider's channel metadata endpoint can return a short-lived 404
/// while live channel servers are being updated. Retry only brief failures.
/// This is not an authentication or region-access bypass.
bool yacineRetryableProviderStatus(int status) =>
    status == 404 || status == 408 || status == 425 ||
    status == 429 || (status >= 500 && status <= 504);
