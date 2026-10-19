# Model catalog

The app learns which models exist from a **signed catalog**: a JSON manifest
signed with Ed25519. The app accepts a catalog only if its signature verifies
against a public key compiled into the app. That means new models can be
added without an app update, and nobody else can add or change entries: not
a compromised server, not a network attacker, not a mirror.

## Files

| Path | What |
|---|---|
| `tool/catalog/catalog_source.json` | Human edited source: models, metadata, descriptions (en, bn), licenses. |
| `tool/catalog/build_catalog.dart` | Adds exact file sizes, SHA-256 hashes and commit pinned URLs from Hugging Face. |
| `tool/catalog/sign_catalog.dart` | Signs the manifest into an envelope. |
| `tool/catalog/keygen.dart` | Creates a signing key pair. |
| `assets/catalog/catalog.signed.json` | Signed catalog bundled in the app (offline fallback). |
| `lib/features/model_catalog/data/catalog_trust.dart` | Trusted public keys. |

## Signed envelope

```json
{
  "format": "emberwit.signed-catalog.v1",
  "keyId": "0c9e7ac09c6f1f62",
  "payload": "<base64 of the manifest bytes>",
  "signature": "<base64 Ed25519 signature of those bytes>"
}
```

The signature covers the exact payload bytes. JSON formatting cannot break
it, and the app never parses unverified JSON.

## Manifest schema (version 1)

```json
{
  "schemaVersion": 1,
  "catalogVersion": 1,
  "generatedAt": "2026-09-24T10:18:16Z",
  "models": [
    {
      "id": "qwen3-0.6b-q4_k_m",
      "displayName": "Qwen3 0.6B",
      "family": "qwen3",
      "parameterCount": 751632384,
      "quantization": "Q4_K_M",
      "fileSizeBytes": 484220320,
      "sha256": "9acfc1e0…",
      "downloadUrls": ["https://huggingface.co/<repo>/resolve/<commit>/<file>",
                       "https://hf-mirror.com/<repo>/resolve/<commit>/<file>"],
      "minRamBytes": 2147483648,
      "recommendedContextLength": 8192,
      "kvCacheBytesPerToken": 114688,
      "languages": [{"code": "en", "quality": "good"}, {"code": "bn", "quality": "basic"}],
      "license": {"id": "Apache-2.0", "name": "Apache License 2.0",
                  "url": "https://…", "requiresAgreement": false},
      "chatTemplate": "chatml",
      "description": {"en": "…", "bn": "…"}
    }
  ]
}
```

| Field | Rules |
|---|---|
| `schemaVersion` | The app rejects a version higher than it supports (currently 1). Adding optional fields does **not** need a new version: apps ignore unknown fields and unknown enum values. |
| `catalogVersion` | Must increase with every release. The app refuses a catalog older than the one it has (rollback protection). |
| `id` | Lowercase `[a-z0-9._-]`, at most 64 characters. Also the installed file name. Never reuse an id for different weights. |
| `sha256` | Lowercase hex. Every download is checked against it before it can be loaded. A mismatch deletes the file. |
| `downloadUrls` | HTTPS only; others are dropped. The first URL is primary, the rest are mirrors of the **same file**, tried in order on failure. URLs are pinned to a commit so the file cannot change under the hash. |
| `kvCacheBytesPerToken` | `2 × layers × kv_heads × head_dim × 2` bytes (f16 K and V). Lets the recommendation engine estimate memory exactly. |
| `languages[].quality` | `good`, `basic` or `limited`. Bengali quality is shown to every user. |
| `license.requiresAgreement` | `true` for licenses with usage rules (Gemma, Llama). The app asks the user to agree before downloading. |
| `chatTemplate` | `chatml`, `gemma`, `llama3` or `phi4`; see the chat feature. |

An entry that breaks these rules is skipped, not fatal: the rest of the
catalog still loads.

## Adding or updating a model

1. Pick an ungated GGUF on Hugging Face (anonymous downloads must work) and
   verify its license and the base model's license.
