/// Ed25519 public keys trusted to sign the model catalog, by key id
/// (first 8 bytes of the key's SHA-256, hex).
///
/// Keys are public by design; only the private keys must stay secret
/// (offline, see CATALOG.md). To rotate: add the new key here, ship an app
/// update, start signing with the new key, and remove the old key in a
/// later release.
const Map<String, String> trustedCatalogKeys = {
  '0c9e7ac09c6f1f62': 'GZVkihZZ0MZPn/h9HQ3V+ChdQlRTUtWr7Mkmgmq+EMc=',
};

/// Flutter asset key of the signed catalog bundled with the app.
const String bundledCatalogAsset = 'assets/catalog/catalog.signed.json';

/// Largest catalog the app accepts, to bound memory use.
const int maxCatalogBytes = 2 * 1024 * 1024;
