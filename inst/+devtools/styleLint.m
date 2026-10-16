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
## @deftypefn  {devtools} {} devtools.styleLint (@var{TARGET})
## @deftypefnx {devtools} {} devtools.styleLint (@var{TARGET}, @var{RULES})
## @deftypefnx {devtools} {@var{R} =} devtools.styleLint (@dots{})
##
## Check code against the layout rules of the Octave packages' coding style.
##
## @code{devtools.styleLint (@var{TARGET})} prints every line that breaks one
## of the rules below.  @var{TARGET} is one file, the folder a package's
## source is in, or the name of an installed package.
##
## @code{devtools.styleLint (@var{TARGET}, @var{RULES})} checks only the rules
## named in @var{RULES}, a cell array of character vectors.  The rules are
## one maintainer's style rather than anything Octave requires, so each can be
## left out.
##
## @code{@var{R} = devtools.styleLint (@dots{})} prints nothing and returns
## the findings as a structure array holding @code{file}, @code{line},
## @code{column}, @code{rule} and @code{message}, empty where there is nothing
## to report.  Columns count characters.
##
## The test blocks are code too: a line opening with @code{%!} is checked as
## the code after its @code{%! } prefix, and the body of a @code{%!function}
## block as the code after @code{%!}, its header sitting there.
##
## @table @asis
## @item @qcode{'tab'}
## A tab character anywhere, inside a string too, where @code{\t} says it
## plainly.
##
## @item @qcode{'indent'}
## Two spaces per level of nesting.  A @code{case} sits two spaces inside its
## @code{switch} and its body four; @code{else}, @code{elseif}, @code{catch},
## @code{unwind_protect_cleanup} and @code{until} sit at the level of the line
## that opened their block.  A comment line takes the level of the next line
## of code, or the level of its own block where that line closes or continues
## the block, as a comment standing alone in a @code{case} does.  A section
## banner, a comment spanning the page from column one, is exempt.  A line
## continuing a statement is not checked, whether @code{...} continues it or
## an open bracket does.
##
## @item @qcode{'quote'}
## Single quotes are the default for a string.  Double quotes are for the
## strings passed to @code{error}, @code{warning}, @code{printf},
## @code{fprintf} and @code{sprintf}, and those are always double, the
## strings of a @code{[]} or a @code{strcat} building one included.  The
## double quotes are for the message text, so the strings of a @code{warning}
## state call, @code{warning ('off', @var{id})} and the like, are single.  A
## double-quoted string holding a backslash escape is accepted anywhere,
## having no single-quoted spelling.
##
## @item @qcode{'length'}
## A line longer than 80 columns.  The lines of a texinfo block are left to
## @code{devtools.docLint}, and the header of an @code{%!error} or
## @code{%!warning} block is exempt, the message it expects having nowhere
## to break.
##
## @item @qcode{'condition'}
## The condition of @code{if}, @code{elseif}, @code{while} and @code{until},
## or the value of @code{switch}, not in parentheses; or a condition running
## over a line with @code{...}, the parentheses continuing it already.
## @end table
##
## A file that does not parse is reported once as @qcode{'syntax'}, with the
## line that stopped it, in place of the rules that read the syntax tree:
## @qcode{'indent'}, @qcode{'quote'} and @qcode{'condition'}.  The test blocks
## are parsed apart from the code, so either can fail alone.
##
## The parser is a compiled file, so this raises where the package was
## installed without a working compiler and a rule reading the syntax tree is
## asked for.
##
## @seealso{devtools.dialectLint, devtools.docLint}
## @end deftypefn

