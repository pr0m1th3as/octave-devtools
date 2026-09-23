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
## @deftypefn {devtools} {@var{D} =} devtools.__parseDefs__ (@var{TEXT})
##
## The classes, functions, methods and properties defined in source.
## Internal; not a supported entry point.
##
## @var{D} is a structure array in source order, read with the lenient
## grammar, with the fields @code{devtools.__parseAt__} describes.
## @code{type} is @qcode{'classdef_definition'},
## @qcode{'function_definition'} or @qcode{'property'}, and @code{parent} is
## the index in @var{D} of the definition enclosing it, 0 at the top level, so
## a method's parent is its class.  Only the definitions themselves are read,
## never a statement, so a long body costs only its top level.
##
## Like @code{devtools.__parse__}, this raises where the parser was not built.
##
## @end deftypefn

function D = __parseDefs__ (TEXT)

  if (nargin != 1)
    error ("devtools.__parseDefs__: invalid number of input arguments.");
  endif
  if (! (ischar (TEXT) && (isrow (TEXT) || isempty (TEXT))))
    error ("devtools.__parseDefs__: TEXT must be a character vector.");
  endif

  persistent built = [];
  if (isempty (built))
    built = (exist ("__devtools_parse__", "file") == 3);
  endif
  if (! built)
    error (strcat ("devtools.__parseDefs__: the parser was not built, so", ...
                   " no source can be read; install the package on a", ...
                   " machine with a working compiler."));
  endif

  D = __devtools_parse__ (TEXT, '', 'defs');

endfunction

%!shared T
%! T = sprintf (["classdef K < P & handle\n  properties\n    X = 1;\n", ...
%!               "  end\n  methods\n    function obj = K (x)\n    end\n", ...
%!               "  end\n  methods (Static)\n    function r = make (a)\n", ...
%!               "    end\n  end\nend\nfunction h = helper (a)\nend\n"]);

%!test
%! D = devtools.__parseDefs__ (T);
%! assert_equal ({D.name}, {"K", "X", "K", "make", "helper"});

%!test
%! D = devtools.__parseDefs__ (T);
%! assert_equal ([D.parent], [0, 1, 1, 1, 0]);

%!test
%! D = devtools.__parseDefs__ (T);
%! assert_equal ([D.static], [false, false, false, true, false]);

%!test
%! D = devtools.__parseDefs__ (T);
%! assert_equal (D(1).supers, {"P", "handle"});

%!test
%! D = devtools.__parseDefs__ (T);
%! assert_equal ([D(4).nrow, D(4).ncol], [9, 17]);

%!test
%! D = devtools.__parseDefs__ (sprintf ("function y = f (x)\n  y = x;\nend\n"));
%! assert_equal (D.outputs, {"y"});

%!test
%! D = devtools.__parseDefs__ ("x = 1;");
%! assert_equal (numel (D), 0);

%!error<devtools.__parseDefs__: invalid number of input arguments.> ...
%! devtools.__parseDefs__ ()
%!error<devtools.__parseDefs__: TEXT must be a character vector.> ...
%! devtools.__parseDefs__ (5)
