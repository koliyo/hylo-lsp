#if os(macOS)
import Darwin
import Foundation

// https://stackoverflow.com/questions/24321773/how-can-i-demangle-a-swift-class-name-dynamically
typealias Swift_Demangle = @convention(c) (_ mangledName: UnsafePointer<UInt8>?,
                                           _ mangledNameLength: Int,
                                           _ outputBuffer: UnsafeMutablePointer<UInt8>?,
                                           _ outputBufferSize: UnsafeMutablePointer<Int>?,
                                           _ flags: UInt32) -> UnsafeMutablePointer<Int8>?

func swift_demangle(_ mangled: String) -> String? {
    let RTLD_DEFAULT = dlopen(nil, RTLD_NOW)
    if let sym = dlsym(RTLD_DEFAULT, "swift_demangle") {
        let f = unsafeBitCast(sym, to: Swift_Demangle.self)
        if let cString = f(mangled, mangled.count, nil, nil, 0) {
            defer { cString.deallocate() }
            return String(cString: cString)
        }
    }
    return nil
}

func printStackTrace() {
  for s in Thread.callStackSymbols {
    printStackFrame(s)
  }
}

func printStackFrame(_ frameStr: String) {
    let search = #/(\d+)\s+([.\w-]+)\s+(0x\w+)\s+(\$?\w+)\s+\+\s+(\d+)/#
    if let result = try? search.firstMatch(in: frameStr) {
      // print("\(result.1), \(result.2), \(result.3), \(result.4), \(result.5)")
      let frame = result.1
      let symbol = result.4
      if let demangled = swift_demangle(String(symbol)) {
        print("\(frame): \(demangled)")
      }
      else {
        print("\(frame): \(symbol) (demangle failed)")
      }
    }
    else {
      print("\(frameStr)")
    }
}
#endif
