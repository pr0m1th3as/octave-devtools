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
#include <octave/quit.h>
#include <octave/interpreter.h>

#include <chrono>
#include <condition_variable>
#include <mutex>
#include <string>
#include <thread>

DEFUN_DLD (__devtools_guard__, args, ,
           R"(-*- texinfo -*-
@deftypefn {devtools} {@var{tf} =} __devtools_guard__ (@var{code}, @var{seconds})

Evaluate @var{code} in the caller's scope and stop it after @var{seconds}.
Returns true if it was stopped.  Internal; not a supported entry point.

A thread waits out the deadline and, if the evaluation has not finished, raises
the interpreter's own interrupt state, which is the mechanism Ctrl-C uses.  The
evaluation then unwinds to the @code{catch} here, the state is cleared, and the
interpreter carries on.

@strong{This cannot be written in Octave.}  Measured on 11.2.0: an interrupt
raised this way unwinds straight through @code{try}, honouring
@code{unwind_protect} blocks on the way but never being caught, and takes the
process with it.  Only a @code{catch} in C++ stops it, which is why a watchdog
that keeps the server alive has to live in an oct-file.

The evaluation runs in the caller's scope, so a variable the code assigned
before the deadline is still there afterwards, and an error raised by the code
propagates as an ordinary Octave error.

@end deftypefn)")
{
  if (args.length () != 2)
    error ("__devtools_guard__: invalid number of input arguments.");

  std::string code
    = args(0).xstring_value ("__devtools_guard__: CODE must be a string.");
  double secs
    = args(1).xdouble_value ("__devtools_guard__: SECONDS must be numeric.");

  if (! (secs > 0) || octave::math::isinf (secs))
    error ("__devtools_guard__: SECONDS must be finite and positive.");

  octave::interpreter *interp = octave::interpreter::the_interpreter ();
  if (! interp)
    error ("__devtools_guard__: no interpreter is running.");

  std::mutex m;
  std::condition_variable cv;
  bool finished = false;

  std::thread timer ([&] ()
    {
      std::unique_lock<std::mutex> lock (m);
      if (! cv.wait_for (lock,
                         std::chrono::milliseconds ((long) (secs * 1000.0)),
                         [&] { return finished; }))
        {
          octave_interrupt_state = 1;
          octave_signal_caught = true;
        }
    });

  // Whatever happens next, the thread is told to stop waiting and joined
  // before this returns: a detached timer outliving its deadline would raise
  // an interrupt inside whatever the server was doing next.
  auto release = [&] ()
    {
      {
        std::lock_guard<std::mutex> lock (m);
        finished = true;
      }
      cv.notify_all ();
      timer.join ();
    };

  bool stopped = false;

  try
    {
      int parse_status = 0;
      interp->eval_string (code, false, parse_status, 0);
    }
  catch (octave::interrupt_exception&)
    {
      stopped = true;
      octave_interrupt_state = 0;
      octave_signal_caught = false;
    }
  catch (...)
    {
      release ();
      throw;
    }

  release ();

  return octave_value_list (octave_value (stopped));
}
