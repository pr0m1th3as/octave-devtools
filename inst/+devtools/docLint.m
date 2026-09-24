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
## @deftypefn  {devtools} {} devtools.docLint (@var{TARGET})
## @deftypefnx {devtools} {@var{R} =} devtools.docLint (@var{TARGET})
##
## Check the documentation of a package against the code it describes.
##
## @code{devtools.docLint (@var{TARGET})} prints every disagreement it finds
## between a package's texinfo blocks and the package itself.  @var{TARGET} is
## either the folder a package's source is in or the name of an installed
## package, which is looked up with @code{pkg ("list")}.
##
## @code{@var{R} = devtools.docLint (@var{TARGET})} prints nothing and returns
## the findings as a structure array holding @code{file}, @code{line},
## @code{rule} and @code{message}, empty where there is nothing to report.
##
## Documentation is the one part of a package that never runs, so no test
## suite reaches it: a name that changed, a cross-reference to something that
## was removed and a line that grew past the margin all survive every test the
## package has.  These are the checks that can be made mechanically.
##
## @table @asis
## @item @qcode{'deftypefn-name'}
## The name a header documents is not the name of the function that follows
## it, or a function file documents a name other than its own.
##
## @item @qcode{'category'}
## The first brace group of a header is not what it should be: the package
## for a function, for the block documenting a class and for the constructor
## of an old-style @@class, the class for a classdef constructor, a method and
## a property.  The package is the name in @file{DESCRIPTION}, never a
## namespace, and the class is named in full, @code{prob.BetaDistribution}
## rather than @code{BetaDistribution}.
##
## @item @qcode{'seealso-target'}
## An @code{@@seealso} names something that is not in this package, not in
## core and not in any package now loaded.
##
## @item @qcode{'seealso-member'}
## An @code{@@seealso} names a class member without its class.  @code{help}
## finds @code{ClassificationTree.margin} and does not find @code{margin}, so
## a bare member tells the reader to type something that does not work.
##
## @item @qcode{'width'}
## A texinfo body line is longer than 80 columns.  Header lines are exempt,
## their signatures being allowed to run over, and so is a line holding
## nothing but a URL, bare or in @code{@@url} or @code{@@uref}, and trailing
## punctuation, a URL having nowhere to break.  A URL sharing its line with
## text is still reported: it moves to a line of its own.
##
## @item @qcode{'index-missing'}
## @file{INDEX} lists a name the package does not supply.
##
## @item @qcode{'index-unlisted'}
## The package supplies a function or a class that @file{INDEX} does not
## list.  @file{INDEX} gates what is cached and published, so an omission is
## how a name is kept off both; this rule reports them so that the omissions
## are the ones that were meant.
## @end table
##
## Skipped throughout are @file{private}, @file{tests} and @file{demos}
## folders, and names wrapped in double underscores, none of which are a
## package's documented surface.  A cross-reference is resolved against what
## is on the load path at the time, so a package whose dependencies are not
## loaded reports references into them as unresolved.
##
## @seealso{devtools.mcp, devtools.selftest}
## @end deftypefn

function R = docLint (TARGET)

  ## Input validation
  if (nargin != 1)
    error ("devtools.docLint: invalid number of input arguments.");
  endif
  if (! (ischar (TARGET) && isrow (TARGET)))
    error ("devtools.docLint: TARGET must be a character vector.");
  endif

  root = __resolveTarget__ (TARGET);
  pkgname = __packageName__ (root);
  INV = devtools.__pkgInventory__ (root);
  if (isempty (INV))
    error ("devtools.docLint: no function files found under '%s'", root);
  endif

  F = struct ("file", {}, "line", {}, "rule", {}, "message", {});
  files = unique ({INV.file});
  for ii = 1:numel (files)
    [~, ~, ext] = fileparts (files{ii});
    if (! strcmp (ext, ".m"))
      continue;
    endif
    F = __checkFile__ (F, files{ii}, INV, pkgname);
  endfor
  F = __checkIndex__ (F, root, INV);

  if (nargout > 0)
    R = F;
    return;
  endif
  __report__ (F, root);

