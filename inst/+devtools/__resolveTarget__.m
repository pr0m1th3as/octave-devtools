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
## @deftypefn {devtools} {[@var{ROOT}, @var{FILES}] =} devtools.__resolveTarget__ (@var{TARGET})
##
## Read a check's target.  Internal; not a supported entry point.
##
## @var{TARGET} is one file, a folder, or the name of an installed package,
## which is looked up with @code{pkg ("list")}.  @var{ROOT} is the folder the
## findings are reported relative to, the file's own folder where one file was
## named, and @var{FILES} the cell array of @file{.m} files to read.
##
## Every @file{.m} file under the target is returned, a @file{private} or
## @file{demos} folder included: which of them a check cares about is the
## check's own business.  Documentation obligations stop at a private helper
## and dialect rules do not.
##
## @end deftypefn

function [ROOT, FILES] = __resolveTarget__ (TARGET)

  if (nargin != 1)
    error ("devtools.__resolveTarget__: invalid number of input arguments.");
  endif
  if (! (ischar (TARGET) && isrow (TARGET)))
    error ("devtools.__resolveTarget__: TARGET must be a character vector.");
  endif

  if (isfile (TARGET))
    [ROOT, ~, ext] = fileparts (TARGET);
    if (! strcmp (ext, ".m"))
      error ("devtools.__resolveTarget__: '%s' is not an m-file.", TARGET);
    endif
    if (isempty (ROOT))
      ROOT = ".";
    endif
    FILES = {TARGET};
    return;
  endif

  if (isfolder (TARGET))
    ROOT = TARGET;
  else
    ROOT = '';
    installed = pkg ("list");
    for ii = 1:numel (installed)
      if (strcmp (installed{ii}.name, TARGET))
        ROOT = installed{ii}.dir;
        break;
      endif
    endfor
    if (isempty (ROOT))
      error (strcat ("devtools.__resolveTarget__: TARGET is not a file, a", ...
                     " folder or an installed package: '%s'"), TARGET);
    endif
  endif

  walk = fullfile (ROOT, "inst");
  if (! isfolder (walk))
    walk = ROOT;
  endif
  FILES = __gather__ (walk);

endfunction

function FILES = __gather__ (DIR)

  FILES = {};
  entries = dir (DIR);
  for ii = 1:numel (entries)
    name = entries(ii).name;
    if (name(1) == '.')
      continue;
    endif
    path = fullfile (DIR, name);
    if (entries(ii).isdir)
      FILES = [FILES, __gather__(path)];
    elseif (numel (name) > 2 && strcmp (name(end-1:end), ".m"))
      FILES{end+1} = path;
    endif
  endfor

endfunction

%!test
%! [r, f] = devtools.__resolveTarget__ (which ("devtools.docLint"));
%! assert_equal (numel (f), 1);

%!test
%! [r, f] = devtools.__resolveTarget__ (fileparts (which ("devtools.docLint")));
%! assert_equal (numel (f) > 10, true);

%!error<devtools.__resolveTarget__: invalid number of input arguments.> ...
%! devtools.__resolveTarget__ ()
%!error<devtools.__resolveTarget__: TARGET must be a character vector.> ...
%! devtools.__resolveTarget__ (5)
%!error<devtools.__resolveTarget__: TARGET is not a file, a folder or an installed package: 'zznope'> ...
%! devtools.__resolveTarget__ ('zznope')
