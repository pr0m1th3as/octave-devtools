# Tool description style

The rule in this file governs the `description` strings this package emits in
`tools/list`, and nothing else. It exists because those strings are not reached
by any rule in `OCTAVE_PACKAGES_CODING_STYLE.md`, and because they are the only
documentation the consumer that matters ever reads.

A tool description is not a docstring. The texinfo help for a function must
explain it completely without recourse to the source. A tool description must
be as short as possible while still steering a model to the right tool with the
right arguments. Those are opposite jobs, which is why the two are written
separately and why **a description is never generated from the texinfo block**.

## Size

- Tool description: **300 bytes maximum.**
- Each parameter description: **100 bytes maximum.**

The whole tool list is re-sent on every request. Four tools with their schemas
cost roughly 500 tokens of standing overhead per call, paid by the user, every
time. Size is a performance property here, not an aesthetic one, and the same
reasoning applies to the number of tools: adding a fifth requires an argument.

## Content

Three parts, in this order, and nothing else.

1. **What it answers**, in one sentence.
2. **When to prefer it over its siblings.** This is the highest-value sentence
   in the file. A model choosing between `octave_help`, `octave_which` and
   `octave_search` is exactly where it guesses wrong, and the schema cannot
   help it.
3. **The failure mode and the fallback.** For example: errors if the name is
   not on the load path; use `octave_search` when the name is unknown.

## Prohibited

- Texinfo markup. The consumer is JSON, not `makeinfo`.
- Examples. The schema carries those.
- Rationale, version history, and anything decorative.
- Non-ASCII characters, which serve no purpose here and tokenise badly.

## Validation

**A description is never judged by reading it.**

The check is a fixed set of about twenty natural-language questions, each with
a known-correct tool and argument set, run against the server at release and
scored on two things: did the model select the right tool, and did it pass the
right arguments. A description that reads beautifully and scores badly is a bad
description.

Changing a description is therefore a change that must be re-measured, in the
same way that changing a numerical implementation must be re-tested.
