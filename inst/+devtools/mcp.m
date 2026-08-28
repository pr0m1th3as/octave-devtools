## Copyright (C) 2026 Andreas Bertsatos <abertsatos@biol.uoa.gr>
##
## This file is part of the devtools package for GNU Octave.
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
## @deftypefn {devtools} {} devtools.mcp ()
##
## Serve the Model Context Protocol on standard input and output.
##
## @code{devtools.mcp ()} reads newline-delimited JSON-RPC messages from standard
## input, answers each one, writes the answer to standard output, and returns
## only when standard input reaches end of file.  It is the entry point a host
## launches; it is not meant to be called at an interactive prompt, where it
## would take the terminal.
##
## Both protocol eras are served.  A client that opens with per-request metadata
## is answered under revision 2026-07-28 and statelessly; a client that opens
## with an @code{initialize} handshake is answered under revision 2025-11-25 for
## the life of the process.  The choice is made by the first request and the
## tools are the same in either case.
##
## The read-only tool set is served here.  This server evaluates no code, runs
## no user function, and writes nothing, which is the property that lets a user
## grant it blanket permission.  Evaluation lives behind a separate entry point
## and a separate configuration entry, so that it cannot be reached by a host
## configured for this one.
##
## Configure a host to launch it with:
##
## @example
## octave-cli -q --no-init-file --eval "pkg load devtools; devtools.mcp ()"
## @end example
##
## @strong{Do not shorten that command.}  @code{-q} suppresses the startup
## banner and @code{--no-init-file} skips @file{~/.octaverc}; both write to
## standard output, both happen before this function exists, and a single byte
## of either corrupts the stream for the whole session.  Use
## @code{devtools.selftest} to check a configuration before suspecting the host.
##
## Everything diagnostic goes to standard error, which the protocol reserves for
## exactly that purpose and which a client may capture, forward or ignore.
##
## One deviation is worth stating.  This loop reads, answers and writes in one
## thread, so a @code{notifications/cancelled} arriving for a request already
## being answered cannot be seen until that answer has been written.  The
## protocol asks that no further message be sent for a cancelled request and
## this implementation cannot honour it.  The tools served here return in
## milliseconds, so the window is small, but it is real.
##
## @seealso{devtools.selftest, devtools.dispatch}
## @end deftypefn

function mcp ()

  if (nargin != 0)
    error ("devtools.mcp: invalid number of input arguments.");
  endif

  devtools.__serveLoop__ ("read-only", "mcp");

endfunction

%!test
%! ## The one test that no offline test can replace: run the real server as a
%! ## subprocess and prove that every byte it wrote to stdout was a message.
%! ok = devtools.selftest ();
%! assert_equal (ok, true);
