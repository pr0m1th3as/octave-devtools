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
## @deftypefn  {devtools} {} devtools.mcpEval ()
## @deftypefnx {devtools} {} devtools.mcpEval (@qcode{"Sandbox"})
##
## Serve the Model Context Protocol on standard input and output, with
## evaluation.
##
## @code{devtools.mcpEval ()} is @code{devtools.mcp} plus the two tools that run
## code, @code{octave_eval} and @code{octave_test}.
## It reads newline-delimited JSON-RPC messages from standard input, answers
## each one, writes the answer to standard output, and returns only when
## standard input reaches end of file.
##
## @strong{This is a separate entry point on purpose.}  It is a separate
## function, a separate launch command and a separate entry in a host's
## configuration, so that a host configured for @code{devtools.mcp} cannot reach
## these tools however a model asks.  The read-only server evaluates no code,
## runs no user function and writes nothing, which is what lets a user grant it
## blanket permission; this one does all three, and is meant to be configured
## under its own name, conventionally @qcode{"octave-eval"}, so that the
## permission rules for the two can differ.
##
## @subsubheading Configuration
##
## Configure a host to launch it under its own name with:
##
## @example
## octave-cli -q --no-init-file --eval "pkg load devtools; devtools.mcpEval ()"
## @end example
##
## The rules are those of @code{devtools.mcp} and they matter as much here: do
## not shorten the command, name @file{octave-cli.exe} in full on Windows, and
## load whatever packages this server is meant to see, since it sees the ones
## its own launch command loads and no others.
##
## @subsubheading Tools
##
## The five read-only tools of @code{devtools.mcp} are served here as well,
## plus two that run code:
##
## @table @code
## @item octave_eval
## what running some Octave code produces, in a workspace that persists between
## calls.
##
## @item octave_test
## how many of a function's built-in tests pass, and what failed.
## @end table
##
## @subsubheading Testing
##
## @code{octave_test} runs the built-in tests of one function or file and
## reports how many passed, with the assertion behind each failure.  It
## resolves a name through @code{which} and then runs the @emph{file}, which is
## what lets it test a namespaced function or a class method: core's
## @code{test} cannot resolve @code{devtools.jsonrpcError} and answers
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
## interpreter, and @code{__devtools_capture__} holds descriptor 1 over a file
## for the length of the call, which is the only thing that catches a
## @strong{subprocess}: a child inherits the descriptor and writes past
## @code{evalc} entirely, into the stream that carries the protocol.  What a
## child printed comes back labelled in the reply.
##
## Because that containment is at the descriptor and not at a name,
## @code{builtin ("system", @dots{})} does not get around it.  Where the
## package was installed without a compiler and @code{__devtools_capture__}
## could not be built, the containment moves to the two forms that let a child
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
## raised from a thread and caught in @code{__devtools_guard__}.  It cannot be
## done in Octave: measured on 11.2.0, an interrupt raised this way unwinds
## straight through @code{try} and takes the process with it, honouring
## @code{unwind_protect} on the way but never being caught.
##
## Set @env{DEVTOOLS_EVAL_SECONDS} in the launch command for an installation
## whose work honestly takes longer, up to six hundred.  It is not a tool
## argument, since that would cost tokens in every request and is a decision for
## whoever configures the server rather than for the model.
##
## The deadline does not recover everything.  A call wedged inside one long
## native call, or blocked on a read, reaches no checkpoint at which the
## interrupt can be noticed, and the host restarting the process is what
## remains.  Where the oct-files could not be built there is no deadline at
## all.
##
## @subsubheading Sandbox
##
## @code{devtools.mcpEval ("Sandbox")} serves a program rather than a model,
## @strong{inside a sandbox where this machine can build one}: on GNU/Linux
## with @command{bwrap} from the @code{bubblewrap} package and
## @command{prlimit} installed, and on macOS with the system's own
## @command{sandbox-exec}.  Where it cannot, it serves without one and says
## so.  A host that does not read the report below should not be given this
## option on a machine without a sandbox.
##
## Every result states the sandbox in
## @code{_meta["io.github.pr0m1th3as.devtools/sandbox"]}, one of three states,
## and the @code{instructions} say the same to a model:
##
## @table @asis
## @item @qcode{"active"}
## The sandbox was built and verified from inside, and every call runs in it.
##
## @item @qcode{"failed"}
## The machine has the mechanism, but the sandbox did not start or did not
## pass its check.  The server serves unconfined.
##
## @item @qcode{"unavailable"}
## The machine has no mechanism for one: another system, or @command{bwrap},
## @command{prlimit} or @command{sandbox-exec} missing.  The server serves
## unconfined.
## @end table
##
## For the last two, @code{_meta["io.github.pr0m1th3as.devtools/sandboxReason"]}
## says why, and standard error logs it as the server starts.
##
## Either way it offers @code{octave_call} and @code{octave_test} beside the
## read-only tools, and not @code{octave_eval}: every call starts from the same
## state in a process of its own, so a workspace would carry nothing.
## @code{octave_call} is for programs, which read its structured result, its
## text being a summary without the values.  It runs no code text: it calls
## one function by name on typed arguments, a matrix as a list of rows, a flat
## list being a column, and a range carrying each cell's kind and value, and
## returns each output as typed cells row by row, dates as serial numbers from
## the document's null date, with anything the function printed beside them.
## A call that crashes the interpreter comes back as an error, and the server
## keeps serving.
##
## The folders it may read and the packages it loads are set in the launch
## environment, never in the command.  @env{DEVTOOLS_SANDBOX_FOLDERS} holds
## absolute folder paths separated by @code{pathsep}, and
## @env{DEVTOOLS_SANDBOX_PACKAGES} holds package names separated by commas,
## loaded in that order.  Nothing checks whether two of them conflict.  The
## folders are on the load path, ahead of the packages, with or without the
## sandbox.  A host launches it like the plain server:
##
## @example
## octave-cli -q --no-init-file \
##   --eval "pkg load devtools; devtools.mcpEval ('Sandbox')"
## @end example
##
## @subsubheading Inside the sandbox
##
## The server first builds the sandbox once, checks it from inside and leaves
## it, and serves unconfined, @qcode{"failed"}, if that check does not pass.
## Only then does it replace its own process with a sandboxed
## @file{octave-cli} built by @code{devtools.sandboxCommand}.  The process, its
## standard streams and its exit code carry through unchanged.  The trial is
## there because a replaced process cannot come back: a sandbox found wanting
## from inside has no unconfined process left to serve from.  Should the check
## pass on the trial and fail on the real run, the server stays up, reports
## @qcode{"failed"} and offers no tools at all, since serving half-confined is
## what the check exists to prevent.
##
## The check is that there is no @file{/usr/bin}, no network interface
## besides the loopback, an address-space limit in force, and nothing under
## @file{/home} or the home directory that was not mounted.  The limit is this
## process's size plus 2 GB, or plus the number of gigabytes in
## @env{DEVTOOLS_SANDBOX_MEMORY}, and an allocation beyond it fails with
## Octave's own out-of-memory error.  @file{/tmp}, whose files are memory too,
## holds at most 2 GB, or the number of gigabytes in
## @env{DEVTOOLS_SANDBOX_TMP}.  It lists only the packages that are mounted,
## so loading any other says it is not installed.  See
## @code{devtools.sandboxCommand} for what is mounted and what is refused.
## Each call runs in a process forked for it, which is killed when it returns
## or when the deadline passes, together with every process it started, and
## @file{/tmp} is emptied before the next call, so that nothing one call does
## reaches another.
##
## The two systems confine by different means, so each names the guarantees it
## holds rather than claiming the other's.  On macOS a sandboxed server writes
## one line to standard error as it starts,
## @code{OMP: Warning #179: Function Can't set size of /tmp file failed:}, and
## then serves normally.  OpenMP registers itself by making
## @file{/tmp/__KMP_REGISTERED_LIB_<pid>}, naming @file{/tmp} rather
## than reading @env{TMPDIR}, and the sandbox does not grant the host's
## @file{/tmp}.  What that registration detects is a second OpenMP runtime in
## the same process, which Octave does not have, so nothing is lost by it.  It
## is left alone deliberately: granting the write would put a file of the
## server's outside the sandbox at every launch, and suppressing the warning
## would hide the next thing to go wrong on the same path.
##
## @subsubheading Without the sandbox
##
## Unconfined, each call still runs in a process of its own and is stopped at
## the deadline: forked where the system can fork, and on Windows, which
## cannot, an @file{octave-cli} started for the call inside a job object by
## @code{__devtools_spawn__}, which a working compiler builds at installation.
## A process a call starts outlives it where it was forked, and the call can
## read and write files and use the network as any Octave code can.
##
## @subsubheading What this is not
##
## Unless started with @qcode{"Sandbox"} and reporting it @qcode{"active"},
## none of this is a sandbox.  Evaluated code can read and write files, use the
## network and consume memory exactly as any code in this interpreter can.
## Configure this server only where that is acceptable.
##
## @seealso{devtools.mcp, devtools.selftest, devtools.sandboxCommand}
## @end deftypefn