endfunction

function ROOT = __resolveTarget__ (TARGET)

  if (isfolder (TARGET))
    ROOT = TARGET;
    return;
  endif
  installed = pkg ("list");
  for ii = 1:numel (installed)
    if (strcmp (installed{ii}.name, TARGET))
      ROOT = installed{ii}.dir;
      return;
    endif
  endfor
  error (strcat ("devtools.docLint: TARGET is neither a folder nor an", ...
                 " installed package: '%s'"), TARGET);

endfunction

function NAME = __packageName__ (ROOT)

  NAME = '';
  desc = fullfile (ROOT, "DESCRIPTION");
  if (! isfile (desc))
    return;
  endif
  tok = regexp (fileread (desc), '^Name:\s*(\S+)', 'tokens', 'lineanchors', ...
                'once');
  if (! isempty (tok))
    NAME = tok{1};
  endif

endfunction

function F = __checkFile__ (F, FILE, INV, PKGNAME)

  lines = strsplit (strrep (fileread (FILE), "\r\n", "\n"), "\n", ...
                  "CollapseDelimiters", false);
  blocks = devtools.__texiBlocks__ (lines);
  own = INV(strcmp ({INV.file}, FILE));
  cls = '';
  isclassdef = false;
  kc = find (strcmp ({own.kind}, 'class'), 1);
  km = find (strcmp ({own.kind}, 'method'), 1);
  if (! isempty (kc))
    cls = own(kc).name;
    isclassdef = true;
  elseif (! isempty (km))
    cls = own(km).cls;                         # a file in an @class folder
    isclassdef = true;
  endif
  kf = find (strcmp ({INV.name}, cls) & strcmp ({INV.kind}, 'class'), 1);
  folderclass = (! isempty (kf) && isfolder (INV(kf).file));

  for bb = 1:numel (blocks)
    B = blocks(bb);

    ## Lines that run past the margin, headers exempt
    for kk = B.body
      if (numel (lines{kk}) > 80 && ! __urlLine__ (lines{kk}))
        msg = sprintf ("texinfo body line is %d columns.", numel (lines{kk}));
        F = __add__ (F, FILE, kk, 'width', msg);
      endif
    endfor

    ## The name and the category of every header of the block
    [defname, defkind] = __nextDef__ (lines, B.last + 1);
    for hh = 1:numel (B.header)
      idx = B.header{hh};
      text = __joinHeader__ (lines(idx));
      [name, category] = devtools.__texiName__ (text);
      if (isempty (name))
        continue;
      endif
      F = __checkName__ (F, FILE, idx(1), name, defname, defkind, B.kind, ...
                         own, cls, isclassdef);
      F = __checkCategory__ (F, FILE, idx(1), name, category, PKGNAME, ...
                             cls, isclassdef, folderclass, B.kind);
    endfor

    ## Cross-references
    [names, lnum] = devtools.__seealsoNames__ (lines(B.first:B.last));
    for kk = 1:numel (names)
      F = __checkSeealso__ (F, FILE, B.first + lnum(kk) - 1, names{kk}, INV);
    endfor
  endfor

endfunction

function [NAME, KIND] = __nextDef__ (LINES, FROM)

  NAME = '';
  KIND = '';
  keywords = {'properties', 'endproperties', 'methods', 'endmethods', ...
              'classdef', 'endclassdef', 'end', 'events', 'enumeration'};
  for ii = FROM:numel (LINES)
    line = strtrim (LINES{ii});
    if (isempty (line) || strncmp (line, "##", 2) || strncmp (line, "%", 1))
      continue;
    endif
    tok = regexp (line, ...
      '^function\s+(?:\[[^\]]*\]\s*=\s*|[\w.]+\s*=\s*)?([A-Za-z_][\w.]*)', ...
      'tokens', 'once');
    if (! isempty (tok))
      NAME = tok{1};
      KIND = 'function';
      return;
    endif
    word = regexp (line, '^[A-Za-z_]\w*', 'match', 'once');
    if (any (strcmp (word, keywords)))
      continue;                    # a block opener, the definition is past it
    endif
    tok = regexp (line, '^([A-Za-z_]\w*)\s*(?:=[^=]|;|$)', 'tokens', 'once');
    if (! isempty (tok))
      NAME = tok{1};
      KIND = 'property';
    endif
    return;
  endfor

