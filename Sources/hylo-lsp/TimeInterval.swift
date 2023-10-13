import Foundation

extension TimeInterval {

  var seconds: Int {
    return Int(self.rounded())
  }

  var milliseconds: Int {
    return Int((self * 1_000).rounded())
  }
}
