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
## @deftypefn {devtools} {[@var{S}, @var{HEAD}] =} devtools.__testStream__ (@var{LINES})
##
## The test blocks of a file as code.  Internal; not a supported entry point.
##
## @var{LINES} is a cell array of a file's lines.  @var{S} is a column cell
## array of the same lines with every line outside the test blocks empty and
## each @code{%!} prefix two spaces, so that rows and byte columns stay those
## of the file.  A header keeps the code that follows it: after @code{%!test},
## @code{%!xtest}, @code{%!demo}, @code{%!error} and @code{%!warning}, the
## code past a bug number or an expected message in angle brackets, or past an
## @code{id=} for the last two; @code{%!function}, @code{%!endfunction},
## @code{%!assert} and @code{%!fail} keep the whole line.  @code{%!testif} and
## @code{%!shared} headers are blank.  @var{HEAD} is a column cell array
## holding the keyword of each header line and empty elsewhere.
##
## @end deftypefn

function [S, HEAD] = __testStream__ (LINES)

  if (nargin != 1)
    error ("devtools.__testStream__: invalid number of input arguments.");
  endif
  if (! iscellstr (LINES))
    error (strcat ("devtools.__testStream__: LINES must be a cell array of", ...
                   " character vectors."));
  endif

  kw = {'test', 'xtest', 'testif', 'shared', 'function', 'endfunction', ...
        'assert', 'fail', 'error', 'warning', 'demo'};
  n = numel (LINES);
  S = repmat ({''}, n, 1);
  HEAD = repmat ({''}, n, 1);
  for r = find (strncmp (LINES(:), '%!', 2))'
    s = LINES{r};
    w = regexp (s, '^%!([a-z]+)', 'tokens', 'once');
    if (isempty (w) || ! any (strcmp (w{1}, kw)))
      S{r} = ['  ', s(3:end)];
      continue;
    endif
    HEAD{r} = w{1};
    switch (w{1})
      case {'function', 'endfunction', 'assert', 'fail'}
        S{r} = ['  ', s(3:end)];
      case {'test', 'xtest', 'demo', 'error', 'warning'}
        ## A bug number or an expected message runs to the first '>', as
        ## test reads it, and the code follows
        k = 2 + numel (w{1});
        rest = s(k+1:end);
        e = regexp (rest, '^\s*<[^>]*>', 'end', 'once');
        if (isempty (e) && any (strcmp (w{1}, {'error', 'warning'})))
          e = regexp (rest, '^\s*id=\S*', 'end', 'once');
        endif
        if (isempty (e))
          e = 0;
        endif
        S{r} = [blanks(k + e), rest(e+1:end)];
    endswitch
  endfor

endfunction

%!shared L
%! L = {'x = 1;', '%!test', '%! y = f (x);', '%!error <bad> g (1)', ...
%!      '%!shared a, b', '%!assert (h (2), 3)'};

%!test
%! S = devtools.__testStream__ (L);
%! assert_equal (S{1}, '');

%!test
%! S = devtools.__testStream__ (L);
%! assert_equal (S{3}, '   y = f (x);');

%!test
%! S = devtools.__testStream__ (L);
%! assert_equal (S{4}, '              g (1)');

%!test
%! S = devtools.__testStream__ (L);
%! assert_equal (S{5}, '');

%!test
%! S = devtools.__testStream__ (L);
%! assert_equal (S{6}, '  assert (h (2), 3)');

%!test
%! [~, H] = devtools.__testStream__ (L);
%! assert_equal (H', {'', 'test', '', 'error', 'shared', 'assert'});

%!test
%! S = devtools.__testStream__ (L);
%! assert_equal (size (S), [6, 1]);

%!error<devtools.__testStream__: invalid number of input arguments.> ...
%! devtools.__testStream__ ()
%!error<devtools.__testStream__: LINES must be a cell array of character vectors.> ...
%! devtools.__testStream__ (5)
