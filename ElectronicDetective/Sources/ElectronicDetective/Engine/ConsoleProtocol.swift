import Foundation

/// The function-key vocabulary on the original console. Used as the discrete
/// key set on the on-screen keypad and as the operation set the
/// `ConsoleViewModel` interprets.
enum ConsoleKey: Hashable, Sendable {
    case digit(Int)               // 0...9
    case onOff                    // ON
    case suspect                  // SUSPECT
    case privateQuestion          // PRIVATE QUESTION
    case enter                    // ENTER
    case endTurn                  // END TURN
    case iAccuse                  // I ACCUSE
    case clear                    // CLEAR
    case readout                  // READOUT (re-display the last answer)
}

/// What the LED is currently showing.
enum LEDLine: Equatable, Sendable {
    case off
    case ready                    // boot complete, awaiting input
    case prompt(String)           // e.g. "PL?" → enter player count
    case echo(String)             // echo of digits being typed
    case answer(String)           // result of a query
    case error(String)            // bad input
    case verdict(correct: Bool)
}
