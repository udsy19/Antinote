import Foundation
import JotterCore

/// First-launch tutorial: a short stack of notes that teach swiping, keywords and slots by example.
@MainActor
enum Onboarding {
    static func runIfNeeded() {
        guard !Defaults[.onboardingCompleted] else { return }
        if Services.store.deck.isEmpty { seedTutorial() }
        Defaults[.onboardingCompleted] = true
    }

    /// Front (newest) note first; swiping "previous" walks down the list.
    static let tutorialNotes: [String] = [
        """
        Welcome to Jotter!

        Jot first, sort never. Notes here are scraps: no titles, no folders, no filing.

        ← Swipe right with two fingers (or press ⌘[) for the next tip.
        """,
        """
        list
        The first line decides what a note does
        Tick this line with ⇧⌘M
        “todo” and “tasks” work as keywords too

        ← Keep swiping
        """,
        """
        math
        Lines ending in = get answered.
        12 × 4 =
        15% of 80 =
        5 km in miles =
        rent = 1200
        rent / 3 =

        ← Next
        """,
        """
        sum
        Coffee 4.50
        Train ticket 12
        Lunch 9.80

        Every number below “sum” is added up. Try “avg” for an average.

        ← Next
        """,
        """
        count
        Basil
        Mint
        Thyme

        “count” tallies the lines below it.

        ← Next
        """,
        """
        timer 5
        A countdown starts when the first line says “timer 5”.
        “timer” alone is a stopwatch, “pomodoro” runs work and break rounds.

        ← Next
        """,
        """
        code
        func greet(_ name: String) {
            print("Hi, \\(name)")
        }

        “code” highlights syntax and pastes text exactly as copied.

        ← Next
        """,
        """
        paste
        While this note is open, everything you copy lands here.

        ← Next
        """,
        """
        Commands start with two colons. Type ::today on the empty line below and press Return.


        ⌘K opens the command palette, ⇧⌘F searches every note.

        ← One more
        """,
        """
        That's the tour!

        ⌘N  new note        ⌘⌫  send to The Void
        ⇧⌘P  pin on top     ⌘1…⌘9  slotted notes
        ⌘,  settings

        Hover the top edge for buttons. Swipe left (⌘]) past the newest note to start a fresh one.
        """,
    ]

    static let slottedNote = """
    Slot 1

    Slotted notes stay put while the rest of the deck moves on. ⌘1…⌘9 open them, ⌘0 goes back to the deck, \
    ⌃⌘1…⌃⌘9 put the current note in a slot.
    """

    /// Adds the tutorial notes to the front of the deck (and the slotted example when slot 1 is free).
    static func seedTutorial() {
        let store = Services.store!
        if !store.deck.contains(where: { $0.slot == 0 }) {
            let note = store.create(content: slottedNote)
            store.setSlot(0, for: note.id)
        }
        // `create` puts each note at the front, so add them oldest first.
        for text in tutorialNotes.reversed() { store.create(content: text) }
    }
}
