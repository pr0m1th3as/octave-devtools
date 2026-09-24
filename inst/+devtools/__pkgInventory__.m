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
## @deftypefn {devtools} {@var{INV} =} devtools.__pkgInventory__ (@var{ROOT})
##
## List everything a package puts on the load path.  Internal; not a supported
## entry point.
##
## @var{ROOT} is a package's root folder.  @var{INV} is a structure array with
## one element per name, holding @code{name}, the name qualified as a caller
## would write it, @code{kind}, one of @qcode{'function'}, @qcode{'class'},
## @qcode{'method'} and @qcode{'property'}, @code{file}, the file it is defined
## in, and @code{cls}, the class a method or a property belongs to and empty
## otherwise.
##
## Walked are @file{inst} and, for the names an oct-file supplies, the base
## names of the @file{.cc} files in @file{src}.  A @file{+name} folder
## qualifies what is under it, an @file{@@name} folder declares a class whose
## files are its methods, and a file declaring a @code{classdef} contributes
## the class and every method it declares before @code{endclassdef}, so that a
## local helper written under the class is not taken for one, and every
## property a caller can read, which is every property not declared under a
## private or protected @code{Access} or @code{GetAccess}.  Skipped are
## @file{private}, @file{tests} and @file{demos} folders, and every plain
## folder inside a @file{+name} one, since a namespace reaches neither: their
## contents are not on the load path and are not documented as though they
## were.
##
## @end deftypefn

function INV = __pkgInventory__ (ROOT)

  if (nargin != 1)
    error ("devtools.__pkgInventory__: invalid number of input arguments.");
  endif
  if (! (ischar (ROOT) && isrow (ROOT)))
    error ("devtools.__pkgInventory__: ROOT must be a character vector.");
  endif

  INV = struct ("name", {}, "kind", {}, "file", {}, "cls", {});

  instdir = fullfile (ROOT, "inst");
  if (! isfolder (instdir))
    instdir = ROOT;
  endif
  INV = __walk__ (INV, instdir, '', '');

  ## The names the compiled sources supply, which no .m file declares
  srcdir = fullfile (ROOT, "src");
  if (isfolder (srcdir))
    cc = dir (fullfile (srcdir, "*.cc"));
    for ii = 1:numel (cc)
      [~, base] = fileparts (cc(ii).name);
      INV(end+1) = struct ("name", base, "kind", 'function', ...
                           "file", fullfile (srcdir, cc(ii).name), "cls", '');
    endfor
  endif

endfunction

function INV = __walk__ (INV, DIR, PREFIX, CLS)

  entries = dir (DIR);
  for ii = 1:numel (entries)
    name = entries(ii).name;
    if (name(1) == '.')
      continue;
    endif
    path = fullfile (DIR, name);
    if (entries(ii).isdir)
      if (any (strcmp (name, {'private', 'tests', 'demos'})))
        continue;
      elseif (name(1) == '+')
        INV = __walk__ (INV, path, [PREFIX, name(2:end), '.'], '');
      elseif (name(1) == '@')
        cls = [PREFIX, name(2:end)];
        INV(end+1) = struct ("name", cls, "kind", 'class', "file", path, ...
                             "cls", '');
        INV = __walk__ (INV, path, PREFIX, cls);
      elseif (isempty (PREFIX))
        INV = __walk__ (INV, path, PREFIX, CLS);
      endif
      continue;
    endif

    [~, base, ext] = fileparts (name);
    if (! strcmp (ext, ".m"))
      continue;
    endif

    if (! isempty (CLS))
      INV(end+1) = struct ("name", [CLS, '.', base], "kind", 'method', ...
                           "file", path, "cls", CLS);
      continue;
    endif

    txt = fileread (path);
    cd_pat = '^\s*classdef(?![A-Za-z0-9_])';
    if (isempty (regexp (txt, cd_pat, 'lineanchors', 'once')))
      INV(end+1) = struct ("name", [PREFIX, base], "kind", 'function', ...
                           "file", path, "cls", '');
      continue;
    endif

    cls = [PREFIX, base];
    INV(end+1) = struct ("name", cls, "kind", 'class', "file", path, "cls", '');
    end_pat = '^\s*endclassdef(?![A-Za-z0-9_])';
    stop = regexp (txt, end_pat, 'lineanchors', 'start', 'once');
    if (! isempty (stop))
      txt = txt(1:stop);
    endif
    pat = strcat ('^\s*function\s+(?:\[[^\]]*\]\s*=\s*|[\w.]+\s*=\s*)?', ...
                  '([A-Za-z_]\w*)\s*[(\s]');
    m = regexp (txt, pat, 'tokens', 'lineanchors');
    for kk = 1:numel (m)
      INV(end+1) = struct ("name", [cls, '.', m{kk}{1}], "kind", 'method', ...
                           "file", path, "cls", cls);
    endfor
    INV = __properties__ (INV, txt, path, cls);
  endfor

