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
## @code{mcp.serveEval ()} is @code{mcp.serve} plus the tools that run code.
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
## Output is captured, so what evaluated code prints is returned to the model
## rather than written into the protocol stream.  While a call is running,
## @code{input} and @code{keyboard} are shadowed by functions that raise, since
## there is no terminal for either to read from, and so are @code{system},
## @code{unix}, @code{dos}, @code{popen} and @code{popen2}, because a
## subprocess inherits the real standard output and writes @strong{past} the
## capture and into the stream that carries the protocol.
##
## The shadowing is a guard against accident, not a sandbox.  It is defeated by
## @code{builtin}, and evaluated code can read and write files, use the network
## and consume memory exactly as any code in this interpreter can.  Configure
## this server only where that is acceptable.
##
## @seealso{mcp.serve, mcp.selftest}
## @end deftypefn

function serveEval ()

  if (nargin != 0)
    error ("mcp.serveEval: invalid number of input arguments.");
  endif

  mcp.__serveLoop__ ("eval", "serveEval");

endfunction
