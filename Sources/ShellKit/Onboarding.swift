import Foundation
import SuperNotesCore

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
        let previous = key("Show Previous Note", "⌘[")
        let hotkey = Defaults[.globalHotkey]?.displayString ?? "⌥A"
        return [
            """
            Welcome to Super Notes!

            This is a scratchpad, not a filing cabinet. Don't title your notes, don't sort them, don't tidy them up. Just write.

            Typos and half-thoughts are welcome here.

            Press \(hotkey) from anywhere to show or hide Super Notes.

            Everything you write stays on this Mac. Nothing is uploaded unless you turn on sync yourself.

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
            list: Weekend
            [ ] Every line becomes something to tick off

            # Headers split a list into sections
            [ ] Water the plants
            [ ] Return the library books
            [ ] Click a box, or press \(key("Check Off Current Line", "⇧⌘K")), to check it
            [x] Like this one

            [←] Great job!
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

            [←] Almost at the end!
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

            Type “/” on an empty line: every keyword and command shows up right there, and 1–9 picks one.

            \(key("Command Palette…", "⌘K")) opens the same commands, plus your notes, in their own window.

            Commands also run inside notes. Type ::today() on the empty line below and press Return.


            ↑ Right there
            [←] One more!
            """,
            """


            Last trick, promise.

            Take a screenshot of some text, then drag or paste it into this note. Super Notes types the text out for you.


            [←]
            """,
            """
            That's the tour!

            \(key("Search All Notes", "⌘F"))  Search every note
            \(key("Pin Super Notes to Top", "⌘P"))  Keep Super Notes above other windows
            \(key("Delete Note", "⌘D"))  Delete a note (it waits in The Void)
            \(key("Jump to Front", "⌘1"))  Jump to the latest note
            \(key("Move Note to Front", "⇧⌘1"))  Bring a note to the front

            Hover over the top of the window for more buttons.

            Settings (\(key("Settings…", "⌘,"))) has themes, keywords, privacy switches and plenty more.

            When you're ready, start your first note with \(key("Create New Note", "⌘N")).

            Happy jotting!
            """,
        ]
    }

    /// One note per slot, named for the god of its planet (Mercury → Hermes … Pluto → Hades).
    static let slottedNotes: [String] = [
        "# Hermes\n\nThe first of nine slotted notes. Slotted notes stay put while the deck moves on.",
        "# Aphrodite", "# Gaia", "# Ares", "# Zeus", "# Cronus", "# Ouranos", "# Poseidon", "# Hades",
    ]

    /// Adds the tutorial notes to the front of the deck and fills every free slot with its slotted note.
    static func seedTutorial() {
        let store = Services.store!
        for (slot, text) in slottedNotes.enumerated() where !store.deck.contains(where: { $0.slot == slot }) {
            store.setSlot(slot, for: store.create(content: text).id)
        }
        // `create` puts each note at the front, so add them oldest first. The oldest is the tutorial's last note.
        for (i, text) in tutorialNotes.reversed().enumerated() {
            let note = store.create(content: text)
            if i == 0 { Defaults[.tutorialFinaleNote] = note.id.uuidString }
        }
    }

    /// Shows the "tutorial is over" pill the first time the last tutorial note comes up.
    static func noteShown(_ id: UUID) {
        guard !Defaults[.tutorialFinaleNote].isEmpty, Defaults[.tutorialFinaleNote] == id.uuidString else { return }
        Defaults[.tutorialFinaleNote] = ""
        HUD.show("The tutorial is over. You can start using the app now.", kind: .success)
    }
}
