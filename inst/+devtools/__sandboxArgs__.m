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
## @deftypefn {devtools} {[@var{ARGS}, @var{ERRMSG}] =} devtools.__sandboxArgs__ (@var{HOST}, @var{FOLDERS}, @var{PACKAGES})
##
## Assemble the @command{bwrap} arguments of a sandbox.  Internal; not a
## supported entry point.
##
## @var{HOST} is the structure of host facts @code{devtools.sandboxCommand}
## gathers, @var{FOLDERS} a cell array of canonical folder paths and
## @var{PACKAGES} a cell array of package names.  Nothing here touches the
## filesystem, which is what lets the assembly be tested with made-up facts on
## any machine.  @var{ARGS} is a row cell array ending with the
## @file{octave-cli} command, to which the caller appends its @option{--eval}
## text.
##
## A refusal is returned as @var{ERRMSG}, the body of an error message, with
## @var{ARGS} empty, so that the caller raises it under its own name.
##
## @end deftypefn

function [ARGS, ERRMSG] = __sandboxArgs__ (HOST, FOLDERS, PACKAGES)

  if (nargin != 3)
    error ("devtools.__sandboxArgs__: invalid number of input arguments.");
  endif

  ARGS = {};
  ERRMSG = "";

  ## The home directory is what the sandbox hides, and the history file holds
  ## everything typed at a prompt.
  for i = 1:numel (FOLDERS)
    f = FOLDERS{i};
    if (strcmp (f, HOST.home))
      ERRMSG = sprintf ("folder '%s' is the home directory.", f);
      return;
    endif
    if (! isempty (HOST.history) && isUnder (HOST.history, f))
      ERRMSG = sprintf ("folder '%s' contains Octave's history file '%s'.", ...
                        f, HOST.history);
      return;
    endif
  endfor

  ## Requested names keep their order, which is the load order.
  [~, first] = unique (PACKAGES, "first");
  PACKAGES = PACKAGES(sort (first));

  ## The mounted set is the requested packages and everything they depend on,
  ## resolved here because inside the sandbox neither a missing package nor a
  ## missing dependency is reported.  A running copy that is installed joins it.
  names = {HOST.installed.name};
  queue = PACKAGES;
  parent = repmat ({""}, size (PACKAGES));
  selfIdx = find (strcmp ({HOST.installed.dir}, HOST.selfDir), 1);
  if (! isempty (selfIdx) && ! any (strcmp (queue, names{selfIdx})))
    queue{end+1} = names{selfIdx};
    parent{end+1} = "";
  endif
  mounted = [];
  k = 1;
  while (k <= numel (queue))
    idx = find (strcmp (names, queue{k}), 1);
    if (isempty (idx))
      if (isempty (parent{k}))
        ERRMSG = sprintf ("package '%s' is not installed.", queue{k});
      else
        fmt = "package '%s' needs '%s', which is not installed.";
        ERRMSG = sprintf (fmt, parent{k}, queue{k});
      endif
      return;
    endif
    if (! any (mounted == idx))
      mounted(end+1) = idx;
      deps = HOST.installed(idx).depends;
      for j = 1:numel (deps)
        if (! strcmpi (deps{j}, "octave") && ! any (strcmp (queue, deps{j})))
          queue{end+1} = deps{j};
          parent{end+1} = queue{k};
        endif
      endfor
    endif
    k++;
  endwhile

  ## A folder inside another mounted folder is already visible.
  roDirs = {};
  for i = 1:numel (HOST.roDirs)
    d = HOST.roDirs{i};
    others = HOST.roDirs(! strcmp (HOST.roDirs, d));
    if (! any (strcmp (roDirs, d))
        && ! any (cellfun (@(e) isUnder (d, e), others)))
      roDirs{end+1} = d;
    endif
  endfor

  ## Every folder holding installed packages inside a mounted folder is covered,
  ## so that only the mounted set shows through.
  parents = {};
  for i = 1:numel (HOST.installed)
    parents = [parents, {fileparts(HOST.installed(i).dir), ...
                         fileparts(HOST.installed(i).archprefix)}];
  endfor
  [~, first] = unique (parents, "first");
  parents = parents(sort (first));
  masks = {};
  for i = 1:numel (parents)
    p = parents{i};
    if (any (cellfun (@(e) isUnder (p, e), roDirs)))
      masks{end+1} = p;
    endif
  endfor
  nested = false (size (masks));
  for i = 1:numel (masks)
    others = masks(! strcmp (masks, masks{i}));
    nested(i) = any (cellfun (@(e) isUnder (masks{i}, e), others));
  endfor
  masks = masks(! nested);

  A = {'--unshare-all', '--die-with-parent', '--new-session', '--clearenv', ...
       '--setenv', 'HOME', HOST.home};
  if (! isempty (HOST.lang))
    A = [A, {'--setenv', 'LANG', HOST.lang}];
  endif
  A = [A, {'--setenv', 'DEVTOOLS_SANDBOX', '1', ...
           '--setenv', 'DEVTOOLS_SANDBOX_FOLDERS', ...
           strjoin(FOLDERS, pathsep()), ...
           '--setenv', 'DEVTOOLS_SANDBOX_PACKAGES', strjoin(PACKAGES, ',')}];
  if (isempty (selfIdx))
    A = [A, {'--setenv', 'DEVTOOLS_SANDBOX_SELF', HOST.selfDir}];
  endif
  if (! isempty (HOST.evalSeconds))
    A = [A, {'--setenv', 'DEVTOOLS_EVAL_SECONDS', HOST.evalSeconds}];
  endif

  for i = 1:numel (roDirs)
    A = [A, {'--ro-bind', roDirs{i}, roDirs{i}}];
  endfor
  for i = 1:numel (HOST.links)
    L = HOST.links(i);
    if (isempty (L.target))
      A = [A, {'--ro-bind', L.path, L.path}];
    else
      A = [A, {'--symlink', L.target, L.path}];
    endif
  endfor
  for i = 1:numel (HOST.roFiles)
    A = [A, {'--ro-bind', HOST.roFiles{i}, HOST.roFiles{i}}];
  endfor
  if (! isempty (HOST.localtime))
    A = [A, {'--symlink', HOST.localtime, '/etc/localtime'}];
  endif

  ## A cover is remounted read-only once the packages are back in it, since
  ## remounting the root does not reach it.
  for i = 1:numel (masks)
    A = [A, {'--tmpfs', masks{i}}];
  endfor
  for i = mounted
    p = {HOST.installed(i).dir, HOST.installed(i).archprefix};
    p = unique (p(! cellfun (@isempty, p)), "stable");
    for j = 1:numel (p)
      if (any (cellfun (@(m) isUnder (p{j}, m), masks)))
        A = [A, {'--dir', p{j}}];
      endif
      A = [A, {'--ro-bind', p{j}, p{j}}];
    endfor
  endfor
  for i = 1:numel (masks)
    A = [A, {'--remount-ro', masks{i}}];
  endfor

  for i = 1:numel (FOLDERS)
    A = [A, {'--ro-bind', FOLDERS{i}, FOLDERS{i}}];
  endfor
  if (isempty (selfIdx))
    A = [A, {'--ro-bind', HOST.selfDir, HOST.selfDir}];
  endif

  ## The root is built in memory and writable until remounted, last, so that
  ## the in-memory /tmp is the only place a call can write.
  ARGS = [A, {'--proc', '/proc', '--dev', '/dev', '--tmpfs', '/tmp', ...
              '--dir', '/tmp/work', '--chdir', '/tmp/work', ...
              '--remount-ro', '/', ...
              HOST.octaveCli, '--no-history', '--no-init-file', '-q'}];

