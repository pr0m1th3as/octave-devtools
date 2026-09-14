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
## @deftypefn {devtools} {[@var{R}, @var{ERRMSG}] =} devtools.__callEncode__ (@var{OUTS}, @var{NULLDATE})
##
## Encode the outputs of an @code{octave_call} as typed cells.  Internal; not a
## supported entry point.
##
## @var{OUTS} is a cell array holding one value per output, and @var{NULLDATE}
## the date serial number 0 stands for, written @qcode{"YYYY-MM-DD"}.  @var{R}
## is a cell array holding, per output, a structure with the fields
## @code{kind}, @code{class}, @code{rows}, @code{cols} and @code{cells}, the
## cells listed row by row, which @code{jsonencode} writes as the result the
## tool returns.  It holds only numbers, logical values, text, cell arrays and
## structures, so it can be saved by the forked process a call runs in and
## loaded by the server without running any class's code.
##
## @table @asis
## @item @qcode{"number"}
## A real numeric array, as numbers, @code{NaN} (which @code{jsonencode} writes
## as @code{null}) and the strings @qcode{"Inf"} and @qcode{"-Inf"}.
## @item @qcode{"logical"}
## A logical array.
## @item @qcode{"text"}
## A character array, one string per row, or a cell array of character
## vectors.
## @item @qcode{"datetime"}
## A @code{datetime} array, as days since @var{NULLDATE}, a @code{NaT} being
## @code{NaN}.  A time zone is dropped, keeping the local time.
## @item @qcode{"duration"}
## A @code{duration} array, as days.
## @item @qcode{"cell"}
## A cell array of scalars, text and empty values, each cell a structure with
## its own @code{kind} and @code{value}.
## @end table
##
## An output with more than two dimensions, a complex output, and any other
## class is refused.  A refusal is returned as @var{ERRMSG}, the body of an
## error message, with @var{R} empty.
##
## @end deftypefn

function [R, ERRMSG] = __callEncode__ (OUTS, NULLDATE)

  if (nargin != 2)
    error ("devtools.__callEncode__: invalid number of input arguments.");
  endif

  R = {};
  ERRMSG = "";
  for i = 1:numel (OUTS)
    [d, ERRMSG] = encodeOutput (OUTS{i}, i, NULLDATE);
    if (! isempty (ERRMSG))
      R = {};
      return;
    endif
    R{i} = d;
  endfor

endfunction

function [d, e] = encodeOutput (x, i, NULLDATE)

  d = [];
  e = "";
  cls = class (x);
  if (isa (x, "string"))
    x = cellstr (x);
  endif
  if (ndims (x) > 2)
    e = sprintf ("output %d has %d dimensions, and cells hold two.", ...
                 i, ndims (x));
    return;
  endif
  [r, c] = size (x);

  if (isa (x, "datetime"))
    kind = "datetime";
    cells = numberCells (serial (x, NULLDATE));
  elseif (isa (x, "duration"))
    kind = "duration";
    cells = numberCells (days (x));
  elseif (islogical (x))
    kind = "logical";
    cells = num2cell (rowMajor (full (x)));
  elseif (isnumeric (x))
    if (! isreal (x))
      e = sprintf ("output %d is complex, which a cell cannot hold.", i);
      return;
    endif
    kind = "number";
    cells = numberCells (double (full (x)));
  elseif (ischar (x))
    kind = "text";
    if (isempty (x))
      r = 1;
      cells = {''};
    else
      cells = arrayfun (@(k) x(k,:), 1:r, "UniformOutput", false);
    endif
    c = 1;
  elseif (iscellstr (x))
    kind = "text";
    cells = rowMajor (x);
  elseif (iscell (x))
    kind = "cell";
    m = rowMajor (x);
    cells = cell (1, numel (m));
    for k = 1:numel (m)
      [cells{k}, e] = encodeElement (m{k}, i, k, NULLDATE);
      if (! isempty (e))
        return;
      endif
    endfor
  else
    e = sprintf ("output %d is a %s, which cannot be placed in cells.", i, cls);
    return;
  endif

  d = struct ("kind", kind, "class", cls, "rows", r, "cols", c, ...
              "cells", {cells});

endfunction

function [s, e] = encodeElement (v, i, k, NULLDATE)

  s = [];
  e = "";
  if (isnumeric (v) && isempty (v))
    s = struct ("kind", "empty");
  elseif (ischar (v) && rows (v) <= 1)
    s = struct ("kind", "text", "value", v);
  elseif (! isscalar (v))
    fmt = "output %d: element %d of the cell array is a %d-by-%d %s.";
    e = sprintf (fmt, i, k, rows (v), columns (v), class (v));
  elseif (isa (v, "datetime"))
    s = struct ("kind", "datetime", ...
                "value", numberCells (serial (v, NULLDATE)));
  elseif (isa (v, "duration"))
    s = struct ("kind", "duration", "value", numberCells (days (v)));
  elseif (islogical (v))
    s = struct ("kind", "logical", "value", v);
  elseif (isnumeric (v) && isreal (v))
    s = struct ("kind", "number", "value", numberCells (double (v)));
  else
    fmt = strcat ("output %d: element %d of the cell array is a %s, which", ...
                  " a cell cannot hold.");
    e = sprintf (fmt, i, k, class (v));
  endif
  ## A scalar's value is the number itself, not a one-element array
  if (isstruct (s) && isfield (s, "value") && iscell (s.value))
    s.value = s.value{1};
  endif

endfunction