function mcpEval (varargin)

  if (nargin == 0)
    devtools.__serveLoop__ ("eval", "mcpEval");
    return;
  endif
  if (nargin != 1)
    error ("devtools.mcpEval: invalid number of input arguments.");
  endif
  if (! (ischar (varargin{1}) && strcmpi (varargin{1}, "Sandbox")))
    error ("devtools.mcpEval: the only option is 'Sandbox'.");
  endif

  ## The marker only says which side of the relaunch this is; what proves
  ## the sandbox is the check the relaunched server makes.
  if (strcmp (getenv ("DEVTOOLS_SANDBOX"), "1"))
    serveInside ();
    return;
  endif

  ## Outside.  No mechanism is "unavailable", a mechanism that refuses is
  ## "failed", and both serve here, unconfined, saying which.  Where the
  ## sandbox can be built it is tried once before it is entered, since an
  ## exec cannot come back: a sandbox that fails its check from inside
  ## leaves no unconfined process to serve from.
  [why, state] = devtools.__sandboxUsable__ ();
  if (isempty (why))
    folders = splitEnv ("DEVTOOLS_SANDBOX_FOLDERS", pathsep ());
    packages = splitEnv ("DEVTOOLS_SANDBOX_PACKAGES", ",");
    try
      [prog, args] = devtools.sandboxCommand (folders, packages);
      why = trialRun (prog, args);
    catch err
      why = regexprep (err.message, '^devtools\.sandboxCommand: |\.$', "");
    end_try_catch
    if (isempty (why))
      [~, msg] = exec (prog, [args, {"--eval", insideCode("")}]);
      why = sprintf ("the sandbox did not start: %s", msg);
    endif
    state = "failed";
  endif
  serveOutside (state, why);

