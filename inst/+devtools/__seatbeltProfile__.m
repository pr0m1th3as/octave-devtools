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
## @deftypefn {devtools} {[@var{PROFILE}, @var{ARGS}, @var{ERRMSG}] =} devtools.__seatbeltProfile__ (@var{HOST}, @var{FOLDERS}, @var{PACKAGES})
##
## Assemble the Seatbelt profile and launch of a sandbox on macOS.  Internal;
## not a supported entry point.
##
## The sibling of @code{devtools.__sandboxArgs__}, which does the same for
## @command{bwrap} on Linux.  @var{HOST} is the structure of host facts
## @code{devtools.sandboxCommand} gathers, @var{FOLDERS} a cell array of
## canonical folder paths and @var{PACKAGES} a cell array of package names.
## Nothing here touches the filesystem, which is what lets the assembly be
## tested with made-up facts on any machine.
##
## @var{PROFILE} is the profile text, which the caller writes to
## @code{HOST.profilePath}.  @var{ARGS} is the row cell array of arguments for
## @code{HOST.shell}, ending with @code{"$@@"} so that the caller appends its
## @option{--eval} text as further elements, as it does on Linux.
##
## Darwin has no @command{prlimit}, so the address-space limit is set by the
## shell before it execs, and it is the only reason a shell is involved.
##
## The guarantees are enumerated rather than structural: a Seatbelt profile
## denies rather than hides, so what is not reachable is what is refused, and
## a rule that comes later wins.  Every @code{allow} is therefore emitted after
## the @code{deny} it overrides, since the caller's folders and the installed
## packages usually lie inside the home directory the profile denies.
##
## A refusal is returned as @var{ERRMSG}, the body of an error message, with
## @var{PROFILE} and @var{ARGS} empty, so that the caller raises it under its
## own name.
##
## @end deftypefn

