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
## @deftypefn  {devtools} {} devtools.dialectLint (@var{TARGET})
## @deftypefnx {devtools} {} devtools.dialectLint (@var{TARGET}, @var{DIALECT})
## @deftypefnx {devtools} {@var{R} =} devtools.dialectLint (@dots{})
##
## Check which language a file is written in.
##
## @code{devtools.dialectLint (@var{TARGET})} prints every file that is not
## written in Octave's own dialect.  @var{TARGET} is one file, the folder a
## package's source is in, or the name of an installed package.
##
## @code{devtools.dialectLint (@var{TARGET}, @qcode{'matlab'})} asks the other
## question instead: whether MATLAB would accept the file.  That is the check
## to run on a probe before it is sent to a MATLAB machine, where Octave-only
## syntax fails with a message naming nothing useful.
##
## @code{@var{R} = devtools.dialectLint (@dots{})} prints nothing and returns
## the findings as a structure array holding @code{file}, @code{line},
## @code{column}, @code{rule} and @code{message}, empty where there is nothing
## to report.
##
## A file is read twice.  Where it does not parse at all the finding is
## @qcode{'syntax'} and names a fault the file has in any dialect; where it
## parses but the dialect refuses it the finding is @qcode{'dialect-octave'}
## or @qcode{'dialect-matlab'} and carries the line that stopped it.  The two
## are kept apart because a broken file is not a dialect question.
##
## The two names are the two @code{devtools.__parse__} takes, and there is no
## lenient mode here: whether a file parses as either language is not a
## dialect question, and is reported as @qcode{'syntax'} instead.
##
## @table @asis
## @item @qcode{'octave'}
## Octave's own dialect: @code{#} comments, @code{!} and @code{!=}, and the
## typed block terminators.  A file that passes is one MATLAB cannot read.
## The two spellings Octave has no alternative for are still accepted, a
## @code{~} standing for an ignored output and @code{%!} opening a test block.
##
## @item @qcode{'matlab'}
## MATLAB's: @code{%} comments, @code{~} and @code{~=}, and a bare @code{end}.
## Rejected are the constructs Octave alone has, among them
## @code{do @dots{} until}, @code{unwind_protect}, compound assignment,
## @code{++}, an index chained onto a call and an assignment used as an
## expression.
## @end table
##
## The parser is a compiled file, so this raises where the package was
## installed without a working compiler rather than reporting a file clean
## because nothing read it.
##
## @seealso{devtools.docLint}
## @end deftypefn

function R = dialectLint (TARGET, DIALECT = 'octave')

  ## Input validation
  if (nargin < 1 || nargin > 2)
    error ("devtools.dialectLint: invalid number of input arguments.");
  endif
  if (! (ischar (TARGET) && isrow (TARGET)))
    error ("devtools.dialectLint: TARGET must be a character vector.");
  endif
  if (! (ischar (DIALECT) && isrow (DIALECT)))
    error ("devtools.dialectLint: DIALECT must be a character vector.");
  endif
  if (! any (strcmp (DIALECT, {'octave', 'matlab'})))
    error ("devtools.dialectLint: DIALECT must be 'octave' or 'matlab'.");
  endif

  rule = ["dialect-" DIALECT];

  [root, files] = devtools.__resolveTarget__ (TARGET);

  F = struct ("file", {}, "line", {}, "column", {}, "rule", {}, "message", {});
  for ii = 1:numel (files)
    text = fileread (files{ii});
    lines = strsplit (strrep (text, "\r\n", "\n"), "\n", ...
                      "CollapseDelimiters", false);

    ## A file that does not parse at all is broken, not in the wrong dialect
    loose = devtools.__parse__ (text);
    if (! loose.ok)
      F = __add__ (F, files{ii}, loose.faults(1), 'syntax', lines);
      continue;
    endif

    tight = devtools.__parse__ (text, DIALECT);
    if (! tight.ok)
      F = __add__ (F, files{ii}, tight.faults(1), rule, lines);
    endif
  endfor

  if (nargout > 0)
    R = F;
    return;
  endif
  __report__ (F, root, DIALECT);