endfunction

## The code a relaunched interpreter evaluates.  A trial run sets its marker
## first, the sandbox clearing every variable it was not given.
function code = insideCode (pre)
  code = strcat (pre, " self = getenv ('DEVTOOLS_SANDBOX_SELF');", ...
                 " if (isempty (self)) pkg ('load', 'devtools');", ...
                 " else addpath (self); endif;", ...
                 " devtools.mcpEval ('Sandbox')");
endfunction

## Build the sandbox once, check it from inside and leave, so that the
## server enters only a sandbox that is known to hold.  Returns the empty
## string, or why it does not.
function why = trialRun (prog, args)

  why = "";
  code = insideCode ("setenv ('DEVTOOLS_SANDBOX_TRIAL', '1');");
  [in, out, pid] = popen2 (prog, [args, {"--eval", code}]);
  fclose (in);
  if (pid < 0)
    why = "the sandbox could not be started for its trial run";
    fclose (out);
    return;
  endif
  t0 = tic ();
  while (true)
    [r, status] = waitpid (pid, WNOHANG ());
    if (r == pid)
      break;
    endif
    if (toc (t0) > 60)
      kill (pid, 9);
      waitpid (pid);
      fclose (out);
      why = "the sandbox did not finish its trial run within 60 seconds";
      return;
    endif
    pause (0.05);
  endwhile
  txt = fread (out, Inf, "char=>char").';
  fclose (out);
  k = regexp (txt, 'devtools-sandbox: (ok|failed: [^\n]*)', "tokens", "once");
  if (isempty (k))
    why = sprintf (strcat ("the sandbox ended its trial run without an", ...
                           " answer, exit %d"), WEXITSTATUS (status));
  elseif (! strcmp (k{1}, "ok"))
    why = k{1}(9:end);
  endif