endfunction

## True if path P is folder D or lies inside it.
function r = isUnder (P, D)
  if (strcmp (D, "/"))
    r = true;
  else
    r = strcmp (P, D) || strncmp (P, [D, "/"], numel (D) + 1);
  endif
endfunction

%!shared H
%! H.bwrap = "/usr/bin/bwrap";
%! H.octaveCli = "/usr/local/bin/octave-cli-11.3.0";
%! H.roDirs = {'/usr/lib', '/usr/share', '/usr/local/lib', '/usr/lib/octave'};
%! H.roFiles = {'/usr/local/bin/octave-cli-11.3.0', ...
%!              '/home/u/.config/octave/list'};
%! H.links = struct ("path", {"/lib", "/lib64"}, "target", {"usr/lib", ""});
%! H.localtime = "../usr/share/zoneinfo/Europe/Athens";
%! H.home = "/home/u";
%! H.history = "/home/u/.local/share/octave/history";
%! H.lang = "C.UTF-8";
%! H.evalSeconds = "";
%! H.installed = struct ( ...
%!   "name", {"statistics", "datatypes", "io", "nan", "devtools", "arch"}, ...
%!   "dir", {"/home/u/pk/statistics-1", "/home/u/pk/datatypes-1", ...
%!           "/home/u/pk/io-2", "/usr/share/octave/packages/nan-3", ...
%!           "/home/u/pk/devtools-0", "/home/u/pk/arch-1"}, ...
%!   "archprefix", {"/home/u/pk/statistics-1", "/home/u/pk/datatypes-1", ...
%!                  "/home/u/pk/io-2", "/usr/lib/octave/packages/nan-3", ...
%!                  "/home/u/pk/devtools-0", "/home/u/ar/arch-1"}, ...
%!   "depends", {{'octave', 'datatypes'}, {'octave'}, {'octave'}, ...
%!               {'octave'}, {'octave'}, {'octave'}});
%! H.selfDir = "/home/u/src/octave-devtools/inst";