2. Add an entry to `tool/catalog/catalog_source.json` with `huggingFace.repo`
   and `huggingFace.file`, English and Bengali descriptions, the language
   qualities (test Bengali yourself), the license, the chat template, and
   `kvCacheBytesPerToken` from the model's `config.json`.
3. Increase `catalogVersion`.
4. Build and sign:
   ```bash
   dart run tool/catalog/build_catalog.dart           # -> build/catalog/catalog.json
   dart run tool/catalog/sign_catalog.dart build/catalog/catalog.json \
       ~/.emberwit-release/catalog-signing.key assets/catalog/catalog.signed.json
   ```
5. Run `flutter test test/features/model_catalog` (it verifies the bundled
   catalog with the shipped key), then commit the source and the signed file.
6. Publish the same `catalog.signed.json` at the flavor's catalog URL
   (`FlavorConfig.catalogUrl`). Apps pick it up on their next refresh.

## Keys

- Generate a key: `dart run tool/catalog/keygen.dart <path>`. It writes the
  private seed with 0600 permissions and prints the key id and public key.
- **The private key never enters the repository or CI.** Keep it offline,
  back it up in two places, and sign on a trusted machine.
- The current key (`0c9e7ac09c6f1f62`) was generated on the development
  machine at `~/.emberwit-release/catalog-signing.key`. Before the first
  public release, generate a production key on an offline machine and
  replace it.
- **Rotation:** add the new public key to `trustedCatalogKeys` and ship an
  update. Then sign with the new key, and remove the old key a release later.
- **Compromise:** ship an app update without the compromised key, re-sign the
  catalog with a new key, and bump `catalogVersion`.

## Hosting

The catalog is served by GitHub Pages from this repository:
`docs/catalog/<dev|staging|v1>/manifest.json` is published at
`https://tanim913.github.io/emberwit/catalog/<dev|staging|v1>/manifest.json`.
To publish a new catalog, sign it, copy `catalog.signed.json` over the
matching `manifest.json`, and push. When the fetch fails, the app uses the
bundled catalog.

GitHub's certificates rotate, so the Pages host is not pinned; the Ed25519
signature carries integrity. If the catalog moves to a host you control,
pin it: compute the SPKI pins of the live key and a backup key, and set
`catalogCertificatePins` in `FlavorConfig`:
   ```bash
   openssl s_client -connect <host>:443 -servername <host> </dev/null \
     | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der \
     | openssl dgst -sha256 -binary | base64
   ```
   Pins take the form `sha256/<base64>`. The signature already protects
   integrity; pinning adds protection against a tampered transport and
   hides catalog traffic from TLS interception.

## Seed catalog (catalogVersion 1, verified 2026-09-24)

| Model | File (bartowski, Q4_K_M) | Size | License | Bengali |
|---|---|---|---|---|
| Qwen3 0.6B | Qwen_Qwen3-0.6B-Q4_K_M.gguf | 484 MB | Apache-2.0 | basic |
| Qwen3 1.7B | Qwen_Qwen3-1.7B-Q4_K_M.gguf | 1.28 GB | Apache-2.0 | basic |
| Qwen3 4B | Qwen_Qwen3-4B-Q4_K_M.gguf | 2.50 GB | Apache-2.0 | good |
| Gemma 3 1B | google_gemma-3-1b-it-Q4_K_M.gguf | 806 MB | Gemma Terms of Use (agreement) | basic |
| Gemma 3 4B | google_gemma-3-4b-it-Q4_K_M.gguf | 2.49 GB | Gemma Terms of Use (agreement) | good |
| Llama 3.2 1B | Llama-3.2-1B-Instruct-Q4_K_M.gguf | 808 MB | Llama 3.2 Community License (agreement) | limited |
| Llama 3.2 3B | Llama-3.2-3B-Instruct-Q4_K_M.gguf | 2.02 GB | Llama 3.2 Community License (agreement) | limited |
| Phi 4 mini | microsoft_Phi-4-mini-instruct-Q4_K_M.gguf | 2.49 GB | MIT | limited |

Qwen3 and Phi 4 mini are permissively licensed. Gemma 3 and Llama 3.2 have
custom licenses with acceptable use policies, and Llama requires "Built with
Llama" attribution. Keep them only if the product accepts those terms.
