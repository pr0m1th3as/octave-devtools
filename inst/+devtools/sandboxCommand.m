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
## @deftypefn {devtools} {[@var{PROG}, @var{ARGS}] =} devtools.sandboxCommand (@var{FOLDERS}, @var{PACKAGES})
##
## Build the command that runs @file{octave-cli} inside a sandbox.
##
## @code{[@var{PROG}, @var{ARGS}] = devtools.sandboxCommand (@var{FOLDERS},
## @var{PACKAGES})} returns the path of @command{bwrap} as @var{PROG} and its
## arguments as the row cell array @var{ARGS}, ending with the @file{octave-cli}
## command.  Append @option{--eval} and its text to @var{ARGS} and pass both to
## @code{exec}, which supplies the program name itself.
##
## @var{FOLDERS} is a cell array of absolute paths to existing folders, mounted
## read-only.  @var{PACKAGES} is a cell array of installed package names; those
## packages and every package they depend on are mounted read-only, and no
## other package is visible.  Either may be empty.  Nothing is loaded here: the
## names reach the sandboxed Octave in the order given, through the environment,
## and nothing checks whether two of them conflict.
##
## The sandbox is built from what is mounted rather than from which functions
## are refused.  Mounted read-only are the system libraries and shared data,
## Octave's own installation, the @file{octave-cli} binary, the package lists,
## the packages and the folders; not mounted are @file{/usr/bin}, so there is
## no shell or other program to start, and the rest of the home directory.
## There is no network.  The only writable place is an in-memory @file{/tmp},
## whose @file{/tmp/work} is the working directory, so nothing on the host disk
## can be written.  The sandboxed process dies with its parent.
##
## @var{FOLDERS} may not be the home directory itself, nor any folder that
## contains Octave's history file, which holds everything typed at a prompt.
## Nor may a folder lie inside @file{/tmp}, @file{/proc} or @file{/dev}, which
## the sandbox replaces with its own, so that such a folder would be invisible.
##
## The environment inside is cleared except for @env{HOME}, @env{LANG} and
## @env{DEVTOOLS_EVAL_SECONDS}, and carries @env{DEVTOOLS_SANDBOX} set to 1,
## @env{DEVTOOLS_SANDBOX_FOLDERS} and @env{DEVTOOLS_SANDBOX_PACKAGES}.  Where
## this copy of @code{devtools} is not an installed package, its folder is
## mounted as well and named in @env{DEVTOOLS_SANDBOX_SELF}.
##
## A sandbox is available on Linux only, and needs @command{bwrap} from the
## @code{bubblewrap} package on the @env{PATH}.
##
## @seealso{devtools.mcpEval}
## @end deftypefn