endfunction

function INV = __properties__ (INV, TXT, FILE, CLS)

  ## Every property a caller can read, one per declaration in a block
  attrs = {'Access', 'GetAccess', 'SetAccess', 'Constant', 'Dependent', ...
           'Hidden', 'Abstract', 'Transient', 'AbortSet', 'NonCopyable', ...
           'GetObservable', 'SetObservable'};
  lines = strsplit (strrep (TXT, "\r", ""), "\n", "CollapseDelimiters", false);
  inblock = false;
  public = false;
  incomment = false;
  more = false;
  depth = 0;
  for ii = 1:numel (lines)
    raw = lines{ii};
    if (incomment)
      incomment = isempty (regexp (raw, '^\s*[#%]\}\s*$', 'once'));
      continue;
    elseif (! isempty (regexp (raw, '^\s*[#%]\{\s*$', 'once')))
      incomment = true;
      continue;
    endif

    if (! inblock)
      [s, tok] = regexp (regexprep (raw, '[#%].*$', ''), ...
                         '^\s*properties\s*(?:\(([^)]*)\))?\s*$', ...
                         'start', 'tokens', 'once');
      if (isempty (s))
        continue;
      endif
      [inblock, public] = __blockAttributes__ (tok, attrs);
      more = false;
      depth = 0;
      continue;
    endif

    ## Strings, continuations and comments out, so brackets can be counted
    code = regexprep (raw, '"(?:[^"\\]|\\.)*"', '');
    code = regexprep (code, '(?<=^|[=\s,;(\[{])''[^'']*''', '');
    code = regexprep (code, '[#%].*$', '');
    cont = more;
    k = strfind (code, "...");
    more = ! isempty (k);
    if (more)
      code = code(1:k(1)-1);
    endif

    if (! cont && depth == 0)
      if (! isempty (regexp (code, '^\s*(?:end|endproperties)\s*;?\s*$', ...
                             'once')))
        inblock = false;
        continue;
      endif
      name = regexp (code, '^\s*([A-Za-z_]\w*)', 'tokens', 'once');
      if (public && ! isempty (name))
        INV(end+1) = struct ("name", [CLS, '.', name{1}], ...
                             "kind", 'property', "file", FILE, "cls", CLS);
      endif
    endif
    depth = max (depth + sum (ismember (code, "([{")) ...
                 - sum (ismember (code, ")]}")), 0);
  endfor

endfunction

