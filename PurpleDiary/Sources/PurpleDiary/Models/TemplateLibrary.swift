import Foundation

/// A curated, built-in library of entry templates the user can add from. These
/// are *static content* (no journal data), shipped in-app — like the writing
/// prompts — so they need no network and no bundled file.
///
/// Two roles:
/// - **Seed defaults** (`seedByDefault == true`) are inserted on a brand-new
///   install by `DatabaseService.seedDefaultTemplatesIfEmpty`, so a fresh journal
///   opens with a small, useful starter set (not an overwhelming wall).
/// - **The full set** is browsable from **Manage Templates… → Add from Library…**,
///   so *existing* installs (whose templates table isn't empty, and so never
///   re-seeds) can still pull in any of these whenever they like.
///
/// Bodies use the same `{{date}}` / `{{date_long}}` / `{{time}}` / `{{weekday}}` /
/// `{{year}}` tokens that `TemplateService.render` fills in at entry-creation
/// time. Adding a library template just copies its body into a normal, fully
/// editable `Template` row — nothing here is special-cased after insert.
struct CuratedTemplate: Identifiable, Hashable {
    var id: String { name }   // names are unique across the library (asserted in tests)
    let name: String
    let blurb: String         // one-line description for the library browser
    let body: String          // Markdown scaffold, may contain {{tokens}}
    let seedByDefault: Bool
}

enum TemplateLibrary {

    /// Templates seeded on a fresh install (a small, broadly-useful starter set).
    static var seedDefaults: [CuratedTemplate] { all.filter(\.seedByDefault) }