endfunction

## Serve without a sandbox, the packages and folders set up as they would be
## inside it, and every result saying why there is none.
function serveOutside (state, why)

  packages = splitEnv ("DEVTOOLS_SANDBOX_PACKAGES", ",");
  for i = 1:numel (packages)
    pkg ("load", packages{i});
  endfor
  folders = splitEnv ("DEVTOOLS_SANDBOX_FOLDERS", pathsep ());
  for i = 1:numel (folders)
    addpath (folders{i});
  endfor
  devtools.__serveLoop__ ("program", "mcpEval", ...
                          struct ("state", state, "reason", why));

endfunction

## Inside the sandbox: check it, and serve only if it holds.
function serveInside ()

  ## Inside.  A killed Octave writes octave-workspace into its working
  ## directory unless told not to.
  crash_dumps_octave_core (false);
  sighup_dumps_octave_core (false);
  sigquit_dumps_octave_core (false);
  sigterm_dumps_octave_core (false);

  [localPkgs, globalPkgs] = pkg ("list");
  entries = [localPkgs(:).', globalPkgs(:).'];
  allowed = [splitEnv("DEVTOOLS_SANDBOX_FOLDERS", pathsep ()), ...
             {pkg("local_list"), pkg("global_list")}, ...
             cellfun(@(s) s.dir, entries, "UniformOutput", false), ...
             cellfun(@(s) s.archprefix, entries, "UniformOutput", false)];
  self = getenv ("DEVTOOLS_SANDBOX_SELF");
  if (! isempty (self))
    allowed{end+1} = self;
  endif
  ## A distribution puts octave-cli in /usr/bin, and binding it there makes
  ## the directory, so the question is not whether /usr/bin exists but whether
  ## anything in it was not mounted.  The name it was mounted under is the one
  ## the sandbox was told to use, which cannot be worked out again from in
  ## here: only the canonical name exists inside.
  cli = getenv ("DEVTOOLS_SANDBOX_CLI");
  if (ismac ())
    ## The roots are what the promise covers, and the two platforms promise
    ## different things about the same folders.  bwrap leaves /usr/bin
    ## unmounted, so nothing there exists and its absence is checked; Seatbelt
    ## refuses to execute what is there and does not hide it, so /bin being
    ## readable is not a failure and demanding otherwise would refuse a
    ## sandbox that is working.  What is promised here is that home and the
    ## packages that were not asked for cannot be read, and that no program
    ## runs at all, which the check tests directly.
    roots = {getenv("HOME")};
    for i = 1:numel (entries)
      roots = [roots, {fileparts(entries{i}.dir), ...
                       fileparts(entries{i}.archprefix)}];
    endfor
  else
    roots = {"/home", getenv("HOME"), "/usr/bin", "/bin"};
    if (! isempty (cli))
      roots{end+1} = fileparts (cli);
    endif
  endif
  if (! isempty (cli))
    allowed{end+1} = cli;
  endif
  roots = unique (roots(! cellfun (@isempty, roots)));
  failed = devtools.__sandboxCheck__ (allowed, roots);
  if (strcmp (getenv ("DEVTOOLS_SANDBOX_TRIAL"), "1"))
    if (isempty (failed))
      printf ("devtools-sandbox: ok\n");
    else
      printf ("devtools-sandbox: failed: the sandbox is not in force: %s\n", ...
              strjoin (failed, "; "));
    endif
    fflush (stdout);
    exit (0);
  endif
  ## Only a race gets here: the trial run passed and this one did not.  It
  ## cannot leave the sandbox, and serving half-confined is what the check
  ## exists to prevent, so it runs nothing and says why.
  if (! isempty (failed))
    why = sprintf ("the sandbox is not in force: %s", strjoin (failed, "; "));
    devtools.__serveLoop__ ("halted", "mcpEval", ...
                            struct ("state", "failed", "reason", why));
    return;
  endif

  ## The mounted lists name every installed package.  The server reads lists
  ## naming only what is mounted, rebuilt from these read-only originals
  ## before every call, since /tmp is writable and a call could change them.
  setenv ("DEVTOOLS_SANDBOX_LOCAL_LIST", pkg ("local_list"));
  setenv ("DEVTOOLS_SANDBOX_GLOBAL_LIST", pkg ("global_list"));
  ## The writable root is whatever the sandbox published: /tmp under bwrap,
  ## and a folder of its own under Seatbelt, which has no tmpfs to make.
  root = getenv ("DEVTOOLS_SANDBOX_ROOT");
  if (isempty (root))
    root = "/tmp";
  endif
  devtools.__sandboxLists__ (getenv ("DEVTOOLS_SANDBOX_LOCAL_LIST"), ...
                             getenv ("DEVTOOLS_SANDBOX_GLOBAL_LIST"), ...
                             fullfile (root, "devtools-0"));

  packages = splitEnv ("DEVTOOLS_SANDBOX_PACKAGES", ",");
  for i = 1:numel (packages)
    pkg ("load", packages{i});
  endfor
  ## Added after the packages, so that a function in a folder is found ahead
  ## of a package function of the same name.
  folders = splitEnv ("DEVTOOLS_SANDBOX_FOLDERS", pathsep ());
  for i = 1:numel (folders)
    addpath (folders{i});
  endfor

  devtools.__serveLoop__ ("program", "mcpEval", ...
                          struct ("state", "active", "reason", ""));