%!function r = hasSeq (A, S)
%!  r = false;
%!  for i = 1:(numel (A) - numel (S) + 1)
%!    if (isequal (A(i:i+numel (S)-1), S))
%!      r = true;
%!      return;
%!    endif
%!  endfor
%!endfunction

%!function r = envOf (A, name)
%!  i = find (strcmp (A, "--setenv") & [strcmp(A(2:end), name), false], 1);
%!  if (isempty (i))
%!    r = [];
%!  else
%!    r = A{i+2};
%!  endif
%!endfunction

%!test
%! A = devtools.__sandboxArgs__ (H, {}, {});
%! assert_equal (A(1:4), {'--unshare-all', '--die-with-parent', ...
%!                        '--new-session', '--clearenv'});
%!test
%! A = devtools.__sandboxArgs__ (H, {}, {});
%! assert_equal (A(end-3:end), {'/usr/local/bin/octave-cli-11.3.0', ...
%!                              '--no-history', '--no-init-file', '-q'});
%!test
%! ## The root is remounted read-only after everything written into it.
%! A = devtools.__sandboxArgs__ (H, {}, {});
%! S = {'--proc', '/proc', '--dev', '/dev', '--tmpfs', '/tmp', ...
%!      '--dir', '/tmp/work', '--chdir', '/tmp/work', '--remount-ro', '/'};
%! assert_equal (A(end-15:end-4), S);
%!test
%! A = devtools.__sandboxArgs__ (H, {}, {});
%! assert_equal (envOf (A, "HOME"), "/home/u");
%! assert_equal (envOf (A, "LANG"), "C.UTF-8");
%! assert_equal (envOf (A, "DEVTOOLS_SANDBOX"), "1");
%!test
%! A = devtools.__sandboxArgs__ (H, {'/data/a', '/data/b'}, {});
%! assert_equal (envOf (A, "DEVTOOLS_SANDBOX_FOLDERS"), "/data/a:/data/b");
%!test
%! A = devtools.__sandboxArgs__ (H, {'/data/a'}, {});
%! assert_equal (hasSeq (A, {'--ro-bind', '/data/a', '/data/a'}), true);
%!test
%! ## Requested names keep their order and lose their repeats.
%! A = devtools.__sandboxArgs__ (H, {}, {'io', 'statistics', 'io'});
%! assert_equal (envOf (A, "DEVTOOLS_SANDBOX_PACKAGES"), "io,statistics");
%!test
%! H1 = H;
%! H1.lang = "";
%! A = devtools.__sandboxArgs__ (H1, {}, {});
%! assert_equal (envOf (A, "LANG"), []);
%!test
%! A = devtools.__sandboxArgs__ (H, {}, {});
%! assert_equal (envOf (A, "DEVTOOLS_EVAL_SECONDS"), []);
%!test
%! H1 = H;
%! H1.evalSeconds = "60";
%! A = devtools.__sandboxArgs__ (H1, {}, {});
%! assert_equal (envOf (A, "DEVTOOLS_EVAL_SECONDS"), "60");
%!test
%! ## A folder inside another mounted folder is not mounted again.
%! A = devtools.__sandboxArgs__ (H, {}, {});
%! assert_equal (hasSeq (A, {'--ro-bind', '/usr/lib', '/usr/lib'}), true);
%! assert_equal (any (strcmp (A, "/usr/lib/octave")), false);
%!test
%! A = devtools.__sandboxArgs__ (H, {}, {});
%! assert_equal (hasSeq (A, {'--symlink', 'usr/lib', '/lib'}), true);
%!test
%! A = devtools.__sandboxArgs__ (H, {}, {});
%! assert_equal (hasSeq (A, {'--ro-bind', '/lib64', '/lib64'}), true);
%!test
%! A = devtools.__sandboxArgs__ (H, {}, {});
%! assert_equal (hasSeq (A, {'--ro-bind', '/home/u/.config/octave/list', ...
%!                           '/home/u/.config/octave/list'}), true);
%!test
%! A = devtools.__sandboxArgs__ (H, {}, {});
%! assert_equal (hasSeq (A, {'--symlink', ...
%!                           '../usr/share/zoneinfo/Europe/Athens', ...
%!                           '/etc/localtime'}), true);
%!test
%! H1 = H;
%! H1.localtime = "";
%! A = devtools.__sandboxArgs__ (H1, {}, {});
%! assert_equal (any (strcmp (A, "/etc/localtime")), false);
%!test
%! ## A dependency is mounted with the package that needs it, nothing else.
%! A = devtools.__sandboxArgs__ (H, {}, {'statistics'});
%! assert_equal (hasSeq (A, {'--ro-bind', '/home/u/pk/datatypes-1', ...
%!                           '/home/u/pk/datatypes-1'}), true);
%! assert_equal (any (strcmp (A, "/home/u/pk/io-2")), false);
%!test
%! A = devtools.__sandboxArgs__ (H, {}, {'statistics'});
%! assert_equal (envOf (A, "DEVTOOLS_SANDBOX_PACKAGES"), "statistics");
%!test
%! ## An architecture folder apart from the install folder is mounted too.
%! A = devtools.__sandboxArgs__ (H, {}, {'arch'});
%! assert_equal (hasSeq (A, {'--ro-bind', '/home/u/ar/arch-1', ...
%!                           '/home/u/ar/arch-1'}), true);
%!test
%! ## Packages inside a mounted folder are covered, the requested one put back.
%! A = devtools.__sandboxArgs__ (H, {}, {'nan'});
%! assert_equal (hasSeq (A, {'--tmpfs', '/usr/share/octave/packages'}), true);
%! n = "/usr/share/octave/packages/nan-3";
%! assert_equal (hasSeq (A, {'--dir', n, '--ro-bind', n, n}), true);
%!test
%! A = devtools.__sandboxArgs__ (H, {}, {'nan'});
%! S = {'--remount-ro', '/usr/share/octave/packages'};
%! assert_equal (hasSeq (A, S), true);
%! S = {'--remount-ro', '/usr/lib/octave/packages'};
%! assert_equal (hasSeq (A, S), true);
%!test
%! ## The cover goes on before the package is put back into it.
%! A = devtools.__sandboxArgs__ (H, {}, {'nan'});
%! m = [strcmp(A(2:end), "/usr/share/octave/packages"), false];
%! t = find (strcmp (A, "--tmpfs") & m);
%! b = find (strcmp (A, "/usr/share/octave/packages/nan-3"), 1);
%! r = find (strcmp (A, "--remount-ro") & m);
%! assert_equal (t < b && b < r, true);
%!test
%! ## Packages outside every mounted folder need no cover.
%! A = devtools.__sandboxArgs__ (H, {}, {'io'});
%! assert_equal (any (strcmp (A, "/home/u/pk")), false);
%!test
%! ## A working tree is mounted and named for the relaunched server.
%! A = devtools.__sandboxArgs__ (H, {}, {});
%! assert_equal (envOf (A, "DEVTOOLS_SANDBOX_SELF"), H.selfDir);
%! assert_equal (hasSeq (A, {'--ro-bind', H.selfDir, H.selfDir}), true);
%!test
%! ## An installed copy is mounted as a package.
%! H1 = H;
%! H1.selfDir = "/home/u/pk/devtools-0";
%! A = devtools.__sandboxArgs__ (H1, {}, {});
%! assert_equal (envOf (A, "DEVTOOLS_SANDBOX_SELF"), []);
%! assert_equal (hasSeq (A, {'--ro-bind', '/home/u/pk/devtools-0', ...
%!                           '/home/u/pk/devtools-0'}), true);
%!test
%! [A, E] = devtools.__sandboxArgs__ (H, {}, {'tablicious'});
%! assert_equal (A, {});
%! assert_equal (E, "package 'tablicious' is not installed.");
%!test
%! H1 = H;
%! H1.installed(2) = [];
%! [A, E] = devtools.__sandboxArgs__ (H1, {}, {'statistics'});
%! assert_equal (E, ["package 'statistics' needs 'datatypes',", ...
%!                   " which is not installed."]);
%!test
%! [A, E] = devtools.__sandboxArgs__ (H, {'/data/a', '/home/u'}, {});
%! assert_equal (A, {});
%! assert_equal (E, "folder '/home/u' is the home directory.");
%!test
%! [A, E] = devtools.__sandboxArgs__ (H, {'/home/u/.local'}, {});
%! assert_equal (E, ["folder '/home/u/.local' contains Octave's history", ...
%!                   " file '/home/u/.local/share/octave/history'."]);
%!test
%! [A, E] = devtools.__sandboxArgs__ (H, {'/'}, {});
%! assert_equal (E, ["folder '/' contains Octave's history", ...
%!                   " file '/home/u/.local/share/octave/history'."]);
%!test
%! [A, E] = devtools.__sandboxArgs__ (H, {'/home/u/.localx'}, {});
%! assert_equal (E, "");

%!error <devtools\.__sandboxArgs__: invalid number of input arguments\.> ...
%! devtools.__sandboxArgs__ (struct (), {})
