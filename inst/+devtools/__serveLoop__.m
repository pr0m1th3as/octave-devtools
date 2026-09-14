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
## @deftypefn  {devtools} {} devtools.__serveLoop__ (@var{surface}, @var{name})
## @deftypefnx {devtools} {} devtools.__serveLoop__ (@var{surface}, @var{name}, @var{sandboxed})
##
## Read, dispatch and answer until standard input reaches end of file.
## Internal; not a supported entry point.
##
## @var{surface} is passed to @code{devtools.__newSession__} and decides which tool
## set the session offers; @var{name} is the entry point's name and appears in
## every line this writes to standard error.  @var{sandboxed}, false by default,
## is true only for a server that has verified its sandbox from inside, and
## makes every result report it.
##
## Both entry points share this loop rather than a flag: @code{devtools.mcp} and
## @code{devtools.mcpEval} are separate functions, separate commands and separate
## configuration entries, so that the evaluating server cannot be reached by a
## host configured for the read-only one.  What they must not have is two
## copies of the protocol loop.
##
## @end deftypefn

function __serveLoop__ (surface, name, sandboxed)

  if (nargin < 2 || nargin > 3)
    error ("devtools.__serveLoop__: invalid number of input arguments.");
  endif

  logmsg (name, "listening, MCP 2026-07-28 and 2025-11-25, pid %d", getpid ());
  ## The tool surface belongs to the session, not to a flag on a call
  S = devtools.__newSession__ (surface);
  if (nargin > 2)
    S.sandboxed = sandboxed;
  endif

  while (true)

    line = readLine ();
    if (! ischar (line))
      break;                          # end of file: the shutdown signal
    endif

    R = [];
    try
      R = devtools.decodeRequest (line);
      [RESP, S] = devtools.dispatch (R, S);
    catch err
      logmsg (name, "internal error: %s", err.message);
      RESP = internalError (R);
    end_try_catch

    if (! isempty (RESP))
      fputs (stdout, [devtools.encodeResponse(RESP) "\n"]);
      fflush (stdout);
    endif

  endwhile

  logmsg (name, "end of input, exiting");

endfunction

function L = readLine ()

  ## Not fgetl, and not fgets.  Both of them block on a pipe until the writer
  ## closes it, even when a complete newline-terminated line is already
  ## available: measured at 5.5 s against a writer that held the pipe open for
  ## 6 s, where a single-byte fread returned in 0.00 s.  A server built on
  ## either answers nothing until its client gives up and disconnects, which no
  ## test feeding it a file can ever notice, because a file is at end of input
  ## the moment it is read.
  ##
  ## The cost is a call per byte, about 21 KB/s.  Requests are small, so this is
  ## milliseconds; it is the responses that are large and those are written
  ## whole.  Doing better needs a non-blocking read, which Octave does not
  ## expose.

  buf = zeros (1, 4096, "uint8");
  n = 0;

  while (true)

    c = fread (stdin, 1, "uint8");

    if (isempty (c))                  # end of file
      if (n == 0)
        L = -1;
      else
        L = char (buf(1:n));          # a final line with no newline
      endif
      return;
    endif

    if (c == 10)
      L = char (buf(1:n));
      return;
    endif

    if (c != 13)                      # tolerate CRLF from a Windows client
      n++;
      if (n > numel (buf))
        buf = [buf, zeros(1, numel (buf), "uint8")];
      endif
      buf(n) = c;
    endif

  endwhile

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
  RESP = devtools.jsonrpcError (id, -32603, "Internal error");

endfunction

function logmsg (name, fmt, varargin)
  ## stderr, never stdout: the specification blesses it for logging and
  ## reserves stdout for messages
  fprintf (stderr, ["devtools." name ": " fmt "\n"], varargin{:});
  fflush (stderr);
endfunction
