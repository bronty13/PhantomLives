import Foundation

/// Forward-compat event stream. Every inbound IRC message, every state
/// transition, and the outbound lines a connection emits fan out through this
/// enum so a session layer (and any scripting host / listener) can subscribe
/// without touching core dispatch. Kept `Sendable` so a consumer off the main
/// actor can handle events safely.
///
/// Lives in IRCKit so every PhantomLives IRC app (PurpleIRC's `IRCConnection`,
/// Ircle's `IrcleSession`) speaks the same connection-event vocabulary.
public enum IRCConnectionEvent: Sendable {
    case state(IRCConnectionState)
    case inbound(IRCMessage)
    case outbound(String)
    case ownNickChanged(String)
    /// Any user on a shared channel changed nick. `isSelf == true` on our
    /// own changes (which are *also* delivered as `.ownNickChanged`).
    case nickChanged(old: String, new: String, isSelf: Bool)
    case privmsg(from: String, target: String, text: String, isAction: Bool, isMention: Bool)
    case notice(from: String, target: String, text: String)
    case join(nick: String, channel: String, isSelf: Bool)
    case part(nick: String, channel: String, reason: String?, isSelf: Bool)
    case quit(nick: String, reason: String?)
    case topic(channel: String, topic: String, setter: String?)
    case ctcpRequest(from: String, target: String, command: String, args: String)
    case awayChanged(isAway: Bool, reason: String?)
    case ignoredMessage(from: String, target: String)
    /// Fired when a fresh query buffer is auto-created by an inbound
    /// PRIVMSG from a watched contact AND the user has opted into the
    /// pop-on-watch behavior. A session layer consumes this by switching
    /// the active connection (if needed) and selecting the new buffer.
    /// The event carries the connection's UUID via the events publisher
    /// tuple, so the receiver knows which network owns `bufferID`.
    case watchedQueryAutoOpened(bufferID: UUID, from: String)
}
