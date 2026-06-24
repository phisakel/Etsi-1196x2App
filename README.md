# Etsi-1196x2App

A Swift demo application showing how to integrate the [EudiEtsi1196x2](https://github.com/eu-digital-identity-wallet/eudi-lib-ios-etsi-1196x2) package into an iOS wallet. It covers all major usage patterns: live LoTE trust list fetching, cached resolution, bundled certificate pinning, and interactive chain validation.

## Requirements

- Xcode 15+
- iOS 16+ deployment target
- An internet connection for the LoTE / network flows

## Adding the library to your project

In Xcode: **File → Add Package Dependencies** and enter the repository URL. Select the version you want and add `EudiEtsi1196x2` to your app target.

Then import the module wherever you need it:

```swift
import EudiEtsi1196x2
```

## Core concepts

### `EudiwIosTrust.shared`

The single entry point to the library. All validators are created through it.

### Verification contexts

A verification context tells the library which ETSI trust-list profile to apply when resolving anchors and validating chains:

```swift
VerificationContextPID.shared                              // PID issuers
VerificationContextWalletProviderAttestation.shared        // Wallet providers
VerificationContextWalletRelyingPartyAccessCertificate.shared   // WRPAC
VerificationContextWalletRelyingPartyRegistrationCertificate.shared // WRPRC
VerificationContextQEAA.shared                             // QEAA issuers
VerificationContextEAA(useCase: EudiwIosTrust.shared.mdlUseCase) // mDL / EAA
```

### `TrustListUrls`

A configuration object for LoTE endpoint URLs. Set only the slots your environment provides; leave the rest as `nil`.

```swift
let urls = TrustListUrls()
urls.pidProviders    = "https://example.com/pid-providers.json"
urls.walletProviders = "https://example.com/wallet-providers.json"
urls.wrpacProviders  = "https://example.com/wrpac-providers.json"
// urls.wrprcProviders, .pubEaaProviders, .qeaProviders, .mdlProviders also available
```

---

## Usage patterns

### 1. Non-cached (fresh fetch every time)

Fetches and parses the LoTE on every call. Good for one-off checks.

```swift
let urls = TrustListUrls()
urls.pidProviders = "https://acceptance.trust.tech.ec.europa.eu/lists/eudiw/pid-providers.json"

// In production, replace InsecureAcceptAllJwtSignature with a real verifier.
let validator = EudiwIosTrust.shared.nonCached(
    urls: urls,
    verifyJwtSignature: InsecureAcceptAllJwtSignature.shared
)

// Resolve the trust anchors for a context.
let anchors = try await EudiwIosTrust.shared.trustAnchors(
    validator: validator,
    context: VerificationContextPID.shared
)
print("PID anchors: \(anchors.count)")

// Validate a DER-encoded certificate chain (leaf first).
let result = try await EudiwIosTrust.shared.validate(
    validator: validator,
    chain: [leafDerData, intermediateDerData],
    context: VerificationContextPID.shared
)
print(result.isTrusted ? "trusted" : "not trusted: \(result.failureReason ?? "")")
```

### 2. Cached validator

Keeps an in-memory cache so repeated resolutions within the TTL window skip the network. Create it once per session and hold the reference; call `dispose()` when done.

```swift
// At session start:
let urls = TrustListUrls()
urls.pidProviders = "https://example.com/pid-providers.json"

let cachedValidator = EudiwIosTrust.shared.cached(
    urls: urls,
    ttlHours: 24,
    verifyJwtSignature: InsecureAcceptAllJwtSignature.shared
)

// Use the handle directly — it owns the cache:
let anchors = try await cachedValidator.trustAnchors(context: VerificationContextPID.shared)
let result  = try await cachedValidator.validate(chain: chain, context: VerificationContextPID.shared)

// At session end (or in deinit):
cachedValidator.dispose()
```

### 3. Bundled anchors (no network)

For environments where trust anchors are shipped with the app rather than fetched from LoTE. Two modes are supported.

#### PKIX — validate a chain up to a trusted root CA

```swift
guard let rootDer = Bundle.main.url(forResource: "my-root-ca", withExtension: "der")
        .flatMap({ try? Data(contentsOf: $0) }) else { return }

let anchors = BundledAnchors()
anchors.pid = [rootDer]          // assign DER bytes to the relevant slot(s)

let validator = EudiwIosTrust.shared.usingBundledAnchors(anchors: anchors, method: .pkix)

let result = try await EudiwIosTrust.shared.validate(
    validator: validator,
    chain: [leafDerData],
    context: VerificationContextPID.shared
)
```

#### Direct trust — pin a specific leaf certificate

```swift
let pinAnchors = BundledAnchors()
pinAnchors.pid = [leafDerData]   // pin the exact leaf

let pinValidator = EudiwIosTrust.shared.usingBundledAnchors(anchors: pinAnchors, method: .directTrust)

let result = try await EudiwIosTrust.shared.validate(
    validator: pinValidator,
    chain: [leafDerData],
    context: VerificationContextPID.shared
)
```

### 4. Validate a pasted or runtime-provided chain

Parse PEM text (single certificate or a full chain) then validate:

```swift
// pemText may contain one or more "-----BEGIN CERTIFICATE-----" blocks.
var chain: [Data] = []
var current = ""
var inCert = false
for rawLine in pemText.split(whereSeparator: \.isNewline) {
    let line = rawLine.trimmingCharacters(in: .whitespaces)
    if line.hasPrefix("-----BEGIN") { inCert = true; current = "" }
    else if line.hasPrefix("-----END") {
        inCert = false
        if let data = Data(base64Encoded: current) { chain.append(data) }
    } else if inCert { current.append(line) }
}

let result = try await EudiwIosTrust.shared.validate(
    validator: validator,
    chain: chain,
    context: VerificationContextPID.shared
)
```

---

## App demo flows

| Button | What it does |
|--------|-------------|
| **Load & validate (LoTE)** | Fetches the EC DIGIT acceptance LoTE, resolves anchors per context, and runs a cross-context validation demo (mDL anchor vs PID and mDL contexts). |
| **Load (EUDI Ref Impl)** | Fetches the EUDI Reference Implementation LoTE (PID, Wallet, WRPAC, WRPRC) and shows anchor counts. |
| **Validate (cached)** | Creates a 24-hour cached validator (reused on repeated taps), resolves anchors, and prints cold vs warm timing. |
| **Validate bundled certificate** | Loads `eudi-test-root.der` and `eudi-test-leaf.der` from the app bundle and runs PKIX, direct-trust, and negative validation checks. |
| **Validate certificate** | Parses the certificate pasted in the text editor, validates it against the EUDI Ref Impl LoTE, and reports the ETSI profile result. |

---

## Production checklist

- **Replace `InsecureAcceptAllJwtSignature.shared`** — this stub skips JWT signature verification entirely and is suitable only for local development. A production wallet must supply a real `VerifyJwtSignature` implementation that validates each LoTE JWT against the scheme operator's trusted signing keys.
- **Choose the right validator lifetime** — a `nonCached` validator makes a network request on every call; a `CachedTrustValidator` amortises that cost but must be `dispose()`d when no longer needed to release its resources.
- **Use the correct verification context** — each context applies a distinct ETSI profile. Validating a PID credential with `VerificationContextWalletProviderAttestation` will correctly reject it.
