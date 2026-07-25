# Day 1 Mountain Stairs Redirect

## Problem

The Day 1 mountain-stairs hotspot correctly starts Piposh's
`stairsclimbup` animation. At the animation's original completion handler,
Godot does not execute the dynamic Lingo redirect to `lighttop`. Score playback
therefore falls through into the adjacent `stairsclimbdown` animation, making
Piposh appear to turn around and walk back down.

The original route is:

`stairs` → `stairsclimbup` → `lighttop`

## Design

Preserve the walk and climb animation. At the exported completion point for
`stairsclimbup`, resolve the missing Day 1 destination and enter `lighttop`.
Represent the correction by transition label rather than by a raw frame number,
so the intent remains readable if render-model frame positions change.

Keep this correction in the Godot runtime layer. Do not skip directly from the
stairs hotspot to `lighttop`, and do not alter unrelated Day 1 routes in this
change.

## Testing

Add a headless regression that:

1. Loads Day 1 at the `stairsgo` room.
2. Activates the mountain-stairs hotspot.
3. Advances the puppet walk and score through `stairsclimbup`.
4. Asserts that the runtime enters `lighttop`.
5. Asserts that it never enters `stairsclimbdown`.

Run the focused headless suite and the Godot editor parse check after the fix.

## Follow-up Audit

After this route passes, inspect all Day 1 frames using the same original
dynamic completion handler. Compare each exported transition with the
decompiled destination, add a regression matrix, and repair any additional
missing redirects as a separate change.