endfunction

## The non-empty parts of an environment variable split at SEP.
function C = splitEnv (name, sep)
  C = strsplit (getenv (name), sep);
  C = C(! cellfun (@isempty, C));
endfunction

## A real sandbox needs GNU/Linux with bwrap, or macOS.
%!shared canRun, exe, instdir, req, meta
%! canRun = isempty (devtools.__sandboxUsable__ ());
%! meta = ['"_meta":{"io.modelcontextprotocol/protocolVersion":', ...
%!         '"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}'];
%! exe = fullfile (OCTAVE_HOME (), "bin", "octave-cli");
%! instdir = fileparts (fileparts (which ("devtools.mcpEval")));
%! req = ['{"jsonrpc":"2.0","id":1,"method":"server/discover","params":', ...
%!        '{"_meta":{"io.modelcontextprotocol/protocolVersion":', ...
%!        '"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}'];

%!test
%! ## Started outside, the server relaunches inside and reports it active.
%! if (canRun)
%!   f = tempname ();
%!   fid = fopen (f, "w");
%!   fprintf (fid, "%s\n", req);
%!   fclose (fid);
%!   cmd = sprintf (['env DEVTOOLS_SANDBOX= DEVTOOLS_SANDBOX_FOLDERS=', ...
%!                   ' DEVTOOLS_SANDBOX_PACKAGES= "%s" -q --no-init-file', ...
%!                   ' --eval "addpath (''%s''); devtools.mcpEval', ...
%!                   ' (''Sandbox'')" < "%s" 2>/dev/null'], ...
%!                  exe, instdir, f);
%!   [~, out] = system (cmd);
%!   delete (f);
%!   k = '"io.github.pr0m1th3as.devtools/sandbox":"active"';
%!   assert_equal (isempty (strfind (out, k)), false);
%! endif
%!test
%! ## The marker alone is not a sandbox: outside, the check fails and the
%! ## server runs nothing, saying why.
%! if (canRun)
%!   f = tempname ();
%!   fid = fopen (f, "w");
%!   fprintf (fid, "%s\n", req);
%!   fclose (fid);
%!   cmd = sprintf (['env DEVTOOLS_SANDBOX=1 "%s" -q --no-init-file', ...
%!                   ' --eval "addpath (''%s''); devtools.mcpEval', ...
%!                   ' (''Sandbox'')" < "%s" 2>/dev/null'], ...
%!                  exe, instdir, f);
%!   [status, out] = system (cmd);
%!   delete (f);
%!   k = '"io.github.pr0m1th3as.devtools/sandbox":"failed"';
%!   assert_equal ([status, isempty(strfind (out, k)), ...
%!                  isempty(strfind (out, "not in force"))], [0, false, false]);
%! endif

