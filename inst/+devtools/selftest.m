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
## @deftypefn  {devtools} {} devtools.selftest ()
## @deftypefnx {devtools} {@var{OK} =} devtools.selftest ()
## @deftypefnx {devtools} {[@var{OK}, @var{REPORT}] =} devtools.selftest ()
## @deftypefnx {devtools} {@dots{} =} devtools.selftest (@var{CMD})
##
## Check that a configured server starts and speaks cleanly.
##
## @code{devtools.selftest ()} launches the server as a subprocess, drives a short
## session through it in @emph{each} of the two protocol eras, and prints what
## it found.  A server that answers only one era works with only some hosts, so
## both are exercised.  The check it exists for is the
## one that cannot be made from inside: that @strong{every byte written to
## standard output was a protocol message}.  A stray @code{printf}, an
## unsuppressed statement or a line printed by @file{~/.octaverc} corrupts the
## stream, and the only symptom a host can show for it is an unexplained
## failure to connect.  Standard error is read too, for the complementary
## claim: the server may write its own diagnostics there, but a diagnostic the
## @emph{interpreter} raised about the server is a defect nothing else here
## would see.
##
## @code{@var{OK} = devtools.selftest ()} returns true when every check passed and
## prints nothing, which is the form a test uses.
##
## @code{[@var{OK}, @var{REPORT}] = devtools.selftest ()} also returns the cell array
## of strings that would have been printed, one per check.
##
## @code{@dots{} = devtools.selftest (@var{CMD})} tests the shell command @var{CMD}
## rather than the default one.  Give it the exact command from your host
## configuration to find out whether that configuration is sound; it must launch
## a server that reads standard input and writes standard output, and nothing
## else.  The default launches the interpreter running this function against the
## package directory this file lives in, which works from a source tree as well
## as from an installed package.
##
## @seealso{devtools.mcp}
## @end deftypefn

