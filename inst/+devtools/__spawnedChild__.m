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
## @deftypefn {devtools} {} devtools.__spawnedChild__ (@var{d})
##
## Run one call in an interpreter started for it.  Internal; not a supported
## entry point.
##
## Windows has no @code{fork}, so a program server there starts an
## @file{octave-cli} for every call and hands it the folder @var{d}.  This
## loads the packages and adds the folders the server was launched with, reads
## the variables and the code from @file{@var{d}/call}, runs the code in
## @var{d}, and writes what it produced to @file{@var{d}/result}, keeping only
## plain values, as a forked child does.  Its standard output and standard
## error are already @file{@var{d}/output}, set by the process that started it.
##
## @end deftypefn

function __spawnedChild__ (d)

  if (nargin != 1)
    error ("devtools.__spawnedChild__: invalid number of input arguments.");
  endif

  packages = splitEnv ("DEVTOOLS_SANDBOX_PACKAGES", ",");
  for i = 1:numel (packages)
    pkg ("load", packages{i});
  endfor
  folders = splitEnv ("DEVTOOLS_SANDBOX_FOLDERS", pathsep ());
  for i = 1:numel (folders)
    addpath (folders{i});
  endfor

  C = load (fullfile (d, "call"));
  cd (d);
  warning ("off", "Octave:shadowed-function");
  addpath (fullfile (fileparts (mfilename ("fullpath")), "evalshadow"), ...
           "-begin");
  [out, vars, err] = devtools.__evalIn__ (C.W, C.code, 0);
  ## Plain values only: loading an object would run its class's code in the
  ## server.
  names = fieldnames (vars);
  for i = 1:numel (names)
    if (! isPlain (vars.(names{i})))
      vars = rmfield (vars, names{i});
    endif
  endfor
  save ("-binary", fullfile (d, "result"), "out", "err", "vars");

endfunction

## The non-empty parts of an environment variable split at SEP.
function C = splitEnv (name, sep)
  C = strsplit (getenv (name), sep);
  C = C(! cellfun (@isempty, C));
endfunction

function tf = isPlain (v)
  if (isnumeric (v) || islogical (v) || ischar (v))
    tf = true;
  elseif (iscell (v))
    tf = all (cellfun (@isPlain, v(:)));
  elseif (isstruct (v))
    c = struct2cell (v);
    tf = all (cellfun (@isPlain, c(:)));
  else
    tf = false;
  endif
endfunction

%!test
%! ## A call handed over in a folder comes back as a result beside it.
%! d = tempname ();
%! mkdir (d);
%! W = struct ("x", 3);
%! code = "y = x + 1;";
%! save ("-binary", fullfile (d, "call"), "W", "code");
%! here = pwd ();
%! unwind_protect
%!   devtools.__spawnedChild__ (d);
%! unwind_protect_cleanup
%!   cd (here);
%!   warning ("off", "Octave:rmpath-not-found", "local");
%!   rmpath (fullfile (fileparts (which ("devtools.__spawnedChild__")), ...
%!                     "evalshadow"));
%! end_unwind_protect
%! R = load (fullfile (d, "result"));
%! confirm_recursive_rmdir (false, "local");
%! rmdir (d, "s");
%! assert_equal ([R.vars.y, isempty(R.err)], [4, true]);

%!error <devtools\.__spawnedChild__: invalid number of input arguments\.> ...
%! devtools.__spawnedChild__ ()
