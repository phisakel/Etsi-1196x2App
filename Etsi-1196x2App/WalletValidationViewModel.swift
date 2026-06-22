//
//  WalletValidationViewModel.swift
//  Etsi-1196x2App
//
//  Demonstrates how a wallet developer uses the EudiEtsi1196x2 package to:
//   1. resolve trust anchors from ETSI TS 119 602 Lists of Trusted Entities (LoTE) per context, and
//   2. validate a certificate chain against those anchors.
//
//  MVVM: all logic and state live here; the View only renders state and calls actions.
//

import Foundation
import Combine
import EudiEtsi1196x2

/// The verification contexts the EUDI Reference Implementation environment exposes.
/// Drives the picker in the "Test certificate" section.
enum TestContext: String, CaseIterable, Identifiable {
    case pid = "PID"
    case wallet = "Wallet"
    case wrpac = "WRPAC"
    case wrprc = "WRPRC"

    var id: String { rawValue }

    var verificationContext: VerificationContext {
        switch self {
        case .pid:    return VerificationContextPID.shared
        case .wallet: return VerificationContextWalletProviderAttestation.shared
        case .wrpac:  return VerificationContextWalletRelyingPartyAccessCertificate.shared
        case .wrprc:  return VerificationContextWalletRelyingPartyRegistrationCertificate.shared
        }
    }
}

@MainActor
final class WalletValidationViewModel: ObservableObject {

    /// The screen's lifecycle.
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// Trust anchors resolved for a verification context.
    struct ContextResult: Identifiable {
        let id = UUID()
        let name: String
        let anchorCount: Int
    }

    /// Outcome of validating a sample chain against a context.
    struct ValidationOutcome: Identifiable {
        let id = UUID()
        let label: String
        let trusted: Bool
        let detail: String?
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var results: [ContextResult] = []
    @Published private(set) var validations: [ValidationOutcome] = []

    /// User input for the "Test certificate" section — a pasted PEM block (or chain), or raw base64.
    @Published var pastedPEM: String = ""

    /// User selection for the "Test certificate" section.
    @Published var selectedTestContext: TestContext = .pid

    /// The cached validator owns an in-memory anchor cache; it is created once and reused so repeated
    /// resolutions are served from the cache, then released in `deinit`.
    private var cachedValidator: CachedTrustValidator?

    deinit {
        cachedValidator?.dispose()
    }

    // MARK: - Configuration

    // LoTE trust-list endpoints (EC DIGIT acceptance environment). `nil` = context not used.
    // `DIGITTrustLists.mdlProviders` has no dedicated slot in the trust-list configuration, so it
    // is not wired here.
    private let pidProvidersURL: String? = DIGITTrustLists.pidProviders
    private let walletProvidersURL: String? = DIGITTrustLists.walletProviders
    private let wrpacProvidersURL: String? = DIGITTrustLists.wrpacProviders
    private let wrprcProvidersURL: String? = nil
    private let pubEaaProvidersURL: String? = nil
    private let qeaProvidersURL: String? = nil
    private let mdlProvidersURL: String? = DIGITTrustLists.mdlProviders

    /// The mDL verification context (registered under the "mdl" use case).
    private var mdlContext: VerificationContext { VerificationContextEAA(useCase: EudiwIosTrust.shared.mdlUseCase) }

    /// The verification contexts this screen resolves anchors for.
    private var contexts: [(name: String, context: VerificationContext)] {
        [
            ("PID providers", VerificationContextPID.shared),
            ("Wallet providers", VerificationContextWalletProviderAttestation.shared),
            ("WRPAC providers", VerificationContextWalletRelyingPartyAccessCertificate.shared),
            ("mDL providers", mdlContext),
        ]
    }

    // MARK: - Actions

