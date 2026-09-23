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
## @deftypefn {devtools} {@var{C} =} devtools.__parseAt__ (@var{TEXT}, @var{ROW}, @var{COL})
##
## The syntax enclosing a point in source.  Internal; not a supported entry
## point.
##
## @var{ROW} is zero-based and @var{COL} a zero-based byte offset into that
## line.  @var{C} is a structure array of the named nodes enclosing the point,
## innermost first, read with the lenient grammar.  Each element holds
## @code{type}; @code{field}, the field the node fills in its parent;
## @code{text}, its source where that is at most 512 bytes; its range as
## @code{srow}, @code{scol}, @code{erow} and @code{ecol}; and, where the node
## carries them, @code{name} with its range @code{nrow}, @code{ncol},
## @code{nerow} and @code{necol}, @code{params}, @code{outputs},
## @code{supers}, @code{static}, and @code{arg1}, the first argument of a call
## when that is a plain name.  A point just past the end of a name, where an
## editor leaves the cursor after typing it, finds the name.
##
## Like @code{devtools.__parse__}, this raises where the parser was not built.
##
## @end deftypefn

function C = __parseAt__ (TEXT, ROW, COL)

  if (nargin != 3)
    error ("devtools.__parseAt__: invalid number of input arguments.");
  endif
  if (! (ischar (TEXT) && (isrow (TEXT) || isempty (TEXT))))
    error ("devtools.__parseAt__: TEXT must be a character vector.");
  endif
  if (! (isnumeric (ROW) && isscalar (ROW) && ROW >= 0 && ROW == fix (ROW)))
    error ("devtools.__parseAt__: ROW must be a non-negative integer.");
  endif
  if (! (isnumeric (COL) && isscalar (COL) && COL >= 0 && COL == fix (COL)))
    error ("devtools.__parseAt__: COL must be a non-negative integer.");
  endif

  persistent built = [];
  if (isempty (built))
    built = (exist ("__devtools_parse__", "file") == 3);
  endif
  if (! built)
    error (strcat ("devtools.__parseAt__: the parser was not built, so no", ...
                   " source can be read; install the package on a machine", ...
                   " with a working compiler."));
  endif

  C = __devtools_parse__ (TEXT, '', 'at', double (ROW), double (COL));

endfunction

%!shared T
%! T = sprintf (["classdef K < P\n  methods\n    function y = f (obj, x)\n", ...
%!               "      y = g (obj, x) + prob.Beta.fit (x);\n    end\n", ...
%!               "  end\nend\n"]);

%!test
%! C = devtools.__parseAt__ (T, 3, 10);
%! assert_equal (C(1).text, "g");

%!test
%! C = devtools.__parseAt__ (T, 3, 10);
%! assert_equal (C(2).arg1, "obj");

%!test
%! C = devtools.__parseAt__ (T, 3, 10);
%! k = find (strcmp ({C.type}, "function_definition"), 1);
%! assert_equal (C(k).params, {"obj", "x"});

%!test
%! C = devtools.__parseAt__ (T, 3, 10);
%! k = find (strcmp ({C.type}, "classdef_definition"), 1);
%! assert_equal (C(k).supers, {"P"});

%!test
%! C = devtools.__parseAt__ (T, 3, 11);
%! assert_equal (C(1).text, "g");

%!test
%! C = devtools.__parseAt__ (T, 3, 30);
%! assert_equal (C(2).text, "prob.Beta");

%!test
%! C = devtools.__parseAt__ (T, 3, 30);
%! assert_equal (C(1).field, "field");

%!test
%! C = devtools.__parseAt__ ("", 0, 0);
%! assert_equal ({C.type}, {"source_file"});

%!error<devtools.__parseAt__: invalid number of input arguments.> ...
%! devtools.__parseAt__ ("x")
%!error<devtools.__parseAt__: TEXT must be a character vector.> ...
%! devtools.__parseAt__ (5, 0, 0)
%!error<devtools.__parseAt__: ROW must be a non-negative integer.> ...
%! devtools.__parseAt__ ("x", -1, 0)
%!error<devtools.__parseAt__: COL must be a non-negative integer.> ...
%! devtools.__parseAt__ ("x", 0, 1.5)
