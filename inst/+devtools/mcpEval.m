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
## @deftypefnx {devtools} {} devtools.mcpEval (@qcode{"Sandbox"}, @var{TF})
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
## @code{devtools.mcpEval ("Sandbox", true)} serves the same protocol from
## inside a sandbox, on GNU/Linux with @command{bwrap} from the
## @code{bubblewrap} package installed, and on macOS with the system's own
## @command{sandbox-exec}.  The two confine by different means, so each names
## the guarantees it holds rather than claiming the other's.
##
## On macOS a sandboxed server writes one line to standard error as it starts,
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
## Before serving, the server replaces its
## own process with a sandboxed @file{octave-cli} built by
## @code{devtools.sandboxCommand}.  The process, its standard streams and its
## exit code carry through unchanged, so a host launches it like the plain
## server:
##
## @example
## octave-cli -q --no-init-file \
##   --eval "pkg load devtools; devtools.mcpEval ('Sandbox', true)"
## @end example
##
## The folders it may read and the packages it loads are set in the launch
## environment, never in the command.  @env{DEVTOOLS_SANDBOX_FOLDERS} holds
## absolute folder paths separated by @code{pathsep}, and
## @env{DEVTOOLS_SANDBOX_PACKAGES} holds package names separated by commas,
## loaded in that order.  Nothing checks whether two of them conflict.  See
## @code{devtools.sandboxCommand} for what is mounted and what is refused.
##
## Before it answers anything, the sandboxed server checks from inside that
## there is no @file{/usr/bin}, no network interface besides the loopback, an
## address-space limit in force, and nothing under @file{/home} or the home
## directory that was not mounted, and it refuses to serve if any check fails.
## The limit is this process's size plus 2 GB, or plus the number of gigabytes
## in @env{DEVTOOLS_SANDBOX_MEMORY}, and an allocation beyond it fails with
## Octave's own out-of-memory error.  @file{/tmp}, whose files are memory too,
## holds at most 2 GB, or the number of gigabytes in
## @env{DEVTOOLS_SANDBOX_TMP}.  It lists only the packages that are
## mounted, so loading any other says it is not installed.  Every result then
## carries @code{_meta["io.github.pr0m1th3as.devtools/sandbox"]} set to true,
## which is absent from a server that is not sandboxed, and the
## @code{instructions} say so.
##
## The folders are on the load path, ahead of the packages.
##
## A sandboxed server offers @code{octave_call} and @code{octave_test} beside
## the read-only tools, and not @code{octave_eval}: every call starts from the
## same state, so a workspace would carry nothing.  @code{octave_call} is for
## programs, which read its structured result, its text being a summary without
## the values.  It runs no code text: it calls one function by name on typed
## arguments, a range carrying each cell's kind and value, and returns each
## output as typed cells
## row by row, dates as serial numbers from the document's null date, with
## anything the function printed beside them.  Each call runs in a process
## forked for it,
## which is killed when it returns or when the deadline passes, together with
## every process it started, and @file{/tmp} is emptied before the next call,
## so that nothing one call does reaches another.  A call that crashes the
## interpreter comes back as an error, and the server keeps serving.
##
## @code{devtools.mcpEval ("Sandbox", false)} serves exactly as
## @code{devtools.mcpEval ()}.
##
## @subsubheading What this is not
##
## Unless started with @qcode{"Sandbox"}, none of this is a sandbox.  Evaluated
## code can read and write files, use the network and consume memory exactly as
## any code in this interpreter can.  Configure this server only where that is
## acceptable.
##
## @seealso{devtools.mcp, devtools.selftest, devtools.sandboxCommand}
## @end deftypefn

