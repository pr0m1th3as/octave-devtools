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
## @deftypefn {devtools} {[@var{NAME}, @var{CATEGORY}] =} devtools.__texiName__ (@var{HEADER})
##
## Read the name and the category of a texinfo header.  Internal; not a
## supported entry point.
##
## @var{HEADER} is the text of one @code{@@deftypefn}, @code{@@deftypefnx} or
## @code{@@deftp} header, its comment marker stripped and its continuation
## lines already joined.  @var{NAME} is the name the header documents and
## @var{CATEGORY} the contents of its first brace group, the one @code{help}
## prints as the heading; both are empty where the header does not parse.
##
## The brace groups between the category and the name are skipped, however
## many there are and however deeply they nest: a return list such as
## @code{@{[@var{A}, @var{B}] =@}} nests a brace for every @code{@@var} in it,
## so the groups are matched rather than searched for.
##
## @end deftypefn

function [NAME, CATEGORY] = __texiName__ (HEADER)

  if (nargin != 1)
    error ("devtools.__texiName__: invalid number of input arguments.");
  endif
  if (! (ischar (HEADER) && (isrow (HEADER) || isempty (HEADER))))
    error ("devtools.__texiName__: HEADER must be a character vector.");
  endif

  NAME = '';
  CATEGORY = '';

  txt = strtrim (regexprep (HEADER, '^\s*##', ''));
  stop = regexp (txt, '^@(?:deftypefnx?|deftp)(?![A-Za-z0-9_])', 'end', 'once');
  if (isempty (stop))
    return;
  endif
  txt = txt(stop+1:end);

  ## The category is the first group, the name the first token after the rest
  first = true;
  while (true)
    txt = strtrim (txt);
    if (isempty (txt) || txt(1) != '{')
      break;
    endif
    [group, txt, ok] = __takeGroup__ (txt);
    if (! ok)
      return;                                  # unbalanced braces, no reading
    endif
    if (first)
      CATEGORY = strtrim (group);
      first = false;
    endif
  endwhile

  NAME = regexp (strtrim (txt), '^[A-Za-z_][A-Za-z0-9_.]*', 'match', 'once');

endfunction

function [GROUP, REST, OK] = __takeGroup__ (TXT)
  GROUP = '';
  REST = TXT;
  OK = false;
  depth = 0;
  for ii = 1:numel (TXT)
    if (TXT(ii) == '{')
      depth = depth + 1;
    elseif (TXT(ii) == '}')
      depth = depth - 1;
      if (depth == 0)
        GROUP = TXT(2:ii-1);
        REST = TXT(ii+1:end);
        OK = true;
        return;
      endif
    endif
  endfor
endfunction

%!test
%! [n, c] = devtools.__texiName__ ('@deftypefn {statistics} {@var{D} =} mean (@var{X})');
%! assert_equal (n, 'mean');
%! assert_equal (c, 'statistics');

%!test
%! [n, c] = devtools.__texiName__ ('@deftypefn {ClassificationKNN} {@var{L} =} loss (@var{obj})');
%! assert_equal (n, 'loss');
%! assert_equal (c, 'ClassificationKNN');

%!test
%! h = '@deftypefn {devtools} {[@var{PROG}, @var{ARGS}] =} devtools.sandboxCommand (@var{F})';
%! assert_equal (devtools.__texiName__ (h), 'devtools.sandboxCommand');

%!test
%! [n, c] = devtools.__texiName__ ('@deftp {prob.BetaDistribution} {property} a');
%! assert_equal (n, 'a');
%! assert_equal (c, 'prob.BetaDistribution');

%!test
%! [n, c] = devtools.__texiName__ ('@deftp {statistics} prob.BetaDistribution');
%! assert_equal (n, 'prob.BetaDistribution');
%! assert_equal (c, 'statistics');

%!test
%! assert_equal (devtools.__texiName__ ('@deftypefnx  {p} {} duration.empty ()'), ...
%!               'duration.empty');

%!test
%! assert_equal (devtools.__texiName__ ('## @deftypefn {p} {} f ()'), 'f');

%!test
%! [n, c] = devtools.__texiName__ ('@deftypefn {p} {@var{a} =} f');
%! assert_equal (n, 'f');
%! assert_equal (c, 'p');

%!test
%! assert_equal (devtools.__texiName__ ('Not a header at all.'), '');

%!test
%! assert_equal (devtools.__texiName__ ('@deftypefn {p} {@var{a} =} f ('), 'f');

%!test
%! assert_equal (devtools.__texiName__ ('@deftypefn {p} {unclosed f ()'), '');

%!error<devtools.__texiName__: invalid number of input arguments.> ...
%! devtools.__texiName__ ()
%!error<devtools.__texiName__: HEADER must be a character vector.> ...
%! devtools.__texiName__ ({'a'})