    /// The full curated library (seed defaults first, then the rest). Order here
    /// is the order shown in the library browser.
    static let all: [CuratedTemplate] = [

        // — Seed defaults: the starter set a new install opens with —
        CuratedTemplate(
            name: "Daily Check-in",
            blurb: "A quick once-a-day pulse: what you did, one good thing, what's on your mind.",
            body: "## {{weekday}}, {{date}}\n\n**Today I…**\n- \n\n**One good thing:** \n\n**On my mind:** ",
            seedByDefault: true),
        CuratedTemplate(
            name: "Gratitude",
            blurb: "Three things you're grateful for, and why they matter.",
            body: "## Grateful — {{date}}\n\nThree things I'm grateful for today:\n1. \n2. \n3. \n\n**Why they matter:** ",
            seedByDefault: true),
        CuratedTemplate(
            name: "Morning Pages",
            blurb: "A blank, unfiltered brain-clear to start the day.",
            body: "## Morning Pages — {{date}}\n\n*Whatever's on my mind, unfiltered:*\n\n",
            seedByDefault: true),
        CuratedTemplate(
            name: "Evening Reflection",
            blurb: "Close the day: highlight, what drained you, tomorrow's one priority.",
            body: "## Evening Reflection — {{weekday}} {{time}}\n\n**Today's highlight:** \n\n**What drained me:** \n\n**What I'm letting go of:** \n\n**Tomorrow's one priority:** ",
            seedByDefault: true),
        CuratedTemplate(
            name: "Weekly Review",
            blurb: "Wins, what slipped, lessons, and next week's focus.",
            body: "# Weekly Review — week of {{date}}\n\n**Wins this week**\n- \n\n**What didn't go to plan**\n- \n\n**What I learned**\n- \n\n**Next week's focus**\n- ",
            seedByDefault: true),

        // — Library-only: add from Manage Templates… → Add from Library… —
        CuratedTemplate(
            name: "Three Good Things",
            blurb: "A short positivity practice — three good moments from today.",
            body: "## Three Good Things — {{date}}\n\n1. \n2. \n3. \n\n**The best of the three, and why:** ",
            seedByDefault: false),
        CuratedTemplate(
            name: "Week Ahead",
            blurb: "Plan the week: top three priorities, deadlines, and something for you.",
            body: "# Week Ahead — {{date}}\n\n**Top 3 priorities**\n1. \n2. \n3. \n\n**Appointments & deadlines**\n- \n\n**Something for me**\n- ",
            seedByDefault: false),
        CuratedTemplate(
            name: "Monthly Review",
            blurb: "Step back: the month in a sentence, highlights, challenges, next goals.",
            body: "# Monthly Review — {{date}}\n\n**This month in a sentence:** \n\n**Highlights**\n- \n\n**Challenges**\n- \n\n**Goals for next month**\n- ",
            seedByDefault: false),
        CuratedTemplate(
            name: "Goals & Intentions",
            blurb: "Name a focus, why it matters, the first small step, and how you'll measure it.",
            body: "## Goals & Intentions — {{date}}\n\n**What I want to focus on:** \n\n**Why it matters:** \n\n**First small step:** \n\n**How I'll know it's working:** ",
            seedByDefault: false),
        CuratedTemplate(
            name: "Mood & Energy Check",
            blurb: "Rate your mood and energy and note what's moving them.",
            body: "## Mood & Energy — {{weekday}} {{time}}\n\n**Mood (1–10):** \n**Energy (1–10):** \n\n**What's affecting it:** \n\n**One thing that would help:** ",
            seedByDefault: false),
        CuratedTemplate(
            name: "Lessons Learned",
            blurb: "Turn an experience into a takeaway you'll act on.",
            body: "## Lessons Learned — {{date}}\n\n**What happened:** \n\n**What I learned:** \n\n**What I'll do differently:** ",
            seedByDefault: false),
        CuratedTemplate(
            name: "Decision Journal",
            blurb: "Weigh a decision now so you can review how it turned out later.",
            body: "## Decision — {{date}}\n\n**The decision:** \n\n**Options I'm weighing**\n- \n\n**What matters most here:** \n\n**Leaning toward:** \n\n*(Revisit later: how did it turn out?)*",
            seedByDefault: false),
        CuratedTemplate(
            name: "Travel Log",
            blurb: "Capture a day on a trip — place, moments, food and finds.",
            body: "# Travel — {{date_long}}\n\n**Where I am:** \n\n**Today we…**\n- \n\n**Best moment:** \n\n**Food & finds:** \n\n**To remember:** ",
            seedByDefault: false),
        CuratedTemplate(
            name: "Dream Journal",
            blurb: "Record a dream before it fades — what happened and how it felt.",
            body: "## Dream — {{date}} (woke {{time}})\n\n**What happened:** \n\n**How it felt:** \n\n**Anything it might connect to:** ",
            seedByDefault: false),
        CuratedTemplate(
            name: "Reading Notes",
            blurb: "Keep what mattered from a book or article, and how you'll use it.",
            body: "## Reading — {{date}}\n\n**Book / article:** \n**Author:** \n\n**Key ideas**\n- \n\n**A quote worth keeping:** \n\n**How I might use this:** ",
            seedByDefault: false),
        CuratedTemplate(
            name: "Meeting Notes",
            blurb: "Who, what, decisions, and action items with checkboxes.",
            body: "## Meeting — {{date}} {{time}}\n\n**With:** \n**About:** \n\n**Notes**\n- \n\n**Decisions**\n- \n\n**Action items**\n- [ ] ",
            seedByDefault: false),
        CuratedTemplate(
            name: "Workout Log",
            blurb: "Log a session — type, duration, how it felt, what to change.",
            body: "## Workout — {{weekday}}, {{date}}\n\n**Type:** \n**Duration:** \n\n**What I did**\n- \n\n**How it felt (1–10):** \n\n**Next time:** ",
            seedByDefault: false),
        CuratedTemplate(
            name: "Brain Dump",
            blurb: "Empty your head onto the page — no order, no judgement.",
            body: "## Brain Dump — {{date}} {{time}}\n\n*Everything in my head, no order, no judgement:*\n\n- ",
            seedByDefault: false),
    ]
}
