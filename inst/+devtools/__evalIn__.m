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
## @deftypefn {devtools} {[@var{out}, @var{vars}, @var{err}, @var{stopped}] =} devtools.__evalIn__ (@var{vars}, @var{code}, @var{secs})
##
## Evaluate @var{code} in a scope holding @var{vars}, and return what it
## printed, the variables left behind, the error message if it raised one, and
## whether a deadline stopped it.  Internal; not a supported entry point.
##
## The workspace is a structure whose fields are variable names.  They are
## assigned into this function's own scope before the code runs and collected
## from it afterwards, so that a variable made by one call is there for the
## next one and @code{clear} does what it says.
##
## @strong{Every local here is prefixed}, for the same reason the locals of
## @code{whichReport} are: the code being evaluated chooses its own names, and
## an unprefixed local would be overwritten by a user variable of that name or
## would leak into the workspace as one.  A user variable whose name begins
## with @code{devtools__} is therefore not kept, which is the one name a caller
## cannot use and is documented rather than defended against.
##
## There are two ways to run the code and @var{secs} chooses between them.
## With @var{secs} greater than zero the evaluation goes through
## @code{__devtools_guard__}, which stops it at the deadline and, being C++, can
## catch the interrupt that stopping it raises; output is then not returned
## here at all, because the caller is holding the descriptors over a file and
## that file has everything, in order, including what a subprocess and a
## warning wrote.  With @var{secs} zero the evaluation goes through
## @code{evalc}, which returns what the interpreter printed and misses both of
## those, and nothing stops code that does not return.
##
## The second way is the fallback for an installation whose oct-files could not
## be built.  Choosing it is the caller's business, not this function's.
##
## @end deftypefn

function [devtools__out, devtools__vars, devtools__err, devtools__stopped] = __evalIn__ (devtools__vars, devtools__code, devtools__secs)

  if (nargin < 2 || nargin > 3)
    error ("devtools.__evalIn__: invalid number of input arguments.");
  endif
  if (nargin < 3)
    devtools__secs = 0;
  endif
  if (! (isnumeric (devtools__secs) && isscalar (devtools__secs) && devtools__secs >= 0))
    error ("devtools.__evalIn__: SECS must be a nonnegative scalar.");
  endif
  if (! (isstruct (devtools__vars) && isscalar (devtools__vars)))
    error ("devtools.__evalIn__: VARS must be a scalar structure.");
  endif
  if (! (ischar (devtools__code) && (isrow (devtools__code) || isempty (devtools__code))))
    error ("devtools.__evalIn__: CODE must be a character vector.");
  endif

  devtools__err = "";
  devtools__out = "";
  devtools__stopped = false;

  devtools__names = fieldnames (devtools__vars);
  for devtools__i = 1:numel (devtools__names)
    eval ([devtools__names{devtools__i} " = devtools__vars.(devtools__names{devtools__i});"]);
  endfor

  if (devtools__secs > 0)
    try
      devtools__stopped = __devtools_guard__ (devtools__code, devtools__secs);
    catch devtools__e
      devtools__err = devtools__e.message;
    end_try_catch
  else
    try
      devtools__out = evalc (devtools__code);
    catch devtools__e
      devtools__err = devtools__e.message;
    end_try_catch
  endif

  ## Collected after the fact rather than tracked, so that clear, a rename and
  ## a variable made inside an if all come out right without parsing anything
  devtools__vars = struct ();
  devtools__live = who ();
  for devtools__i = 1:numel (devtools__live)
    if (strncmp (devtools__live{devtools__i}, "devtools__", 10))
      continue;
    endif
    devtools__vars.(devtools__live{devtools__i}) = eval (devtools__live{devtools__i});
  endfor

endfunction
