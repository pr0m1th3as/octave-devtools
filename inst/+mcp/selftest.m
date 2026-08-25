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
## session through it in @emph{each} of the two protocol eras, and prints what
## it found.  A server that answers only one era works with only some hosts, so
## both are exercised.  The check it exists for is the
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

  ## Two sessions, one per protocol era, because a client may open either way
  ## and a server that works in only one of them works with only some hosts.
  meta = ['"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28",' ...
          '"io.modelcontextprotocol/clientCapabilities":{}}'];
  modern = {sprintf('{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{%s}}', meta), ...
            sprintf('{"jsonrpc":"2.0","id":"two","method":"tools/list","params":{%s}}', meta), ...
            sprintf('{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"octave_which","arguments":{"name":"mean"},%s}}', meta), ...
            '{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":3}}'};
  legacy = {['{"jsonrpc":"2.0","id":1,"method":"initialize","params":' ...
             '{"protocolVersion":"2025-11-25","capabilities":{},' ...
             '"clientInfo":{"name":"selftest","version":"1"}}}'], ...
            '{"jsonrpc":"2.0","method":"notifications/initialized"}', ...
            '{"jsonrpc":"2.0","id":"two","method":"tools/list","params":{}}', ...
            ['{"jsonrpc":"2.0","id":3,"method":"tools/call","params":' ...
             '{"name":"octave_which","arguments":{"name":"mean"}}}']};

  infile = tempname ();
  errfile = tempname ();
  unwind_protect

    OK = true;
    for era = {'modern', 'legacy'}

      if (strcmp (era{1}, "modern"))
        session = modern;
      else
        session = legacy;
      endif

      fid = fopen (infile, "w");
      if (fid < 0)
        error ("mcp.selftest: cannot write a temporary file in %s.", tempdir ());
      endif
      fprintf (fid, "%s\n", session{:});
      fclose (fid);

      [status, out] = system (sprintf ('%s < "%s" 2> "%s"', CMD, infile, errfile));

      lines = strsplit (strrep (out, "\r\n", "\n"), "\n");
      lines = lines(! cellfun (@isempty, lines));
      tag = era{1};

      [REPORT, OK] = check (REPORT, [tag ": server exited cleanly"], ...
                            status == 0, sprintf ("exit status %d", status), OK);

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
      [REPORT, OK] = check (REPORT, ...
                            [tag ": every stdout line is a protocol message"], ...
                            bad == 0, detail, OK);

      [REPORT, OK] = check (REPORT, ...
                            [tag ": one response per request, none for the notification"], ...
                            numel (lines) == 3, ...
                            sprintf ("got %d lines, expected 3", numel (lines)), OK);

      if (numel (lines) < 3 || bad != 0)
        continue;
      endif
      A = jsondecode (lines{1});
      B = jsondecode (lines{2});
      C = jsondecode (lines{3});

      [REPORT, OK] = check (REPORT, [tag ": identifiers echo back with their type"], ...
                            isequal (A.id, 1) && ischar (B.id) ...
                                             && strcmp (B.id, "two"), ...
                            "an identifier came back changed", OK);

      if (strcmp (tag, "modern"))
        [REPORT, OK] = check (REPORT, "modern: server/discover names a version", ...
                              isfield (A, "result") ...
                              && isfield (A.result, "supportedVersions"), ...
                              "no supportedVersions in the discovery result", OK);
        [REPORT, OK] = check (REPORT, "modern: results carry resultType", ...
                              isfield (B.result, "resultType") ...
                              && strcmp (B.result.resultType, "complete"), ...
                              "a modern result had no resultType", OK);
      else
        [REPORT, OK] = check (REPORT, "legacy: initialize agrees a version", ...
                              isfield (A, "result") ...
                              && isfield (A.result, "protocolVersion") ...
                              && isfield (A.result, "serverInfo"), ...
                              "the initialize result was not well formed", OK);
        [REPORT, OK] = check (REPORT, "legacy: results carry no resultType", ...
                              ! isfield (B.result, "resultType"), ...
                              "a legacy result carried a modern envelope", OK);
      endif

      [REPORT, OK] = check (REPORT, [tag ": tools/list advertises a tool"], ...
                            isfield (B, "result") && isfield (B.result, "tools") ...
                            && ! isempty (B.result.tools), ...
                            "the tool list came back empty", OK);
      [REPORT, OK] = check (REPORT, [tag ": tools/call returns a result"], ...
                            isfield (C, "result") ...
                            && isfield (C.result, "content") ...
                            && ! C.result.isError, ...
                            "the tool call did not return content", OK);
    endfor

    ## The check that a file-fed session structurally cannot make: a pipe that
    ## stays open after the request.  A server that answers only at end of
    ## input passes every check above and works with no real client.
    if (OK && haveTimeout ())
      outfile = tempname ();
      shfile = tempname ();
      fid = fopen (infile, "w");
      fprintf (fid, "%s\n", modern{1});
      fclose (fid);
      fid = fopen (shfile, "w");
      fprintf (fid, "#!/bin/sh\n{ cat \"%s\"; sleep 6; } | %s > \"%s\" 2>/dev/null\n", ...
               infile, CMD, outfile);
      fclose (fid);
      system (sprintf ('timeout 3 sh "%s"', shfile));
      resp = "";
      if (exist (outfile, "file") == 2)
        resp = fileread (outfile);
        delete (outfile);
      endif
      delete (shfile);
      [REPORT, OK] = check (REPORT, "answers before the input stream closes", ...
                            ! isempty (strtrim (resp)), ...
                            "nothing until end of input: a live client will time out", OK);
    endif


    ## The evaluating server, and the claim only it can break: a child process
    ## inherits descriptor 1, so code that spawns one writes into the stream
    ## that carries the protocol unless something holds that descriptor.  Run
    ## against mcp.serveEval rather than mcp.serve, and only with the default
    ## commands, since a caller-supplied one may not be an evaluating server.
    if (nargin < 1)

      [ECMD, capdir] = defaultEvalCommand ();
      esession = {sprintf(['{"jsonrpc":"2.0","id":1,"method":"tools/call",' ...
                  '"params":{"name":"octave_eval","arguments":' ...
                  '{"code":"system (\\"echo mcpzzchild\\");",' ...
                  '"workspace":"new"},%s}}'], meta)};

      fid = fopen (infile, "w");
      if (fid < 0)
        error ("mcp.selftest: cannot write a temporary file in %s.", tempdir ());
      endif
      fprintf (fid, "%s\n", esession{:});
      fclose (fid);

      [status, out] = system (sprintf ('%s < "%s" 2> "%s"', ECMD, infile, errfile));

      lines = strsplit (strrep (out, "\r\n", "\n"), "\n");
      lines = lines(! cellfun (@isempty, lines));

      [REPORT, OK] = check (REPORT, "eval: server exited cleanly", ...
                            status == 0, sprintf ("exit status %d", status), OK);

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
      [REPORT, OK] = check (REPORT, ...
        "eval: a subprocess wrote nothing into the protocol stream", ...
        bad == 0, detail, OK);

      txt = "";
      if (numel (lines) == 1 && bad == 0)
        A = jsondecode (lines{1});
        if (isfield (A, "result") && isfield (A.result, "content"))
          C = A.result.content;
          if (iscell (C) && ! isempty (C) && isfield (C{1}, "text"))
            txt = C{1}.text;
          elseif (isstruct (C) && ! isempty (C) && isfield (C, "text"))
            txt = C(1).text;
          endif
        endif
      endif

      ## The deadline, end to end: code that never returns must not take the
      ## server with it.  Two seconds through the environment variable rather
      ## than the server's own deadline, so that this stays a test and not a
      ## wait.  setenv rather than a shell prefix, which cmd.exe would not
      ## understand.
      had = getenv ("MCP_EVAL_SECONDS");
      unwind_protect
        setenv ("MCP_EVAL_SECONDS", "2");
        loopy = {sprintf(['{"jsonrpc":"2.0","id":1,"method":"tools/call",' ...
                 '"params":{"name":"octave_eval","arguments":' ...
                 '{"code":"while (true), mcpzzspin = 1; endwhile",' ...
                 '"workspace":"new"},%s}}'], meta), ...
                 sprintf(['{"jsonrpc":"2.0","id":2,"method":"tools/call",' ...
                 '"params":{"name":"octave_eval","arguments":' ...
                 '{"code":"mcpzzalive = 42;","workspace":"new"},%s}}'], meta)};
        fid = fopen (infile, "w");
        if (fid < 0)
          error ("mcp.selftest: cannot write a temporary file in %s.", tempdir ());
        endif
        fprintf (fid, "%s\n", loopy{:});
        fclose (fid);
        [status, out] = system (sprintf ('%s < "%s" 2> "%s"', ECMD, infile, errfile));
      unwind_protect_cleanup
        if (isempty (had))
          unsetenv ("MCP_EVAL_SECONDS");
        else
          setenv ("MCP_EVAL_SECONDS", had);
        endif
      end_unwind_protect

      lines = strsplit (strrep (out, "\r\n", "\n"), "\n");
      lines = lines(! cellfun (@isempty, lines));
      stopped = ! isempty (strfind (out, "[stopped]"));
      answered = numel (lines) == 2;

      [REPORT, OK] = check (REPORT, ...
        "eval: code that does not return is stopped, and the server answers on", ...
        stopped && answered, ...
        sprintf ("stopped=%d, %d replies", stopped, numel (lines)), OK);

      if (isempty (capdir))
        ## No capture built here, so the refusal is the correct answer and the
        ## check is that it refused rather than ran
        [REPORT, OK] = check (REPORT, ...
          "eval: without the capture, a subprocess is refused", ...
          ! isempty (strfind (txt, "without its output capture")), ...
          trunc (txt), OK);
      else
        [REPORT, OK] = check (REPORT, ...
          "eval: what the subprocess printed came back in the result", ...
          ! isempty (strfind (txt, "mcpzzchild")), trunc (txt), OK);
      endif

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