endfunction

function TEXT = __joinHeader__ (LINES)

  TEXT = '';
  for ii = 1:numel (LINES)
    piece = strtrim (regexprep (LINES{ii}, '^\s*##', ''));
    piece = regexprep (piece, '@\s*$', '');
    if (ii == 1)
      TEXT = piece;
    else
      TEXT = [TEXT, " ", piece];
    endif
  endfor

endfunction

function F = __checkName__ (F, FILE, LINE, NAME, DEFNAME, DEFKIND, KIND, ...
                            OWN, CLS, ISCLASSDEF)

  parts = strsplit (NAME, ".");
  tail = parts{end};

  if (ISCLASSDEF && __isClassName__ (NAME, CLS))
    return;                                    # the class's own block
  endif

  if (isempty (DEFNAME))
    return;                                    # nothing follows to compare to
  endif

  if (! strcmp (tail, DEFNAME))
    msg = sprintf ("documents '%s' above %s '%s'.", NAME, DEFKIND, DEFNAME);
    F = __add__ (F, FILE, LINE, 'deftypefn-name', msg);
    return;
  endif

  if (numel (parts) > 1 && ISCLASSDEF)
    qualifier = strjoin (parts(1:end-1), ".");
    if (! strcmp (qualifier, CLS))
      msg = sprintf ("'%s' is a member of '%s'.", NAME, CLS);
      F = __add__ (F, FILE, LINE, 'deftypefn-name', msg);
    endif
    return;
  endif

  if (! ISCLASSDEF && strcmp (DEFKIND, "function"))
    kf = find (strcmp ({OWN.name}, [NAME]), 1);
    if (isempty (kf))
      expected = '';
      for ii = 1:numel (OWN)
        pp = strsplit (OWN(ii).name, ".");
        if (strcmp (pp{end}, DEFNAME))
          expected = OWN(ii).name;
          break;
        endif
      endfor
      if (! isempty (expected) && ! strcmp (expected, NAME))
        msg = sprintf ("documents '%s'; the name is '%s'.", NAME, expected);
        F = __add__ (F, FILE, LINE, 'deftypefn-name', msg);
      endif
    endif
  endif

endfunction

function F = __checkCategory__ (F, FILE, LINE, NAME, CATEGORY, PKGNAME, ...
                                CLS, ISCLASSDEF, FOLDERCLASS, KIND)

  if (isempty (CATEGORY) || strcmp (CATEGORY, "Private Function"))
    return;
  endif
  if (isempty (PKGNAME))
    return;                                    # no DESCRIPTION to check against
  endif

  if (! ISCLASSDEF)
    want = {PKGNAME};
  elseif (__isClassName__ (NAME, CLS) && strcmp (KIND, 'deftp'))
    want = {PKGNAME};                          # the class block
  elseif (__isClassName__ (NAME, CLS) && FOLDERCLASS)
    want = {PKGNAME};                          # an @class constructor
  else
    want = {CLS};
  endif
  if (! any (strcmp (CATEGORY, want)))
    msg = sprintf ("heading is '%s'; expected %s.", CATEGORY, ...
                   __orList__ (want));
    F = __add__ (F, FILE, LINE, 'category', msg);
  endif

endfunction

