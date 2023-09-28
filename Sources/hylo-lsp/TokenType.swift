
public enum TokenType : UInt32, CaseIterable {
  case type
  case typeParameter
  case identifier
  case number
  case string
  case variable
  case parameter
  case label
  case `operator`
  case function
  case keyword
  case namespace
  case unknown

  var description: String {
      return String(describing: self)
  }
}
