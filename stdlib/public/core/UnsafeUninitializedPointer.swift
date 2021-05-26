//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@usableFromInline
@frozen
internal struct _StackArray64B {
  private var _storage: (UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64)
    = (.init(), .init(), .init(), .init(), .init(), .init(), .init(), .init())

  @inlinable
  internal init() { }
}

@usableFromInline
@frozen
internal struct _StackArray256B {
  private var _storage: (_StackArray64B, _StackArray64B, _StackArray64B, _StackArray64B)
    = (.init(), .init(), .init(), .init())

  @inlinable
  internal init() { }
}

@usableFromInline
@frozen
internal struct _StackArray1KB {
  private var _storage: (_StackArray256B, _StackArray256B, _StackArray256B, _StackArray256B)
    = (.init(), .init(), .init(), .init())

  @inlinable
  internal init() { }
}

/// Provides scoped access to a raw buffer pointer with the specified byte count
/// and alignment.
///
/// - Parameters:
///   - byteCount: The number of bytes to temporarily allocate. `byteCount` must
///     not be negative.
///   - alignment: The alignment of the new, temporary region of allocated
///     memory, in bytes.
///   - body: A closure to invoke and to which the allocated buffer pointer
///     should be passed.
///
///  - Returns: Whatever is returned by `body`.
///
///  - Throws: Whatever is thrown by `body`.
///
/// This function is useful for cheaply allocating raw storage for a brief
/// duration. Storage may be allocated on the heap or on the stack, depending on
/// the required size and alignment.
///
/// When `body` is called, the contents of the buffer pointer passed to it are
/// in an unspecified, uninitialized state. `body` is responsible for
/// initializing the buffer pointer before it is used _and_ for deinitializing
/// it before returning. `body` does not need to deallocate the buffer pointer.
///
/// The implementation may allocate a larger buffer pointer than is strictly
/// necessary to contain `byteCount` bytes. The behavior of a program that
/// attempts to access any such additional storage is undefined.
///
/// The buffer pointer passed to `body` (as well as any pointers to elements in
/// the buffer) must not escape—it will be deallocated when `body` returns and
/// cannot be used afterward.
@inlinable
public func withUnsafeUninitializedMutableRawBufferPointer<ReturnType>(byteCount: Int, alignment: Int, _ body: (UnsafeMutableRawBufferPointer) throws -> ReturnType) rethrows -> ReturnType {
  precondition(byteCount > 0, "Too little uninitialized memory requested.")
  precondition(alignment > 0, "Nonsensical alignment requested.")

  let heapNeeded: Bool
  if byteCount > MemoryLayout<_StackArray1KB>.size {
    heapNeeded = true
  } else if alignment > MemoryLayout<_StackArray1KB>.alignment {
    heapNeeded = true
  } else {
    heapNeeded = false
  }

  if _slowPath(heapNeeded) {
    let heapBuffer = UnsafeMutableRawBufferPointer.allocate(byteCount: byteCount, alignment: alignment)
    defer {
      heapBuffer.deallocate()
    }
    return try body(heapBuffer)
  }

  // Try to find a reasonably-sized stack buffer to use.
  if byteCount <= MemoryLayout<UInt64>.size {
    var buffer = UInt64()
    return try withUnsafeMutableBytes(of: &buffer, body)
  } else if byteCount <= MemoryLayout<_StackArray64B>.size {
    var buffer = _StackArray64B()
    return try withUnsafeMutableBytes(of: &buffer, body)
  } else if byteCount <= MemoryLayout<_StackArray256B>.size {
    var buffer = _StackArray256B()
    return try withUnsafeMutableBytes(of: &buffer, body)
  } else {
    var buffer = _StackArray1KB()
    return try withUnsafeMutableBytes(of: &buffer, body)
  }
}

/// Provides scoped access to a buffer pointer to memory of the specified type
/// and with the specified capacity.
///
/// - Parameters:
///   - type: The type of the buffer pointer being temporarily allocated.
///   - capacity: The capacity of the buffer pointer being temporarily
///     allocated.
///   - body: A closure to invoke and to which the allocated buffer pointer
///     should be passed.
///
///  - Returns: Whatever is returned by `body`.
///
///  - Throws: Whatever is thrown by `body`.
///
/// This function is useful for cheaply allocating storage for a sequence of
/// values for a brief duration. Storage may be allocated on the heap or on the
/// stack, depending on the required size and alignment.
///
/// When `body` is called, the contents of the buffer pointer passed to it are
/// in an unspecified, uninitialized state. `body` is responsible for
/// initializing the buffer pointer before it is used _and_ for deinitializing
/// it before returning. `body` does not need to deallocate the buffer pointer.
///
/// The implementation may allocate a larger buffer pointer than is strictly
/// necessary to contain `capacity` values of type `type`. The behavior of a
/// program that attempts to access any such additional storage is undefined.
///
/// The buffer pointer passed to `body` (as well as any pointers to elements in
/// the buffer) must not escape—it will be deallocated when `body` returns and
/// cannot be used afterward.
@inlinable
public func withUnsafeUninitializedMutableBufferPointer<StorageType, ReturnType>(for type: StorageType.Type, capacity: Int, _ body: (UnsafeMutableBufferPointer<StorageType>) throws -> ReturnType) rethrows -> ReturnType {
  precondition(capacity > 0, "Too little uninitialized memory requested.")
  let (byteCount, overflowed) = MemoryLayout<StorageType>.stride.multipliedReportingOverflow(by: capacity)
  precondition(!overflowed, "Too much uninitialized memory requested.")
  let alignment = MemoryLayout<StorageType>.alignment

  return try withUnsafeUninitializedMutableRawBufferPointer(byteCount: byteCount, alignment: alignment) { buffer in
    let typedBuffer = buffer.bindMemory(to: StorageType.self)
    assert(typedBuffer.count >= capacity)
    let sizedTypedBuffer = UnsafeMutableBufferPointer(start: typedBuffer.baseAddress, count: capacity)
    return try body(sizedTypedBuffer)
  }
}

/// Provides scoped access to a pointer to memory of the specified type.
///
/// - Parameters:
///   - type: The type of the pointer to allocate.
///   - body: A closure to invoke and to which the allocated pointer should be
///     passed.
///
///  - Returns: Whatever is returned by `body`.
///
///  - Throws: Whatever is thrown by `body`.
///
/// This function is useful for cheaply allocating storage for a single value
/// for a brief duration. Storage may be allocated on the heap or on the stack,
/// depending on the required size and alignment.
///
/// When `body` is called, the contents of the pointer passed to it are in an
/// unspecified, uninitialized state. `body` is responsible for initializing the
/// pointer before it is used _and_ for deinitializing it before returning.
/// `body` does not need to deallocate the pointer.
///
/// The pointer passed to `body` must not escape—it will be deallocated when
/// `body` returns and cannot be used afterward.
@inlinable
public func withUnsafeUninitializedMutablePointer<StorageType, ReturnType>(for type: StorageType.Type, _ body: (UnsafeMutablePointer<StorageType>) throws -> ReturnType) rethrows -> ReturnType {
  return try withUnsafeUninitializedMutableBufferPointer(for: type, capacity: 1) { buffer in
    return try body(buffer.baseAddress!)
  }
}

