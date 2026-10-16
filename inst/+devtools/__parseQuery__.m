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
## @deftypefn {devtools} {@var{Q} =} devtools.__parseQuery__ (@var{TEXT}, @var{QUERY})
##
## Run a tree-sitter query over source.  Internal; not a supported entry
## point.
##
## @var{TEXT} is read with the lenient grammar and @var{QUERY} is a query in
## tree-sitter's own syntax.  @var{Q} is a scalar structure holding
## @code{ok}, true where the grammar completed the parse, and column vectors
## with one row per capture of every match, in the order the matches are
## found: @code{pattern}, the one-based index of the pattern that matched;
## @code{match}, a one-based number shared by the captures of one match;
## @code{capture}, the capture's name without its @code{@@}; @code{type}, the
## node's type; its range as @code{srow}, @code{scol}, @code{erow} and
## @code{ecol}, zero-based, columns counting bytes; and @code{sbyte} and
## @code{ebyte}, zero-based, so that a node's source is
## @code{@var{TEXT}(@var{sbyte}+1:@var{ebyte})}.
##
## Predicates such as @code{#match?} are not evaluated: a caller filters the
## captures itself.  A query naming a node type the grammar lacks raises.
##
## Like @code{devtools.__parse__}, this raises where the parser was not built.
##
## @end deftypefn

function Q = __parseQuery__ (TEXT, QUERY)

  if (nargin != 2)
    error ("devtools.__parseQuery__: invalid number of input arguments.");
  endif
  if (! (ischar (TEXT) && (isrow (TEXT) || isempty (TEXT))))
    error ("devtools.__parseQuery__: TEXT must be a character vector.");
  endif
  if (! (ischar (QUERY) && isrow (QUERY)))
    error ("devtools.__parseQuery__: QUERY must be a character vector.");
  endif

  persistent built = [];
  if (isempty (built))
    built = (exist ('__devtools_parse__', 'file') == 3);
  endif
  if (! built)
    error (strcat ("devtools.__parseQuery__: the parser was not built, so", ...
                   " no source can be read; install the package on a", ...
                   " machine with a working compiler."));
  endif

  Q = __devtools_parse__ (TEXT, '', 'query', QUERY);

endfunction

%!shared T, P
%! T = sprintf ("if (a)\n  x = f ('s');\nendif\n");
%! P = '(index_expression (identifier) @f (string) @s)';

%!test
%! Q = devtools.__parseQuery__ (T, '(string) @s');
%! assert_equal (T(Q.sbyte+1:Q.ebyte), '''s''');

%!test
%! Q = devtools.__parseQuery__ (T, '(string) @s');
%! assert_equal ([Q.srow, Q.scol, Q.erow, Q.ecol], [1, 9, 1, 12]);

%!test
%! Q = devtools.__parseQuery__ (T, '(if_statement condition: (_) @c)');
%! assert_equal (Q.type, {'parenthesized_expression'});

%!test
%! Q = devtools.__parseQuery__ (T, P);
%! assert_equal (Q.capture, {'f'; 's'});

%!test
%! Q = devtools.__parseQuery__ (T, P);
%! assert_equal (Q.match, [1; 1]);

%!test
%! Q = devtools.__parseQuery__ (T, '"endif" @e (string) @s');
%! assert_equal (Q.pattern, [2; 1]);

%!test
%! Q = devtools.__parseQuery__ (T, '(comment) @c');
%! assert_equal (Q.ok, true);

%!test
%! Q = devtools.__parseQuery__ ('x = (1;', '(comment) @c');
%! assert_equal (Q.ok, false);

%!test
%! Q = devtools.__parseQuery__ (T, '(comment) @c');
%! assert_equal (size (Q.srow), [0, 1]);

%!error<devtools.__parseQuery__: invalid number of input arguments.> ...
%! devtools.__parseQuery__ ('x')
%!error<devtools.__parseQuery__: TEXT must be a character vector.> ...
%! devtools.__parseQuery__ (5, '(string) @s')
%!error<devtools.__parseQuery__: QUERY must be a character vector.> ...
%! devtools.__parseQuery__ ('x', 5)
%!error<__devtools_parse__: QUERY has an unknown node type at byte 2.> ...
%! devtools.__parseQuery__ ('x', '(klingon) @k')