endfunction

function F = __add__ (F, FILE, FAULT, RULE, LINES)

  text = '';
  if (FAULT.row >= 1 && FAULT.row <= numel (LINES))
    text = strtrim (LINES{FAULT.row});
  endif
  F(end+1) = struct ("file", FILE, "line", FAULT.row, "column", FAULT.column,
                     "rule", RULE, "message", text);

endfunction

function __report__ (F, ROOT, DIALECT)

  if (isempty (F))
    printf ("devtools.dialectLint: %s, every file is %s.\n", ROOT, ...
            ifelse (strcmp (DIALECT, "octave"), "Octave's own", ...
                    "readable by MATLAB"));
    return;
  endif

  for ii = 1:numel (F)
    printf ("  %5d  %-15s %s\n", F(ii).line, F(ii).rule, ...
            __relative__ (F(ii).file, ROOT));
    if (! isempty (F(ii).message))
      printf ("         %s\n", F(ii).message);
    endif
  endfor

  rules = unique ({F.rule});
  printf ("\n");
  for ii = 1:numel (rules)
    printf ("  %-15s %d\n", rules{ii}, sum (strcmp ({F.rule}, rules{ii})));
  endfor
  printf ("  %-15s %d of %d files\n", "total", numel (F), numel (F));

endfunction

function OUT = ifelse (COND, A, B)
  if (COND)
    OUT = A;
  else
    OUT = B;
  endif
endfunction

function REL = __relative__ (FILE, ROOT)
  REL = FILE;
  if (strncmp (FILE, ROOT, numel (ROOT)))
    REL = FILE(numel (ROOT)+1:end);
    if (! isempty (REL) && (REL(1) == filesep () || REL(1) == '/'))
      REL = REL(2:end);
    endif
  endif
endfunction

%!shared D
%! D = tempname ();
%! mkdir (D);
%! fid = fopen (fullfile (D, "octave_dialect.m"), "w");
%! fputs (fid, "# a comment\nif (a)\n  x = !b;\nendif\n");
%! fclose (fid);
%! fid = fopen (fullfile (D, "matlab_dialect.m"), "w");
%! fputs (fid, "% a comment\nif (a)\n  x = ~b;\nend\n");
%! fclose (fid);
%! fid = fopen (fullfile (D, "broken.m"), "w");
%! fputs (fid, "x = (1;\n");
%! fclose (fid);

%!test
%! R = devtools.dialectLint (fullfile (D, "octave_dialect.m"));
%! assert_equal (isempty (R), true);

%!test
%! R = devtools.dialectLint (fullfile (D, "matlab_dialect.m"));
%! assert_equal (numel (R), 1);
%! assert_equal (R.rule, 'dialect-octave');

%!test
%! R = devtools.dialectLint (fullfile (D, "matlab_dialect.m"), "matlab");
%! assert_equal (isempty (R), true);

%!test
%! R = devtools.dialectLint (fullfile (D, "octave_dialect.m"), "matlab");
%! assert_equal (numel (R), 1);
%! assert_equal (R.rule, 'dialect-matlab');

%!test
%! R = devtools.dialectLint (fullfile (D, "broken.m"));
%! assert_equal (R.rule, 'syntax');

%!test
%! R = devtools.dialectLint (fullfile (D, "matlab_dialect.m"));
%! assert_equal (R.line, 1);

%!error<devtools.dialectLint: invalid number of input arguments.> ...
%! devtools.dialectLint ()
%!error<devtools.dialectLint: TARGET must be a character vector.> ...
%! devtools.dialectLint (5)
%!error<devtools.dialectLint: DIALECT must be 'octave' or 'matlab'.> ...
%! devtools.dialectLint (pwd (), 'klingon')