function [CMD, capdir] = defaultEvalCommand ()

  ## The same command the README gives for the evaluating server, plus
  ## whatever directory holds __mcp_capture__ in this process, so that a
  ## source tree is exercised the way an installed package is.
  exe = fullfile (OCTAVE_HOME (), "bin", "octave-cli");
  if (exist (exe, "file") != 2)
    exe = "octave-cli";
  endif
  instdir = fileparts (fileparts (mfilename ("fullpath")));

  capdir = "";
  cap = which ("__mcp_capture__");
  if (! isempty (cap))
    capdir = fileparts (cap);
  endif

  add = sprintf ("addpath ('%s');", instdir);
  if (! isempty (capdir))
    add = [add sprintf(" addpath ('%s');", capdir)];
  endif
  CMD = sprintf ('"%s" -q --no-init-file --eval "%s mcp.serveEval ()"', ...
                 exe, add);

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

function tf = haveTimeout ()
  ## The responsiveness check needs a way to bound a run; skip it where there
  ## is none rather than fail for a reason that is not the server's
  [status, ~] = system ("command -v timeout > /dev/null 2>&1");
  tf = (status == 0);
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
%! assert_equal (any (! cellfun (@isempty, strfind (rep, "every stdout line"))), true);

%!error <mcp\.selftest: CMD must be a character vector\.> mcp.selftest (5)