function F = __checkSeealso__ (F, FILE, LINE, NAME, INV)

  if (any (strcmp ({INV.name}, NAME)))
    return;
  endif

  parts = strsplit (NAME, ".");
  if (numel (parts) > 1)
    qualifier = strjoin (parts(1:end-1), ".");
    if (any (strcmp ({INV.name}, qualifier)))
      msg = sprintf ("'%s' has no member '%s'.", qualifier, parts{end});
      F = __add__ (F, FILE, LINE, 'seealso-target', msg);
      return;
    endif
    if (__onPath__ (qualifier))
      return;                                  # a class from elsewhere
    endif
    F = __add__ (F, FILE, LINE, 'seealso-target', ...
                 sprintf ("'%s' resolves nowhere.", NAME));
    return;
  endif

  if (__onPath__ (NAME))
    return;
  endif

  members = INV(ismember ({INV.kind}, {'method', 'property'}));
  owners = {};
  for ii = 1:numel (members)
    pp = strsplit (members(ii).name, ".");
    if (strcmp (pp{end}, NAME))
      owners{end+1} = members(ii).cls;
    endif
  endfor
  if (! isempty (owners))
    msg = sprintf ("'%s' is a member of %s; write it qualified.", ...
                   NAME, strjoin (unique (owners), ", "));
    F = __add__ (F, FILE, LINE, 'seealso-member', msg);
    return;
  endif

  F = __add__ (F, FILE, LINE, 'seealso-target', ...
               sprintf ("'%s' resolves nowhere.", NAME));

endfunction

function TF = __urlLine__ (LINE)
  pat = strcat ('^\s*[#%]+\s*(?:@(?:url|uref)\{)?', ...
                '[A-Za-z][\w+.-]*://[^\s{}]+\}?[.,;:)]*\s*$');
  TF = ! isempty (regexp (LINE, pat, 'once'));
endfunction

function F = __add__ (F, FILE, LINE, RULE, MSG)
  F(end+1) = struct ("file", FILE, "line", LINE, "rule", RULE, "message", MSG);
endfunction

function TF = __isClassName__ (NAME, CLS)
  parts = strsplit (CLS, ".");
  TF = (strcmp (NAME, CLS) || strcmp (NAME, parts{end}));
endfunction

function TXT = __orList__ (WANT)
  quoted = cellfun (@(w) sprintf ("'%s'", w), WANT, "UniformOutput", false);
  TXT = strjoin (quoted, " or ");
endfunction

function TF = __onPath__ (NAME)
  TF = (exist (NAME, "file") != 0 || exist (NAME, "builtin") != 0);
endfunction

function F = __checkIndex__ (F, ROOT, INV)

  idxfile = fullfile (ROOT, "INDEX");
  if (! isfile (idxfile))
    return;
  endif

  lines = strsplit (strrep (fileread (idxfile), "\r\n", "\n"), "\n", ...
                  "CollapseDelimiters", false);
  listed = {};
  lnum = [];
  for ii = 1:numel (lines)
    line = lines{ii};
    if (isempty (strtrim (line)) || ! isspace (line(1)))
      continue;                                # a heading, not an entry
    endif
    names = strsplit (strtrim (line));
    for kk = 1:numel (names)
      listed{end+1} = regexprep (names{kk}, '^@(\w+)/(\w+)$', '$1.$2');
      lnum(end+1) = ii;
    endfor
  endfor

  for ii = 1:numel (listed)
    if (! any (strcmp ({INV.name}, listed{ii})))
      msg = sprintf ("lists '%s', which the package does not supply.", ...
                     listed{ii});
      F = __add__ (F, idxfile, lnum(ii), 'index-missing', msg);
    endif
  endfor

  for ii = 1:numel (INV)
    if (! any (strcmp (INV(ii).kind, {'function', 'class'})))
      continue;
    endif
    parts = strsplit (INV(ii).name, ".");
    if (__isInternal__ (parts{end}))
      continue;
    endif
    if (! any (strcmp (listed, INV(ii).name)))
      F = __add__ (F, idxfile, 0, 'index-unlisted', ...
                   sprintf ("does not list '%s'.", INV(ii).name));
    endif
  endfor

endfunction

function TF = __isInternal__ (NAME)
  TF = (numel (NAME) > 4 && strncmp (NAME, "__", 2) ...
        && strcmp (NAME(end-1:end), "__"));
endfunction

