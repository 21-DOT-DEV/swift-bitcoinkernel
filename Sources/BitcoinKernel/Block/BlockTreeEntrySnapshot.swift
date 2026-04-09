/// An owned snapshot of a ``BlockTreeEntry``'s data.
///
/// Unlike ``BlockTreeEntry`` (a view type whose pointer lifetime is tied to
/// ``ChainstateManager``), a snapshot owns all its data and is safe to store
/// indefinitely. Used in callback contexts where the C pointer is only valid
/// during the callback invocation.
public struct BlockTreeEntrySnapshot: Sendable {
    /// The block height.
    public let height: Int32
    /// The block hash (owned copy).
    public let blockHash: BlockHash
    /// The block header (owned copy).
    public let blockHeader: BlockHeader
}