function [OK, REPORT] = selftest (CMD)

  ## Input validation
  if (nargin > 1)
    error ("devtools.selftest: invalid number of input arguments.");
  endif
  if (nargin == 1 && ! (ischar (CMD) && isrow (CMD)))
    error ("devtools.selftest: CMD must be a character vector.");
  endif

  REPORT = {};
  if (nargin < 1)
    [CMD, dexe, dargv] = defaultCommand ();
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
        error ("devtools.selftest: cannot write a temporary file in %s.", tempdir ());
      endif
      fprintf (fid, "%s\n", session{:});
      fclose (fid);

      [status, out] = system (sprintf ('%s < "%s" 2> "%s"', CMD, infile, errfile));

      lines = strsplit (strrep (out, "\r\n", "\n"), "\n");
      lines = lines(! cellfun (@isempty, lines));
      tag = era{1};

      [REPORT, OK] = check (REPORT, [tag ": server exited cleanly"], ...
                            status == 0, sprintf ("exit status %d", status), OK);

      [quiet, noisy] = quietStderr (errfile);
      [REPORT, OK] = check (REPORT, ...
        [tag ": the interpreter raised nothing about the server"], ...
        quiet, trunc (noisy), OK);

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

    ## The check that a file-fed session structurally cannot make: a pipe held
    ## open after the request, and requests arriving in more than one burst.  A
    ## server that answers only at end of input passes every check above and
    ## works with no real client.
    ##
    ## popen2 rather than a shell script, which is what lets this run
    ## everywhere: it holds standard input and standard output for the child's
    ## lifetime, the shape a host has, and the run is bounded by killing the
    ## child rather than by a command that bounds one, which Windows does not
    ## have.  Nothing is read until after the kill, since a read before it
    ## would block for ever against exactly the server being looked for; what
    ## the child wrote stays in the pipe.
    if (! OK)
      REPORT = skipped (REPORT, ...
        "answers before the input stream closes", ...
        "an earlier check failed, so this one was not attempted");
    else
      if (nargin < 1)
        pexe = dexe;
        pargv = dargv;
      elseif (ispc () && ! isunix ())
        pexe = "cmd";
        pargv = {"/c", CMD};
      else
        pexe = "/bin/sh";
        pargv = {"-c", CMD};
      endif

      ## Two small replies on purpose.  Nothing is read until the kill, and a
      ## pipe holds about 4 KB on Windows against 64 on Linux, so a reply
      ## larger than that blocks the server in its own write and is lost when
      ## the child dies: measured with tools/list, whose 4.4 KB answer never
      ## arrived while a 664 byte one did.  A real host reads continuously and
      ## never meets this, and octave_which answers in a few hundred bytes.
      probe = {sprintf(['{"jsonrpc":"2.0","id":1,"method":"tools/call","params":' ...
                        '{"name":"octave_which","arguments":{"name":"mean"},%s}}'], ...
                       meta), ...
               sprintf(['{"jsonrpc":"2.0","id":2,"method":"tools/call","params":' ...
                        '{"name":"octave_which","arguments":{"name":"sum"},%s}}'], ...
                       meta)};

      resp = burstPipe (pexe, pargv, probe);
      lines = strsplit (strrep (strtrim (resp), "\r\n", "\n"), "\n");
      lines = lines(! cellfun (@isempty, lines));
      answered = 0;
      for i = 1:numel (lines)
        try
          jsondecode (lines{i});
          answered = answered + 1;
        catch
          ## Not a message.  Which line is not one is another check's business
        end_try_catch
      endfor

      [REPORT, OK] = check (REPORT, "answers before the input stream closes", ...
        answered == 2, ...
        sprintf ("%d of 2 bursts answered: a live client will time out", ...
                 answered), OK);
    endif


    ## The evaluating server, and the claim only it can break: a child process
    ## inherits descriptor 1, so code that spawns one writes into the stream
    ## that carries the protocol unless something holds that descriptor.  Run
    ## against devtools.mcpEval rather than devtools.mcp, and only with the default
    ## commands, since a caller-supplied one may not be an evaluating server.
    if (nargin < 1)

      [ECMD, capdir, contained] = defaultEvalCommand ();
      esession = {sprintf(['{"jsonrpc":"2.0","id":1,"method":"tools/call",' ...
                  '"params":{"name":"octave_eval","arguments":' ...
                  '{"code":"system (\\"echo devtoolszzchild\\");",' ...
                  '"workspace":"new"},%s}}'], meta)};

      fid = fopen (infile, "w");
      if (fid < 0)
        error ("devtools.selftest: cannot write a temporary file in %s.", tempdir ());
      endif
      fprintf (fid, "%s\n", esession{:});
      fclose (fid);

      [status, out] = system (sprintf ('%s < "%s" 2> "%s"', ECMD, infile, errfile));

      lines = strsplit (strrep (out, "\r\n", "\n"), "\n");
      lines = lines(! cellfun (@isempty, lines));

      [REPORT, OK] = check (REPORT, "eval: server exited cleanly", ...
                            status == 0, sprintf ("exit status %d", status), OK);

      [quiet, noisy] = quietStderr (errfile);
      [REPORT, OK] = check (REPORT, ...
        "eval: the interpreter raised nothing about the server", ...
        quiet, trunc (noisy), OK);

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
      ##
      ## Only where there is a deadline to reach.  Without __devtools_guard__ code
      ## that does not return never does, so sending it would hang this
      ## function rather than fail it, for as long as the machine runs.  The
      ## skip is reported rather than dropped: a selftest that quietly stops
      ## testing the deadline is worse than one that says it cannot.
      if (! contained)
        REPORT = skipped (REPORT, ...
          "eval: code that does not return is stopped", ...
          "no __devtools_guard__ here, so there is no deadline to reach");
      else
        had = getenv ("DEVTOOLS_EVAL_SECONDS");
        unwind_protect
          setenv ("DEVTOOLS_EVAL_SECONDS", "2");
          loopy = {sprintf(['{"jsonrpc":"2.0","id":1,"method":"tools/call",' ...
                   '"params":{"name":"octave_eval","arguments":' ...
                   '{"code":"while (true), devtoolszzspin = 1; endwhile",' ...
                   '"workspace":"new"},%s}}'], meta), ...
                   sprintf(['{"jsonrpc":"2.0","id":2,"method":"tools/call",' ...
                   '"params":{"name":"octave_eval","arguments":' ...
                 '{"code":"devtoolszzalive = 42;","workspace":"new"},%s}}'], meta)};
          fid = fopen (infile, "w");
          if (fid < 0)
            error ("devtools.selftest: cannot write a temporary file in %s.", ...
                   tempdir ());
          endif
          fprintf (fid, "%s\n", loopy{:});
          fclose (fid);
          ecmd = sprintf ('%s < "%s" 2> "%s"', ECMD, infile, errfile);
          [status, out] = system (ecmd);
        unwind_protect_cleanup
          if (isempty (had))
            unsetenv ("DEVTOOLS_EVAL_SECONDS");
          else
            setenv ("DEVTOOLS_EVAL_SECONDS", had);
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
      endif

      if (contained)
        [REPORT, OK] = check (REPORT, ...
          "eval: what the subprocess printed came back in the result", ...
          ! isempty (strfind (txt, "devtoolszzchild")), trunc (txt), OK);
      else
        ## No capture here, so the shadow took the output back and printed it
        ## through the interpreter.  It still reaches the reply, by the other
        ## route and without the label the capture adds.
        [REPORT, OK] = check (REPORT, ...
          "eval: without the capture, the subprocess output came back", ...
          ! isempty (strfind (txt, "devtoolszzchild")), trunc (txt), OK);
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

function [CMD, exe, argv] = defaultCommand ()

  ## The command string and the argument array describe one launch: a shell
  ## takes the first, popen2 takes the second, and they must not drift apart.
  exe = octaveExe ();
  instdir = fileparts (fileparts (mfilename ("fullpath")));
  code = sprintf ("addpath ('%s'); devtools.mcp ()", instdir);
  argv = {"-q", "--no-init-file", "--eval", code};
  CMD = sprintf ('"%s" -q --no-init-file --eval "%s"', exe, code);

