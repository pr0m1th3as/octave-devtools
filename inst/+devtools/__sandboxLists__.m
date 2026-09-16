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
## @deftypefn {devtools} {} devtools.__sandboxLists__ (@var{LOCAL}, @var{GLOBAL}, @var{DIR})
##
## Point @code{pkg} at package lists naming only the packages that are
## present.  Internal; not a supported entry point.
##
## @var{LOCAL} and @var{GLOBAL} are the original local and global package list
## files.  The packages they name whose install folder exists are written to
## @file{local_packages} and @file{global_packages} in the folder @var{DIR},
## which is created, and @code{pkg} is pointed at those two files.  The global
## entries are read through @code{pkg ("list")}, so their relative paths are
## expanded before they are checked.
##
## Inside a sandbox only the mounted packages have an install folder, so
## @code{pkg load} of any other says it is not installed.  A sandboxed server
## rebuilds the lists before every call, into a new @var{DIR}, because
## @file{/tmp} is writable and a call could have changed them.
##
## @end deftypefn

function __sandboxLists__ (LOCAL, GLOBAL, DIR)

  if (nargin != 3)
    error ("devtools.__sandboxLists__: invalid number of input arguments.");
  endif

  pkg ("local_list", LOCAL);
  pkg ("global_list", GLOBAL);
  [localPkgs, globalPkgs] = pkg ("list");
  local_packages = localPkgs(cellfun (@(s) isfolder (s.dir), localPkgs));
  global_packages = globalPkgs(cellfun (@(s) isfolder (s.dir), globalPkgs));

  [ok, msg] = mkdir (DIR);
  if (! ok)
    error ("devtools.__sandboxLists__: cannot create '%s': %s.", DIR, msg);
  endif
  save ("-text", fullfile (DIR, "local_packages"), "local_packages");
  save ("-text", fullfile (DIR, "global_packages"), "global_packages");
  pkg ("local_list", fullfile (DIR, "local_packages"));
  pkg ("global_list", fullfile (DIR, "global_packages"));

endfunction

%!test
%! T = tempname ();
%! mkdir (fullfile (T, "pkgA"));
%! ## macOS hands out /var/folders, a link to /private/var/folders, and pkg
%! ## reports the canonical path.
%! T = canonicalize_file_name (T);
%! mk = @(n, d) struct ("name", n, "version", "1.0.0", "dir", d, ...
%!                      "archprefix", d, "depends", {{}}, "autoload", 0);
%! local_packages = {mk("a", fullfile (T, "pkgA")), ...
%!                   mk("b", fullfile (T, "missing"))};
%! save ("-text", fullfile (T, "local"), "local_packages");
%! oldLocal = pkg ("local_list");
%! oldGlobal = pkg ("global_list");
%! unwind_protect
%!   devtools.__sandboxLists__ (fullfile (T, "local"), fullfile (T, "none"), ...
%!                              fullfile (T, "out"));
%!   L = load (fullfile (T, "out", "local_packages"));
%!   assert_equal (cellfun (@(s) s.name, L.local_packages, ...
%!                          "UniformOutput", false), {'a'});
%!   assert_equal (pkg ("local_list"), fullfile (T, "out", "local_packages"));
%! unwind_protect_cleanup
%!   pkg ("local_list", oldLocal);
%!   pkg ("global_list", oldGlobal);
%!   confirm_recursive_rmdir (false, "local");
%!   rmdir (T, "s");
%! end_unwind_protect

%!error <devtools\.__sandboxLists__: invalid number of input arguments\.> ...
%! devtools.__sandboxLists__ ("a", "b")