function mcpEval (varargin)

  if (nargin == 0)
    sandbox = false;
  elseif (nargin == 2)
    if (! (ischar (varargin{1}) && strcmpi (varargin{1}, "Sandbox")))
      error ("devtools.mcpEval: the only option is 'Sandbox'.");
    endif
    sandbox = varargin{2};
    if (! (islogical (sandbox) && isscalar (sandbox)))
      error ("devtools.mcpEval: 'Sandbox' must be a logical scalar.");
    endif
  else
    error ("devtools.mcpEval: invalid number of input arguments.");
  endif

  if (! sandbox)
    devtools.__serveLoop__ ("eval", "mcpEval");
    return;
  endif

  ## Outside: relaunch inside and never return.  The marker only prevents a
  ## loop; what proves the sandbox is the check the relaunched server makes.
  if (! strcmp (getenv ("DEVTOOLS_SANDBOX"), "1"))
    folders = splitEnv ("DEVTOOLS_SANDBOX_FOLDERS", pathsep ());
    packages = splitEnv ("DEVTOOLS_SANDBOX_PACKAGES", ",");
    [prog, args] = devtools.sandboxCommand (folders, packages);
    code = strcat ("self = getenv ('DEVTOOLS_SANDBOX_SELF');", ...
                   " if (isempty (self)) pkg ('load', 'devtools');", ...
                   " else addpath (self); endif;", ...
                   " devtools.mcpEval ('Sandbox', true)");
    [~, msg] = exec (prog, [args, {"--eval", code}]);
    error ("devtools.mcpEval: the sandbox did not start: %s.", msg);
  endif

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
  if (! isempty (failed))
    error (strcat ("devtools.mcpEval: refusing to serve, the sandbox is", ...
                   " not in force: %s."), strjoin (failed, "; "));
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

  devtools.__serveLoop__ ("eval", "mcpEval", true);

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
%! ## Started outside, the server relaunches inside and reports the sandbox.
%! if (canRun)
%!   f = tempname ();
%!   fid = fopen (f, "w");
%!   fprintf (fid, "%s\n", req);
%!   fclose (fid);
%!   cmd = sprintf (['env DEVTOOLS_SANDBOX= DEVTOOLS_SANDBOX_FOLDERS=', ...
%!                   ' DEVTOOLS_SANDBOX_PACKAGES= "%s" -q --no-init-file', ...
%!                   ' --eval "addpath (''%s''); devtools.mcpEval', ...
%!                   ' (''Sandbox'', true)" < "%s" 2>/dev/null'], ...
%!                  exe, instdir, f);
%!   [~, out] = system (cmd);
%!   delete (f);
%!   k = '"io.github.pr0m1th3as.devtools/sandbox":true';
%!   assert_equal (isempty (strfind (out, k)), false);
%! endif
%!test
%! ## The marker alone is not a sandbox: outside, the check refuses to serve.
%! if (canRun)
%!   f = tempname ();
%!   fid = fopen (f, "w");
%!   fprintf (fid, "%s\n", req);
%!   fclose (fid);
%!   cmd = sprintf (['env DEVTOOLS_SANDBOX=1 "%s" -q --no-init-file', ...
%!                   ' --eval "addpath (''%s''); devtools.mcpEval', ...
%!                   ' (''Sandbox'', true)" < "%s" 2>/dev/null'], ...
%!                  exe, instdir, f);
%!   [status, out] = system (cmd);
%!   delete (f);
%!   assert_equal ([status != 0, isempty(out)], [true, true]);
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
%!                  ' (''Sandbox'', true)" < "%s" 2> "%s"'], ...
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

%!error <devtools\.mcpEval: invalid number of input arguments\.> ...
%! devtools.mcpEval ("Sandbox")
%!error <devtools\.mcpEval: invalid number of input arguments\.> ...
%! devtools.mcpEval ("Sandbox", true, 1)
%!error <devtools\.mcpEval: the only option is 'Sandbox'\.> ...
%! devtools.mcpEval ("Sandboxed", true)
%!error <devtools\.mcpEval: the only option is 'Sandbox'\.> ...
%! devtools.mcpEval (1, true)
%!error <devtools\.mcpEval: 'Sandbox' must be a logical scalar\.> ...
%! devtools.mcpEval ("Sandbox", 1)
%!error <devtools\.mcpEval: 'Sandbox' must be a logical scalar\.> ...
%! devtools.mcpEval ("Sandbox", [true, false])