    /// Builds the LoTE-based validator, resolves anchors per context, and runs a validation demo.
    func run() async {
        phase = .loading
        results = []
        validations = []

        // Build the validator. NOTE: `InsecureAcceptAllJwtSignature` performs NO JWT verification
        // and is for local development only — a production wallet MUST pass a real
        // `VerifyJwtSignature` that validates each LoTE against the trusted scheme-operator keys.
        let urls = TrustListUrls()
        urls.pidProviders    = pidProvidersURL
        urls.walletProviders = walletProvidersURL
        urls.wrpacProviders  = wrpacProvidersURL
        urls.mdlProviders    = mdlProvidersURL
        
       let validator = EudiwIosTrust.shared.nonCached(urls: urls, verifyJwtSignature: InsecureAcceptAllJwtSignature.shared)

        do {
            // 1. Resolve trust anchors per context.
            var collected: [ContextResult] = []
            for entry in contexts {
                let anchors = try await EudiwIosTrust.shared.trustAnchors(
                    validator: validator,
                    context: entry.context
                )
                collected.append(ContextResult(name: entry.name, anchorCount: anchors.count))
            }
            results = collected

            // 2. Validation demo, using real DIGIT data. The mDL context has no end-entity profile
            //    (the DIGIT acceptance lists don't satisfy the strict ETSI profiles), so its check
            //    is pure direct trust: "is this certificate one of the trusted mDL entities?".
            //    Validating an mDL trust anchor against:
            //      - the mDL context  → Trusted   (it IS a trusted mDL entity), and
            //      - the PID context  → NotTrusted (PID enforces an end-entity signing profile that
            //                                        a CA / non-PID cert cannot satisfy).
            //    A real wallet would instead pass the leaf-first chain from a received credential.
            let mdlAnchors = try await EudiwIosTrust.shared.trustAnchors(
                validator: validator,
                context: mdlContext
            )
            if let sample = mdlAnchors.first {
                let chain = [sample]
                let asMdl = try await EudiwIosTrust.shared.validate(
                    validator: validator,
                    chain: chain,
                    context: mdlContext
                )
                let asPid = try await EudiwIosTrust.shared.validate(
                    validator: validator,
                    chain: chain,
                    context: VerificationContextPID.shared
                )
                validations = [
                    ValidationOutcome(label: "mDL anchor → mDL context",
                                      trusted: asMdl.isTrusted,
                                      detail: asMdl.failureReason),
                    ValidationOutcome(label: "mDL anchor → PID context",
                                      trusted: asPid.isTrusted,
                                      detail: asPid.failureReason),
                ]
            }

            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Resolves trust anchors from the **EUDI Reference Implementation** environment.
    /// No chain validation yet (a real cert that satisfies the strict ETSI profiles is needed for
    /// that and isn't bundled with the app). This action just proves the ref-impl LoTE URLs work
    /// end-to-end: download, JWT parse, anchor extraction, and per-context counts.
    func runRefImpl() async {
        phase = .loading
        results = []
        validations = []

        let urls = TrustListUrls()
        urls.pidProviders    = EUDIRefImplLists.pidProviders
        urls.walletProviders = EUDIRefImplLists.walletProviders
        urls.wrpacProviders  = EUDIRefImplLists.wrpacProviders
        urls.wrprcProviders  = EUDIRefImplLists.wrprcProviders
        let validator = EudiwIosTrust.shared.nonCached(urls: urls, verifyJwtSignature: InsecureAcceptAllJwtSignature.shared)

        do {
            // Ref-impl contexts (no mDL, plus WRPRC compared to DIGIT).
            let refImplContexts: [(name: String, context: VerificationContext)] = [
                ("PID providers", VerificationContextPID.shared),
                ("Wallet providers", VerificationContextWalletProviderAttestation.shared),
                ("WRPAC providers", VerificationContextWalletRelyingPartyAccessCertificate.shared),
                ("WRPRC providers", VerificationContextWalletRelyingPartyRegistrationCertificate.shared),
            ]

            var collected: [ContextResult] = []
            for entry in refImplContexts {
                let anchors = try await EudiwIosTrust.shared.trustAnchors(
                    validator: validator,
                    context: entry.context
                )
                collected.append(ContextResult(name: entry.name, anchorCount: anchors.count))
            }
            results = collected

            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Builds (once) a **cached** validator and reuses it so repeated anchor resolutions are served
    /// from the in-memory cache. Demonstrates the cache by resolving PID anchors twice and comparing
    /// the cold (network) vs warm (cache) timing, then runs the same validation demo as `run()`.
    func runCached() async {
        phase = .loading
        results = []
        validations = []

        // Create the cached validator once and keep it for the session; reusing it is what makes the
        // second resolution a cache hit. `dispose()` is called in `deinit`.
        let validator: CachedTrustValidator
        if let existing = cachedValidator {
            validator = existing
        } else {
            let urls = TrustListUrls()
            urls.pidProviders    = pidProvidersURL
            urls.walletProviders = walletProvidersURL
            urls.wrpacProviders  = wrpacProvidersURL
            urls.mdlProviders    = mdlProvidersURL
            validator = EudiwIosTrust.shared.cached(urls: urls, ttlHours: 24, verifyJwtSignature: InsecureAcceptAllJwtSignature.shared)
            cachedValidator = validator
        }

        do {
            // Demonstrate the cache: resolve PID anchors twice and compare timing.
            let coldStart = Date()
            _ = try await validator.trustAnchors(context: VerificationContextPID.shared)
            let coldMs = Int(Date().timeIntervalSince(coldStart) * 1000)

            let warmStart = Date()
            _ = try await validator.trustAnchors(context: VerificationContextPID.shared)
            let warmMs = Int(Date().timeIntervalSince(warmStart) * 1000)

            // Resolve anchors per context for the counts (all served from cache after the first hit).
            var collected: [ContextResult] = []
            for entry in contexts {
                let anchors = try await validator.trustAnchors(context: entry.context)
                collected.append(ContextResult(name: entry.name, anchorCount: anchors.count))
            }
            results = collected

            var outcomes: [ValidationOutcome] = [
                ValidationOutcome(
                    label: "PID anchors: cold \(coldMs) ms → warm \(warmMs) ms",
                    trusted: true,
                    detail: "second resolution served from the in-memory cache"
                )
            ]

            // Same validation demo as the LoTE flow, but through the cached handle.
            let mdlAnchors = try await validator.trustAnchors(context: mdlContext)
            if let sample = mdlAnchors.first {
                let chain = [sample]
                let asMdl = try await validator.validate(chain: chain, context: mdlContext)
                let asPid = try await validator.validate(chain: chain, context: VerificationContextPID.shared)
                outcomes.append(ValidationOutcome(label: "mDL anchor → mDL context",
                                                  trusted: asMdl.isTrusted, detail: asMdl.failureReason))
                outcomes.append(ValidationOutcome(label: "mDL anchor → PID context",
                                                  trusted: asPid.isTrusted, detail: asPid.failureReason))
            }
            validations = outcomes

            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Validates a chain against trust anchors **bundled with the app** (no LoTE / no network).
    ///
    /// Demonstrates `EudiwIosTrust.usingBundledAnchors`, the iOS counterpart of bundling root
    /// certificates and validating credential chains against them — the "classic" pre-LoTE flow.
    /// Loads two DER certificates shipped in the app bundle (a self-signed test root CA and a leaf
    /// issued by it) and runs three checks.
    func runBundled() async {
        phase = .loading
        results = []
        validations = []

        guard let rootData = Self.loadBundledDER("eudi-test-root"),
              let leafData = Self.loadBundledDER("eudi-test-leaf") else {
            phase = .failed(
                "Could not load bundled certificates. Ensure eudi-test-root.der and " +
                "eudi-test-leaf.der are members of the app target."
            )
            return
        }

        let root = rootData
        let leaf = leafData

        results = [
            ContextResult(name: "Bundled root CA (DER bytes)", anchorCount: rootData.count),
            ContextResult(name: "Bundled leaf (DER bytes)", anchorCount: leafData.count),
        ]

        do {
            // PKIX: the trust anchor is the bundled root CA; validate the leaf chain against it.
            let pkixAnchors = BundledAnchors()
            pkixAnchors.pid = [root]
            let pkix = EudiwIosTrust.shared.usingBundledAnchors(anchors: pkixAnchors, method: .pkix)
            let rootToLeaf = try await EudiwIosTrust.shared.validate(
                validator: pkix, chain: [leaf], context: VerificationContextPID.shared)

            // Direct trust: pin the bundled leaf itself; validate the same leaf.
            let pinAnchors = BundledAnchors()
            pinAnchors.pid = [leaf]
            let pinning = EudiwIosTrust.shared.usingBundledAnchors(anchors: pinAnchors, method: .directTrust)
            let pinnedLeaf = try await EudiwIosTrust.shared.validate(
                validator: pinning, chain: [leaf], context: VerificationContextPID.shared)

            // Negative: the PKIX validator has no anchors for QEAA, so the leaf is not trusted there.
            let unconfigured = try await EudiwIosTrust.shared.validate(
                validator: pkix, chain: [leaf], context: VerificationContextQEAA.shared)

            validations = [
                ValidationOutcome(label: "Bundled root CA → leaf (PID, PKIX)",
                                  trusted: rootToLeaf.isTrusted, detail: rootToLeaf.failureReason),
                ValidationOutcome(label: "Pinned leaf → leaf (PID, direct trust)",
                                  trusted: pinnedLeaf.isTrusted, detail: pinnedLeaf.failureReason),
                ValidationOutcome(label: "Leaf → QEAA (no bundled anchors)",
                                  trusted: unconfigured.isTrusted, detail: unconfigured.failureReason),
            ]
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private static func loadBundledDER(_ name: String) -> Data? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "der") else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Validates the pasted certificate (single PEM, multi-PEM chain, or raw base64 DER) against
    /// the picked verification context, using a fresh ref-impl validator. No relax — the strict
    /// ETSI profile is enforced; a profile-violation reason is surfaced in `failureReason`.
    func runTestCertificate() async {
        phase = .loading
        results = []
        validations = []

        let chain = Self.pemToCertChain(pastedPEM)
        guard !chain.isEmpty else {
            phase = .failed("Could not parse certificate. Paste a PEM block (with -----BEGIN/END CERTIFICATE-----) or a raw base64 DER.")
            return
        }

        let urls = TrustListUrls()
        urls.pidProviders    = EUDIRefImplLists.pidProviders
        urls.walletProviders = EUDIRefImplLists.walletProviders
        urls.wrpacProviders  = EUDIRefImplLists.wrpacProviders
        urls.wrprcProviders  = EUDIRefImplLists.wrprcProviders
        let validator = EudiwIosTrust.shared.nonCached(urls: urls, verifyJwtSignature: InsecureAcceptAllJwtSignature.shared)

        do {
            let outcome = try await EudiwIosTrust.shared.validate(
                validator: validator,
                chain: chain,
                context: selectedTestContext.verificationContext
            )
            let chainLabel = "Pasted chain (\(chain.count) cert\(chain.count == 1 ? "" : "s"))"
            validations = [
                ValidationOutcome(
                    label: "\(chainLabel) → \(selectedTestContext.rawValue) context",
                    trusted: outcome.isTrusted,
                    detail: outcome.failureReason
                )
            ]
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Parses one or more PEM-encoded certificates from a free-form text block (the typical paste).
    /// Falls back to treating the whole text as a single base64-encoded DER if no PEM headers are
    /// present (e.g. a single `x5c` JSON entry).
    private static func pemToCertChain(_ text: String) -> [Data] {
        var chain: [Data] = []
        var current = ""
        var inCert = false
        for rawLine in text.split(whereSeparator: { $0.isNewline }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("-----BEGIN") {
                inCert = true
                current = ""
            } else if line.hasPrefix("-----END") {
                inCert = false
                if let data = Data(base64Encoded: current) {
                    chain.append(data)
                }
            } else if inCert {
                current.append(line)
            }
        }
        if chain.isEmpty {
            let stripped = text.filter { !$0.isWhitespace }
            if !stripped.isEmpty, let data = Data(base64Encoded: stripped) {
                chain.append(data)
            }
        }
        return chain
    }
}