%!function out = sandboxRun (exe, instdir, envs, lines)
%!  f = tempname ();
%!  fid = fopen (f, "w");
%!  fprintf (fid, "%s\n", lines{:});
%!  fclose (fid);
%!  e = tempname ();
%!  cmd = sprintf (['env DEVTOOLS_SANDBOX= DEVTOOLS_SANDBOX_FOLDERS=', ...
%!                  ' DEVTOOLS_SANDBOX_PACKAGES= %s "%s" -q --no-init-file', ...
%!                  ' --eval "addpath (''%s''); devtools.mcpEval', ...
%!                  ' (''Sandbox'')" < "%s" 2> "%s"'], ...
%!                 envs, exe, instdir, f, e);
%!  [status, out] = system (cmd);
%!  ## A sandbox that refuses to serve says why here and nowhere else, so a
%!  ## discarded standard error left every such failure without a diagnosis.
%!  if (status != 0 && exist (e, "file") == 2)
%!    printf ("sandboxRun: exit %d: %s\n", status, strtrim (fileread (e)));
%!  endif
%!  delete (f);
%!  if (exist (e, "file") == 2)
%!    delete (e);
%!  endif
%!endfunction

%!test
%! ## A sandboxed server offers octave_test and not octave_eval.
%! if (canRun)
%!   L = ['{"jsonrpc":"2.0","id":1,"method":"tools/list",', ...
%!        '"params":{', meta, '}}'];
%!   out = sandboxRun (exe, instdir, "", {L});
%!   assert_equal ([isempty(strfind (out, '"name":"octave_test"')), ...
%!                  isempty(strfind (out, '"name":"octave_eval"'))], ...
%!                 [false, true]);
%! endif
%!test
%! ## A call runs in a forked child and comes back with its count.
%! if (canRun)
%!   T = ['{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{', meta, ...
%!        ',"name":"octave_test",', ...
%!        '"arguments":{"name":"devtools.jsonrpcError"}}}'];
%!   out = sandboxRun (exe, instdir, "", {T});
%!   p = '\[tests\] (\d+) of \1 passed';
%!   assert_equal (isempty (regexp (out, p, "once")), false);
%! endif
%!test
%! ## A call stopped at the deadline leaves the server serving the next one.
%! if (canRun)
%!   D = ['{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{', meta, ...
%!        ',"name":"octave_test","arguments":{"name":"devtools.dispatch"}}}'];
%!   T = ['{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{', meta, ...
%!        ',"name":"octave_test",', ...
%!        '"arguments":{"name":"devtools.jsonrpcError"}}}'];
%!   out = sandboxRun (exe, instdir, "DEVTOOLS_EVAL_SECONDS=1", {D, T});
%!   p = '\[tests\] (\d+) of \1 passed';
%!   assert_equal ([isempty(strfind (out, "[stopped]")), ...
%!                  isempty(regexp (out, p, "once"))], [false, false]);
%! endif
%!test
%! ## octave_call over a range: an empty cell is NaN, a NaN result is null.
%! if (canRun)
%!   C = ['{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{', meta, ...
%!        ',"name":"octave_call","arguments":{"function":"mean","args":[', ...
%!        '{"type":"range","rows":2,"cols":3,"cells":[', ...
%!        '{"kind":"number","value":1},{"kind":"number","value":2},', ...
%!        '{"kind":"number","value":3},{"kind":"number","value":4},', ...
%!        '{"kind":"empty"},{"kind":"number","value":6}]}]}}}'];
%!   out = sandboxRun (exe, instdir, "", {C});
%!   assert_equal (isempty (strfind (out, '"cells":[2.5,null,4.5]')), false);
%! endif
%!test
%! ## Every output asked for comes back, in order.
%! if (canRun)
%!   C = ['{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{', meta, ...
%!        ',"name":"octave_call","arguments":{"function":"max",', ...
%!        '"nargout":2,', ...
%!        '"args":[{"type":"range","rows":1,"cols":3,"cells":[', ...
%!        '{"kind":"number","value":3},{"kind":"number","value":7},', ...
%!        '{"kind":"number","value":5}]}]}}}'];
%!   out = sandboxRun (exe, instdir, "", {C});
%!   assert_equal (isempty (regexp (out, '"cells":\[7\].*"cells":\[2\]', ...
%!                                  "once")), false);
%! endif
%!test
%! ## What the function printed comes back beside its outputs.
%! if (canRun)
%!   C = ['{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{', meta, ...
%!        ',"name":"octave_call","arguments":{"function":"fprintf",', ...
%!        '"args":[{"type":"string","value":"hello\n"}]}}}'];
%!   out = sandboxRun (exe, instdir, "", {C});
%!   assert_equal ([isempty(strfind (out, '"cells":[6]')), ...
%!                  isempty(strfind (out, '"printed":"hello\n"'))], ...
%!                 [false, false]);
%! endif
%!test
%! ## An Octave error comes back with its message and identifier.
%! if (canRun)
%!   C = ['{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{', meta, ...
%!        ',"name":"octave_call","arguments":{"function":"error","args":[', ...
%!        '{"type":"string","value":"devtools:probe"},', ...
%!        '{"type":"string","value":"boom"}]}}}'];
%!   out = sandboxRun (exe, instdir, "", {C});
%!   k = '"error":"boom","identifier":"devtools:probe"';
%!   assert_equal ([isempty(strfind (out, '"isError":true')), ...
%!                  isempty(strfind (out, k))], [false, false]);
%! endif
%!test
%! ## Dates go in as datetime and come back as serial numbers.
%! L = pkg ("list");
%! if (canRun && any (cellfun (@(s) strcmp (s.name, "datatypes"), L)))
%!   C = ['{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{', meta, ...
%!        ',"name":"octave_call","arguments":{"function":"max","args":[', ...
%!        '{"type":"range","rows":1,"cols":2,"cells":[', ...
%!        '{"kind":"date","value":46279},{"kind":"date","value":46300}]}]}}}'];
%!   env = "DEVTOOLS_SANDBOX_PACKAGES=datatypes";
%!   out = sandboxRun (exe, instdir, env, {C});
%!   assert_equal ([isempty(strfind (out, '"kind":"datetime"')), ...
%!                  isempty(strfind (out, '"cells":[46300]'))], [false, false]);
%! endif
%!test
%! ## Without datatypes, a range of dates is refused.
%! if (canRun)
%!   C = ['{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{', meta, ...
%!        ',"name":"octave_call","arguments":{"function":"max","args":[', ...
%!        '{"type":"range","rows":1,"cols":1,"cells":[', ...
%!        '{"kind":"date","value":46279}]}]}}}'];
%!   out = sandboxRun (exe, instdir, "", {C});
%!   p = "need the datatypes package";
%!   assert_equal (isempty (strfind (out, p)), false);
%! endif

