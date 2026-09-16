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
## @deftypefn {devtools} {} devtools.__sweepCall__ ()
##
## Kill every process a call left behind.  Internal; not a supported entry
## point.
##
## Does nothing at all unless @code{devtools.__sweepCheck__} finds that a
## sweep is safe here, so that calling it on a desktop is harmless.  Where it
## is safe, the process namespace holds only the sandbox: PID 1 is
## @command{bwrap}, and every other process is this server or something a call
## started.
##
## This function and @code{devtools.__sweepCheck__} are the only two places
## that name the platform's process containment, so a port changes these and
## nothing else.
##
## @seealso{devtools.__sweepCheck__}
## @end deftypefn

function __sweepCall__ ()

  if (! isempty (devtools.__sweepCheck__ ()))
    return;
  endif

  names = readdir ("/proc");
  me = getpid ();
  for i = 1:numel (names)
    p = str2double (names{i});
    if (! isnan (p) && p != 1 && p != me)
      kill (p, 9);
    endif
  endfor

endfunction

%!test
%! ## Outside a sandbox it sweeps nothing, so this process reaches the check
%! ## that refused it.
%! devtools.__sweepCall__ ();
%! assert_equal (isempty (devtools.__sweepCheck__ ()), false);
