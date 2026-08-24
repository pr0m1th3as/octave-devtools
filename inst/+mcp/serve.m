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
## @deftypefn {mcp} {} mcp.serve ()
##
## Serve the Model Context Protocol on standard input and output.
##
## @code{mcp.serve ()} reads newline-delimited JSON-RPC messages from standard
## input, answers each one, writes the answer to standard output, and returns
## only when standard input reaches end of file.  It is the entry point a host
## launches; it is not meant to be called at an interactive prompt, where it
## would take the terminal.
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
## octave-cli -q --no-init-file --eval "pkg load mcp; mcp.serve ()"
## @end example
##
## @strong{Do not shorten that command.}  @code{-q} suppresses the startup
## banner and @code{--no-init-file} skips @file{~/.octaverc}; both write to
## standard output, both happen before this function exists, and a single byte
## of either corrupts the stream for the whole session.  Use
## @code{mcp.selftest} to check a configuration before suspecting the host.
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
## @seealso{mcp.selftest, mcp.dispatch}
## @end deftypefn

function serve ()

  if (nargin != 0)
    error ("mcp.serve: invalid number of input arguments.");
  endif

  logmsg ("listening, MCP 2026-07-28, pid %d", getpid ());
  seenfirst = false;

  while (true)

    line = fgetl (stdin);
    if (! ischar (line))
      break;                          # end of file: the shutdown signal
    endif

    ## The opening message of a real host is the evidence that decides whether
    ## a legacy era needs supporting at all, so it is logged verbatim once
    if (! seenfirst && ! isempty (strtrim (line)))
      seenfirst = true;
      logmsg ("first message verbatim: %s", line);
    endif

    R = [];
    try
      R = mcp.decodeRequest (line);
      RESP = mcp.dispatch (R);
    catch err
      logmsg ("internal error: %s", err.message);
      RESP = internalError (R);
    end_try_catch

    if (! isempty (RESP))
      fputs (stdout, [mcp.encodeResponse(RESP) "\n"]);
      fflush (stdout);
    endif

  endwhile

  logmsg ("end of input, exiting");

endfunction

function RESP = internalError (R)

  ## A notification is never answered, even when answering it went wrong
  if (isstruct (R) && isfield (R, "type") ...
                   && any (strcmp (R.type, {'notification', 'blank'})))
    RESP = [];
    return;
  endif

  id = [];
  if (isstruct (R) && isfield (R, "hasid") && R.hasid)
    id = R.id;
  endif
  RESP = mcp.jsonrpcError (id, -32603, "Internal error");

endfunction

function logmsg (fmt, varargin)
  fprintf (stderr, ["mcp.serve: " fmt "\n"], varargin{:});
  fflush (stderr);
endfunction

%!test
%! ## The one test that no offline test can replace: run the real server as a
%! ## subprocess and prove that every byte it wrote to stdout was a message.
%! ok = mcp.selftest ();
%! assert_equal (ok, true);
