/// An owned snapshot of a ``BlockTreeEntry``'s data — three fields
/// (height, block hash, block header) captured as Swift-owned values.
///
/// Unlike ``BlockTreeEntry`` (a view type whose pointer lifetime is tied
/// to ``ChainstateManager``), a snapshot owns all its data and is safe to
/// store indefinitely, pass across tasks, and capture in closures.
///
/// Used primarily by kernel notification callbacks
/// (``NotificationCallbacks/blockTip``,
/// ``ValidationInterfaceCallbacks/blockConnected`` etc.), where the
/// underlying C pointer is only valid during the callback invocation.
/// Promote any `BlockTreeEntry` to a snapshot before escaping the
/// callback scope.
public struct BlockTreeEntrySnapshot: Sendable {
    /// The block's height above genesis (`0` for genesis).
    public let height: Int32

    /// The block's hash, as an owned copy safe to store indefinitely.
    public let blockHash: BlockHash

    /// The 80-byte block header, as an owned copy safe to store
    /// indefinitely.
    public let blockHeader: BlockHeader
}