function [ISBLOCK, PUBLIC] = __blockAttributes__ (TOK, ATTRS)

  ## A properties block, and whether a caller can read what it declares;
  ## anything but attributes in the parentheses is a call, not a block
  ISBLOCK = true;
  PUBLIC = true;
  if (isempty (TOK) || isempty (strtrim (TOK{1})))
    return;
  endif
  for item = strsplit (TOK{1}, ",")
    parts = strsplit (item{1}, "=");
    name = regexprep (strtrim (parts{1}), '^[~!]', '');
    if (! any (strcmp (name, ATTRS)))
      ISBLOCK = false;
      PUBLIC = false;
      return;
    endif
    if (any (strcmp (name, {'Access', 'GetAccess'})) && numel (parts) > 1)
      value = regexprep (strtrim (strjoin (parts(2:end), "=")), '[''"]', '');
      PUBLIC = PUBLIC && strcmp (value, 'public');
    endif
  endfor

endfunction

%!shared D
%! D = tempname ();
%! mkdir (D);
%! mkdir (fullfile (D, "inst"));
%! mkdir (fullfile (D, "inst", "+ns"));
%! mkdir (fullfile (D, "inst", "private"));
%! fid = fopen (fullfile (D, "inst", "plain.m"), "w");
%! fputs (fid, "function plain ()\nendfunction\n");
%! fclose (fid);
%! fid = fopen (fullfile (D, "inst", "cls.m"), "w");
%! fputs (fid, "classdef cls\n");
%! fputs (fid, "  properties (GetAccess = public, SetAccess = protected)\n");
%! fputs (fid, "    Alpha = max (1, ...\n                 eps);\n");
%! fputs (fid, "    Beta   # a comment\n  endproperties\n");
%! fputs (fid, "  properties (Access = private)\n    Gamma\n  endproperties\n");
%! fputs (fid, "  methods\n    function m = one (this)\n");
%! fputs (fid, "    endfunction\n  endmethods\nendclassdef\n");
%! fputs (fid, "function helper ()\nendfunction\n");
%! fclose (fid);
%! fid = fopen (fullfile (D, "inst", "+ns", "inside.m"), "w");
%! fputs (fid, "function inside ()\nendfunction\n");
%! fclose (fid);
%! fid = fopen (fullfile (D, "inst", "private", "hidden.m"), "w");
%! fputs (fid, "function hidden ()\nendfunction\n");
%! fclose (fid);

%!test
%! I = devtools.__pkgInventory__ (D);
%! assert_equal (any (strcmp ({I.name}, 'plain')), true);

%!test
%! I = devtools.__pkgInventory__ (D);
%! assert_equal (any (strcmp ({I.name}, 'ns.inside')), true);

%!test
%! I = devtools.__pkgInventory__ (D);
%! assert_equal (any (strcmp ({I.name}, 'hidden')), false);

%!test
%! I = devtools.__pkgInventory__ (D);
%! assert_equal (I(strcmp ({I.name}, 'cls')).kind, 'class');

%!test
%! I = devtools.__pkgInventory__ (D);
%! assert_equal (any (strcmp ({I.name}, 'cls.one')), true);

%!test
%! I = devtools.__pkgInventory__ (D);
%! assert_equal (any (strcmp ({I.name}, 'cls.helper')), false);

%!test
%! I = devtools.__pkgInventory__ (D);
%! assert_equal (I(strcmp ({I.name}, 'cls.one')).cls, 'cls');

%!test
%! I = devtools.__pkgInventory__ (D);
%! assert_equal (I(strcmp ({I.name}, 'cls.Alpha')).kind, 'property');

%!test
%! I = devtools.__pkgInventory__ (D);
%! assert_equal (I(strcmp ({I.name}, 'cls.Beta')).cls, 'cls');

%!test
%! I = devtools.__pkgInventory__ (D);
%! assert_equal (any (strcmp ({I.name}, 'cls.eps')), false);

%!test
%! I = devtools.__pkgInventory__ (D);
%! assert_equal (any (strcmp ({I.name}, 'cls.Gamma')), false);

%!error<devtools.__pkgInventory__: invalid number of input arguments.> ...
%! devtools.__pkgInventory__ ()
%!error<devtools.__pkgInventory__: ROOT must be a character vector.> ...
%! devtools.__pkgInventory__ (5)