function [PROG, ARGS] = sandboxCommand (FOLDERS, PACKAGES)

  ## Input validation
  if (nargin != 2)
    error ("devtools.sandboxCommand: invalid number of input arguments.");
  endif
  if (! iscellstr (FOLDERS))
    error (strcat ("devtools.sandboxCommand: FOLDERS must be a cell array", ...
                   " of character vectors."));
  endif
  if (! iscellstr (PACKAGES))
    error (strcat ("devtools.sandboxCommand: PACKAGES must be a cell array", ...
                   " of character vectors."));
  endif
  folders = cell (1, numel (FOLDERS));
  for i = 1:numel (FOLDERS)
    f = FOLDERS{i};
    if (! (isrow (f) && f(1) == "/"))
      error (strcat ("devtools.sandboxCommand: folder '%s' is not an", ...
                     " absolute path."), f);
    endif
    if (! isfolder (f))
      error ("devtools.sandboxCommand: folder '%s' does not exist.", f);
    endif
    folders{i} = canonicalize_file_name (f);
  endfor

  u = uname ();
  if (! strcmp (u.sysname, "Linux"))
    error ("devtools.sandboxCommand: a sandbox is available on Linux only.");
  endif
  PROG = file_in_path (getenv ("PATH"), "bwrap");
  if (isempty (PROG))
    error (strcat ("devtools.sandboxCommand: 'bwrap' is not on the PATH;", ...
                   " install bubblewrap."));
  endif

  c = __octave_config_info__ ();
  H.bwrap = PROG;
  H.octaveCli = canonicalize_file_name (fullfile (c.bindir, "octave-cli"));
  if (isempty (H.octaveCli))
    error ("devtools.sandboxCommand: 'octave-cli' is not in '%s'.", c.bindir);
  endif

  ## /etc/alternatives is where Debian resolves libGL and BLAS.
  d = {'/usr/lib', '/usr/lib64', '/usr/share', c.libdir, c.datadir, ...
       '/etc/alternatives'};
  H.roDirs = d(cellfun (@isfolder, d));

  ## The dynamic loader is found through /lib64, a link where /usr is merged.
  H.links = struct ("path", {}, "target", {});
  for p = {'/lib', '/lib64'}
    [target, err] = readlink (p{1});
    if (err == 0)
      H.links(end+1) = struct ("path", p{1}, "target", target);
    elseif (isfolder (p{1}))
      H.links(end+1) = struct ("path", p{1}, "target", "");
    endif
  endfor

  f = {H.octaveCli, pkg("local_list"), pkg("global_list")};
  H.roFiles = f(cellfun (@isfile, f));

  ## datatypes reads the time zone name from the link, so it is recreated as
  ## one rather than mounted as a file.
  [target, err] = readlink ("/etc/localtime");
  if (err == 0)
    H.localtime = target;
  else
    H.localtime = "";
    if (isfile ("/etc/localtime"))
      H.roFiles{end+1} = "/etc/localtime";
    endif
  endif

  H.home = canonicalize_file_name (getenv ("HOME"));
  H.history = history_file ();
  H.lang = getenv ("LANG");
  H.evalSeconds = getenv ("DEVTOOLS_EVAL_SECONDS");

  ## Local packages come first, which is the one pkg load takes.
  [localPkgs, globalPkgs] = pkg ("list");
  entries = [localPkgs(:).', globalPkgs(:).'];
  H.installed = struct ("name", {}, "dir", {}, "archprefix", {}, "depends", {});
  for i = 1:numel (entries)
    s = entries{i};
    deps = cellfun (@(e) e.package, s.depends, "UniformOutput", false);
    H.installed(end+1) = struct ("name", s.name, "dir", s.dir, ...
                                 "archprefix", s.archprefix, "depends", {deps});
  endfor
  H.selfDir = fileparts (fileparts (mfilename ("fullpath")));

  [ARGS, errmsg] = devtools.__sandboxArgs__ (H, folders, PACKAGES(:).');
  if (! isempty (errmsg))
    error ("devtools.sandboxCommand: %s", errmsg);
  endif

endfunction

## A real command needs Linux and bwrap.
%!shared canRun
%! canRun = isunix () && ! ismac () ...
%!          && ! isempty (file_in_path (getenv ("PATH"), "bwrap"));

%!test
%! if (canRun)
%!   [P, A] = devtools.sandboxCommand ({}, {});
%!   assert_equal (P, file_in_path (getenv ("PATH"), "bwrap"));
%! endif
%!test
%! if (canRun)
%!   [P, A] = devtools.sandboxCommand ({}, {});
%!   assert_equal (A(end-2:end), {'--no-history', '--no-init-file', '-q'});
%! endif
%!test
%! if (canRun)
%!   [P, A] = devtools.sandboxCommand ({OCTAVE_HOME()}, {});
%!   i = find (strcmp (A, "DEVTOOLS_SANDBOX_FOLDERS"));
%!   assert_equal (A{i+1}, canonicalize_file_name (OCTAVE_HOME ()));
%! endif

%!error <devtools\.sandboxCommand: invalid number of input arguments\.> ...
%! devtools.sandboxCommand ({})
%!error <devtools\.sandboxCommand: FOLDERS must be a cell array of character vectors\.> ...
%! devtools.sandboxCommand ("/tmp", {})
%!error <devtools\.sandboxCommand: PACKAGES must be a cell array of character vectors\.> ...
%! devtools.sandboxCommand ({}, "statistics")
%!error <devtools\.sandboxCommand: folder 'data' is not an absolute path\.> ...
%! devtools.sandboxCommand ({'data'}, {})
%!error <devtools\.sandboxCommand: folder '' is not an absolute path\.> ...
%! devtools.sandboxCommand ({''}, {})
%!error <devtools\.sandboxCommand: folder '/devtools-no-such-folder' does not exist\.> ...
%! devtools.sandboxCommand ({'/devtools-no-such-folder'}, {})
%!error <devtools\.sandboxCommand: 'bwrap' is not on the PATH; install bubblewrap\.> ...
%! p = getenv ("PATH");
%! setenv ("PATH", "");
%! unwind_protect
%!   devtools.sandboxCommand ({}, {});
%! unwind_protect_cleanup
%!   setenv ("PATH", p);
%! end_unwind_protect
