import Foundation

/// The pomodoro "no-peek" streak: breaks sat out without sneaking a peek at the notes, in a row.
public struct NoPeekStreak: Codable, Equatable, Sendable {
    public var current = 0
    public var best = 0

    public init(current: Int = 0, best: Int = 0) { self.current = current; self.best = best }

    /// A break ran to the end with the break screen still up.
    public mutating func breakCompleted() {
        current += 1
        best = max(best, current)
    }

    /// "Sneak a peek" (or Esc) during a break.
    public mutating func peeked() { current = 0 }
}

/// Short lines for the full-screen timer screens.
enum BreakContent {
    /// Shown on the break screen under "Wildlife fact-file".
    static let facts = [
        "Octopuses have three hearts and blue blood.",
        "A group of flamingos is called a flamboyance.",
        "Sea otters hold paws while they sleep so they don't drift apart.",
        "Hummingbirds can hover in place and even fly backwards.",
        "Elephants recognise themselves in a mirror.",
        "Crows can remember a human face for years.",
        "Honeybees tell each other where flowers are by dancing.",
        "A blue whale's heart is about the size of a golf cart.",
        "Gentoo penguins court their mates with a carefully chosen pebble.",
        "Wombats leave cube-shaped droppings.",
        "Cheetahs can't roar, but they do purr.",
        "A giraffe's neck has seven bones, the same number as yours.",
        "A shrimp's heart sits in its head.",
        "Owls can't move their eyes, so they turn their whole head instead.",
        "Axolotls can regrow lost legs.",
        "Dolphins call each other by signature whistles that work like names.",
        "Butterflies taste with their feet.",
        "Squirrels plant forests by forgetting where they buried their nuts.",
        "Under their white-looking fur, polar bears have black skin.",
        "Tardigrades can survive years of being frozen and dried out.",
        "Horses can doze standing up.",
        "Ants get by without lungs.",
        "Rats make laughing sounds when they're tickled.",
        "Male seahorses are the ones who carry the babies.",
        "Bats are the only mammals that can truly fly.",
        "Goats have rectangular pupils.",
        "Frogs drink water through their skin.",
        "Sea stars have no brain at all.",
        "Snow leopards can't roar; they chuff instead.",
        "A koala can sleep around twenty hours a day.",
    ]

    /// Shown when a break ends.
    static let backToWork = [
        "Break's done. Pick up where you left off.",
        "Rested? Let's get the next one done.",
        "Back to it, one small step at a time.",
        "Fresh eyes. Good time to start again.",
        "Whenever you're ready, the work is waiting.",
        "Next round. You've got this.",
    ]

    static func randomFact() -> String { facts.randomElement() ?? "" }
}
