## Copyright (C) 2026 Andreas Bertsatos <abertsatos@biol.uoa.gr>
##
## This file is part of the mcp package for GNU Octave.
##
## This program is free software; you can redistribute it and/or modify it under
## the terms of the GNU General Public License as published by the Free Software
## Foundation; either version 3 of the License, or (at your option) any later
## version.
##
## This program is distributed in the hope that it will be useful, but WITHOUT
## ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
## FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
## details.
##
## You should have received a copy of the GNU General Public License along with
## this program; if not, see <http://www.gnu.org/licenses/>.

## -*- texinfo -*-
## @deftypefn {mcp} {} mcp.serveEval ()
##
## Serve the Model Context Protocol on standard input and output, with
## evaluation.
##
## @code{mcp.serveEval ()} is @code{mcp.serve} plus the two tools that run
## code, @code{octave_eval} and @code{octave_test}.
## It reads newline-delimited JSON-RPC messages from standard input, answers
## each one, writes the answer to standard output, and returns only when
## standard input reaches end of file.
##
## @strong{This is a separate entry point on purpose.}  It is a separate
## function, a separate launch command and a separate entry in a host's
## configuration, so that a host configured for @code{mcp.serve} cannot reach
## these tools however a model asks.  The read-only server evaluates no code,
## runs no user function and writes nothing, which is what lets a user grant it
## blanket permission; this one does all three, and is meant to be configured
## under its own name, conventionally @qcode{"octave-eval"}, so that the
## permission rules for the two can differ.
##
## @subsubheading Testing
##
## @code{octave_test} runs the built-in tests of one function or file and
## reports how many passed, with the assertion behind each failure.  It
## resolves a name through @code{which} and then runs the @emph{file}, which is
## what lets it test a namespaced function or a class method: core's
## @code{test} cannot resolve @code{mcp.jsonrpcError} and answers
## @qcode{"does not exist in path"} with a count of zero, and a count of zero
## reads as @qcode{"no tests"} rather than as a name it could not resolve.
##
## It takes no workspace.  Tests run in a context of their own every time, so
## that what passed cannot depend on what was evaluated before.
##
## @subsubheading Workspaces
##
## Evaluation state is held in a @emph{workspace}, named by an opaque handle.
## Every call names one: @qcode{"new"} opens a workspace and the reply gives
## its handle, and that handle passed back continues it.  This is what the
## protocol requires, state that spans requests being referenced by an explicit
## identifier rather than by the connection it arrived on.  A handle lives
## until the process ends or until it is the oldest of more than eight, and a
## call naming one that is gone is a tool error that says so rather than a
## fresh workspace that says nothing.
##
## The handle is required rather than optional, and that is a deliberate
## departure from the specification's suggested shape of a separate creation
## tool: a model that omits an argument is the measured case, and an omitted
## handle read as @qcode{"start clean"} would lose a workspace in silence.
##
## @subsubheading What contains it, and what does not
##
## Output is captured twice over, and the two halves catch different things.
## @code{evalc} takes every route to standard output that stays inside the
## interpreter, and @code{__mcp_capture__} holds descriptor 1 over a file for
## the length of the call, which is the only thing that catches a
## @strong{subprocess}: a child inherits the descriptor and writes past
## @code{evalc} entirely, into the stream that carries the protocol.  What a
## child printed comes back labelled in the reply.
##
## Because that containment is at the descriptor and not at a name,
## @code{builtin ("system", @dots{})} does not get around it.  Where the
## package was installed without a compiler and @code{__mcp_capture__} could
## not be built, the containment moves to the two forms that let a child
## inherit descriptor 1: @code{system} is shadowed by one that asks for the
## output back and prints it through the interpreter, where @code{evalc} takes
## it, and @code{popen} by one that refuses its write mode, whose output
## nothing there could read.  That is weaker in one way, since a shadow at a
## name @emph{is} defeated by @code{builtin}, and it costs an asynchronous
## @code{system}, whose output core will not return at all.
##
## @code{input} and @code{keyboard} are shadowed in either case, since there is
## no terminal for them to read from.
##
## @subsubheading The deadline
##
## An evaluation that is still running after twenty seconds is stopped, and the
## reply says so.  What the code assigned before it was stopped is still in the
## workspace and what it printed is still returned, which is the difference
## between this and letting the host restart the process.
##
## The stopping is the interpreter's own interrupt, the mechanism Ctrl-C uses,
## raised from a thread and caught in @code{__mcp_guard__}.  It cannot be done
## in Octave: measured on 11.2.0, an interrupt raised this way unwinds straight
## through @code{try} and takes the process with it, honouring
## @code{unwind_protect} on the way but never being caught.
##
## Set @env{MCP_EVAL_SECONDS} in the launch command for an installation whose
## work honestly takes longer, up to six hundred.  It is not a tool argument,
## since that would cost tokens in every request and is a decision for whoever
## configures the server rather than for the model.
##
## The deadline does not recover everything.  A call wedged inside one long
## native call, or blocked on a read, reaches no checkpoint at which the
## interrupt can be noticed, and the host restarting the process is what
## remains.  Where the oct-files could not be built there is no deadline at
## all.
##
## @subsubheading What this is not
##
## None of this is a sandbox.  Evaluated code can read and write files, use the
## network and consume memory exactly as any code in this interpreter can.
## Configure this server only where that is acceptable.
##
## @seealso{mcp.serve, mcp.selftest}
## @end deftypefn

function serveEval ()

  if (nargin != 0)
    error ("mcp.serveEval: invalid number of input arguments.");
  endif

  mcp.__serveLoop__ ("eval", "serveEval");

endfunction
