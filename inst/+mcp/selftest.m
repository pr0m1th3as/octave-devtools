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
## @deftypefn  {mcp} {} mcp.selftest ()
## @deftypefnx {mcp} {@var{OK} =} mcp.selftest ()
## @deftypefnx {mcp} {[@var{OK}, @var{REPORT}] =} mcp.selftest ()
## @deftypefnx {mcp} {@dots{} =} mcp.selftest (@var{CMD})
##
## Check that a configured server starts and speaks cleanly.
##
## @code{mcp.selftest ()} launches the server as a subprocess, drives a short
## session through it, and prints what it found.  The check it exists for is the
## one that cannot be made from inside: that @strong{every byte written to
## standard output was a protocol message}.  A stray @code{printf}, an
## unsuppressed statement or a line printed by @file{~/.octaverc} corrupts the
## stream, and the only symptom a host can show for it is an unexplained
## failure to connect.
##
## @code{@var{OK} = mcp.selftest ()} returns true when every check passed and
## prints nothing, which is the form a test uses.
##
## @code{[@var{OK}, @var{REPORT}] = mcp.selftest ()} also returns the cell array
## of strings that would have been printed, one per check.
##
## @code{@dots{} = mcp.selftest (@var{CMD})} tests the shell command @var{CMD}
## rather than the default one.  Give it the exact command from your host
## configuration to find out whether that configuration is sound; it must launch
## a server that reads standard input and writes standard output, and nothing
## else.  The default launches the interpreter running this function against the
## package directory this file lives in, which works from a source tree as well
## as from an installed package.
##
## @seealso{mcp.serve}
## @end deftypefn

function [OK, REPORT] = selftest (CMD)

  ## Input validation
  if (nargin > 1)
    error ("mcp.selftest: invalid number of input arguments.");
  endif
  if (nargin == 1 && ! (ischar (CMD) && isrow (CMD)))
    error ("mcp.selftest: CMD must be a character vector.");
  endif

  REPORT = {};
  if (nargin < 1)
    CMD = defaultCommand ();
  endif

  ## A session that exercises discovery, listing, a call, and a notification.
  ## The notification is the one that must produce no line at all.
  meta = ['"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28",' ...
          '"io.modelcontextprotocol/clientCapabilities":{}}'];
  session = {sprintf('{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{%s}}', meta), ...
             sprintf('{"jsonrpc":"2.0","id":"two","method":"tools/list","params":{%s}}', meta), ...
             sprintf('{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"octave_version",%s}}', meta), ...
             '{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":3}}'};

  infile = tempname ();
  errfile = tempname ();
  unwind_protect

    fid = fopen (infile, "w");
    if (fid < 0)
      error ("mcp.selftest: cannot write a temporary file in %s.", tempdir ());
    endif
    fprintf (fid, "%s\n", session{:});
    fclose (fid);

    [status, out] = system (sprintf ('%s < "%s" 2> "%s"', CMD, infile, errfile));

    lines = strsplit (strrep (out, "\r\n", "\n"), "\n");
    lines = lines(! cellfun (@isempty, lines));

    [REPORT, OK] = check (REPORT, "server exited cleanly", status == 0, ...
                          sprintf ("exit status %d", status));

    ## The check this function exists for
    bad = 0;
    for i = 1:numel (lines)
      try
        jsondecode (lines{i});
      catch
        bad = i;
        break;
      end_try_catch
    endfor
    if (bad > 0)
      detail = sprintf ("line %d of stdout is not a message: %s", bad, ...
                        trunc (lines{bad}));
    else
      detail = "";
    endif
    [REPORT, OK] = check (REPORT, "every stdout line is a protocol message", ...
                          bad == 0, detail, OK);

    [REPORT, OK] = check (REPORT, "one response per request, none for the notification", ...
                          numel (lines) == 3, ...
                          sprintf ("got %d lines, expected 3", numel (lines)), OK);

    if (numel (lines) >= 3 && bad == 0)
      A = jsondecode (lines{1});
      B = jsondecode (lines{2});
      C = jsondecode (lines{3});
      [REPORT, OK] = check (REPORT, "identifiers echo back with their type", ...
                            isequal (A.id, 1) && ischar (B.id) ...
                                             && strcmp (B.id, "two"), ...
                            "an identifier came back changed", OK);
      [REPORT, OK] = check (REPORT, "server/discover names a protocol version", ...
                            isfield (A, "result") ...
                            && isfield (A.result, "supportedVersions"), ...
                            "no supportedVersions in the discovery result", OK);
      [REPORT, OK] = check (REPORT, "tools/list advertises a tool", ...
                            isfield (B, "result") && isfield (B.result, "tools") ...
                            && ! isempty (B.result.tools), ...
                            "the tool list came back empty", OK);
      [REPORT, OK] = check (REPORT, "tools/call returns a result", ...
                            isfield (C, "result") ...
                            && isfield (C.result, "content") ...
                            && ! C.result.isError, ...
                            "the tool call did not return content", OK);
    endif

  unwind_protect_cleanup
    if (exist (infile, "file") == 2)
      delete (infile);
    endif
    if (exist (errfile, "file") == 2)
      delete (errfile);
    endif
  end_unwind_protect

  if (nargout == 0)
    printf ("%s\n", REPORT{:});
    printf ("\n%s\n", merge (OK, "SELFTEST PASSED", "SELFTEST FAILED"));
    clear OK;
  endif

endfunction

function CMD = defaultCommand ()
  exe = fullfile (OCTAVE_HOME (), "bin", "octave-cli");
  if (exist (exe, "file") != 2)
    exe = "octave-cli";
  endif
  instdir = fileparts (fileparts (mfilename ("fullpath")));
  CMD = sprintf ('"%s" -q --no-init-file --eval "addpath (''%s''); mcp.serve ()"', ...
                 exe, instdir);
endfunction

function [REPORT, OK] = check (REPORT, what, passed, detail, OK)
  if (nargin < 5)
    OK = true;
  endif
  if (passed)
    REPORT{end+1} = sprintf ("PASS  %s", what);
  else
    REPORT{end+1} = sprintf ("FAIL  %s: %s", what, detail);
    OK = false;
  endif
endfunction

function s = trunc (s)
  if (numel (s) > 120)
    s = [s(1:120) " ..."];
  endif
endfunction

%!test
%! [ok, rep] = mcp.selftest ();
%! assert_equal (ok, true);
%! assert_equal (iscellstr (rep), true);
%! assert_equal (all (strncmp (rep, "PASS", 4)), true);

%!test
%! ## A command that writes something other than a message must be caught.
%! cmd = 'printf ''hello\n''';
%! [ok, rep] = mcp.selftest (cmd);
%! assert_equal (ok, false);
%! assert_equal (any (strncmp (rep, "FAIL  every stdout line", 23)), true);

%!error <mcp\.selftest: CMD must be a character vector\.> mcp.selftest (5)