function R = styleLint (TARGET, RULES)

  ## Input validation
  if (nargin < 1 || nargin > 2)
    error ("devtools.styleLint: invalid number of input arguments.");
  endif
  if (! (ischar (TARGET) && isrow (TARGET)))
    error ("devtools.styleLint: TARGET must be a character vector.");
  endif
  known = {'tab', 'indent', 'quote', 'length', 'condition'};
  if (nargin < 2)
    RULES = known;
  endif
  if (! iscellstr (RULES))
    error (strcat ("devtools.styleLint: RULES must be a cell array of", ...
                   " character vectors."));
  endif
  if (isempty (RULES))
    error ("devtools.styleLint: RULES must name at least one rule.");
  endif
  bad = find (! ismember (RULES, known), 1);
  if (! isempty (bad))
    error ("devtools.styleLint: unknown rule: '%s'", RULES{bad});
  endif

  [root, files] = devtools.__resolveTarget__ (TARGET);

  per = cell (1, numel (files));
  for ii = 1:numel (files)
    per{ii} = __lintFile__ (files{ii}, RULES);
  endfor
  F = [struct('file', {}, 'line', {}, 'column', {}, 'rule', {}, ...
              'message', {}), per{:}];

  if (nargout > 0)
    R = F;
    return;
  endif
  __report__ (F, root, files);

endfunction

function F = __lintFile__ (FILE, RULES)

  text = fileread (FILE);
  lines = strsplit (text, "\n", 'CollapseDelimiters', false);
  lines = regexprep (lines, '\r$', '');

  L = zeros (0, 1);
  C = zeros (0, 1);
  K = cell (0, 1);
  M = cell (0, 1);

  if (any (strcmp (RULES, 'tab')))
    [l, c, k, m] = __tabRule__ (lines);
    L = [L; l];  C = [C; c];  K = [K; k];  M = [M; m];
  endif
  if (any (strcmp (RULES, 'length')))
    [l, c, k, m] = __lengthRule__ (lines);
    L = [L; l];  C = [C; c];  K = [K; k];  M = [M; m];
  endif

  tree = intersect (RULES, {'indent', 'quote', 'condition'});
  if (! isempty (tree))
    ## The code, test blocks being comments to it
    istest = strncmp (lines, '%!', 2);
    n = numel (lines);
    [l, c, k, m] = __treeRules__ (lines, lines, zeros (n, 1), ! istest(:), ...
                                  tree);
    L = [L; l];  C = [C; c];  K = [K; k];  M = [M; m];
    ## The test blocks, everything else blank
    if (any (istest))
      [S, base, check] = __testStream__ (lines, istest);
      [l, c, k, m] = __treeRules__ (S, lines, base, check, tree);
      L = [L; l];  C = [C; c];  K = [K; k];  M = [M; m];
    endif
  endif

  [~, order] = sortrows ([L, C]);
  F = struct ('file', FILE, 'line', num2cell (L(order))', ...
              'column', num2cell (zeros (1, numel (L))), ...
              'rule', K(order)', 'message', M(order)');
  for ii = 1:numel (F)
    F(ii).column = __columns__ (lines{F(ii).line}(1:C(order(ii)))) + 1;
  endfor

endfunction

function [L, C, K, M] = __tabRule__ (LINES)

  t = regexp (LINES, "\t", 'once');
  hit = ! cellfun ('isempty', t);
  L = find (hit)(:);
  C = [t{hit}](:) - 1;
  K = repmat ({'tab'}, numel (L), 1);
  M = repmat ({'tab character.'}, numel (L), 1);

endfunction

function [L, C, K, M] = __lengthRule__ (LINES)

  n = cellfun (@__columns__, LINES);
  skip = ! cellfun ('isempty', regexp (LINES, '^%!(error|warning)', 'once'));
  B = devtools.__texiBlocks__ (LINES);
  for ii = 1:numel (B)
    skip(B(ii).first:B(ii).last) = true;
  endfor
  L = find (n > 80 & ! skip)(:);
  C = zeros (numel (L), 1);
  M = cell (numel (L), 1);
  for ii = 1:numel (L)
    b = double (LINES{L(ii)});
    starts = find (b < 128 | b >= 192);
    C(ii) = starts(81) - 1;
    M{ii} = sprintf ("line is %d columns.", n(L(ii)));
  endfor
  K = repmat ({'length'}, numel (L), 1);

endfunction

