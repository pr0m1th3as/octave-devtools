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
## @deftypefn {devtools} {[@var{NAMES}, @var{LNUM}] =} devtools.__seealsoNames__ (@var{LINES})
##
## Read the cross-references of a texinfo block.  Internal; not a supported
## entry point.
##
## @var{LINES} is a cell array of the block's lines, comment markers included.
## @var{NAMES} is the cell array of the names every @code{@@seealso} in the
## block lists, in order, and @var{LNUM} the index into @var{LINES} of the line
## each name was written on, so that a finding names the line the reader has to
## edit rather than the line the list opened on.
##
## A list that wraps over several lines is read whole, the lines being joined
## before the names are taken.  An @code{@@@@seealso} is prose about the
## command and is not read as one.  Nothing here decides whether a name
## resolves.
##
## @end deftypefn

function [NAMES, LNUM] = __seealsoNames__ (LINES)

  if (nargin != 1)
    error ("devtools.__seealsoNames__: invalid number of input arguments.");
  endif
  if (! iscellstr (LINES))
    error (strcat ("devtools.__seealsoNames__: LINES must be a cell array", ...
                   " of character vectors."));
  endif

  NAMES = {};
  LNUM = [];

  ## Join the block, keeping the line each character came from
  txt = '';
  map = [];
  for ii = 1:numel (LINES)
    piece = regexprep (LINES{ii}, '^\s*##', '');
    txt = [txt, piece, " "];
    map = [map, ii * ones(1, numel (piece) + 1)];
  endfor

  at = strfind (txt, "@seealso");
  for ii = 1:numel (at)
    if (at(ii) > 1 && txt(at(ii)-1) == '@')
      continue;                                # @@seealso, prose about it
    endif
    rest = txt(at(ii):end);
    open = strfind (rest, '{');
    if (isempty (open))
      continue;
    endif
    depth = 0;
    close = 0;
    for kk = open(1):numel (rest)
      if (rest(kk) == '{')
        depth = depth + 1;
      elseif (rest(kk) == '}')
        depth = depth - 1;
        if (depth == 0)
          close = kk;
          break;
        endif
      endif
    endfor
    if (close == 0)
      continue;                                # unterminated list, nothing read
    endif
    inner = rest(open(1)+1:close-1);
    base = at(ii) + open(1);                   # offset of inner's first char
    [tok, pos] = regexp (inner, '[^,\s]+', 'match', 'start');
    for kk = 1:numel (tok)
      NAMES{end+1} = tok{kk};
      LNUM(end+1) = map(base + pos(kk) - 1);
    endfor
  endfor

endfunction

%!test
%! L = {'## @seealso{mean, median}', '## @end deftypefn'};
%! [n, l] = devtools.__seealsoNames__ (L);
%! assert_equal (n, {'mean', 'median'});
%! assert_equal (l, [1, 1]);

%!test
%! L = {'## Body text.', '## @seealso{mean,', '## median, mode}'};
%! [n, l] = devtools.__seealsoNames__ (L);
%! assert_equal (n, {'mean', 'median', 'mode'});
%! assert_equal (l, [2, 3, 3]);

%!test
%! L = {'## @seealso{duration.days, datetime}'};
%! assert_equal (devtools.__seealsoNames__ (L), {'duration.days', 'datetime'});

%!test
%! L = {'## @seealso{a}', '## @seealso{b}'};
%! [n, l] = devtools.__seealsoNames__ (L);
%! assert_equal (n, {'a', 'b'});
%! assert_equal (l, [1, 2]);

%!test
%! assert_equal (devtools.__seealsoNames__ ({'## No references here.'}), {});

%!test
%! assert_equal (devtools.__seealsoNames__ ({'## @seealso{unterminated'}), {});

%!test
%! [n, l] = devtools.__seealsoNames__ ({'## @seealso{ mean }'});
%! assert_equal (n, {'mean'});
%! assert_equal (l, 1);

%!error<devtools.__seealsoNames__: invalid number of input arguments.> ...
%! devtools.__seealsoNames__ ()
%!error<devtools.__seealsoNames__: LINES must be a cell array of character vectors.> ...
%! devtools.__seealsoNames__ ('x')
