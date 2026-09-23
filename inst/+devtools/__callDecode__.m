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
## @deftypefn {devtools} {[@var{V}, @var{ERRMSG}] =} devtools.__callDecode__ (@var{ARGS}, @var{NULLDATE}, @var{DATES})
##
## Build the Octave arguments of an @code{octave_call} request.  Internal; not
## a supported entry point.
##
## @var{ARGS} is the @code{args} member as @code{jsondecode} returns it: a cell
## array of structures, a structure array when every argument has the same
## fields, a scalar structure for one argument, or an empty double for none.
## Each argument has a @code{type}: @qcode{"number"}, @qcode{"string"} and
## @qcode{"logical"} carry a @code{value}; @qcode{"matrix"} carries a
## @code{value} that is a list of rows, such as @code{[[1, 2], [3, 4]]}, with
## @code{null} for @code{NaN} and the text @qcode{"Inf"} and @qcode{"-Inf"}
## for the infinities; and @qcode{"range"} carries
## @code{rows}, @code{cols} and @code{cells}, listed row by row, each with a
## @code{kind} (@qcode{"empty"}, @qcode{"number"}, @qcode{"logical"},
## @qcode{"text"}, @qcode{"error"}, @qcode{"date"}, @qcode{"datetime"},
## @qcode{"time"} or @qcode{"duration"}) and, except when empty, a
## @code{value}; dates and times carry their serial number.  @var{NULLDATE} is
## the date serial number 0 stands for, written @qcode{"YYYY-MM-DD"}, and
## @var{DATES} is true when @code{datetime} and @code{duration} are available.
##
## @var{V} is a cell array holding one value per argument.  A matrix becomes a
## logical matrix when every element is @code{true} or @code{false}, and a
## double matrix otherwise.  A flat list is a column: @code{jsondecode} reads
## @code{[1, 2, 3]} and @code{[[1], [2], [3]]} alike, so a row vector is
## written @code{[[1, 2, 3]]}.  Rows of different lengths, text other than the
## infinities, and more than two levels of lists are refused, and the only
## empty matrix is @code{[]}, which is 0-by-0.
##
## A range becomes:
##
## @itemize
## @item a double matrix when its cells are numbers, logical values or empty,
## an empty cell being @code{NaN}, and a logical matrix when every cell is a
## logical value;
## @item a @code{datetime} array when its cells are dates, datetimes or empty,
## an empty cell being @code{NaT}, and a @code{duration} array when they are
## times, durations or empty, an empty cell being @code{NaN};
## @item a cell array of character vectors when its cells are text or empty,
## an empty cell being empty text;
## @item otherwise a cell array holding each cell's own value, an empty cell
## being @code{[]}.
## @end itemize
##
## A range holding an error cell is refused, and so is a range holding dates or
## times when @var{DATES} is false.  A refusal is returned as @var{ERRMSG}, the
## body of an error message, with @var{V} empty.
##
## @end deftypefn

function [V, ERRMSG] = __callDecode__ (ARGS, NULLDATE, DATES)

  if (nargin != 3)
    error ("devtools.__callDecode__: invalid number of input arguments.");
  endif

  V = {};
  ERRMSG = "";

  if (! (ischar (NULLDATE) && ! isempty (regexp (NULLDATE, ...
                                   '^\d{4}-\d{2}-\d{2}$', "once"))))
    ERRMSG = "nullDate must be a date written YYYY-MM-DD.";
    return;
  endif

  args = asCell (ARGS);
  for i = 1:numel (args)
    a = args{i};
    if (! (isstruct (a) && isscalar (a) && isfield (a, "type") ...
           && ischar (a.type)))
      ERRMSG = sprintf ("argument %d has no type.", i);
      V = {};
      return;
    endif
    switch (a.type)
      case 'number'
        if (! (isfield (a, "value") && isnumeric (a.value) ...
               && isscalar (a.value)))
          fmt = "argument %d is a number without a numeric value.";
          ERRMSG = sprintf (fmt, i);
          V = {};
          return;
        endif
        V{i} = double (a.value);
      case 'string'
        if (! (isfield (a, "value") && ischar (a.value)))
          ERRMSG = sprintf ("argument %d is a string without a text value.", i);
          V = {};
          return;
        endif
        V{i} = a.value(:).';
      case 'logical'
        if (! (isfield (a, "value") && islogical (a.value) ...
               && isscalar (a.value)))
          fmt = "argument %d is a logical without true or false.";
          ERRMSG = sprintf (fmt, i);
          V = {};
          return;
        endif
        V{i} = a.value;
      case 'matrix'
        [x, ERRMSG] = decodeMatrix (a, i);
        if (! isempty (ERRMSG))
          V = {};
          return;
        endif
        V{i} = x;
      case 'range'
        [x, ERRMSG] = decodeRange (a, i, NULLDATE, DATES);
        if (! isempty (ERRMSG))
          V = {};
          return;
        endif
        V{i} = x;
      otherwise
        ERRMSG = sprintf ("argument %d has the unknown type '%s'.", i, a.type);
        V = {};
        return;
    endswitch
  endfor

