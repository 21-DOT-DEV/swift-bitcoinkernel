//
//  DeploymentInfo.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Deployment information from `getdeploymentinfo` (v24+).
public struct DeploymentInfo: Codable, Sendable, Equatable {
    /// The block hash at which deployment info was queried.
    public let hash: String

    /// The block height.
    public let height: Int

    /// Map of deployment name to its status.
    public let deployments: [String: Deployment]
}

/// Status of a single soft-fork deployment.
public struct Deployment: Codable, Sendable, Equatable {
    /// The deployment type: "buried" or "bip9".
    public let type: String

    /// Whether the deployment is currently active.
    public let active: Bool

    /// The block height at which the deployment activated (buried deployments).
    public let height: Int?

    /// BIP9 status info (present for BIP9 deployments only).
    public let bip9: BIP9Status?
}

/// BIP9 deployment status.
public struct BIP9Status: Codable, Sendable, Equatable {
    /// The BIP9 status: "defined", "started", "locked_in", "active", "failed".
    public let status: String

    /// The bit position (0-28) in the block version field.
    public let bit: Int?

    /// The start time of the BIP9 deployment.
    public let startTime: Int64

    /// The timeout of the BIP9 deployment.
    public let timeout: Int64

    /// The block height of the beginning of the current period.
    public let since: Int

    /// Statistics about signalling for a softfork (only for "started" status).
    public let statistics: BIP9Statistics?

    /// The minimum activation height (0 for no minimum).
    public let minActivationHeight: Int

    enum CodingKeys: String, CodingKey {
        case status, bit, timeout, since, statistics
        case startTime = "start_time"
        case minActivationHeight = "min_activation_height"
    }
}

/// BIP9 signalling statistics.
public struct BIP9Statistics: Codable, Sendable, Equatable {
    /// The length in blocks of the signalling period.
    public let period: Int

    /// The number of blocks with the version bit set in this period.
    public let count: Int

    /// The number of blocks elapsed in this period.
    public let elapsed: Int

    /// `true` if the threshold was reached in this period.
    public let possible: Bool

    /// The required number of signalling blocks.
    public let threshold: Int
}