function [PROFILE, ARGS, ERRMSG] = __seatbeltProfile__ (HOST, FOLDERS, ...
                                                        PACKAGES)

  if (nargin != 3)
    error ("devtools.__seatbeltProfile__: invalid number of input arguments.");
  endif

  PROFILE = "";
  ARGS = {};
  ERRMSG = "";

  ## The home directory is what the sandbox hides, and the history file holds
  ## everything typed at a prompt.  A folder inside the sandbox's own writable
  ## root, or inside /dev, would be granted and then overridden, so it is
  ## refused rather than left silently unreadable.
  replaced = {HOST.tmpDir, '/dev'};
  for i = 1:numel (FOLDERS)
    f = FOLDERS{i};
    hit = find (cellfun (@(r) isUnder (f, r), replaced), 1);
    if (! isempty (hit))
      fmt = "folder '%s' lies inside '%s', which the sandbox replaces.";
      ERRMSG = sprintf (fmt, f, replaced{hit});
      return;
    endif
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

  ## The readable set is the requested packages and everything they depend on,
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
  granted = [];
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
    if (! any (granted == idx))
      granted(end+1) = idx;
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

  ## Every folder holding installed packages is denied, so that a package that
  ## was not asked for stays unreadable; the granted ones are allowed back
  ## below, where a later rule wins.
  pkgParents = {};
  for i = 1:numel (HOST.installed)
    pkgParents = [pkgParents, {fileparts(HOST.installed(i).dir), ...
                               fileparts(HOST.installed(i).archprefix)}];
  endfor
  [~, first] = unique (pkgParents, "first");
  pkgParents = pkgParents(sort (first));
  ## One inside the home directory is denied by that already.
  pkgParents = pkgParents(! cellfun (@(p) isUnder (p, HOST.home), pkgParents));

  grantedDirs = {};
  for i = 1:numel (granted)
    grantedDirs = [grantedDirs, {HOST.installed(granted(i)).dir, ...
                                 HOST.installed(granted(i)).archprefix}];
  endfor
  [~, first] = unique (grantedDirs, "first");
  grantedDirs = grantedDirs(sort (first));

  L = {"(version 1)", "(allow default)", "", ...
       ";; No network of any kind.", "(deny network*)", "", ...
       ";; No program but the interpreter.  On Linux this comes of leaving", ...
       ";; /usr/bin unmounted; here it has to be said.", ...
       "(deny process-exec*)", ...
       sprintf("(allow process-exec (subpath %s))", sbPath(HOST.prefix)), ...
       "", ...
       ";; Nothing on disk is writable but the sandbox's own folder.", ...
       "(deny file-write*)", ...
       sprintf("(allow file-write* (subpath %s))", sbPath(HOST.tmpDir)), ...
       "(allow file-write* (literal \"/dev/null\"))", ""};

  L = [L, {";; Home is unreadable, and so is every folder holding installed"}];
  L = [L, {";; packages, so that one that was not asked for stays hidden."}];
  L = [L, {sprintf("(deny file-read* (subpath %s))", sbPath(HOST.home))}];
  for i = 1:numel (pkgParents)
    L = [L, {sprintf("(deny file-read* (subpath %s))", ...
             sbPath(pkgParents{i}))}];
  endfor

  ## Everything the caller named comes last, because a later rule wins and
  ## these usually lie inside the home directory denied above.
  L = [L, {"", ";; What was asked for, last, because a later rule wins."}];
  allowed = [grantedDirs, FOLDERS(:)'];
  if (! isempty (HOST.selfDir) && isempty (selfIdx))
    allowed = [allowed, {HOST.selfDir}];
  endif
  for i = 1:numel (allowed)
    L = [L, {sprintf("(allow file-read* (subpath %s))", ...
             sbPath(allowed{i}))}];
  endfor
  PROFILE = strjoin (L, "\n");
  PROFILE = [PROFILE, "\n"];

  ## The limit is set once, on the whole sandbox, and every forked call
  ## inherits it.  The caller's size already holds what the BLAS reserved for
  ## this machine's threads, so the budget is added to it.  Darwin refuses any
  ## absolute cap below that size, which is why nothing fixed is used here.
  limit = HOST.vmSize + gigabytes (HOST.memoryBudget);
  ## TMPDIR is pointed at the one writable folder before anything runs.  On
  ## macOS it is a per-user directory under /var/folders that the profile
  ## denies, and OpenMP opens a file there as the interpreter starts: without
  ## this the server dies with "Can't open TEMP" before it speaks.  On Linux
  ## the case cannot arise, bwrap clearing the environment and /tmp being the
  ## writable mount itself.
  cmd = sprintf (["TMPDIR=%s; export TMPDIR; ulimit -v %d;", ...
                  " exec %s -f %s %s%s \"$@\""], ...
                 shq (HOST.tmpDir), floor (limit / 1024), ...
                 shq (HOST.sandboxExec), shq (HOST.profilePath), ...
                 shq (HOST.octaveCli), " --no-history --no-init-file -q");
  ARGS = {'-c', cmd, 'devtools'};

endfunction

## A path as a Seatbelt string literal.  The profile language takes a
## double-quoted string in which a backslash and a quote are escaped.
function s = sbPath (P)
  s = ['"', strrep(strrep (P, '\', '\\'), '"', '\"'), '"'];
endfunction

## A path as one shell word.  Single quotes take everything but a single
## quote, which is closed, escaped and reopened.
function s = shq (P)
  s = ["'", strrep(P, "'", "'\\''"), "'"];
endfunction

## The budget in bytes.  A value outside (0, 1024] is ignored, as
## DEVTOOLS_EVAL_SECONDS ignores one, and 2 GB is the default.
function b = gigabytes (S)
  g = 2;
  if (! isempty (S))
    v = str2double (S);
    if (! isnan (v) && v > 0 && v <= 1024)
      g = v;
    endif
  endif
  b = round (g * 1024^3);
endfunction

## True when P is D or lies inside it.
function r = isUnder (P, D)
  if (isempty (D))
    r = false;
  elseif (strcmp (D, "/"))
    r = true;
  else
    r = strcmp (P, D) || strncmp (P, [D, "/"], numel (D) + 1);
  endif
endfunction

%!shared H
%! H.sandboxExec = "/usr/bin/sandbox-exec";
%! H.shell = "/bin/sh";
%! H.profilePath = "/private/tmp/devtools-1/profile.sb";
%! H.tmpDir = "/private/tmp/devtools-1";
%! H.octaveCli = "/opt/homebrew/bin/octave-cli";
%! H.prefix = "/opt/homebrew";
%! H.vmSize = 3 * 1024^3;
%! H.memoryBudget = "";
%! H.home = "/Users/u";
%! H.history = "/Users/u/.local/share/octave/history";
%! H.selfDir = "/Users/u/src/octave-devtools/inst";
%! H.installed = struct ( ...
%!   "name", {"statistics", "datatypes", "io", "nan"}, ...
%!   "dir", {"/Users/u/pk/statistics-1", "/Users/u/pk/datatypes-1", ...
%!           "/Users/u/pk/io-2", "/opt/homebrew/share/octave/packages/nan-3"}, ...
%!   "archprefix", {"/Users/u/pk/statistics-1", "/Users/u/pk/datatypes-1", ...
%!                  "/Users/u/pk/io-2", ...
%!                  "/opt/homebrew/lib/octave/packages/nan-3"}, ...
%!   "depends", {{'octave', 'datatypes'}, {'octave'}, {'octave'}, {'octave'}});

%!function r = hasLine (P, L)
%!  r = any (strcmp (strsplit (P, "\n"), L));
%!endfunction

%!function i = lineOf (P, L)
%!  i = find (strcmp (strsplit (P, "\n"), L), 1);
%!endfunction

%!test
%! ## The profile opens by allowing, since Seatbelt denies rather than hides.
%! P = devtools.__seatbeltProfile__ (H, {}, {});
%! L = strsplit (P, "\n");
%! assert_equal (L{1}, "(version 1)");
%! assert_equal (L{2}, "(allow default)");

%!test
%! ## Every guarantee the marker names is a rule in the text.
%! P = devtools.__seatbeltProfile__ (H, {}, {});
%! assert (hasLine (P, "(deny network*)"));
%! assert (hasLine (P, "(deny process-exec*)"));
%! assert (hasLine (P, "(deny file-write*)"));
%! assert (hasLine (P, '(deny file-read* (subpath "/Users/u"))'));

%!test
%! ## Only the interpreter's own prefix may run a program.
%! P = devtools.__seatbeltProfile__ (H, {}, {});
%! assert (hasLine (P, '(allow process-exec (subpath "/opt/homebrew"))'));

%!test
%! ## The sandbox's own folder is the only writable place on disk.
%! P = devtools.__seatbeltProfile__ (H, {}, {});
%! assert (hasLine (P, ...
%!         '(allow file-write* (subpath "/private/tmp/devtools-1"))'));

%!test
%! ## A named folder inside home is allowed, and after the deny, or it would
%! ## not be readable at all.
%! P = devtools.__seatbeltProfile__ (H, {'/Users/u/work'}, {});
%! d = lineOf (P, '(deny file-read* (subpath "/Users/u"))');
%! a = lineOf (P, '(allow file-read* (subpath "/Users/u/work"))');
%! assert (! isempty (a));
%! assert (a > d);

%!test
%! ## A requested package brings its dependencies, and both come after the
%! ## deny of the folder that holds them.
%! P = devtools.__seatbeltProfile__ (H, {}, {'statistics'});
%! assert (hasLine (P, '(allow file-read* (subpath "/Users/u/pk/statistics-1"))'));
%! assert (hasLine (P, '(allow file-read* (subpath "/Users/u/pk/datatypes-1"))'));

%!test
%! ## One that was not asked for stays unreadable.
%! P = devtools.__seatbeltProfile__ (H, {}, {'statistics'});
%! assert (! hasLine (P, '(allow file-read* (subpath "/Users/u/pk/io-2"))'));

%!test
%! ## A package folder outside home is denied on its own, home covering only
%! ## the ones inside it.
%! P = devtools.__seatbeltProfile__ (H, {}, {});
%! assert (hasLine (P, ...
%!   '(deny file-read* (subpath "/opt/homebrew/share/octave/packages"))'));

%!test
%! ## Asking for it allows it back, after that deny.
%! P = devtools.__seatbeltProfile__ (H, {}, {'nan'});
%! d = lineOf (P, ...
%!   '(deny file-read* (subpath "/opt/homebrew/share/octave/packages"))');
%! a = lineOf (P, ...
%!   '(allow file-read* (subpath "/opt/homebrew/share/octave/packages/nan-3"))');
%! assert (a > d);

%!test
%! ## Every allow comes after every deny, which is what makes the profile
%! ## mean what it says.
%! P = devtools.__seatbeltProfile__ (H, {'/Users/u/work'}, {'statistics'});
%! L = strsplit (P, "\n");
%! isDeny = ! cellfun (@isempty, regexp (L, '^\(deny file-read'));
%! isAllow = ! cellfun (@isempty, regexp (L, '^\(allow file-read'));
%! assert (max (find (isDeny)) < min (find (isAllow)));

%!test
%! ## TMPDIR is pointed at the writable folder, or OpenMP kills the server as
%! ## it starts.
%! [~, A] = devtools.__seatbeltProfile__ (H, {}, {});
%! assert (! isempty (strfind (A{2}, ...
%!   "TMPDIR='/private/tmp/devtools-1'; export TMPDIR;")));

%!test
%! ## The launch is a shell, Darwin having no prlimit, and the cap is the
%! ## caller's own size plus the budget, in kilobytes.
%! [~, A] = devtools.__seatbeltProfile__ (H, {}, {});
%! assert_equal (A{1}, '-c');
%! assert (! isempty (strfind (A{2}, sprintf ("ulimit -v %d;", 5 * 1024^2))));

%!test
%! H1 = H;
%! H1.memoryBudget = "4";
%! [~, A] = devtools.__seatbeltProfile__ (H1, {}, {});
%! assert (! isempty (strfind (A{2}, sprintf ("ulimit -v %d;", 7 * 1024^2))));

%!test
%! ## A budget outside the accepted range is ignored, as elsewhere.
%! H1 = H;
%! H1.memoryBudget = "0";
%! [~, A] = devtools.__seatbeltProfile__ (H1, {}, {});
%! assert (! isempty (strfind (A{2}, sprintf ("ulimit -v %d;", 5 * 1024^2))));

%!test
%! ## The command ends with "$@" so that the caller appends its --eval text
%! ## as further arguments, as it does on Linux.
%! [~, A] = devtools.__seatbeltProfile__ (H, {}, {});
%! assert (! isempty (strfind (A{2}, ...
%!   '--no-history --no-init-file -q "$@"')));
%! assert_equal (A{3}, 'devtools');

%!test
%! ## A path holding a space or a quote survives as one shell word.
%! H1 = H;
%! H1.octaveCli = "/Users/u/Applications/Octave 11/bin/octave-cli";
%! H1.profilePath = "/private/tmp/it's/profile.sb";
%! [~, A] = devtools.__seatbeltProfile__ (H1, {}, {});
%! assert (! isempty (strfind (A{2}, ...
%!   "'/Users/u/Applications/Octave 11/bin/octave-cli'")));
%! assert (! isempty (strfind (A{2}, "'/private/tmp/it'\\''s/profile.sb'")));

%!test
%! ## And in the profile it survives as one Seatbelt string.
%! H1 = H;
%! H1.home = '/Users/say "hi"';
%! P = devtools.__seatbeltProfile__ (H1, {}, {});
%! assert (hasLine (P, '(deny file-read* (subpath "/Users/say \"hi\""))'));

%!test
%! ## The running copy is readable even when it is not an installed package.
%! P = devtools.__seatbeltProfile__ (H, {}, {});
%! assert (hasLine (P, ...
%!   '(allow file-read* (subpath "/Users/u/src/octave-devtools/inst"))'));

%!test
%! ## The home directory itself is not a folder a caller may name.
%! [P, A, E] = devtools.__seatbeltProfile__ (H, {'/Users/u'}, {});
%! assert_equal (E, "folder '/Users/u' is the home directory.");
%! assert (isempty (P));
%! assert (isempty (A));

%!test
%! ## Nor one holding the history file.
%! [~, ~, E] = devtools.__seatbeltProfile__ (H, {'/Users/u/.local'}, {});
%! assert_equal (E, ["folder '/Users/u/.local' contains Octave's history", ...
%!                   " file '/Users/u/.local/share/octave/history'."]);

%!test
%! ## Nor one the sandbox replaces with its own.
%! [~, ~, E] = devtools.__seatbeltProfile__ (H, ...
%!                                           {'/private/tmp/devtools-1/x'}, {});
%! assert_equal (E, ["folder '/private/tmp/devtools-1/x' lies inside", ...
%!                   " '/private/tmp/devtools-1', which the sandbox", ...
%!                   " replaces."]);

%!test
%! ## A package that is not installed is refused before the sandbox runs,
%! ## since inside it nothing reports the absence.
%! [~, ~, E] = devtools.__seatbeltProfile__ (H, {}, {'nosuch'});
%! assert_equal (E, "package 'nosuch' is not installed.");

%!test
%! ## And so is a dependency that is missing, naming what needed it.
%! H1 = H;
%! H1.installed(2) = [];
%! [~, ~, E] = devtools.__seatbeltProfile__ (H1, {}, {'statistics'});
%! assert_equal (E, ["package 'statistics' needs 'datatypes', which is", ...
%!                   " not installed."]);

%!error <invalid number of input arguments>
%! devtools.__seatbeltProfile__ (struct ());
%!error <invalid number of input arguments>
%! devtools.__seatbeltProfile__ (struct (), {});