function __report__ (F, ROOT)

  if (isempty (F))
    printf ("devtools.docLint: %s, nothing to report.\n", ROOT);
    return;
  endif

  files = unique ({F.file});
  for ii = 1:numel (files)
    sel = F(strcmp ({F.file}, files{ii}));
    [~, order] = sort ([sel.line]);
    sel = sel(order);
    printf ("%s\n", __relative__ (files{ii}, ROOT));
    for kk = 1:numel (sel)
      this = sel(kk);
      if (this.line > 0)
        printf ("  %5d  %-15s %s\n", this.line, this.rule, this.message);
      else
        printf ("  %5s  %-15s %s\n", "-", this.rule, this.message);
      endif
    endfor
  endfor

  rules = unique ({F.rule});
  printf ("\n");
  for ii = 1:numel (rules)
    printf ("  %-15s %d\n", rules{ii}, sum (strcmp ({F.rule}, rules{ii})));
  endfor
  printf ("  %-15s %d in %d files\n", "total", numel (F), numel (files));

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
%! mkdir (fullfile (D, "inst"));
%! fid = fopen (fullfile (D, "DESCRIPTION"), "w");
%! fputs (fid, "Name: fixt\nVersion: 1.0.0\n");
%! fclose (fid);
%! fid = fopen (fullfile (D, "inst", "plain.m"), "w");
%! fputs (fid, "## -*- texinfo -*-\n## @deftypefn {fixt} {} plain ()\n##\n");
%! fputs (fid, ["## Clean.\n##\n## @url{https://example.org/", ...
%!              repmat("u", 1, 80), "}.\n##\n"]);
%! fputs (fid, "## @seealso{sin, cls.zzprop}\n## @end deftypefn\n");
%! fputs (fid, "function plain ()\nendfunction\n");
%! fclose (fid);
%! fid = fopen (fullfile (D, "inst", "slip.m"), "w");
%! fputs (fid, "## -*- texinfo -*-\n## @deftypefn {fixt} {} other ()\n##\n");
%! fputs (fid, "## Text.\n##\n## @end deftypefn\n");
%! fputs (fid, "function slip ()\nendfunction\n");
%! fclose (fid);
%! fid = fopen (fullfile (D, "inst", "wide.m"), "w");
%! fputs (fid, "## -*- texinfo -*-\n## @deftypefn {fixt} {} wide ()\n##\n");
%! fputs (fid, ["## ", repmat("w", 1, 90), "\n##\n"]);
%! fputs (fid, ["## See https://example.org/", repmat("u", 1, 80), "\n##\n"]);
%! fputs (fid, "## @end deftypefn\n");
%! fputs (fid, "function wide ()\nendfunction\n");
%! fclose (fid);
%! fid = fopen (fullfile (D, "inst", "dangle.m"), "w");
%! fputs (fid, "## -*- texinfo -*-\n## @deftypefn {fixt} {} dangle ()\n##\n");
%! fputs (fid, "## Text.\n##\n## @seealso{zznowhere}\n## @end deftypefn\n");
%! fputs (fid, "function dangle ()\nendfunction\n");
%! fclose (fid);
%! fid = fopen (fullfile (D, "inst", "bare.m"), "w");
%! fputs (fid, "## -*- texinfo -*-\n## @deftypefn {fixt} {} bare ()\n##\n");
%! fputs (fid, "## Text.\n##\n## @seealso{zzmember}\n## @end deftypefn\n");
%! fputs (fid, "function bare ()\nendfunction\n");
%! fclose (fid);
%! fid = fopen (fullfile (D, "inst", "bareprop.m"), "w");
%! fputs (fid, "## -*- texinfo -*-\n## @deftypefn {fixt} {} bareprop ()\n##\n");
%! fputs (fid, "## Text.\n##\n## @seealso{zzprop}\n## @end deftypefn\n");
%! fputs (fid, "function bareprop ()\nendfunction\n");
%! fclose (fid);
%! fid = fopen (fullfile (D, "inst", "cls.m"), "w");
%! fputs (fid, "## -*- texinfo -*-\n## @deftp {fixt} cls\n##\n## Text.\n##\n");
%! fputs (fid, "## @end deftp\nclassdef cls\n  properties\n    zzprop\n");
%! fputs (fid, "  endproperties\n  methods\n");
%! fputs (fid, "    ## -*- texinfo -*-\n    ## @deftypefn {fixt} {} cls ()\n");
%! fputs (fid, "    ##\n    ## Text.\n    ##\n    ## @end deftypefn\n");
%! fputs (fid, "    function this = cls ()\n    endfunction\n");
%! fputs (fid, "    ## -*- texinfo -*-\n");
%! fputs (fid, "    ## @deftypefn {fixt} {} zzmember (@var{this})\n    ##\n");
%! fputs (fid, "    ## Text.\n    ##\n    ## @end deftypefn\n");
%! fputs (fid, "    function zzmember (this)\n    endfunction\n");
%! fputs (fid, "  endmethods\nendclassdef\n");
%! fclose (fid);
%! mkdir (fullfile (D, "inst", "@oc"));
%! fid = fopen (fullfile (D, "inst", "@oc", "oc.m"), "w");
%! fputs (fid, "## -*- texinfo -*-\n## @deftypefn {fixt} {} oc ()\n##\n");
%! fputs (fid, "## Text.\n##\n## @end deftypefn\n");
%! fputs (fid, "function this = oc ()\n  this = class (struct (), 'oc');\n");
%! fputs (fid, "endfunction\n");
%! fclose (fid);
%! fid = fopen (fullfile (D, "inst", "@oc", "ocm.m"), "w");
%! fputs (fid, "## -*- texinfo -*-\n## @deftypefn {fixt} {} ocm (@var{this})\n");
%! fputs (fid, "##\n## Text.\n##\n## @end deftypefn\n");
%! fputs (fid, "function ocm (this)\nendfunction\n");
%! fclose (fid);
%! fid = fopen (fullfile (D, "INDEX"), "w");
%! fputs (fid, "fixt >> Fixture\nFunctions\n plain slip wide dangle bare bareprop cls oc ghost\n");
%! fclose (fid);

