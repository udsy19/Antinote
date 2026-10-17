import Foundation
import JotterCore

/// First-launch tutorial: ordinary notes seeded into the stack. The front note welcomes you; each note ends with a
/// "[←]" hint pointing to the previous one, and every keyword note demonstrates its feature live.
@MainActor
enum Onboarding {
    static func runIfNeeded() {
        guard !Defaults[.onboardingCompleted] else { return }
        if Services.store.deck.isEmpty { seedTutorial() }
        Defaults[.onboardingCompleted] = true
    }

    /// The shortcut a menu item currently uses (from the built main menu), or `fallback`.
    private static func key(_ title: String, _ fallback: String) -> String {
        MainMenu.shortcuts.first { $0.title == title }?.keys ?? fallback
    }

    /// Front (newest) note first; going to the previous note walks down the list.
    static var tutorialNotes: [String] {
        let previous = key("Previous Note", "⌘[")
        return [
            """
            Welcome to Jotter!

            This is a scratchpad, not a filing cabinet. Don't title your notes, don't sort them, don't tidy them up. Just write.

            Typos and half-thoughts are welcome here.

            [←] Swipe right with two fingers (or press \(previous)) to see the previous note.
            """,
            """
            math

            A keyword on the first line switches a note into a mode.

            With “math” up top, every line that ends in an equals sign gets answered.

            180 + (36 / 4) * 3 =

            $3.80 for oat milk + $12 for dumplings =

            And that's only the start.

            [←] Swipe.
            """,
            """
            math

            “math” converts units and currencies too.

            26.2 miles to km =
            5 ft 11 in to cm =
            2 cups in ml =

            €40 to USD =

            An amount on its own converts your primary currency into your secondary one:

            $15 =

            Any other currency converts into your primary one:

            0.01 BTC =

            Pick both currencies in Settings.

            [←] Variables next. They're the best part.
            """,
            """
            math

            Name a number with a colon, then use the name further down.

            friends: 6
            ticket price: $18
            friends * ticket price =

            hourly rate: 31.50
            weekly pay: hourly rate * 37.5 =
            yearly pay: weekly pay * 48 =

            [←] Now, a short pause.
            """,
            """
            Long breath in…

            …and slowly out.

            There. Better.

            For a guided version, choose Breathe in the command palette (\(key("Command Palette…", "⌘K"))).

            [←]
            """,
            """
            sum

            “sum” adds up every number in the note.

            Ferry $7.50, two coffees $9, a paperback $14 and a pretzel $3.25.

            [←] Next
            """,
            """
            avg

            Same idea, but you get the average.

            Monday 7.5 hours
            Tuesday 6 hours
            Wednesday 8.25 hours

            [←] Nearly there!
            """,
            """
            count
            Count tallies lines, words and characters.
            Mango
            Papaya
            Dragon fruit
            [←] Keep going
            """,
            """
            list: Weekend
            [ ] Every line becomes something to tick off

            # Headers split a list into sections
            [ ] Water the plants
            [ ] Return the library books
            [ ] Click a box, or press \(key("Toggle Checklist Item", "⇧⌘M")), to check it
            [x] Like this one

            [←] Well done!
            """,
            """
            Timers live in notes. Start a new note with “timer 5” on the first line and press Return.

            “timer” on its own is a stopwatch
            “timer 5” counts down five minutes
            “timer 3:30” counts down three and a half
            “timer pomo” runs a pomodoro (25/5 by default)
            “timer 50 10” runs a 50/10 pomodoro

            “timer p” pauses or resumes, “timer r” restarts and “timer s” (or Esc) stops.

            The command palette starts timers too.

            [←] Two more tricks!
            """,
            """
            Can't remember something?

            \(key("Command Palette…", "⌘K")) opens the command palette: every action, timer and note in one list.

            Commands also run inside notes. Type ::today() on the empty line below and press Return.


            ↑ Right there
            [←] One more!
            """,
            """


            Last trick, promise.

            Take a screenshot of some text, then drag or paste it into this note. Jotter types the text out for you.


            [←]
            """,
            """
            That's the tour!

            \(key("Search All Notes…", "⇧⌘F"))  Search every note
            \(key("Pin on Top", "⇧⌘P"))  Keep Jotter above other windows
            \(key("Move to The Void", "⌘⌫"))  Send a note to The Void
            \(key("First Note", "⇧⌘L"))  Jump to the latest note
            \(key("Promote to Front", "⇧⌘T"))  Bring a note to the front

            Hover over the top of the window for more buttons.

            Settings (\(key("Settings…", "⌘,"))) has themes, keywords, privacy switches and plenty more.

            When you're ready, start your first note with \(key("New Note", "⌘N")).

            Happy jotting!
            """,
        ]
    }

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