## The test blocks as code: same rows and byte columns as the file, every
## other line blank, and each block's header reduced to the code it holds:
## none for 'testif' and 'shared', whose headers hold none
function [S, BASE, CHECK] = __testStream__ (LINES, ISTEST)

  kw = {'test', 'xtest', 'testif', 'shared', 'function', 'endfunction', ...
        'assert', 'fail', 'error', 'warning', 'demo'};
  n = numel (LINES);
  S = repmat ({''}, n, 1);
  BASE = zeros (n, 1);
  CHECK = false (n, 1);
  infn = false;
  for r = find (ISTEST(:))'
    s = LINES{r};
    w = regexp (s, '^%!([a-z]+)', 'tokens', 'once');
    if (isempty (w) || ! any (strcmp (w{1}, kw)))
      ## A body line, checked after its prefix
      S{r} = ['  ', s(3:end)];
      CHECK(r) = true;
      BASE(r) = 3 - infn;
      continue;
    endif
    switch (w{1})
      case 'function'
        infn = true;
        S{r} = ['  ', s(3:end)];
      case 'endfunction'
        infn = false;
        S{r} = ['  ', s(3:end)];
      case {'assert', 'fail'}
        S{r} = ['  ', s(3:end)];
      case {'test', 'xtest', 'demo', 'error', 'warning'}
        ## A bug number or an expected message runs to the first '>', as
        ## test reads it, and the code follows
        k = 2 + numel (w{1});
        rest = s(k+1:end);
        e = regexp (rest, '^\s*<[^>]*>', 'end', 'once');
        if (isempty (e) && any (strcmp (w{1}, {'error', 'warning'})))
          e = regexp (rest, '^\s*id=\S*', 'end', 'once');
        endif
        if (isempty (e))
          e = 0;
        endif
        S{r} = [blanks(k + e), rest(e+1:end)];
    endswitch
  endfor

endfunction

