public struct BinaryHeap<Element> {
    public typealias Index = Int

    var storage: [Element]
    let comparator: (Element, Element) -> Bool

    public var count: Int {
        storage.count
    }

    public init(comparator: @escaping (Element, Element) -> Bool) {
        self.storage = []
        self.comparator = comparator
    }

    /// Inserts the given element into the `BinaryHeap`.
    ///
    /// - Complexity: O(log n)
    public mutating func insert(_ element: Element) {
        storage.append(element)
        siftUp(startingAt: lastStorageIndex)
    }

    /// Returns the first element in the `BinaryHeap`.
    ///
    /// - Complexity: O(1)
    public func peek() -> Element? {
        storage.first
    }

    /// Removes and returns the first element from the `BinaryHeap`.
    ///
    /// - Complexity: O(log n)
    public mutating func pop() -> Element? {
        delete(at: 0)
    }

    // MARK: - Internals

    /// Remove the item at the given index
    ///
    /// - Complexity: O(log n)
    private mutating func delete(at index: Index) -> Element? {
        guard storage.count > index else {
            return nil
        }

        guard storage.count > 1 else {
            // The element to remove is the only one we have
            return storage.removeLast()
        }

        storage.swapAt(index, lastStorageIndex)
        let removed = storage.removeLast()

        siftDown(startingAt: index)

        return removed
    }

    private mutating func siftUp(startingAt startIndex: Index) {
        var idx = startIndex

        // 1. Compare the element at idx to its parent.
        // 2. If they are not in the correct order:
        //    * Swap them
        //    * Go back to 1
        while idx > 0 && comparator(storage[idx], storage[parentIndex(of: idx)]) {
            let parentIdx = parentIndex(of: idx)
            storage.swapAt(idx, parentIdx)
            idx = parentIdx
        }
    }

    private mutating func siftDown(startingAt startIndex: Index) {
        var idx = startIndex

        // 1. Compare the element at idx with its children.
        // 2. If they are not in the correct order:
        //    * Swap the parent with its children based on the comparator
        //    * Go back to 1
        while idx < lastStorageIndex {
            let leftIdx = leftChildIndex(of: idx)
            let rightIdx = rightChildIndex(of: idx)

            guard leftIdx < storage.count, rightIdx < storage.count else {
                break
            }

            let leftChild = storage[leftIdx]
            let rightChild = storage[rightIdx]

            guard comparator(leftChild, storage[idx]) || comparator(rightChild, storage[idx]) else {
                // The heap is already in the correct order
                break
            }

            if comparator(leftChild, rightChild) {
                storage.swapAt(idx, leftIdx)
                idx = leftIdx
            } else {
                storage.swapAt(idx, rightIdx)
                idx = rightIdx
            }
        }
    }

    // MARK: Index Helpers

    private var lastStorageIndex: Index {
        storage.endIndex - 1
    }

    private func parentIndex(of index: Index) -> Index {
        (index - 1) / 2
    }

    private func leftChildIndex(of index: Index) -> Index {
        index * 2 + 1
    }

    private func rightChildIndex(of index: Index) -> Index {
        index * 2 + 2
    }
}

// MARK: -

extension BinaryHeap {
    public init<Value>(keyPath: KeyPath<Element, Value>, comparator: @escaping (Value, Value) -> Bool) {
        self.init { lhs, rhs in
            comparator(lhs[keyPath: keyPath], rhs[keyPath: keyPath])
        }
    }
}

extension BinaryHeap where Element: Comparable {
    public static func minHeap() -> Self {
        self.init(comparator: <)
    }

    public static func maxHeap() -> Self {
        self.init(comparator: >)
    }
}
