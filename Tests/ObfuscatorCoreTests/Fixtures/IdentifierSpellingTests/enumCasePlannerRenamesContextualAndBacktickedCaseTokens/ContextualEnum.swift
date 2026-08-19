private enum ContextualToken {
    case open
    case get
    case left
}
private let first = ContextualToken.open
private let second = ContextualToken.get
private let third = ContextualToken.left
private enum EscapedToken {
    case `public`
}
private let escaped = EscapedToken.public
