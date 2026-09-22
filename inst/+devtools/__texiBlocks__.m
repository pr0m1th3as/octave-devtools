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
## @deftypefn {devtools} {@var{B} =} devtools.__texiBlocks__ (@var{LINES})
##
## Locate the texinfo blocks of a file.  Internal; not a supported entry point.
##
## @var{LINES} is a cell array of the file's lines, without their newlines.
## @var{B} is a structure array with one element per texinfo block, in the
## order the blocks appear, holding the fields @code{first} and @code{last},
## the line numbers of the @code{-*- texinfo -*-} marker and of the block's
## last comment line; @code{header}, a cell array of row vectors of line
## numbers, one vector per @code{@@deftypefn}, @code{@@deftypefnx} or
## @code{@@deftp} header with the lines a trailing @code{@@} continues it onto;
## @code{body}, the row vector of the block's remaining line numbers; and
## @code{kind}, @qcode{'deftypefn'} or @qcode{'deftp'} taken from the first
## header, empty where the block has none.
##
## A block runs from its marker to the last comment line that follows it
## without a break, which is what the file itself does: the block ends where
## the code begins.  Nothing here reads the filesystem, so the whole of it is
## tested with made-up lines.
##
## @end deftypefn

function B = __texiBlocks__ (LINES)

  if (nargin != 1)
    error ("devtools.__texiBlocks__: invalid number of input arguments.");
  endif
  if (! iscellstr (LINES))
    error (strcat ("devtools.__texiBlocks__: LINES must be a cell array", ...
                   " of character vectors."));
  endif

  B = struct ("first", {}, "last", {}, "header", {}, "body", {}, "kind", {});
  nl = numel (LINES);
  ii = 1;
  while (ii <= nl)
    if (isempty (regexp (LINES{ii}, '^\s*##\s*-\*-\s*texinfo\s*-\*-', 'once')))
      ii = ii + 1;
      continue;
    endif

    ## The block runs to the last unbroken comment line after the marker
    last = ii;
    jj = ii + 1;
    while (jj <= nl && ! isempty (regexp (LINES{jj}, '^\s*##', 'once')))
      last = jj;
      jj = jj + 1;
    endwhile

    ## Group the header lines, each with the lines a trailing @ continues it on
    header = {};
    kind = '';
    kk = ii + 1;
    while (kk <= last)
      txt = __content__ (LINES{kk});
      tok = regexp (txt, '^@(deftypefnx?|deftp)(?![A-Za-z0-9_])', ...
                    'tokens', 'once');
      if (isempty (tok))
        kk = kk + 1;
        continue;
      endif
      if (isempty (kind))
        kind = tok{1};
        if (strcmp (kind, "deftypefnx"))
          kind = 'deftypefn';
        endif
      endif
      group = kk;
      while (kk < last ...
             && ! isempty (regexp (__content__ (LINES{kk}), '@\s*$', 'once')))
        kk = kk + 1;
        group(end+1) = kk;
      endwhile
      header{end+1} = group;
      kk = kk + 1;
    endwhile

    body = setdiff ((ii + 1):last, [header{:}]);
    B(end+1) = struct ("first", ii, "last", last, "header", {header}, ...
                       "body", body, "kind", kind);
    ii = last + 1;
  endwhile

endfunction

function TXT = __content__ (LINE)
  TXT = strtrim (regexprep (LINE, '^\s*##', ''));
endfunction

%!test
%! L = {'## -*- texinfo -*-', '## @deftypefn {p} {} f ()', '## Body.', ...
%!      '## @end deftypefn', 'function f ()'};
%! B = devtools.__texiBlocks__ (L);
%! assert_equal (numel (B), 1);
%! assert_equal ([B.first, B.last], [1, 4]);

%!test
%! L = {'## -*- texinfo -*-', '## @deftypefn {p} {} f ()', '## Body.', ...
%!      '## @end deftypefn', 'function f ()'};
%! B = devtools.__texiBlocks__ (L);
%! assert_equal (B.header, {2});
%! assert_equal (B.body, [3, 4]);

%!test
%! L = {'## -*- texinfo -*-', '## @deftp {p} c', '## @end deftp'};
%! B = devtools.__texiBlocks__ (L);
%! assert_equal (B.kind, 'deftp');

%!test
%! L = {'## -*- texinfo -*-', '## @deftypefnx {p} {} f @', '## (@var{x})', ...
%!      '## @end deftypefn'};
%! B = devtools.__texiBlocks__ (L);
%! assert_equal (B.header, {[2, 3]});
%! assert_equal (B.body, 4);

%!test
%! L = {'## -*- texinfo -*-', '## @deftypefn {p} {} f ()', ...
%!      '## @deftypefnx {p} {} f (@var{x})', '## @end deftypefn'};
%! B = devtools.__texiBlocks__ (L);
%! assert_equal (B.header, {2, 3});

%!test
%! L = {'## -*- texinfo -*-', '## @deftypefn {p} {} f ()', '## @end deftypefn', ...
%!      'function f ()', '## -*- texinfo -*-', '## @deftp {p} c', '## @end deftp'};
%! B = devtools.__texiBlocks__ (L);
%! assert_equal (numel (B), 2);
%! assert_equal ([B(2).first, B(2).last], [5, 7]);

%!test
%! B = devtools.__texiBlocks__ ({'function f ()', 'endfunction'});
%! assert_equal (isempty (B), true);

%!test
%! L = {'  ## -*- texinfo -*-', '  ## @deftypefn {c} {} m ()', '  ## @end deftypefn'};
%! B = devtools.__texiBlocks__ (L);
%! assert_equal (B.first, 1);
%! assert_equal (B.kind, 'deftypefn');

%!error<devtools.__texiBlocks__: invalid number of input arguments.> ...
%! devtools.__texiBlocks__ ()
%!error<devtools.__texiBlocks__: LINES must be a cell array of character vectors.> ...
%! devtools.__texiBlocks__ (5)