%!test
%! R = devtools.docLint (D);
%! S = R(strcmp ({R.rule}, 'deftypefn-name'));
%! assert_equal (numel (S), 1);
%! assert_equal (S.message, "documents 'other' above function 'slip'.");

%!test
%! R = devtools.docLint (D);
%! S = R(strcmp ({R.rule}, 'width'));
%! assert_equal ([S.line], [4, 6]);

%!test
%! R = devtools.docLint (D);
%! S = R(strcmp ({R.rule}, 'seealso-target'));
%! assert_equal (numel (S), 1);
%! assert_equal (S.message, "'zznowhere' resolves nowhere.");

%!test
%! R = devtools.docLint (D);
%! S = R(strcmp ({R.rule}, 'seealso-member'));
%! msg = {"'zzmember' is a member of cls; write it qualified.", ...
%!        "'zzprop' is a member of cls; write it qualified."};
%! assert_equal ({S.message}, msg);

%!test
%! R = devtools.docLint (D);
%! S = R(strcmp ({R.rule}, 'category'));
%! assert_equal (numel (S), 3);
%! msg = "heading is 'fixt'; expected 'cls'.";
%! assert_equal ({S.message}, {"heading is 'fixt'; expected 'oc'.", msg, msg});

%!test
%! R = devtools.docLint (D);
%! S = R(strcmp ({R.rule}, 'index-missing'));
%! assert_equal (numel (S), 1);
%! assert_equal (S.message, "lists 'ghost', which the package does not supply.");

%!test
%! R = devtools.docLint (D);
%! assert_equal (any (strcmp ({R.rule}, 'index-unlisted')), false);

%!test
%! R = devtools.docLint (D);
%! [~, base] = cellfun (@fileparts, {R.file}, "UniformOutput", false);
%! assert_equal (any (strcmp (base, 'plain')), false);

%!error<devtools.docLint: invalid number of input arguments.> devtools.docLint ()
%!error<devtools.docLint: TARGET must be a character vector.> devtools.docLint (5)
%!error<devtools.docLint: TARGET is neither a folder nor an installed package: 'zznopkg'> ...
%! devtools.docLint ('zznopkg')