%!test
%! ## A sandbox that cannot be built serves anyway, unconfined, saying which
%! ## state it is in and why, and a call runs in a process of its own.  A
%! ## folder inside /tmp is one bwrap refuses.
%! if (! ispc ())
%!   d = tempname ();
%!   mkdir (d);
%!   C = ['{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{', meta, ...
%!        ',"name":"octave_call","arguments":{"function":"plus","args":[', ...
%!        '{"type":"number","value":2},{"type":"number","value":3}]}}}'];
%!   out = sandboxRun (exe, instdir, ["DEVTOOLS_SANDBOX_FOLDERS=", d], {C});
%!   rmdir (d);
%!   st = regexp (out, '"io.github.pr0m1th3as.devtools/sandbox":"(\w+)"', ...
%!                "tokens", "once");
%!   assert_equal (isempty (strfind (out, '"cells":[5]')), false);
%!   if (strcmp (uname ().sysname, "Linux"))
%!     assert_equal (any (strcmp (st{1}, {"failed", "unavailable"})), true);
%!     assert_equal (isempty (strfind (out, "sandboxReason")), false);
%!   endif
%! endif

%!error <devtools\.mcpEval: invalid number of input arguments\.> ...
%! devtools.mcpEval ("Sandbox", true)
%!error <devtools\.mcpEval: the only option is 'Sandbox'\.> ...
%! devtools.mcpEval ("Sandboxed")
%!error <devtools\.mcpEval: the only option is 'Sandbox'\.> ...
%! devtools.mcpEval (1)
