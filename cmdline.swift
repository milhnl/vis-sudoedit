import Foundation

let pid: pid_t = Int32(CommandLine.arguments[1]) ?? 0

var query: [CInt] = [CTL_KERN, KERN_PROCARGS2, pid]
var length: size_t = 0
if sysctl(&query, CUnsignedInt(query.count), nil, &length, nil, 0) < 0 {
  exit(1)
}

var buffer = [CChar](repeating: 0, count: length)
if sysctl(&query, CUnsignedInt(query.count), &buffer, &length, nil, 0) < 0 {
  exit(1)
}
buffer.withUnsafeBufferPointer { p in
  if p.count < MemoryLayout<CInt>.size {
    exit(1)
  }
  var argc: CInt = 0
  memcpy(&argc, p.baseAddress, MemoryLayout<CInt>.size)

  var i = MemoryLayout<CInt>.size
  var from: size_t = 0

  for j in 0..<(argc + 1) {
    if j == 1 {
      from = i  //Skip first field, which is a path or something
    }
    while i < p.count && p[i] != 0 {
      i += 1
    }
    while i < p.count && p[i] == 0 {
      i += 1
    }
    if i == p.count {
      exit(1)
    }
  }
  p.baseAddress?.advanced(by: from).withMemoryRebound(
    to: CChar.self, capacity: i - from
  ) {
    ptr in
    FileHandle.standardOutput.write(
      Data(
        bytesNoCopy: UnsafeMutableRawPointer(mutating: ptr), count: i - from,
        deallocator: .none)
    )
  }
}
