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
## @deftypefn {devtools} {@var{ERRMSG} =} devtools.__sandboxUsable__ ()
##
## Whether a sandbox can be built on this machine.  Internal; not a supported
## entry point.
##
## Returns the empty string where one can, and otherwise the reason it cannot,
## as the body of a message the caller completes under its own name.
##
## The last check is the one that matters: @command{bwrap} is asked to build
## its namespaces over a trivial command, because a machine can carry the
## program and still refuse it.  A container does, and so does a kernel with
## unprivileged user namespaces turned off, and a guard that tests only whether
## the program is installed reports such a machine as ready and then fails
## every sandbox test on it.
##
## The answer is measured once and kept for the life of the interpreter.
##
## @seealso{devtools.sandboxCommand}
## @end deftypefn

function ERRMSG = __sandboxUsable__ ()

  persistent measured = false;
  persistent answer = "";

  if (! measured)
    answer = probe ();
    measured = true;
  endif
  ERRMSG = answer;

endfunction

function E = probe ()

  E = "";
  u = uname ();
  if (! strcmp (u.sysname, "Linux"))
    E = "a sandbox runs on Linux only";
    return;
  endif
  if (isempty (file_in_path (getenv ("PATH"), "bwrap")))
    E = "bwrap is not on the PATH; install bubblewrap";
    return;
  endif
  if (isempty (file_in_path (getenv ("PATH"), "prlimit")))
    E = "prlimit is not on the PATH; install util-linux";
    return;
  endif

  t = file_in_path (getenv ("PATH"), "true");
  if (isempty (t))
    t = "/bin/true";
  endif
  ## The mounts are part of the question: a container can permit the
  ## namespaces and refuse a fresh procfs over the one it has masked, and a
  ## probe that stops at the namespaces answers yes about what it never tried.
  cmd = sprintf (strcat ('bwrap --unshare-all --ro-bind / / --proc /proc', ...
                         ' --dev /dev "%s" 2> /dev/null'), t);
  if (system (cmd) != 0)
    E = "bwrap is installed but cannot build its namespaces here";
  endif

endfunction

%!test
%! ## The answer is a character vector either way, and the same one twice.
%! E = devtools.__sandboxUsable__ ();
%! assert_equal ([ischar(E), isrow(E) || isempty(E)], [true, true]);
%! assert_equal (E, devtools.__sandboxUsable__ ());
%!test
%! ## Off GNU/Linux the reason says so and nothing is spawned to find out.
%! if (! strcmp (uname ().sysname, "Linux"))
%!   assert_equal (devtools.__sandboxUsable__ (), ...
%!                 "a sandbox runs on Linux only");
%! endif
