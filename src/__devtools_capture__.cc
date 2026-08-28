// Copyright (C) 2026 Andreas Bertsatos <abertsatos@biol.uoa.gr>
//
// This file is part of the devtools package for GNU Octave.
//
// This program is free software; you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation; either version 3 of the License, or (at your option) any later
// version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
// details.
//
// You should have received a copy of the GNU General Public License along with
// this program; if not, see <http://www.gnu.org/licenses/>.

#include <octave/oct.h>

#include <cstdio>

#if defined (_WIN32) && ! defined (__CYGWIN__)
#  include <io.h>
#  include <fcntl.h>
#  include <sys/stat.h>
#  define DEVTOOLS_DUP _dup
#  define DEVTOOLS_DUP2 _dup2
#  define DEVTOOLS_CLOSE _close
#  define DEVTOOLS_OPEN _open
#  define DEVTOOLS_WRONLY (_O_WRONLY | _O_CREAT | _O_TRUNC | _O_BINARY)
#  define DEVTOOLS_MODE (_S_IREAD | _S_IWRITE)
#else
#  include <unistd.h>
#  include <fcntl.h>
#  include <sys/stat.h>
#  define DEVTOOLS_DUP dup
#  define DEVTOOLS_DUP2 dup2
#  define DEVTOOLS_CLOSE close
#  define DEVTOOLS_OPEN open
#  define DEVTOOLS_WRONLY (O_WRONLY | O_CREAT | O_TRUNC)
#  define DEVTOOLS_MODE 0600
#endif

// The descriptors parked here while 1 and 2 point at a file: 1 carries the
// protocol and 2 carries warnings, which are output the model should see.
// Negative means no capture is running, which is also the state a failed
// start leaves behind.
static int devtools_saved_out = -1;
static int devtools_saved_err = -1;

DEFUN_DLD (__devtools_capture__, args, ,
           R"(-*- texinfo -*-
@deftypefn  {devtools} {} __devtools_capture__ ("start", @var{file})
@deftypefnx {devtools} {} __devtools_capture__ ("stop")
@deftypefnx {devtools} {@var{tf} =} __devtools_capture__ ("active")

Point file descriptors 1 and 2 at @var{file} and back again.  Internal; not a
supported entry point.

@code{evalc} captures every route to standard output that stays inside the
interpreter and none that leaves it: a subprocess inherits descriptor 1 and
writes @strong{past} the capture.  In a server whose descriptor 1 carries the
protocol, that is a corrupted stream rather than stray text, which is why the
containment here is at the descriptor and not at the name.

Descriptor 2 is taken as well, because a warning is output the model should
see and Octave writes warnings there.  Both land in one file, in the order they
were written, which no pair of separate captures can reproduce.

@code{start} flushes, duplicates both descriptors so that the protocol stream
is not lost, and puts @var{file} in their place.  @code{stop} flushes, restores
the duplicates and drops them.  Starting twice without stopping is an error
rather than a leaked descriptor.

@end deftypefn)")
{
  octave_value_list retval;

  int nargin = args.length ();

  if (nargin < 1 || nargin > 2)
    error ("__devtools_capture__: invalid number of input arguments.");

  std::string action
    = args(0).xstring_value ("__devtools_capture__: ACTION must be a string.");

  if (action == "active")
    {
      if (nargin != 1)
        error ("__devtools_capture__: 'active' takes no further argument.");

      return octave_value_list (octave_value (devtools_saved_out >= 0));
    }

  if (action == "start")
    {
      if (nargin != 2)
        error ("__devtools_capture__: 'start' needs a file name.");

      if (devtools_saved_out >= 0)
        error ("__devtools_capture__: a capture is already running.");

      std::string file
        = args(1).xstring_value ("__devtools_capture__: FILE must be a string.");

      std::fflush (stdout);
      std::fflush (stderr);

      int saved_out = DEVTOOLS_DUP (1);
      if (saved_out < 0)
        error ("__devtools_capture__: could not duplicate descriptor 1.");

      int saved_err = DEVTOOLS_DUP (2);
      if (saved_err < 0)
        {
          DEVTOOLS_CLOSE (saved_out);
          error ("__devtools_capture__: could not duplicate descriptor 2.");
        }

      int fd = DEVTOOLS_OPEN (file.c_str (), DEVTOOLS_WRONLY, DEVTOOLS_MODE);
      if (fd < 0)
        {
          DEVTOOLS_CLOSE (saved_out);
          DEVTOOLS_CLOSE (saved_err);
          error ("__devtools_capture__: could not open '%s'.", file.c_str ());
        }

      if (DEVTOOLS_DUP2 (fd, 1) < 0 || DEVTOOLS_DUP2 (fd, 2) < 0)
        {
          DEVTOOLS_CLOSE (fd);
          DEVTOOLS_CLOSE (saved_out);
          DEVTOOLS_CLOSE (saved_err);
          error ("__devtools_capture__: could not redirect the descriptors.");
        }

      DEVTOOLS_CLOSE (fd);
      devtools_saved_out = saved_out;
      devtools_saved_err = saved_err;

      return retval;
    }

  if (action == "stop")
    {
      if (nargin != 1)
        error ("__devtools_capture__: 'stop' takes no further argument.");

      if (devtools_saved_out < 0)
        error ("__devtools_capture__: no capture is running.");

      std::fflush (stdout);
      std::fflush (stderr);

      int bad = 0;
      if (DEVTOOLS_DUP2 (devtools_saved_out, 1) < 0)
        bad = 1;
      if (DEVTOOLS_DUP2 (devtools_saved_err, 2) < 0)
        bad = 2;

      DEVTOOLS_CLOSE (devtools_saved_out);
      DEVTOOLS_CLOSE (devtools_saved_err);
      devtools_saved_out = -1;
      devtools_saved_err = -1;

      if (bad)
        error ("__devtools_capture__: could not restore descriptor %d.", bad);

      return retval;
    }

  error ("__devtools_capture__: ACTION must be 'start', 'stop' or 'active'.");
}