## Days since the null date, the local time kept where there is a time zone.
function x = serial (t, NULLDATE)
  if (! isempty (t.TimeZone))
    t.TimeZone = "";
  endif
  ymd = sscanf (NULLDATE, "%d-%d-%d");
  x = days (t - datetime (ymd(1), ymd(2), ymd(3)));
endfunction

## Numbers row by row, with Inf and -Inf as strings, since JSON has neither.
function C = numberCells (x)
  C = num2cell (rowMajor (x));
  C(rowMajor (x) == Inf) = {'Inf'};
  C(rowMajor (x) == -Inf) = {'-Inf'};
endfunction

function y = rowMajor (x)
  y = x.';
  y = y(:).';
endfunction

%!test
%! R = devtools.__callEncode__ ({[1, NaN; Inf, -Inf]}, "1899-12-30");
%! assert_equal (R{1}.kind, "number");
%! assert_equal ([R{1}.rows, R{1}.cols], [2, 2]);
%! assert_equal (jsonencode (R{1}.cells), '[1,null,"Inf","-Inf"]');
%!test
%! ## Row by row, whatever the storage order.
%! R = devtools.__callEncode__ ({[1, 2, 3; 4, 5, 6]}, "1899-12-30");
%! assert_equal (cell2mat (R{1}.cells), [1, 2, 3, 4, 5, 6]);
%!test
%! R = devtools.__callEncode__ ({int8([1; 2])}, "1899-12-30");
%! assert_equal ({R{1}.kind, R{1}.class}, {'number', 'int8'});
%! assert_equal (cell2mat (R{1}.cells), [1, 2]);
%!test
%! R = devtools.__callEncode__ ({sparse([0, 3])}, "1899-12-30");
%! assert_equal (cell2mat (R{1}.cells), [0, 3]);
%!test
%! R = devtools.__callEncode__ ({[true, false]}, "1899-12-30");
%! assert_equal (R{1}.kind, "logical");
%! assert_equal (jsonencode (R{1}.cells), '[true,false]');
%!test
%! R = devtools.__callEncode__ ({['ab'; 'cd']}, "1899-12-30");
%! assert_equal ({R{1}.kind, R{1}.rows, R{1}.cols}, {'text', 2, 1});
%! assert_equal (R{1}.cells, {'ab', 'cd'});
%!test
%! R = devtools.__callEncode__ ({''}, "1899-12-30");
%! assert_equal ({R{1}.rows, R{1}.cols, R{1}.cells}, {1, 1, {''}});
%!test
%! R = devtools.__callEncode__ ({{'a', 'b'; 'c', 'd'}}, "1899-12-30");
%! assert_equal (R{1}.kind, "text");
%! assert_equal (R{1}.cells, {'a', 'b', 'c', 'd'});
%!test
%! ## A cell array of mixed values gives each cell its own kind.
%! R = devtools.__callEncode__ ({{1, 'x'; [], Inf}}, "1899-12-30");
%! assert_equal (R{1}.kind, "cell");
%! assert_equal (jsonencode (R{1}.cells), ...
%!               ['[{"kind":"number","value":1},', ...
%!                '{"kind":"text","value":"x"},', ...
%!                '{"kind":"empty"},{"kind":"number","value":"Inf"}]']);
%!test
%! R = devtools.__callEncode__ ({zeros(0, 3)}, "1899-12-30");
%! assert_equal ({R{1}.rows, R{1}.cols, numel(R{1}.cells)}, {0, 3, 0});
%!test
%! ## Several outputs, in order.
%! R = devtools.__callEncode__ ({7, 2}, "1899-12-30");
%! assert_equal ([R{1}.cells{1}, R{2}.cells{1}], [7, 2]);
%!test
%! if (! isempty (which ("datetime")))
%!   t = datetime (2026, 9, 14) + [0, NaN];
%!   R = devtools.__callEncode__ ({t}, "1899-12-30");
%!   assert_equal (R{1}.kind, "datetime");
%!   assert_equal (jsonencode (R{1}.cells), '[46279,null]');
%! endif
%!test
%! if (! isempty (which ("datetime")))
%!   R = devtools.__callEncode__ ({datetime(1904, 1, 2)}, "1904-01-01");
%!   assert_equal (R{1}.cells, {1});
%! endif
%!test
%! if (! isempty (which ("duration")))
%!   R = devtools.__callEncode__ ({hours([12, 36])}, "1899-12-30");
%!   assert_equal (R{1}.kind, "duration");
%!   assert_equal (cell2mat (R{1}.cells), [0.5, 1.5]);
%! endif

%!test
%! [R, E] = devtools.__callEncode__ ({1, [1, 2i]}, "1899-12-30");
%! assert_equal (R, {});
%! assert_equal (E, "output 2 is complex, which a cell cannot hold.");
%!test
%! [R, E] = devtools.__callEncode__ ({ones(2, 2, 2)}, "1899-12-30");
%! assert_equal (E, "output 1 has 3 dimensions, and cells hold two.");
%!test
%! [R, E] = devtools.__callEncode__ ({struct("a", 1)}, "1899-12-30");
%! assert_equal (E, "output 1 is a struct, which cannot be placed in cells.");
%!test
%! [R, E] = devtools.__callEncode__ ({{1, [1, 2]}}, "1899-12-30");
%! assert_equal (E, ["output 1: element 2 of the cell array is a", ...
%!                   " 1-by-2 double."]);
%!test
%! [R, E] = devtools.__callEncode__ ({{@sin}}, "1899-12-30");
%! assert_equal (E, ["output 1: element 1 of the cell array is a", ...
%!                   " function_handle, which a cell cannot hold."]);

%!error <devtools\.__callEncode__: invalid number of input arguments\.> ...
%! devtools.__callEncode__ ({1})
