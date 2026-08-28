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
## @deftypefn {devtools} {@var{S} =} devtools.__newSession__ (@var{surface})
##
## Build a fresh session structure.  Internal; not a supported entry point.
##
## @var{surface} is @qcode{"read-only"} for the tool set @code{devtools.mcp}
## offers or @qcode{"eval"} for the one @code{devtools.mcpEval} adds to it.
##
## The double underscore is core Octave's convention for a function that is
## reachable but unsupported, and it is used here because @emph{a namespace has
## no private directory}: measured on 11.2.0, neither @file{+devtools/private/} nor a
## @file{private/} directory beside @file{+devtools/} is visible to a function in
## the namespace, so a helper shared by two entry points has nowhere to live
## except the namespace itself.
##
## @end deftypefn

function S = __newSession__ (surface)

  if (nargin != 1)
    error ("devtools.__newSession__: invalid number of input arguments.");
  endif
  if (! (ischar (surface) && isrow (surface) ...
         && any (strcmp (surface, {'read-only', 'eval'}))))
    error ("devtools.__newSession__: SURFACE must be 'read-only' or 'eval'.");
  endif

  ## era is 'unknown' until the client opens, then 'legacy' or 'modern'.
  ## ws holds the evaluation workspaces by handle and is empty on a read-only
  ## session, which is what makes the surface a property of the session rather
  ## than a flag on a call.
  S = struct ();
  S.era = "unknown";
  S.version = "";
  S.initialized = false;
  S.surface = surface;
  S.ws = struct ();
  S.wsorder = {};
  S.wsnext = 1;

endfunction