endfunction

function [X, e] = decodeMatrix (a, i)

  ## What jsondecode made of a list of rows: a numeric or logical array where
  ## every element had one type, else a cell array, holding per row a column
  ## vector where that row was uniform and a cell array where it was mixed.
  X = [];
  e = "";
  if (! isfield (a, "value"))
    e = sprintf ("argument %d is a matrix without a value.", i);
    return;
  endif
  v = a.value;

  if (isnumeric (v) || islogical (v))
    if (ndims (v) > 2)
      e = sprintf ("argument %d is a matrix of more than two dimensions.", i);
      return;
    endif
    X = v;
    if (isnumeric (X))
      X = double (X);
    endif
    return;
  endif
  if (! iscell (v))
    e = sprintf ("argument %d is a matrix whose value is not a list.", i);
    return;
  endif

  ## A flat list is a column; otherwise each element is a row
  v = v(:);
  flat = all (cellfun (@(x) isItem (x), v));
  if (flat)
    rows = cellfun (@(x) {x}, v, "UniformOutput", false);
  else
    rows = cell (numel (v), 1);
    for r = 1:numel (v)
      x = v{r};
      if (iscell (x))
        rows{r} = x(:).';
      elseif ((isnumeric (x) || islogical (x)) && isvector (x))
        rows{r} = num2cell (x(:).');
      elseif (isItem (x))
        rows{r} = {x};
      else
        e = sprintf ("argument %d is a matrix of more than two dimensions.", i);
        return;
      endif
    endfor
  endif

  n = cellfun (@numel, rows);
  if (any (n != n(1)))
    e = sprintf ("argument %d is a matrix whose rows differ in length.", i);
    return;
  endif
  items = [rows{:}];
  values = nan (1, numel (items));
  logic = true;
  for k = 1:numel (items)
    x = items{k};
    if (ischar (x))
      if (strcmp (x, "Inf"))
        values(k) = Inf;
      elseif (strcmp (x, "-Inf"))
        values(k) = -Inf;
      else
        fmt = ["argument %d is a matrix holding the text '%s', where only", ...
               " \"Inf\" and \"-Inf\" may be text."];
        e = sprintf (fmt, i, x);
        return;
      endif
      logic = false;
    elseif (isempty (x))
      logic = false;                  # null, which is NaN
    elseif ((isnumeric (x) || islogical (x)) && isscalar (x))
      values(k) = double (x);
      logic = logic && islogical (x);
    else
      e = sprintf ("argument %d is a matrix of more than two dimensions.", i);
      return;
    endif
  endfor
  X = reshape (values, n(1), numel (rows)).';
  if (logic)
    X = logical (X);
  endif

endfunction

## One element of a matrix: a scalar, the text of an infinity, or null.
function tf = isItem (x)
  tf = ((isnumeric (x) || islogical (x)) && numel (x) <= 1) || ischar (x);
endfunction

function [X, e] = decodeRange (a, i, NULLDATE, DATES)

  X = [];
  e = "";

  if (! (isfield (a, "rows") && isfield (a, "cols") && isfield (a, "cells") ...
         && isCount (a.rows) && isCount (a.cols)))
    e = sprintf ("argument %d is a range without positive rows and cols.", i);
    return;
  endif
  rows = a.rows;
  cols = a.cols;
  cells = asCell (a.cells);
  n = rows * cols;
  if (numel (cells) != n)
    e = sprintf ("argument %d is a %d-by-%d range with %d cells.", ...
                 i, rows, cols, numel (cells));
    return;
  endif

  kinds = cell (1, n);
  values = cell (1, n);
  for k = 1:n
    c = cells{k};
    r = floor ((k - 1) / cols) + 1;
    col = mod (k - 1, cols) + 1;
    where = sprintf ("argument %d: the cell in row %d, column %d", i, r, col);
    if (! (isstruct (c) && isscalar (c) && isfield (c, "kind") ...
           && ischar (c.kind)))
      e = sprintf ("%s has no kind.", where);
      return;
    endif
    kinds{k} = c.kind;
    switch (c.kind)
      case 'empty'
        values{k} = [];
      case {'number', 'date', 'datetime', 'time', 'duration'}
        if (! (isfield (c, "value") && isnumeric (c.value) ...
               && isscalar (c.value)))
          e = sprintf ("%s is a %s without a numeric value.", where, c.kind);
          return;
        endif
        values{k} = double (c.value);
      case 'logical'
        if (! (isfield (c, "value") && islogical (c.value) ...
               && isscalar (c.value)))
          e = sprintf ("%s is a logical without true or false.", where);
          return;
        endif
        values{k} = c.value;
      case 'text'
        if (! (isfield (c, "value") && ischar (c.value)))
          e = sprintf ("%s is text without a text value.", where);
          return;
        endif
        values{k} = c.value(:).';
      case 'error'
        if (isfield (c, "value") && ischar (c.value) && ! isempty (c.value))
          e = sprintf ("%s holds the error %s.", where, c.value);
        else
          e = sprintf ("%s holds an error.", where);
        endif
        return;
      otherwise
        e = sprintf ("%s has the unknown kind '%s'.", where, c.kind);
        return;
    endswitch
  endfor

  empty = strcmp (kinds, "empty");
  present = unique (kinds(! empty));
  isDate = @(q) any (strcmp (q, {'date', 'datetime'}));
  isTime = @(q) any (strcmp (q, {'time', 'duration'}));
  if (! DATES && any (cellfun (@(q) isDate (q) || isTime (q), present)))
    e = sprintf (strcat ("argument %d holds dates or times, which need the", ...
                         " datatypes package loaded in this sandbox."), i);
    return;
  endif

  ## Cells arrive row by row
  shape = @(x) reshape (x, cols, rows).';

  if (isempty (present) || all (ismember (present, {'number', 'logical'})))
    if (! isempty (present) && all (strcmp (present, "logical")) ...
        && ! any (empty))
      X = shape (cell2mat (values));
    else
      X = shape (numbers (values, empty));
    endif
  elseif (all (cellfun (isDate, present)))
    X = nullDatetime (NULLDATE) + days (shape (numbers (values, empty)));
  elseif (all (cellfun (isTime, present)))
    X = days (shape (numbers (values, empty)));
  elseif (all (strcmp (present, "text")))
    values(empty) = {''};
    X = shape (values);
  else
    base = [];
    for k = 1:n
      if (isDate (kinds{k}))
        if (isempty (base))
          base = nullDatetime (NULLDATE);
        endif
        values{k} = base + days (values{k});
      elseif (isTime (kinds{k}))
        values{k} = days (values{k});
      endif
    endfor
    X = shape (values);
  endif

endfunction

## The cells as one row of doubles, NaN where a cell is empty.
function x = numbers (values, empty)
  x = nan (1, numel (values));
  x(! empty) = cellfun (@double, values(! empty));
endfunction

## A datetime for the null date, written YYYY-MM-DD.
function D = nullDatetime (NULLDATE)
  ymd = sscanf (NULLDATE, "%d-%d-%d");
  D = datetime (ymd(1), ymd(2), ymd(3));
endfunction

## What jsondecode made of a JSON array, as a row cell array.
function C = asCell (x)
  if (iscell (x))
    C = x(:).';
  elseif (isstruct (x))
    C = num2cell (x(:).');
  elseif (isempty (x))
    C = {};
  else
    C = {x};
  endif
endfunction

## True for a whole number of at least 1.
function tf = isCount (x)
  tf = isnumeric (x) && isscalar (x) && x >= 1 && x == fix (x);
endfunction

%!shared J, D
%! J = @(txt) jsondecode (txt);
%! D = ! isempty (which ("datetime"));

%!test
%! [V, E] = devtools.__callDecode__ ([], "1899-12-30", false);
%! assert_equal (V, {});
%! assert_equal (E, "");
%!test
%! A = J ('[{"type":"number","value":2},{"type":"string","value":"omitnan"}]');
%! V = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (V, {2, 'omitnan'});
%!test
%! ## One argument arrives from jsondecode as a scalar structure.
%! V = devtools.__callDecode__ (J ('{"type":"logical","value":true}'), ...
%!                              "1899-12-30", false);
%! assert_equal (V, {true});
%!test
%! ## Cells arrive row by row, and an empty cell in a numeric range is NaN.
%! A = J (['[{"type":"range","rows":2,"cols":3,"cells":[', ...
%!         '{"kind":"number","value":1},{"kind":"number","value":2},', ...
%!         '{"kind":"number","value":3},{"kind":"number","value":4},', ...
%!         '{"kind":"empty"},{"kind":"number","value":6}]}]']);
%! V = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (V{1}, [1, 2, 3; 4, NaN, 6]);
%!test
%! A = J (['[{"type":"range","rows":1,"cols":2,"cells":[', ...
%!         '{"kind":"logical","value":true},', ...
%!         '{"kind":"logical","value":false}]}]']);
%! V = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (V{1}, [true, false]);
%!test
%! ## A logical range with an empty cell cannot stay logical.
%! A = J (['[{"type":"range","rows":1,"cols":2,"cells":[', ...
%!         '{"kind":"logical","value":true},{"kind":"empty"}]}]']);
%! V = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (V{1}, [1, NaN]);
%!test
%! A = J (['[{"type":"range","rows":2,"cols":1,"cells":[', ...
%!         '{"kind":"logical","value":true},{"kind":"number","value":5}]}]']);
%! V = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (V{1}, [1; 5]);
%!test
%! A = J (['[{"type":"range","rows":1,"cols":3,"cells":[', ...
%!         '{"kind":"text","value":"a"},{"kind":"empty"},', ...
%!         '{"kind":"text","value":"bc"}]}]']);
%! V = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (V{1}, {'a', '', 'bc'});
%!test
%! ## A range mixing kinds is a cell array of each cell's own value.
%! A = J (['[{"type":"range","rows":1,"cols":3,"cells":[', ...
%!         '{"kind":"text","value":"a"},{"kind":"number","value":2},', ...
%!         '{"kind":"empty"}]}]']);
%! V = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (V{1}, {'a', 2, []});
%!test
%! ## An empty range is a NaN matrix of its size.
%! A = J (['[{"type":"range","rows":1,"cols":2,"cells":[', ...
%!         '{"kind":"empty"},{"kind":"empty"}]}]']);
%! V = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (V{1}, [NaN, NaN]);
%!test
%! if (D)
%!   A = J (['[{"type":"range","rows":1,"cols":3,"cells":[', ...
%!           '{"kind":"date","value":46279},{"kind":"empty"},', ...
%!           '{"kind":"datetime","value":46279.5}]}]']);
%!   V = devtools.__callDecode__ (A, "1899-12-30", true);
%!   assert_equal (class (V{1}), "datetime");
%!   assert_equal (isnat (V{1}), [false, true, false]);
%!   assert_equal (days (V{1}(3) - datetime (1899, 12, 30)), 46279.5);
%! endif
%!test
%! ## The document's null date is the origin, not Excel's.
%! if (D)
%!   A = J (['[{"type":"range","rows":1,"cols":1,"cells":[', ...
%!           '{"kind":"date","value":0}]}]']);
%!   V = devtools.__callDecode__ (A, "1904-01-01", true);
%!   assert_equal (V{1} == datetime (1904, 1, 1), true);
%! endif
%!test
%! if (D)
%!   A = J (['[{"type":"range","rows":1,"cols":3,"cells":[', ...
%!           '{"kind":"time","value":0.5},{"kind":"empty"},', ...
%!           '{"kind":"duration","value":1.5}]}]']);
%!   V = devtools.__callDecode__ (A, "1899-12-30", true);
%!   assert_equal (class (V{1}), "duration");
%!   assert_equal (days (V{1}), [0.5, NaN, 1.5]);
%! endif
%!test
%! if (D)
%!   A = J (['[{"type":"range","rows":1,"cols":2,"cells":[', ...
%!           '{"kind":"date","value":1},{"kind":"number","value":2}]}]']);
%!   V = devtools.__callDecode__ (A, "1899-12-30", true);
%!   assert_equal (class (V{1}{1}), "datetime");
%!   assert_equal (V{1}{2}, 2);
%! endif

%!test
%! A = J (['[{"type":"range","rows":1,"cols":2,"cells":[', ...
%!         '{"kind":"number","value":1},', ...
%!         '{"kind":"error","value":"#DIV/0!"}]}]']);
%! [V, E] = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (V, {});
%! assert_equal (E, ["argument 1: the cell in row 1, column 2 holds the", ...
%!                   " error #DIV/0!."]);
%!test
%! A = J ('[{"type":"range","rows":1,"cols":1,"cells":[{"kind":"error"}]}]');
%! [V, E] = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (E, "argument 1: the cell in row 1, column 1 holds an error.");
%!test
%! A = J (['[{"type":"range","rows":1,"cols":1,"cells":[', ...
%!         '{"kind":"date","value":1}]}]']);
%! [V, E] = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (E, ["argument 1 holds dates or times, which need the", ...
%!                   " datatypes package loaded in this sandbox."]);
%!test
%! [V, E] = devtools.__callDecode__ ([], "30/12/1899", false);
%! assert_equal (E, "nullDate must be a date written YYYY-MM-DD.");
%!test
%! [V, E] = devtools.__callDecode__ (J ('[{"value":2}]'), "1899-12-30", false);
%! assert_equal (E, "argument 1 has no type.");
%!test
%! [V, E] = devtools.__callDecode__ (J ('[{"type":"tensor"}]'), ...
%!                                   "1899-12-30", false);
%! assert_equal (E, "argument 1 has the unknown type 'tensor'.");
%!test
%! [V, E] = devtools.__callDecode__ (J ('[{"type":"number","value":"2"}]'), ...
%!                                   "1899-12-30", false);
%! assert_equal (E, "argument 1 is a number without a numeric value.");
%!test
%! [V, E] = devtools.__callDecode__ (J ('[{"type":"string","value":2}]'), ...
%!                                   "1899-12-30", false);
%! assert_equal (E, "argument 1 is a string without a text value.");
%!test
%! [V, E] = devtools.__callDecode__ (J ('[{"type":"logical","value":1}]'), ...
%!                                   "1899-12-30", false);
%! assert_equal (E, "argument 1 is a logical without true or false.");
%!test
%! A = J ('[{"type":"range","rows":0,"cols":1,"cells":[]}]');
%! [V, E] = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (E, "argument 1 is a range without positive rows and cols.");
%!test
%! A = J ('[{"type":"range","rows":2,"cols":2,"cells":[{"kind":"empty"}]}]');
%! [V, E] = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (E, "argument 1 is a 2-by-2 range with 1 cells.");
%!test
%! A = J ('[{"type":"range","rows":1,"cols":1,"cells":[{"value":1}]}]');
%! [V, E] = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (E, "argument 1: the cell in row 1, column 1 has no kind.");
%!test
%! A = J ('[{"type":"range","rows":1,"cols":1,"cells":[{"kind":"blob"}]}]');
%! [V, E] = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (E, ["argument 1: the cell in row 1, column 1 has the", ...
%!                   " unknown kind 'blob'."]);
%!test
%! A = J ('[{"type":"range","rows":1,"cols":1,"cells":[{"kind":"date"}]}]');
%! [V, E] = devtools.__callDecode__ (A, "1899-12-30", true);
%! assert_equal (E, ["argument 1: the cell in row 1, column 1 is a date", ...
%!                   " without a numeric value."]);
%!test
%! A = J (['[{"type":"range","rows":1,"cols":1,"cells":[', ...
%!         '{"kind":"logical","value":2}]}]']);
%! [V, E] = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (E, ["argument 1: the cell in row 1, column 1 is a logical", ...
%!                   " without true or false."]);
%!test
%! A = J (['[{"type":"range","rows":1,"cols":1,"cells":[', ...
%!         '{"kind":"text","value":3}]}]']);
%! [V, E] = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (E, ["argument 1: the cell in row 1, column 1 is text", ...
%!                   " without a text value."]);

%!test
%! A = J ('{"type":"matrix","value":[[1,2,3],[4,5,6]]}');
%! V = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (V{1}, [1, 2, 3; 4, 5, 6]);
%!test
%! ## A flat list is a column, as jsondecode reads it.
%! A = J ('{"type":"matrix","value":[1,2,3]}');
%! V = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (V{1}, [1; 2; 3]);
%!test
%! A = J ('{"type":"matrix","value":[[1,2,3]]}');
%! V = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (V{1}, [1, 2, 3]);
%!test
%! A = J ('{"type":"matrix","value":[[1,null],[3,4]]}');
%! V = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (V{1}, [1, NaN; 3, 4]);
%!test
%! A = J ('{"type":"matrix","value":[[1,"Inf"],["-Inf",null]]}');
%! V = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (V{1}, [1, Inf; -Inf, NaN]);
%!test
%! A = J ('{"type":"matrix","value":[1,"Inf",null]}');
%! V = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (V{1}, [1; Inf; NaN]);
%!test
%! A = J ('{"type":"matrix","value":[[true,false],[false,true]]}');
%! V = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (V{1}, [true, false; false, true]);
%!test
%! ## true and false beside numbers are numbers.
%! A = J ('{"type":"matrix","value":[[1,true],[2,false]]}');
%! V = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (V{1}, [1, 1; 2, 0]);
%!test
%! A = J ('{"type":"matrix","value":[]}');
%! V = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (V{1}, zeros (0, 0));
%!test
%! A = J ('{"type":"matrix","value":5}');
%! V = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (V{1}, 5);
%!test
%! A = J ('{"type":"matrix","value":[[1,2],[3]]}');
%! [V, E] = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (E, "argument 1 is a matrix whose rows differ in length.");
%!test
%! A = J ('{"type":"matrix","value":[[1,2],[3,"x"]]}');
%! [V, E] = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (E, ["argument 1 is a matrix holding the text 'x', where", ...
%!                   " only \"Inf\" and \"-Inf\" may be text."]);
%!test
%! A = J ('{"type":"matrix","value":[[[1,2],[3,4]],[[5,6],[7,8]]]}');
%! [V, E] = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (E, "argument 1 is a matrix of more than two dimensions.");
%!test
%! A = J ('{"type":"matrix","value":[[1,[2,3]],[4,5]]}');
%! [V, E] = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (E, "argument 1 is a matrix of more than two dimensions.");
%!test
%! A = J ('{"type":"matrix","value":"abc"}');
%! [V, E] = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (E, "argument 1 is a matrix whose value is not a list.");
%!test
%! A = J ('{"type":"matrix"}');
%! [V, E] = devtools.__callDecode__ (A, "1899-12-30", false);
%! assert_equal (E, "argument 1 is a matrix without a value.");

%!error <devtools\.__callDecode__: invalid number of input arguments\.> ...
%! devtools.__callDecode__ ([], "1899-12-30")
