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
## inside a sandbox, on Linux only and with @command{bwrap} from the
## @code{bubblewrap} package installed.  Before serving, the server replaces its
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
## there is no @file{/usr/bin}, no network interface besides the loopback, and
## nothing under @file{/home} or the home directory that was not mounted, and
## it refuses to serve if any check fails.  It lists only the packages that are
## mounted, so loading any other says it is not installed.  Every result then
## carries @code{_meta["io.github.pr0m1th3as.devtools/sandbox"]} set to true,
## which is absent from a server that is not sandboxed, and the
## @code{instructions} say so.
##
## @code{devtools.mcpEval ("Sandbox", false)} serves exactly as
## @code{devtools.mcpEval ()}.
##
## @subsubheading What this is not
##
## Unless started with @qcode{"Sandbox"}, none of this is a sandbox.  Evaluated
## code can read and write files, use the network and consume memory exactly as
## any code in this interpreter can.  Configure this server only where that is
## acceptable.  A sandboxed server does not cap memory either.
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
  roots = unique ({"/home", getenv("HOME")});
  failed = devtools.__sandboxCheck__ (allowed, roots);
  if (! isempty (failed))
    error (strcat ("devtools.mcpEval: refusing to serve, the sandbox is", ...
                   " not in force: %s."), strjoin (failed, "; "));
  endif

  ## pkg reads the mounted lists, which name every installed package; the
  ## ones it is given instead name only what is mounted.  The global entries
  ## come from pkg ("list"), so their relative paths are already expanded.
  listdir = "/tmp/devtools";
  [ok, msg] = mkdir (listdir);
  if (! ok)
    error ("devtools.mcpEval: cannot write the package lists: %s.", msg);
  endif
  local_packages = localPkgs(cellfun (@(s) isfolder (s.dir), localPkgs));
  global_packages = globalPkgs(cellfun (@(s) isfolder (s.dir), globalPkgs));
  save ("-text", fullfile (listdir, "local_packages"), "local_packages");
  save ("-text", fullfile (listdir, "global_packages"), "global_packages");
  pkg ("local_list", fullfile (listdir, "local_packages"));
  pkg ("global_list", fullfile (listdir, "global_packages"));

  packages = splitEnv ("DEVTOOLS_SANDBOX_PACKAGES", ",");
  for i = 1:numel (packages)
    pkg ("load", packages{i});
  endfor

  devtools.__serveLoop__ ("eval", "mcpEval", true);

endfunction

## The non-empty parts of an environment variable split at SEP.
function C = splitEnv (name, sep)
  C = strsplit (getenv (name), sep);
  C = C(! cellfun (@isempty, C));
endfunction

## A real sandbox needs Linux and bwrap.
%!shared canRun, exe, instdir, req
%! canRun = isunix () && ! ismac () ...
%!          && ! isempty (file_in_path (getenv ("PATH"), "bwrap"));
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
