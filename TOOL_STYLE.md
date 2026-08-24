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

## Measured, not argued

`tool_eval.m` is the check this file demands. It hands a local model the real
tool set, taken from this package's own `tools/list`, asks twenty questions with
a known-correct tool and argument, and scores the choice and the argument
separately. Nothing is executed: only the choice is recorded.

**Baseline, Qwen3:1.7b, five runs of twenty questions, 2026-08-24:**
82% tool choice, 81% choice and argument together.

Three rules come out of establishing it, and all three cost something to learn.

**Judge per question, never by the mean.** The run-to-run spread is about
fifteen points, so a single run tells you almost nothing and two runs differing
by two questions are indistinguishable. Worse, a mean can hide equal and
opposite movements: one rewrite scored 78% before and 79% after while fixing
four questions and breaking one that had been perfect in every prior run.

**State the consequence of skipping a capability, not just the capability.**
`octave_pkg` said "Name one for its dependencies and directory" and the model
omitted the name in four runs of five. Changed to "Name a package to see its
dependencies, **which the bare listing does not show**", it passed nine times
out of ten. Offering an argument is not a reason to use one.

**Do not widen a description to catch a question it is missing.** `octave_which`
was missing situational questions, so its opening was broadened to "Answer
questions about a name you already have". That fixed none of them and swallowed
`octave_help`'s territory, taking "What arguments does linspace take?" from 5/5
to 1/5. It was reverted. A description competes with its siblings, and every
word of extra reach is taken from one of them.

**And a boundary on the whole exercise.** Where a stronger model reads a
description correctly and a weaker one does not, that is the reader. Four
questions have resisted two rewrites here and are answered correctly by
qwen2.5-coder:14b. Tuning a frozen public schema against the weakest model
available makes it worse for every other reader.

## What the harness cannot see

A model may express a tool call as JSON in the message body instead of through
the tool-call channel. qwen2.5-coder:14b does this for every call. Such a
choice is scored, and marked, but it is **inert through a real MCP host**, which
dispatches the `tool_calls` field and nothing else. A model can score 90% here
and do nothing at all in practice.
