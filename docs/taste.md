# The taste of Went Hiking

A note to whoever designs the next feature — including a future session of the
assistant that wrote this one. This is the state of mind behind the 2026
refinement: the compose editor, the mobile chrome, the auth pages, the maps.
Read it before sketching anything new. It is short on rules and long on
instincts, because the rules follow from the instincts.

## What this site is

Twenty years of people writing a few sentences about a day outside, with a
couple of photos. Most reports are short. Nobody is here to use software;
they are here to remember a hike or find one. Every design decision serves
one of two moments: *reading someone's day* or *writing down your own*.
If a feature makes either moment feel like operating a tool, it is wrong.

## The page is the interface

The compose editor's founding decision: writing a hike looks like the
published hike. Title is display type you type into, metadata is a byline of
chips you tap, photos drop into the story where they'll live. There is no
"form" that gets transformed into a page — the page is simply editable.
Apply that test to new features: don't build a control panel *about* the
content; let the content itself be handled. The moment you find yourself
stacking labeled inputs, stop and ask what the published result looks like,
then make the editing surface *be* that.

Corollary: optimize the short case. A three-sentence report with two photos
must feel complete and beautiful, never like an under-filled template.

## Type does the work

Ink (`--ink: #111`) on warm paper, Inter with `cv05`/`cv08`, and scale doing
the hierarchy: titles are huge, metadata is small caps-tracked labels,
everything else is body. Controls dress as text — the mobile year picker is a
native `<select>` costumed as the current-year link (bold, 2px underline,
small chevron) because the *link* was the design and the control snuck into
its clothes. Chrome is a defeat: before adding a border, a background, a
box — try type weight, size, or a hairline rule (`--line`) first. The script
wordmark is the one flourish; it stays the only one.

Display type belongs to the content, never to the furniture around it.
Sections start with a caption, not a headline: the label sits small in its
own hairline, and whatever else the row carries — a count, a "View all" —
rides the far end of the same rule. A page of hikes has exactly one loud
voice, and it is the hikes'.

## One vocabulary per row

The mobile header failed twice because it mixed languages: a text link, a
filled disc, bare dots — three species in one short row. The fix wasn't
resizing the disc; it was admitting the disc didn't belong, and letting the
plus be an ink glyph in the same 44px box as the kebab. When elements share a
row or a surface, they share one vocabulary: all text, or all glyphs, or all
cards. A primary CTA may wear chrome only where the layout gives it room to
be obviously deliberate (the desktop nav disc).

## Space what the eye sees

Box-model symmetry is not visual symmetry. The plus glyph fills more of its
hit box than the kebab's dots fill theirs, so equal margins looked lopsided —
the fix was measuring rendered glyph edges and compensating until the
*visible* gaps matched (16px and 16px). Alignment and spacing are judged on
pixels the user sees, screenshot in hand, at the real breakpoint. Never
trust the arithmetic; measure.

Related: tap targets are 44px but invisible. Hit areas grow with padding or
pseudo-elements while the visible element stays exactly as light as the
design wants.

## Photos sit on the void

Photography is the site's soul, and it gets a stage: images sit on near-black
(`--photo-void`), keep their true aspect (no letterboxing, no stretching),
and the lightbox goes fully dark. Maps are photography's sibling — a hero
map frames its subject (fit to where the hikes actually are, not to
outliers), never a whole-world shrug. If an image or map looks incidental,
crop, frame, or size until it looks intended.

## Quiet interaction, honest states

The hover vocabulary is a whisper: prose links thicken their underline, media
dims a touch, controls invert. One focus ring site-wide. Nothing bounces.

But quiet is not vague — states must be *unmistakable*:

- In-flight looks in-flight: dimmed thumbnail, spinning ring, a progress bar
  thick enough to see. A 3px hairline reads as a border, not as progress.
- Failed looks failed, and offers only honest actions. A failed upload grays
  out and loses "Add to story" — offering it would be a lie.
- Feedback is words, in place: "Check your email to confirm this follow."
  Plain sentences where the person is looking, not toasts, not jargon.

## Friction budget

Confirmation modals are reserved for the genuinely irreversible (deleting a
whole hike). Removing a photo from a draft, dismissing a failure — those are
one tap, immediately, because the person already decided. If an action feels
dangerous enough to want a modal, first ask whether the *action* can be made
less dangerous (drafts, server-side cleanup, sweepable scratch state)
instead.

## The editor never lies about the data

The WYSIWYG is a view over `report_markdown`, and round-tripping is
byte-identical *by construction*: anything the rich view can't faithfully
re-serialize stays a verbatim raw block. This is taste, not just
engineering — prettiness must never quietly rewrite what someone wrote in
2009. Extend the same instinct anywhere: a rendering layer may interpret,
never launder.

## The phone is not a smaller desktop

Small screens get their own answers, not shrunken ones: the year links
become the OS picker wheel; five nav destinations fold into a disclosure;
the CTA sheds its chrome. The question is never "how does this fit at
375px" — it's "what would this feature be if the phone were the only
device," with the desktop version as the one that gets more room.

## Smell tests

Before shipping, at 375px and 1280px, signed in and out:

- Does any surface look like a settings page? (Generic form vibes — redo.)
- Do neighbors in a row speak the same visual language?
- Screenshot the spacing. Do the *visible* gaps match?
- Is every async action's pending state obvious from across the room, and
  its failure state honest about what's still possible?
- Did chrome appear where type could have done the job?
- Would a three-sentence, two-photo hike look finished here?
