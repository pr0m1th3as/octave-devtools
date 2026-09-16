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
## @deftypefn {devtools} {@var{ERRMSG} =} devtools.__sweepCheck__ ()
##
## Whether the processes a call leaves behind can be swept here.  Internal;
## not a supported entry point.
##
## Returns the empty string where they can, and otherwise the reason they
## cannot, as the body of a message the caller completes under its own name.
##
## Sweeping kills every process but this one, which is what a sandbox needs
## and what would wreck a desktop session, so it is allowed only where the
## process namespace holds nothing else.  On GNU/Linux that is a
## @command{bwrap} sandbox, in which PID 1 is @command{bwrap} itself.
##
## This function and @code{devtools.__sweepCall__} are the only two places
## that name the platform's process containment, so a port changes these and
## nothing else.
##
## @seealso{devtools.__sweepCall__}
## @end deftypefn

function ERRMSG = __sweepCheck__ ()

  try
    pid1 = strtrim (fileread ("/proc/1/comm"));
  catch
    pid1 = "";
  end_try_catch

  if (strcmp (pid1, "bwrap"))
    ERRMSG = "";
  else
    ERRMSG = strcat ("this server is marked sandboxed but does not run", ...
                     " inside bwrap");
  endif

endfunction

%!test
%! ## Outside a bwrap sandbox, sweeping is refused and the reason names bwrap.
%! E = devtools.__sweepCheck__ ();
%! assert_equal (isempty (E), false);
