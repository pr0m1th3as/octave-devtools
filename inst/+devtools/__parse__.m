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
## @deftypefn {devtools} {@var{R} =} devtools.__parse__ (@var{TEXT})
##
## Parse Octave source without running it.  Internal; not a supported entry
## point.
##
## @var{R} is a scalar structure holding @code{sexp}, the tree written as an
## s-expression, @code{ok}, true where the grammar completed the parse, and
## @code{faults}, a structure array of the nodes that stopped it, each with
## @code{kind}, @qcode{'error'} or @qcode{'missing'}, and a one-based
## @code{row} and @code{column}.
##
## The parser is a compiled file.  Where the package was installed without a
## working compiler it is absent, and this raises rather than answering
## wrongly: a caller that reports a file clean because nothing parsed it would
## be worse than one that says it could not look.
##
## @end deftypefn

function R = __parse__ (TEXT)

  if (nargin != 1)
    error ("devtools.__parse__: invalid number of input arguments.");
  endif
  if (! (ischar (TEXT) && (isrow (TEXT) || isempty (TEXT))))
    error ("devtools.__parse__: TEXT must be a character vector.");
  endif

  persistent built = [];
  if (isempty (built))
    built = (exist ("__devtools_parse__", "file") == 3);
  endif
  if (! built)
    error (strcat ("devtools.__parse__: the parser was not built, so no", ...
                   " source can be read; install the package on a machine", ...
                   " with a working compiler."));
  endif

  R = __devtools_parse__ (TEXT);

endfunction

%!test
%! R = devtools.__parse__ ("x = 1;");
%! assert_equal (R.ok, true);

%!test
%! R = devtools.__parse__ ("x = 1;");
%! assert_equal (isempty (R.faults), true);

%!test
%! R = devtools.__parse__ (sprintf ("function y = f (x)\n  y = x;\nendfunction\n"));
%! assert_equal (R.ok, true);

%!test
%! R = devtools.__parse__ (sprintf ("if (a)\n  x = 1;\n"));
%! assert_equal (R.ok, false);

%!test
%! R = devtools.__parse__ (sprintf ("if (a)\n  x = 1;\n"));
%! assert_equal (numel (R.faults) > 0, true);

%!test
%! R = devtools.__parse__ ("end = 5;");
%! assert_equal (R.ok, false);

%!test
%! R = devtools.__parse__ ("y = a(end);");
%! assert_equal (R.ok, true);

%!test
%! R = devtools.__parse__ ("x = 1;");
%! assert_equal (R.sexp, "(source_file (assignment left: (identifier) right: (number)))");

%!test
%! R = devtools.__parse__ (sprintf ("x = 1;\n$"));
%! assert_equal (R.faults(1).row, 2);

%!error<devtools.__parse__: invalid number of input arguments.> devtools.__parse__ ()
%!error<devtools.__parse__: TEXT must be a character vector.> devtools.__parse__ (5)
