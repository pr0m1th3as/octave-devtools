// Copyright (C) 2026 Andreas Bertsatos <abertsatos@biol.uoa.gr>
//
// This file is part of the mcp package for GNU Octave.
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
#  define MCP_DUP _dup
#  define MCP_DUP2 _dup2
#  define MCP_CLOSE _close
#  define MCP_OPEN _open
#  define MCP_WRONLY (_O_WRONLY | _O_CREAT | _O_TRUNC | _O_BINARY)
#  define MCP_MODE (_S_IREAD | _S_IWRITE)
#else
#  include <unistd.h>
#  include <fcntl.h>
#  include <sys/stat.h>
#  define MCP_DUP dup
#  define MCP_DUP2 dup2
#  define MCP_CLOSE close
#  define MCP_OPEN open
#  define MCP_WRONLY (O_WRONLY | O_CREAT | O_TRUNC)
#  define MCP_MODE 0600
#endif

// The descriptors parked here while 1 and 2 point at a file: 1 carries the
// protocol and 2 carries warnings, which are output the model should see.
// Negative means no capture is running, which is also the state a failed
// start leaves behind.
static int mcp_saved_out = -1;
static int mcp_saved_err = -1;

DEFUN_DLD (__mcp_capture__, args, ,
           R"(-*- texinfo -*-
@deftypefn  {mcp} {} __mcp_capture__ ("start", @var{file})
@deftypefnx {mcp} {} __mcp_capture__ ("stop")
@deftypefnx {mcp} {@var{tf} =} __mcp_capture__ ("active")

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
    error ("__mcp_capture__: invalid number of input arguments.");

  std::string action
    = args(0).xstring_value ("__mcp_capture__: ACTION must be a string.");

  if (action == "active")
    {
      if (nargin != 1)
        error ("__mcp_capture__: 'active' takes no further argument.");

      return octave_value_list (octave_value (mcp_saved_out >= 0));
    }

  if (action == "start")
    {
      if (nargin != 2)
        error ("__mcp_capture__: 'start' needs a file name.");

      if (mcp_saved_out >= 0)
        error ("__mcp_capture__: a capture is already running.");

      std::string file
        = args(1).xstring_value ("__mcp_capture__: FILE must be a string.");

      std::fflush (stdout);
      std::fflush (stderr);

      int saved_out = MCP_DUP (1);
      if (saved_out < 0)
        error ("__mcp_capture__: could not duplicate descriptor 1.");

      int saved_err = MCP_DUP (2);
      if (saved_err < 0)
        {
          MCP_CLOSE (saved_out);
          error ("__mcp_capture__: could not duplicate descriptor 2.");
        }

      int fd = MCP_OPEN (file.c_str (), MCP_WRONLY, MCP_MODE);
      if (fd < 0)
        {
          MCP_CLOSE (saved_out);
          MCP_CLOSE (saved_err);
          error ("__mcp_capture__: could not open '%s'.", file.c_str ());
        }

      if (MCP_DUP2 (fd, 1) < 0 || MCP_DUP2 (fd, 2) < 0)
        {
          MCP_CLOSE (fd);
          MCP_CLOSE (saved_out);
          MCP_CLOSE (saved_err);
          error ("__mcp_capture__: could not redirect the descriptors.");
        }

      MCP_CLOSE (fd);
      mcp_saved_out = saved_out;
      mcp_saved_err = saved_err;

      return retval;
    }

  if (action == "stop")
    {
      if (nargin != 1)
        error ("__mcp_capture__: 'stop' takes no further argument.");

      if (mcp_saved_out < 0)
        error ("__mcp_capture__: no capture is running.");

      std::fflush (stdout);
      std::fflush (stderr);

      int bad = 0;
      if (MCP_DUP2 (mcp_saved_out, 1) < 0)
        bad = 1;
      if (MCP_DUP2 (mcp_saved_err, 2) < 0)
        bad = 2;

      MCP_CLOSE (mcp_saved_out);
      MCP_CLOSE (mcp_saved_err);
      mcp_saved_out = -1;
      mcp_saved_err = -1;

      if (bad)
        error ("__mcp_capture__: could not restore descriptor %d.", bad);

      return retval;
    }

  error ("__mcp_capture__: ACTION must be 'start', 'stop' or 'active'.");
}