endfunction

function exe = octaveExe ()

  ## The interpreter a spawned server runs.  On Windows the file carries .exe
  ## and OCTAVE_HOME names the mingw64 directory, so the unsuffixed path never
  ## exists there; without the second candidate every launch fell through to
  ## the bare name and depended on PATH, which a host configuration cannot set.
  exe = fullfile (OCTAVE_HOME (), "bin", "octave-cli");
  if (exist (exe, "file") == 2)
    return;
  endif
  if (exist ([exe ".exe"], "file") == 2)
    exe = [exe ".exe"];
    return;
  endif
  exe = "octave-cli";

endfunction

function [CMD, capdir, contained] = defaultEvalCommand ()

  ## The same command the README gives for the evaluating server, plus
  ## whatever directory holds __devtools_capture__ in this process, so that a
  ## source tree is exercised the way an installed package is.
  exe = octaveExe ();
  instdir = fileparts (fileparts (mfilename ("fullpath")));

  capdir = "";
  cap = which ("__devtools_capture__");
  if (! isempty (cap))
    capdir = fileparts (cap);
  endif

  ## The condition dispatch itself routes on, both oct-files or neither, so
  ## that a check asks for the arm the spawned server will actually take.
  contained = (! isempty (cap)) && (! isempty (which ("__devtools_guard__")));

  add = sprintf ("addpath ('%s');", instdir);
  if (! isempty (capdir))
    add = [add sprintf(" addpath ('%s');", capdir)];
  endif
  CMD = sprintf ('"%s" -q --no-init-file --eval "%s devtools.mcpEval ()"', ...
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

function REPORT = skipped (REPORT, what, why)
  ## A check this installation cannot run, named rather than dropped.  It
  ## leaves OK alone: a skip is not a failure and must not read as a pass.
  REPORT{end+1} = sprintf ("SKIP  %s: %s", what, why);
endfunction

function txt = burstPipe (exe, argv, bursts)

  ## Two seconds after each burst.  A running server answers in tens of
  ## milliseconds; the first burst also pays for the interpreter starting and
  ## loading the package, measured at a quarter of a second on both platforms.

  txt = "";
  [in, out, pid] = popen2 (exe, argv);
  if (pid < 0)
    return;
  endif

  unwind_protect
    for i = 1:numel (bursts)
      fprintf (in, "%s\n", bursts{i});
      fflush (in);
      pause (2);
    endfor
    killPid (pid);
    pause (0.5);
    while (true)
      line = fgetl (out);
      if (! ischar (line))
        break;
      endif
      txt = [txt line "\n"];
    endwhile
  unwind_protect_cleanup
    fclose (in);
    fclose (out);
  end_unwind_protect

endfunction

function killPid (pid)

  ## The bound on the run.  Windows has no timeout that limits another program,
  ## its timeout.exe waiting rather than limiting, so the deadline is this kill
  ## rather than the launch.  /T takes the whole tree, cmd.exe having spawned a
  ## child of its own where a caller supplied a command line.
  if (ispc () && ! isunix ())
    [~, ~] = system (sprintf ("taskkill /PID %d /F /T 2>&1", pid));
  else
    [~, ~] = system (sprintf ("kill -9 %d 2> /dev/null", pid));
  endif

endfunction

function [tf, first] = quietStderr (errfile)

  ## The server's own diagnostics belong on standard error; a diagnostic the
  ## interpreter raised about the server does not.  A function whose name
  ## disagrees with its filename, a deprecated call and a failed parse all
  ## announce themselves this way and nothing else here reads that stream, so
  ## each of them survives a run in which every other check passes.
  ##
  ## Matched by the interpreter's own two prefixes rather than by the entry
  ## point's name, which a caller-supplied command is free to choose.

  tf = true;
  first = "";
  if (exist (errfile, "file") != 2)
    return;
  endif

  lines = strsplit (strrep (fileread (errfile), "\r\n", "\n"), "\n");
  for i = 1:numel (lines)
    if (strncmp (lines{i}, "warning:", 8) || strncmp (lines{i}, "error:", 6))
      tf = false;
      first = lines{i};
      return;
    endif
  endfor

endfunction

function s = trunc (s)
  if (numel (s) > 120)
    s = [s(1:120) " ..."];
  endif
endfunction

%!test
%! [ok, rep] = devtools.selftest ();
%! assert_equal (ok, true);
%! assert_equal (iscellstr (rep), true);
%! done = strncmp (rep, "PASS", 4) | strncmp (rep, "SKIP", 4);
%! assert_equal (all (done), true);

%!test
%! ## A command that writes something other than a message must be caught.
%! cmd = 'printf ''hello\n''';
%! [ok, rep] = devtools.selftest (cmd);
%! assert_equal (ok, false);
%! assert_equal (any (! cellfun (@isempty, strfind (rep, "every stdout line"))), true);

%!error <devtools\.selftest: CMD must be a character vector\.> devtools.selftest (5)
