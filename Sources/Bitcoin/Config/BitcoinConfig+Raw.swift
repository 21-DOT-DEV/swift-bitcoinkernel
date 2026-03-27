//
//  BitcoinConfig+Raw.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

// MARK: - Raw Argument Escape Hatch

extension BitcoinConfig {

    /// Appends a raw CLI argument string for options not yet modeled by
    /// the typed API.
    ///
    /// Prefer the typed methods whenever available — they set `ConfigFlags`
    /// so conflicts are caught by `validate()`. Raw arguments bypass this
    /// mechanism entirely: `validate()` cannot detect conflicts introduced
    /// via `.raw()`.
    ///
    /// ```swift
    /// BitcoinConfig.mainnet()
    ///     .server()
    ///     .raw("-newunmodeledoption=value")
    /// ```
    public func raw(_ argument: String) -> Self {
        appending(argument)
    }
}
