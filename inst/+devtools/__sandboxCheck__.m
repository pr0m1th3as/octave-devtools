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
## @deftypefn {devtools} {@var{FAILED} =} devtools.__sandboxCheck__ (@var{ALLOWED}, @var{ROOTS})
##
## Check from inside that a sandbox is in force.  Internal; not a supported
## entry point.
##
## Returns a cell array naming every check that failed, empty when all pass.
## There must be no @file{/usr/bin} or @file{/bin}, no network interface
## besides the loopback in @file{/proc/net/dev}, and nothing under each folder
## of @var{ROOTS} except @var{ALLOWED}, the paths that were mounted, and the
## folders leading to them.  A folder that cannot be read counts as visible.
##
## The environment marker that a relaunch sets is never taken as proof: this is
## what a server checks before it reports itself sandboxed.
##
## @end deftypefn

function FAILED = __sandboxCheck__ (ALLOWED, ROOTS)

  if (nargin != 2)
    error ("devtools.__sandboxCheck__: invalid number of input arguments.");
  endif

  FAILED = {};

  if (isfolder ("/usr/bin") || isfolder ("/bin"))
    FAILED{end+1} = "/usr/bin is present";
  endif

  try
    txt = fileread ("/proc/net/dev");
  catch
    txt = "";
  end_try_catch
  if (isempty (txt))
    FAILED{end+1} = "/proc/net/dev cannot be read";
  else
    ## Two header lines, then one line per interface named before its colon
    lines = strsplit (strtrim (txt), "\n");
    names = cellfun (@(l) strtrim (strtok (l, ":")), lines(3:end), ...
                     "UniformOutput", false);
    if (! all (strcmp (names, "lo")))
      FAILED{end+1} = "a network interface other than lo is present";
    endif
  endif

  for i = 1:numel (ROOTS)
    if (isfolder (ROOTS{i}))
      extra = walk (ROOTS{i}, ALLOWED);
      for j = 1:numel (extra)
        FAILED{end+1} = sprintf ("'%s' is visible but was not mounted", ...
                                 extra{j});
      endfor
    endif
  endfor

endfunction

## Paths under D that are neither mounted nor on the way to a mounted path.
function extra = walk (D, ALLOWED)
  extra = {};
  [names, err] = readdir (D);
  if (err != 0)
    extra = {D};
    return;
  endif
  names = names(! strcmp (names, ".") & ! strcmp (names, ".."));
  for i = 1:numel (names)
    p = fullfile (D, names{i});
    if (any (cellfun (@(a) isUnder (p, a), ALLOWED)))
      continue;
    elseif (isfolder (p) && any (cellfun (@(a) isUnder (a, p), ALLOWED)))
      extra = [extra, walk(p, ALLOWED)];
    else
      extra{end+1} = p;
    endif
  endfor
endfunction

## True if path P is folder D or lies inside it.
function r = isUnder (P, D)
  if (strcmp (D, "/"))
    r = true;
  else
    r = strcmp (P, D) || strncmp (P, [D, "/"], numel (D) + 1);
  endif
endfunction

%!shared T, msg
%! msg = @(p) sprintf ("'%s' is visible but was not mounted", p);
%! T = tempname ();
%! mkdir (fullfile (T, "a", "b"));
%! mkdir (fullfile (T, "c"));
%! fclose (fopen (fullfile (T, "a", "b", "f.m"), "w"));
%! fclose (fopen (fullfile (T, "a", "x.txt"), "w"));

%!test
%! if (isunix () && ! ismac ())
%!   F = devtools.__sandboxCheck__ ({}, {});
%!   assert_equal (any (strcmp (F, "/usr/bin is present")), true);
%! endif
%!test
%! ## A mounted folder and the folders leading to it are expected.
%! F = devtools.__sandboxCheck__ ({fullfile(T, "a", "b")}, {T});
%! assert_equal (any (strcmp (F, msg (fullfile (T, "a", "b")))), false);
%! assert_equal (any (strcmp (F, msg (fullfile (T, "a")))), false);
%!test
%! ## A folder beside the mounted one is not.
%! F = devtools.__sandboxCheck__ ({fullfile(T, "a", "b")}, {T});
%! assert_equal (any (strcmp (F, msg (fullfile (T, "c")))), true);
%!test
%! ## Nor is a file in a folder on the way.
%! F = devtools.__sandboxCheck__ ({fullfile(T, "a", "b")}, {T});
%! assert_equal (any (strcmp (F, msg (fullfile (T, "a", "x.txt")))), true);
%!test
%! ## Everything mounted leaves nothing visible.
%! F = devtools.__sandboxCheck__ ({fullfile(T, "a"), fullfile(T, "c")}, {T});
%! assert_equal (any (strncmp (F, ["'" T], numel (T) + 1)), false);
%!test
%! F = devtools.__sandboxCheck__ ({}, {fullfile(T, "no-such-root")});
%! assert_equal (any (strncmp (F, ["'" T], numel (T) + 1)), false);
%!test
%! confirm_recursive_rmdir (false, "local");
%! rmdir (T, "s");

%!error <devtools\.__sandboxCheck__: invalid number of input arguments\.> ...
%! devtools.__sandboxCheck__ ({})
