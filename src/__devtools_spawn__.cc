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

#include <string>

#if defined (_WIN32)
#  include <windows.h>
#  include <octave/oct-sysdep.h>
#endif

DEFUN_DLD (__devtools_spawn__, args, ,
           R"(-*- texinfo -*-
@deftypefn {devtools} {[@var{status}, @var{stopped}] =} __devtools_spawn__ (@var{cmd}, @var{file}, @var{seconds})

Run the command line @var{cmd} with its standard output and standard error
in @var{file}, and end it after @var{seconds}.  Windows only.  Internal; not
a supported entry point.

@var{status} is the exit code of the process, and @var{stopped} is true when
it was ended at the deadline.  The process runs inside a job object and the
whole job is ended, so a process it started goes with it.

@strong{This cannot be written in Octave.}  On Windows, core's
@code{waitpid} ignores @code{WNOHANG} and waits without end, and @code{kill}
signals the calling process whatever it is asked for, so there is no way from
Octave to wait for a process with a deadline or to end one.

@end deftypefn)")
{
  if (args.length () != 3)
    error ("__devtools_spawn__: invalid number of input arguments.");

  std::string cmd
    = args(0).xstring_value ("__devtools_spawn__: CMD must be a string.");
  std::string file
    = args(1).xstring_value ("__devtools_spawn__: FILE must be a string.");
  double secs
    = args(2).xdouble_value ("__devtools_spawn__: SECONDS must be numeric.");

  if (! (secs > 0) || octave::math::isinf (secs))
    error ("__devtools_spawn__: SECONDS must be finite and positive.");

#if defined (_WIN32)

  SECURITY_ATTRIBUTES sa = { sizeof (sa), nullptr, TRUE };
  std::wstring wfile = octave::sys::u8_to_wstring (file);
  HANDLE out = CreateFileW (wfile.c_str (), GENERIC_WRITE,
                            FILE_SHARE_READ | FILE_SHARE_WRITE, &sa,
                            CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (out == INVALID_HANDLE_VALUE)
    error ("__devtools_spawn__: cannot open '%s' for the output.",
           file.c_str ());

  // Every process of the job ends with its handle, whatever happens here
  HANDLE job = CreateJobObjectW (nullptr, nullptr);
  if (! job)
    {
      CloseHandle (out);
      error ("__devtools_spawn__: cannot create a job object.");
    }
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION lim = {};
  lim.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  SetInformationJobObject (job, JobObjectExtendedLimitInformation,
                           &lim, sizeof (lim));

  STARTUPINFOW si = {};
  si.cb = sizeof (si);
  si.dwFlags = STARTF_USESTDHANDLES;
  si.hStdInput = nullptr;
  si.hStdOutput = out;
  si.hStdError = out;

  PROCESS_INFORMATION pi = {};
  std::wstring wcmd = octave::sys::u8_to_wstring (cmd);
  // Started suspended, so that it is in the job before it can start anything
  if (! CreateProcessW (nullptr, &wcmd[0], nullptr, nullptr, TRUE,
                        CREATE_SUSPENDED | CREATE_NO_WINDOW, nullptr,
                        nullptr, &si, &pi))
    {
      DWORD e = GetLastError ();
      CloseHandle (job);
      CloseHandle (out);
      error ("__devtools_spawn__: the process could not be started, error %lu.",
             (unsigned long) e);
    }
  AssignProcessToJobObject (job, pi.hProcess);
  ResumeThread (pi.hThread);
  CloseHandle (pi.hThread);
  CloseHandle (out);

  bool stopped = false;
  DWORD ms = static_cast<DWORD> (secs * 1000.0);
  if (WaitForSingleObject (pi.hProcess, ms) == WAIT_TIMEOUT)
    {
      TerminateJobObject (job, 1);
      WaitForSingleObject (pi.hProcess, INFINITE);
      stopped = true;
    }
  DWORD code = 0;
  GetExitCodeProcess (pi.hProcess, &code);
  CloseHandle (pi.hProcess);
  CloseHandle (job);

  return ovl (static_cast<double> (code), stopped);

#else

  octave_unused_parameter (cmd);
  octave_unused_parameter (file);
  error ("__devtools_spawn__: only needed on Windows, where there is no fork.");

#endif
}
