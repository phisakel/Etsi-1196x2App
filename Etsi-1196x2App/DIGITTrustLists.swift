//
//  DIGITTrustLists.swift
//  Etsi-1196x2App
//
//  LoTE trust-list endpoints (EC DIGIT acceptance environment).
//

import Foundation

struct DIGITTrustLists {
    static let baseUrl = "https://acceptance.trust.tech.ec.europa.eu/lists/eudiw"

    static let pidProviders = "\(baseUrl)/pid-providers.json"
    static let walletProviders = "\(baseUrl)/wallet-providers.json"
    static let wrpacProviders = "\(baseUrl)/wrpac-providers.json"
    static let mdlProviders = "\(baseUrl)/mdl-providers.json"
}

// LoTE trust-list endpoints for the EUDI Wallet Reference Implementation environment.
// No mDL list (the ref-impl env doesn't publish one); has WRPRC instead.
struct EUDIRefImplLists {
    static let baseUrl = "https://trustedlist.serviceproviders.eudiw.dev/LOTE/json"

    static let pidProviders = "\(baseUrl)/PIDProviders.jwt"
    static let walletProviders = "\(baseUrl)/WalletProviders.jwt"
    static let wrpacProviders = "\(baseUrl)/WRPACProviders.jwt"
    static let wrprcProviders = "\(baseUrl)/WRPRCProviders.jwt"
}