function [L, C, K, M] = __treeRules__ (LINES, ORIG, BASE, CHECK, RULES)

  L = zeros (0, 1);
  C = zeros (0, 1);
  K = cell (0, 1);
  M = cell (0, 1);

  S = strjoin (LINES(:)', "\n");
  Q = devtools.__parseQuery__ (S, __query__ ());
  if (! Q.ok)
    P = devtools.__parse__ (S);
    f = P.faults(1);
    L = f.row;
    C = f.column - 1;
    K = {'syntax'};
    M = {strtrim(ORIG{f.row})};
    return;
  endif

  if (any (strcmp (RULES, 'indent')))
    [l, c, k, m] = __indent__ (LINES, BASE, CHECK, Q);
    L = [L; l];  C = [C; c];  K = [K; k];  M = [M; m];
  endif
  if (any (strcmp (RULES, 'quote')))
    [l, c, k, m] = __quote__ (S, Q);
    L = [L; l];  C = [C; c];  K = [K; k];  M = [M; m];
  endif
  if (any (strcmp (RULES, 'condition')))
    [l, c, k, m] = __condition__ (Q);
    L = [L; l];  C = [C; c];  K = [K; k];  M = [M; m];
  endif

endfunction

function QUERY = __query__ ()

  persistent q = '';
  if (isempty (q))
    blocks = {'if_statement', 'for_statement', 'while_statement', ...
              'do_statement', 'switch_statement', 'case_clause', ...
              'otherwise_clause', 'try_statement', ...
              'unwind_protect_statement', 'function_definition', ...
              'classdef_definition', 'properties_block', 'methods_block', ...
              'events_block', 'enumeration_block', 'arguments_block'};
    outdent = {'end', 'endif', 'endfor', 'endparfor', 'endwhile', ...
               'endswitch', 'end_try_catch', 'end_unwind_protect', ...
               'endfunction', 'endclassdef', 'endproperties', 'endmethods', ...
               'endevents', 'endenumeration', 'else', 'elseif', 'catch', ...
               'unwind_protect_cleanup', 'until'};
    q = [sprintf("[%s] @block\n", sprintf ("(%s) ", blocks{:})), ...
         sprintf("[%s] @outdent\n", sprintf ("\"%s\" ", outdent{:})), ...
         '["(" "[" "{"] @open', "\n", ...
         '[")" "]" "}"] @close', "\n", ...
         '(line_continuation) @continuation', "\n", ...
         '(comment) @comment', "\n", ...
         '(string) @string', "\n", ...
         '(if_statement condition: (_) @condition)', "\n", ...
         '(elseif_clause condition: (_) @condition)', "\n", ...
         '(while_statement condition: (_) @condition)', "\n", ...
         '(do_statement condition: (_) @condition)', "\n", ...
         '(switch_statement value: (_) @condition)', "\n", ...
         '[(matrix) (cell)] @literal', "\n", ...
         '(index_expression value: (identifier) @callee', ...
         ' (string) @argument) @call', "\n", ...
         '(index_expression value: (identifier) @callee', ...
         ' (matrix (row (string) @argument))) @call', "\n", ...
         '(index_expression value: (identifier) @callee', ...
         ' (index_expression value: (identifier) @inner', ...
         ' (string) @argument)) @call', "\n", ...
         '(index_expression value: (identifier) @statefn', ...
         ' . (string) @state) @statecall'];
  endif
  QUERY = q;

endfunction

function [L, C, K, M] = __indent__ (LINES, BASE, CHECK, Q)

  n = numel (LINES);
  len = cellfun ('numel', LINES(:));
  rs = [0; cumsum(len(1:end-1) + 1)];
  fb = regexp (LINES(:), '[^ \t]', 'once');
  blank = cellfun ('isempty', fb);
  fb(blank) = {0};
  fb = cell2mat (fb) - 1;
  fb(blank) = -1;

  ## A row continues a statement inside an open bracket, after '...', or
  ## inside a string or a comment running over more than one row
  p = rs + max (fb, 0);
  depth = __below__ (Q.sbyte(strcmp (Q.capture, 'open')), p) ...
          - __below__ (Q.sbyte(strcmp (Q.capture, 'close')), p);
  cont = depth > 0;
  k = Q.srow(strcmp (Q.capture, 'continuation')) + 2;
  cont(k(k <= n)) = true;
  sc = strcmp (Q.capture, 'string') | strcmp (Q.capture, 'comment');
  sc = sc & Q.erow > Q.srow;
  cont = cont | __span__ (Q.srow(sc) + 2, Q.erow(sc) + 1, n);

  ## A row whose first token is a comment
  ic = find (strcmp (Q.capture, 'comment'));
  ic = ic(Q.scol(ic) == fb(Q.srow(ic) + 1));
  comrow = false (n, 1);
  comrow(Q.srow(ic) + 1) = true;
  code = ! blank & ! cont & ! comrow;

  ## Nesting: rows inside a block, less one where a closing or a continuing
  ## keyword opens the row.  A block with no closing keyword, a case, ends
  ## at the start of the row after it, its terminators being its own.
  ib = find (strcmp (Q.capture, 'block'));
  last = Q.erow(ib) - (Q.ecol(ib) == 0 & Q.erow(ib) > Q.srow(ib));
  level = double (__count__ (Q.srow(ib) + 2, last + 1, n));
  io = find (strcmp (Q.capture, 'outdent'));
  io = io(Q.scol(io) == fb(Q.srow(io) + 1));
  level(Q.srow(io) + 1) -= 1;
  closer = false (n, 1);
  closer(Q.srow(io) + 1) = true;
  icase = ib(strcmp (Q.type(ib), 'case_clause')
             | strcmp (Q.type(ib), 'otherwise_clause'));
  icase = icase(Q.scol(icase) == fb(Q.srow(icase) + 1));
  closer(Q.srow(icase) + 1) = true;

  ## A comment line takes the level of the next line of code, or its own
  ## block's where that line closes or continues the block
  rows = find (code);
  lev = level;
  cr = find (comrow);
  if (isempty (rows))
    j = ones (size (cr));
  else
    j = lookup (rows, cr) + 1;
  endif
  lev(cr) = 0;
  has = j <= numel (rows);
  lev(cr(has)) = level(rows(j(has)));
  own = false (n, 1);
  own(cr(has)) = closer(rows(j(has)));

  ## A section banner spans the page from column one
  banner = regexp (LINES(:), '^(#{10,}|##.*##)\s*$', 'once');
  banner = comrow & ! cellfun ('isempty', banner);

  want = BASE + 2 * lev;
  tabbed = ! cellfun ('isempty', regexp (LINES(:), '^ *\t', 'once'));
  hit = CHECK & (code | comrow) & ! banner & ! tabbed & fb != want;
  hit = find (hit & ! (own & fb == BASE + 2 * level));
  L = hit;
  C = zeros (numel (hit), 1);
  K = repmat ({'indent'}, numel (hit), 1);
  M = cell (numel (hit), 1);
  for ii = 1:numel (hit)
    M{ii} = sprintf ("indented to column %d, expected column %d.", ...
                     fb(hit(ii)) + 1, want(hit(ii)) + 1);
  endfor

endfunction

function [L, C, K, M] = __quote__ (S, Q)

  is = find (strcmp (Q.capture, 'string'));
  sb = Q.sbyte(is);
  dq = (S(sb + 1) == '"')(:);

  ## Strings passed to a message function, directly, inside a [] or inside
  ## a strcat that is itself passed to one
  msgfun = {'error', 'warning', 'printf', 'fprintf', 'sprintf'};
  ia = find (strcmp (Q.capture, 'argument'));
  ic = find (strcmp (Q.capture, 'callee'));
  in = find (strcmp (Q.capture, 'inner'));
  [~, jc] = ismember (Q.match(ia), Q.match(ic));
  callee = __texts__ (S, Q, ic(jc));
  ok = ismember (callee, msgfun);
  [hasin, ji] = ismember (Q.match(ia), Q.match(in));
  inner = repmat ({''}, numel (ia), 1);
  inner(hasin) = __texts__ (S, Q, in(ji(hasin)));
  ok = ok & (! hasin | strcmp (inner, 'strcat'));

  ## A warning state call carries no message: its strings take single quotes
  ik = find (strcmp (Q.capture, 'call'));
  [~, jk] = ismember (Q.match(ia), Q.match(ik));
  is1 = find (strcmp (Q.capture, 'state'));
  if1 = find (strcmp (Q.capture, 'statefn'));
  iq = find (strcmp (Q.capture, 'statecall'));
  st = lower (regexprep (__texts__ (S, Q, is1), '^[''"]|[''"]$', ''));
  [~, jf] = ismember (Q.match(is1), Q.match(if1));
  [~, jq] = ismember (Q.match(is1), Q.match(iq));
  isstate = strcmp (__texts__ (S, Q, if1(jf)), 'warning') ...
            & ismember (st, {'on', 'off', 'query', 'error'});
  ok = ok & ! ismember (Q.sbyte(ik(jk)), Q.sbyte(iq(jq(isstate))));
  [inmsg, jm] = ismember (sb, Q.sbyte(ia(ok)));
  who = callee(ok);

  esc = false (numel (is), 1);
  for ii = find (dq & ! inmsg)'
    esc(ii) = any (S(sb(ii)+2:Q.ebyte(is(ii))-1) == '\');
  endfor

  bad1 = find (dq & ! inmsg & ! esc);
  bad2 = find (! dq & inmsg);
  hit = [bad1; bad2];
  L = Q.srow(is(hit)) + 1;
  C = Q.scol(is(hit));
  K = repmat ({'quote'}, numel (hit), 1);
  M = [repmat({'double-quoted string where single quotes are the default.'}, ...
              numel (bad1), 1);
       cellfun(@(f) sprintf ("single-quoted string passed to %s.", f), ...
               who(jm(bad2)), 'UniformOutput', false)];

endfunction

function [L, C, K, M] = __condition__ (Q)

  ic = find (strcmp (Q.capture, 'condition'));
  bare = ic(! strcmp (Q.type(ic), 'parenthesized_expression'));
  L = Q.srow(bare) + 1;
  C = Q.scol(bare);
  M = repmat ({'condition not in parentheses.'}, numel (bare), 1);

  ## Inside a [] or a {} the continuation is optional, condition or not
  ik = find (strcmp (Q.capture, 'continuation'));
  inside = false (numel (ik), 1);
  for ii = ic(:)'
    inside |= Q.sbyte(ik) >= Q.sbyte(ii) & Q.sbyte(ik) < Q.ebyte(ii);
  endfor
  ik = ik(inside);
  for ii = find (strcmp (Q.capture, 'literal'))'
    if (isempty (ik))
      break;
    endif
    ik = ik(! (Q.sbyte(ik) >= Q.sbyte(ii) & Q.sbyte(ik) < Q.ebyte(ii)));
  endfor
  L = [L; Q.srow(ik) + 1];
  C = [C; Q.scol(ik)];
  M = [M; repmat({'line continuation inside a condition.'}, numel (ik), 1)];
  K = repmat ({'condition'}, numel (L), 1);

endfunction

## How many of the sorted-or-not values in V lie strictly below each of P
function N = __below__ (V, P)
  if (isempty (V))
    N = zeros (size (P));
  else
    N = lookup (sort (V), P - 0.5);
  endif
endfunction

## Per row, how many of the ranges A(i):B(i) cover it
function N = __count__ (A, B, n)
  keep = A <= B;
  d = accumarray ([A(keep); B(keep) + 1], ...
                  [ones(nnz (keep), 1); -ones(nnz (keep), 1)], [n + 1, 1]);
  N = cumsum (d)(1:n);
endfunction

function TF = __span__ (A, B, n)
  TF = __count__ (A, B, n) > 0;
endfunction

function T = __texts__ (S, Q, IDX)
  T = arrayfun (@(i) S(Q.sbyte(i)+1:Q.ebyte(i)), IDX(:), ...
                'UniformOutput', false);
endfunction

## Characters, not bytes: a UTF-8 continuation byte starts no character
function N = __columns__ (LINE)
  b = double (LINE);
  N = sum (b < 128 | b >= 192);
endfunction

function __report__ (F, ROOT, FILES)

  if (isempty (F))
    ## One file is named as itself, not by the folder it sits in
    if (numel (FILES) == 1)
      printf ("devtools.styleLint: %s, nothing to report.\n", FILES{1});
    else
      printf ("devtools.styleLint: %s, nothing to report.\n", ROOT);
    endif
    return;
  endif

  files = unique ({F.file});
  for ii = 1:numel (files)
    sel = F(strcmp ({F.file}, files{ii}));
    printf ("%s\n", __relative__ (files{ii}, ROOT));
    for kk = 1:numel (sel)
      printf ("  %5d:%-4d %-10s %s\n", sel(kk).line, sel(kk).column, ...
              sel(kk).rule, sel(kk).message);
    endfor
  endfor

  rules = unique ({F.rule});
  printf ("\n");
  for ii = 1:numel (rules)
    printf ("  %-10s %d\n", rules{ii}, sum (strcmp ({F.rule}, rules{ii})));
  endfor
  printf ("  %-10s %d in %d of %d files\n", "total", numel (F), ...
          numel (files), numel (FILES));

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

%!function __styleLintFixture__ (DIR, NAME, LINES)
%!  fid = fopen (fullfile (DIR, NAME), 'w');
%!  fputs (fid, strjoin (LINES, "\n"));
%!  fclose (fid);
%!endfunction

%!shared SLD
%! SLD = tempname ();
%! mkdir (SLD);
%! __styleLintFixture__ (SLD, 'clean.m', {'function y = f (x)', ...
%!   '  ## A comment', '  switch (x)', '    case 1', '      y = [1, ...', ...
%!   '        2];', '    case 2', '      ## Nothing to do', '    otherwise', ...
%!   '      y = {''a'', ...', '           ''b''};', '  endswitch', ...
%!   '  if (x > 1 &&', '      x < 3)', ...
%!   '    error ("f: X %s.", strcat ("is", " bad"));', ...
%!   '  else', '    y = strsplit (x, "\n");', '    ## Split', '  endif', ...
%!   '  warning (''off'', ''all'', ''local'');', 'endfunction', ...
%!   '%!test', '%! if (true)', '%!   y = 1;', '%! endif', ...
%!   '%!function z = g ()', '%!  z = 1;', '%!endfunction', ...
%!   '%!error <f: X is bad.> f (2)', ''});
%! __styleLintFixture__ (SLD, 'tab.m', {['x = ''a', char(9), 'b'';'], ''});
%! __styleLintFixture__ (SLD, 'long.m', {['x = 1;  # ', repmat('w', 1, 71)], ...
%!   ['%!error <', repmat('w', 1, 80), '> f ()'], ''});
%! __styleLintFixture__ (SLD, 'indent.m', {'if (a)', '   x = 1;', ...
%!   '  ## A comment', '  y = 2;', '## Misplaced', '  z = 3;', 'endif', ...
%!   '%!test', '%!  z = 3;', ''});
%! __styleLintFixture__ (SLD, 'quote.m', {'x = "a";', ...
%!   'error (''m: bad.'');', 'c = {"a", ''b''};', 'printf (["a", "b"]);', ...
%!   'warning ("off", ''all'');', ''});
%! __styleLintFixture__ (SLD, 'condition.m', {'if a', '  x = 1;', ...
%!   'endif', 'while (a && ...', '       b)', '  x = 2;', 'endwhile', ...
%!   'switch x', '  case 1', 'endswitch', ''});
%! __styleLintFixture__ (SLD, 'broken.m', {'x = (1;', ''});

%!test
%! R = devtools.styleLint (fullfile (SLD, 'clean.m'));
%! assert_equal (isempty (R), true);

%!test
%! R = devtools.styleLint (fullfile (SLD, 'tab.m'));
%! assert_equal ({R.rule, R.line, R.column}, {'tab', 1, 7});

%!test
%! R = devtools.styleLint (fullfile (SLD, 'long.m'));
%! assert_equal ({R.rule, R.line, R.column}, {'length', 1, 81});

%!test
%! R = devtools.styleLint (fullfile (SLD, 'long.m'));
%! assert_equal (R.message, 'line is 81 columns.');

%!test
%! R = devtools.styleLint (fullfile (SLD, 'indent.m'));
%! assert_equal ([R.line], [2, 5, 9]);

%!test
%! R = devtools.styleLint (fullfile (SLD, 'indent.m'));
%! assert_equal (R(1).message, 'indented to column 4, expected column 3.');

%!test
%! R = devtools.styleLint (fullfile (SLD, 'indent.m'));
%! assert_equal (R(2).message, 'indented to column 1, expected column 3.');

%!test
%! R = devtools.styleLint (fullfile (SLD, 'indent.m'));
%! assert_equal (R(3).message, 'indented to column 5, expected column 4.');

%!test
%! R = devtools.styleLint (fullfile (SLD, 'quote.m'));
%! assert_equal ([R.line; R.column], [1, 2, 3, 5; 5, 8, 6, 10]);

%!test
%! R = devtools.styleLint (fullfile (SLD, 'quote.m'));
%! assert_equal (R(2).message, 'single-quoted string passed to error.');

%!test
%! R = devtools.styleLint (fullfile (SLD, 'quote.m'));
%! assert_equal (R(3).message, ...
%!               'double-quoted string where single quotes are the default.');

%!test
%! R = devtools.styleLint (fullfile (SLD, 'condition.m'));
%! assert_equal ([R.line; R.column], [1, 4, 8; 4, 13, 8]);

%!test
%! R = devtools.styleLint (fullfile (SLD, 'condition.m'));
%! assert_equal (R(2).message, 'line continuation inside a condition.');

%!test
%! R = devtools.styleLint (fullfile (SLD, 'broken.m'));
%! assert_equal ({R.rule, R.message}, {'syntax', 'x = (1;'});

%!test
%! R = devtools.styleLint (fullfile (SLD, 'broken.m'), {'tab'});
%! assert_equal (isempty (R), true);

%!test
%! R = devtools.styleLint (fullfile (SLD, 'quote.m'), {'tab', 'condition'});
%! assert_equal (isempty (R), true);

%!test
%! R = devtools.styleLint (SLD);
%! assert_equal (numel (unique ({R.file})), 6);

%!test
%! f = fullfile (SLD, 'clean.m');
%! out = evalc ('devtools.styleLint (f)');
%! assert_equal (out, ...
%!               sprintf ("devtools.styleLint: %s, nothing to report.\n", f));

%!error<devtools.styleLint: invalid number of input arguments.> ...
%! devtools.styleLint ()
%!error<devtools.styleLint: TARGET must be a character vector.> ...
%! devtools.styleLint (5)
%!error<devtools.styleLint: RULES must be a cell array of character vectors.> ...
%! devtools.styleLint (pwd (), 'tab')
%!error<devtools.styleLint: RULES must name at least one rule.> ...
%! devtools.styleLint (pwd (), {})
%!error<devtools.styleLint: unknown rule: 'klingon'> ...
%! devtools.styleLint (pwd (), {'klingon'})
