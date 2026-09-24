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
## @deftypefn  {devtools} {[@var{REPLIES}, @var{S}] =} devtools.__lspDispatch__ (@var{R})
## @deftypefnx {devtools} {[@var{REPLIES}, @var{S}] =} devtools.__lspDispatch__ (@var{R}, @var{S})
##
## Answer one Language Server Protocol message.  Internal; not a supported
## entry point.
##
## @var{R} is a message as @code{devtools.decodeRequest} returns it and
## @var{S} the session state, a new session where it is omitted or empty.
## @var{REPLIES} is a cell array of the response structures to send, empty for
## a notification, and @var{S} the state after the message.  Nothing here
## reads or writes a stream, so the whole protocol is reachable offline.
##
## The state holds the open documents, the position encoding agreed at
## @code{initialize}, and two inventories: the project, the workspace folder
## the client names, and the packages the server was launched with.  The
## project is never put on the load path, @code{addpath} running a folder's
## @file{PKG_ADD}; its names are read from its files instead, and where the
## project and the load path both define a name the project wins, the
## installed copy of a package under development being the stale one.
##
## A method name several classes define is answered only where the class is
## certain: a call to @code{Class.method}, or a method or property of the
## object of the enclosing method, which is the first parameter of a method
## that is not static and the output of a constructor.  Otherwise every
## candidate is listed.  @code{@var{S}.exit} becomes true on @code{exit}, with
## @code{@var{S}.exitCode} 0 after @code{shutdown} and 1 without.
##
## @end deftypefn

function [REPLIES, S] = __lspDispatch__ (R, S)

  if (nargin < 1 || nargin > 2)
    error ("devtools.__lspDispatch__: invalid number of input arguments.");
  endif
  if (! (isstruct (R) && isscalar (R) && isfield (R, "type")))
    error ("devtools.__lspDispatch__: R must be a decoded message.");
  endif
  if (nargin < 2 || isempty (S))
    S = newState ();
  endif

  REPLIES = {};
  switch (R.type)
    case 'blank'
      return;
    case 'invalid'
      if (R.hasid)
        REPLIES = {devtools.jsonrpcError(R.id, R.code, R.message)};
      endif
      return;
  endswitch

  isreq = strcmp (R.type, 'request');
  P = R.params;
  method = R.method;

  if (strcmp (method, 'exit'))
    S.exit = true;
    S.exitCode = double (! S.shutdown);
    return;
  endif
  if (! S.initialized && ! strcmp (method, 'initialize'))
    if (isreq)
      REPLIES = {devtools.jsonrpcError(R.id, -32002, ...
                                       "Server not initialized.")};
    endif
    return;
  endif
  if (S.shutdown && isreq)
    REPLIES = {devtools.jsonrpcError(R.id, -32600, ...
                                     "The server is shutting down.")};
    return;
  endif

  res = [];
  switch (method)
    case 'initialize'
      [res, S] = initialize (P, S);
    case 'shutdown'
      S.shutdown = true;
      res = NaN;
    case 'textDocument/didOpen'
      S = setDoc (S, P.textDocument.uri, P.textDocument.text);
    case 'textDocument/didChange'
      ch = P.contentChanges;
      if (iscell (ch))
        ch = ch{end};
      else
        ch = ch(end);
      endif
      S = setDoc (S, P.textDocument.uri, ch.text);
    case 'textDocument/didClose'
      k = docIndex (S, P.textDocument.uri);
      S.docs(k) = [];
    case 'textDocument/didSave'
      S = reindex (S);
    case 'textDocument/hover'
      res = hover (S, P);
    case 'textDocument/definition'
      res = definition (S, P);
    case 'textDocument/documentSymbol'
      res = documentSymbols (S, P);
    case 'workspace/symbol'
      res = workspaceSymbols (S, P);
    case 'textDocument/completion'
      res = completion (S, P);
    otherwise
      if (isreq)
        REPLIES = {devtools.jsonrpcError(R.id, -32601, ...
                                         sprintf ("Method not found: %s.", ...
                                                  method))};
      endif
      return;
  endswitch

  if (isreq)
    REPLIES = {reply(R.id, res)};
  endif

endfunction

function RESP = reply (id, res)
  RESP = struct ("jsonrpc", "2.0");
  RESP.id = id;
  RESP.result = res;                  # NaN encodes as null
endfunction

function S = newState ()
  S = struct ();
  S.initialized = false;
  S.shutdown = false;
  S.exit = false;
  S.exitCode = 0;
  S.encoding = 'utf-16';
  S.root = '';
  S.project = emptyInventory ();
  S.loaded = emptyInventory ();
  S.docs = struct ("uri", {}, "text", {});
endfunction

function I = emptyInventory ()
  I = struct ("name", {}, "kind", {}, "file", {}, "cls", {});
endfunction

function [res, S] = initialize (P, S)

  ## UTF-8 where the client offers it: the parser counts bytes
  if (isfield (P, "capabilities") && isstruct (P.capabilities) ...
      && isfield (P.capabilities, "general") ...
      && isfield (P.capabilities.general, "positionEncodings"))
    pe = P.capabilities.general.positionEncodings;
    if (iscellstr (pe) && any (strcmp (pe, 'utf-8')))
      S.encoding = 'utf-8';
    endif
  endif

  root = '';
  if (isfield (P, "workspaceFolders") && isstruct (P.workspaceFolders) ...
      && ! isempty (P.workspaceFolders))
    root = uriToPath (P.workspaceFolders(1).uri);
  elseif (isfield (P, "rootUri") && ischar (P.rootUri) && ! isempty (P.rootUri))
    root = uriToPath (P.rootUri);
  elseif (isfield (P, "rootPath") && ischar (P.rootPath))
    root = P.rootPath;
  endif
  if (! isempty (root) && isfolder (root))
    S.root = root;
  endif
  S = reindex (S);
  S.loaded = loadedInventory ();
  S.initialized = true;

  caps = struct ();
  caps.positionEncoding = S.encoding;
  caps.textDocumentSync = struct ("openClose", true, "change", 1, "save", true);
  caps.hoverProvider = true;
  caps.definitionProvider = true;
  caps.documentSymbolProvider = true;
  caps.workspaceSymbolProvider = true;
  caps.completionProvider = struct ();
  caps.completionProvider.triggerCharacters = {'.'};
  res = struct ();
  res.capabilities = caps;
  res.serverInfo = struct ("name", "devtools.lsp", "version", "0.3.0");

endfunction

function S = reindex (S)
  S.project = emptyInventory ();
  if (! isempty (S.root))
    try
      S.project = noProperties (devtools.__pkgInventory__ (S.root));
    catch
    end_try_catch
  endif
endfunction

function I = noProperties (I)
  ## Members here are methods; properties are read from the class file
  I = I(! strcmp ({I.kind}, 'property'));
endfunction

function I = loadedInventory ()
  ## The packages the launch command loaded, read from their folders
  I = emptyInventory ();
  try
    L = pkg ("list");
  catch
    return;
  end_try_catch
  for ii = 1:numel (L)
    if (L{ii}.loaded && isfolder (L{ii}.dir))
      try
        I = [I, noProperties(devtools.__pkgInventory__(L{ii}.dir))];
      catch
      end_try_catch
    endif
  endfor
endfunction

function S = setDoc (S, uri, text)
  k = docIndex (S, uri);
  if (isempty (k))
    k = numel (S.docs) + 1;
  endif
  S.docs(k).uri = uri;
  S.docs(k).text = text;
endfunction

function T = docText (S, uri)
  k = docIndex (S, uri);
  if (isempty (k))
    T = '';
    f = uriToPath (uri);
    if (isfile (f))
      T = fileread (f);
    endif
  else
    T = S.docs(k).text;
  endif
endfunction

function k = docIndex (S, uri)
  ## The open document a URI names, compared as paths: an editor and this
  ## server may spell the same file differently on Windows
  if (isempty (S.docs) || isempty (uri))
    k = [];
    return;
  endif
  want = samePath (uriToPath (uri));
  k = find (strcmp (cellfun (@(u) samePath (uriToPath (u)), {S.docs.uri}, ...
                             "UniformOutput", false), want), 1);
endfunction

function P = samePath (P)
  ## One spelling per file: forward slashes, and any case on Windows
  P = strrep (P, '\', '/');
  if (ispc ())
    P = lower (P);
  endif
endfunction

function P = uriToPath (U)
  P = U;
  if (strncmp (U, 'file://', 7))
    P = U(8:end);
    ## Percent-decoding, byte by byte, so UTF-8 survives
    k = strfind (P, '%');
    if (! isempty (k))
      out = uint8 ([]);
      ii = 1;
      b = uint8 (P);
      while (ii <= numel (b))
        if (b(ii) == 37 && ii + 2 <= numel (b))
          out(end+1) = uint8 (hex2dec (char (b(ii+1:ii+2))));
          ii += 3;
        else
          out(end+1) = b(ii);
          ii += 1;
        endif
      endwhile
      P = char (out);
    endif
    if (numel (P) > 2 && P(1) == '/' && P(3) == ':')
      P = P(2:end);                   # /C:/... on Windows
    endif
  endif
endfunction

function U = pathToUri (P)
  P = strrep (P, '\', '/');
  if (numel (P) > 1 && P(2) == ':')
    P = ['/' P];
  endif
  ## RFC 3986 lets a path carry its sub-delimiters, ':' and '@' bare, so
  ## +namespace and @class folders keep the spelling an editor sends
  b = uint8 (P);
  keep = (b >= 48 & b <= 57) | (b >= 65 & b <= 90) | (b >= 97 & b <= 122) ...
         | ismember (b, uint8 ("/._~-:@!$&'()*+,;="));
  U = 'file://';
  for ii = 1:numel (b)
    if (keep(ii))
      U(end+1) = char (b(ii));
    else
      U = [U sprintf('%%%02X', b(ii))];
    endif
  endfor
endfunction

function L = splitLines (T)
  L = strsplit (T, "\n", "CollapseDelimiters", false);
endfunction

function B = byteCol (line, ch, enc)
  ## A client column to a byte offset in the line
  if (strcmp (enc, 'utf-8'))
    B = min (ch, numel (line));
    return;
  endif
  b = uint8 (line);
  B = 0;
  units = 0;
  while (B < numel (b) && units < ch)
    [n, u] = utf8Width (b(B+1));
    B += n;
    units += u;
  endwhile
  B = min (B, numel (b));
endfunction

function C = charCol (line, B, enc)
  ## A byte offset in the line to a client column
  if (strcmp (enc, 'utf-8'))
    C = B;
    return;
  endif
  b = uint8 (line);
  C = 0;
  ii = 0;
  while (ii < min (B, numel (b)))
    [n, u] = utf8Width (b(ii+1));
    ii += n;
    C += u;
  endwhile
endfunction

function [n, u] = utf8Width (lead)
  ## Bytes in a UTF-8 sequence and the UTF-16 units it takes
  if (lead < 128)
    n = 1;  u = 1;
  elseif (lead >= 240)
    n = 4;  u = 2;
  elseif (lead >= 224)
    n = 3;  u = 1;
  elseif (lead >= 192)
    n = 2;  u = 1;
  else
    n = 1;  u = 1;                    # a stray continuation byte
  endif
endfunction

function R = lspRange (L, srow, scol, erow, ecol, enc)
  R = struct ("start", lspPos (L, srow, scol, enc), ...
              "end", lspPos (L, erow, ecol, enc));
endfunction

function P = lspPos (L, row, col, enc)
  line = '';
  if (row + 1 <= numel (L))
    line = L{row+1};
  endif
  P = struct ("line", row, "character", charCol (line, col, enc));
endfunction

function [T, C, L] = targetsAt (S, P)
  ## The definitions the name under the cursor may refer to, the chain of
  ## syntax enclosing it, and the document's lines
  uri = P.textDocument.uri;
  text = docText (S, uri);
  L = splitLines (text);
  T = noTargets ();
  row = P.position.line;
  line = '';
  if (row + 1 <= numel (L))
    line = L{row+1};
  endif
  C = devtools.__parseAt__ (text, row, byteCol (line, P.position.character, ...
                                                S.encoding));
  if (isempty (C) || ! strcmp (C(1).type, 'identifier'))
    return;
  endif
  X = context (C, uriToPath (uri));
  name = C(1).text;
  parent = struct ("type", '', "text", '', "arg1", '');
  if (numel (C) > 1)
    parent = C(2);
  endif

  ## The name of a definition is that definition
  if (any (strcmp (parent.type, {'function_definition', ...
                                 'classdef_definition', 'property'})) ...
      && strcmp (C(1).field, 'name'))
    T = localTarget (uri, C(1), name);
    return;
  endif

  if (strcmp (parent.type, 'field_expression'))
    if (strcmp (C(1).field, 'field'))
      dotted = regexprep (parent.text, '\s', '');
      if (isempty (regexp (dotted, '^[A-Za-z_]\w*(\.[A-Za-z_]\w*)+$', 'once')))
        return;
      endif
      segs = strsplit (dotted, '.');
      if (! isempty (X.obj) && strcmp (segs{1}, X.obj) && numel (segs) == 2)
        T = memberTargets (S, X.cls, segs{2}, false);
      else
        T = resolveDotted (S, dotted);
      endif
      return;
    endif
    if (! isempty (X.obj) && strcmp (name, X.obj))
      T = resolveDotted (S, X.cls);
      return;
    endif
  endif

  ## A call whose first argument is the object of the enclosing method
  if (strcmp (parent.type, 'index_expression') ...
      && strcmp (C(1).field, 'value') && ! isempty (X.obj) ...
      && strcmp (parent.arg1, X.obj))
    T = memberTargets (S, X.cls, name, true);
    if (! isempty (T))
      return;
    endif
  endif

  if (! isempty (X.obj) && strcmp (name, X.obj))
    T = resolveDotted (S, X.cls);
    return;
  endif
  if (strcmp (C(1).field, 'left'))
    return;                           # an assignment's target is a variable
  endif
  T = resolvePlain (S, name, uri);
endfunction

function X = context (C, file)
  ## The enclosing method's class and object, where there is one
  X = struct ("cls", '', "obj", '');
  kf = find (strcmp ({C.type}, 'function_definition'), 1);
  if (isempty (kf))
    return;
  endif
  F = C(kf);
  kc = find (strcmp ({C.type}, 'classdef_definition'), 1);
  ns = namespaceOf (file);
  if (! isempty (kc))
    X.cls = [ns C(kc).name];
    short = C(kc).name;
  else
    ## A method file in an old-style @class folder
    [folder, base] = fileparts (file);
    [~, cdir] = fileparts (folder);
    if (isempty (cdir) || cdir(1) != '@')
      return;
    endif
    short = cdir(2:end);
    X.cls = [ns short];
    if (! strcmp (F.name, base))
      return;                         # a local function of the method file
    endif
  endif
  if (strcmp (F.name, short))
    if (! isempty (F.outputs))
      X.obj = F.outputs{1};           # the constructor's output
    endif
  elseif (! F.static && ! isempty (F.params))
    X.obj = F.params{1};
  endif
endfunction

function ns = namespaceOf (file)
  parts = strsplit (strrep (fileparts (file), '\', '/'), '/');
  parts = parts(strncmp (parts, '+', 1));
  ns = '';
  for ii = 1:numel (parts)
    ns = [ns parts{ii}(2:end) '.'];
  endfor
endfunction

function T = noTargets ()
  T = struct ("name", {}, "kind", {}, "file", {}, "uri", {}, ...
              "row", {}, "col", {}, "erow", {}, "ecol", {}, "help", {});
endfunction

function T = target (name, kind, file, helpname)
  T = struct ("name", name, "kind", kind, "file", file, "uri", '', ...
              "row", -1, "col", 0, "erow", 0, "ecol", 0, "help", helpname);
endfunction

function T = localTarget (uri, N, name)
  T = target (name, 'definition', uriToPath (uri), '');
  T.uri = uri;
  T.row = N.srow;  T.col = N.scol;
  T.erow = N.erow;  T.ecol = N.ecol;
endfunction

function T = resolvePlain (S, name, uri)
  ## A local function of the document, then the project, then the load path.
  ## A name that classes also define as a method lists them all.
  T = noTargets ();
  D = devtools.__parseDefs__ (docText (S, uri));
  k = find (strcmp ({D.type}, 'function_definition') & [D.parent] == 0 ...
            & strcmp ({D.name}, name), 1);
  if (! isempty (k))
    T = target (name, 'function', uriToPath (uri), '');
    T.uri = uri;
    T.row = D(k).nrow;  T.col = D(k).ncol;
    T.erow = D(k).nerow;  T.ecol = D(k).necol;
    return;
  endif

  own = inventoryTargets (S.project, name);
  if (isempty (own))
    own = pathTarget (name);
    if (isempty (own))
      own = inventoryTargets (S.loaded, name);
    endif
  endif
  T = [own, methodTargets(S, name, own)];
endfunction

function T = resolveDotted (S, dotted)
  ## A class, a namespace function, or Class.method, static or inherited
  T = inventoryTargets (S.project, dotted);
  if (! isempty (T))
    return;
  endif
  T = pathTarget (dotted);
  if (! isempty (T))
    return;
  endif
  T = inventoryTargets (S.loaded, dotted);
  if (! isempty (T))
    return;
  endif
  k = find (dotted == '.', 1, 'last');
  if (! isempty (k))
    T = memberTargets (S, dotted(1:k-1), dotted(k+1:end), false);
  endif
endfunction

function T = inventoryTargets (I, name)
  T = noTargets ();
  k = find (strcmp ({I.name}, name) ...
            & ! strcmp ({I.kind}, 'method'), 1);
  if (isempty (k))
    k = find (strcmp ({I.name}, name), 1);
  endif
  if (! isempty (k))
    T = target (name, I(k).kind, I(k).file, '');
  endif
endfunction

function T = pathTarget (name)
  ## What the load path resolves the name to; a built-in has no file
  T = noTargets ();
  w = '';
  try
    w = which (name);
  catch
  end_try_catch
  if (isempty (w))
    return;
  endif
  if (isfile (w) && ! isempty (regexp (w, '\.m$', 'once')))
    T = target (name, 'function', w, name);
  else
    T = target (name, 'builtin', '', name);
  endif
endfunction

function T = methodTargets (S, name, own)
  ## Every class method of this name, beside what the name itself resolves to
  T = noTargets ();
  for I = {S.project, S.loaded}
    I = I{1};
    m = strcmp ({I.kind}, 'method');
    tail = regexprep ({I(m).name}, '^.*\.', '');
    k = find (m);
    k = k(strcmp (tail, name));
    for jj = k(:)'                    # an empty column would run once
      key = [I(jj).cls '.' name];
      if (any (strcmp ({T.name}, key)))
        continue;
      endif
      T(end+1) = target (key, 'method', I(jj).file, key);
    endfor
  endfor
  T = T(! ismember ({T.name}, {own.name}));
  if (numel (T) + numel (own) < 2)
    T = noTargets ();                 # one definition is not a candidate list
  endif
endfunction

function T = memberTargets (S, cls, member, methodsOnly)
  ## A method or property of a class, looked up its superclass chain
  T = noTargets ();
  seen = {};
  queue = {cls};
  while (! isempty (queue))
    c = queue{1};
    queue(1) = [];
    if (any (strcmp (seen, c)))
      continue;
    endif
    seen{end+1} = c;
    key = [c '.' member];
    for I = {S.project, S.loaded}
      k = find (strcmp ({I{1}.name}, key), 1);
      if (! isempty (k))
        T = target (key, 'method', I{1}(k).file, key);
        return;
      endif
    endfor
    [file, D, kc] = classFile (S, c);
    if (isempty (file))
      w = pathTarget (key);
      if (! isempty (w) && ! strcmp (w.kind, 'builtin'))
        T = w;
        T.kind = 'method';
        return;
      endif
      continue;
    endif
    kids = find ([D.parent] == kc);
    k = kids(strcmp ({D(kids).name}, member));
    if (! isempty (k))
      k = k(1);
      if (methodsOnly && strcmp (D(k).type, 'property'))
        return;
      endif
      kind = 'method';
      if (strcmp (D(k).type, 'property'))
        kind = 'property';
      endif
      T = target (key, kind, file, key);
      T.row = D(k).nrow;  T.col = D(k).ncol;
      T.erow = D(k).nerow;  T.ecol = D(k).necol;
      return;
    endif
    queue = [queue, D(kc).supers];
  endwhile
endfunction

function [file, D, kc] = classFile (S, cls)
  ## The classdef file of a class and its definitions
  file = '';
  D = [];
  kc = 0;
  for I = {S.project, S.loaded}
    k = find (strcmp ({I{1}.name}, cls) & strcmp ({I{1}.kind}, 'class'), 1);
    if (! isempty (k))
      file = I{1}(k).file;
      break;
    endif
  endfor
  if (isempty (file))
    t = pathTarget (cls);
    if (! isempty (t))
      file = t.file;
    endif
  endif
  if (isempty (file) || ! isfile (file))
    file = '';
    return;
  endif
  D = fileDefs (file);
  kc = find (strcmp ({D.type}, 'classdef_definition'), 1);
  if (isempty (kc))
    file = '';
  endif
endfunction

function D = fileDefs (file)
  ## The definitions of a file, kept while the file is unchanged
  persistent keys = {};
  persistent vals = {};
  persistent stamps = [];
  info = dir (file);
  stamp = 0;
  if (! isempty (info))
    stamp = info(1).datenum;
  endif
  k = find (strcmp (keys, file), 1);
  if (! isempty (k) && stamps(k) == stamp)
    D = vals{k};
    return;
  endif
  D = devtools.__parseDefs__ (fileread (file));
  if (isempty (k))
    k = numel (keys) + 1;
  endif
  keys{k} = file;
  vals{k} = D;
  stamps(k) = stamp;
endfunction

function T = locate (S, T)
  ## Fill in the position of each target that lacks one
  for ii = 1:numel (T)
    if (isempty (T(ii).uri) && ! isempty (T(ii).file))
      T(ii).uri = pathToUri (T(ii).file);
    endif
    if (T(ii).row >= 0 || isempty (T(ii).file) || ! isfile (T(ii).file))
      continue;
    endif
    D = defsFor (S, T(ii));
    tail = regexprep (T(ii).name, '^.*\.', '');
    k = [];
    if (strcmp (T(ii).kind, 'class'))
      k = find (strcmp ({D.type}, 'classdef_definition'), 1);
    endif
    if (isempty (k))
      k = find (strcmp ({D.name}, tail), 1);
    endif
    if (isempty (k))
      k = find (strcmp ({D.type}, 'function_definition'), 1);
    endif
    if (isempty (k))
      T(ii).row = 0;
    else
      T(ii).row = D(k).nrow;  T(ii).col = D(k).ncol;
      T(ii).erow = D(k).nerow;  T(ii).ecol = D(k).necol;
    endif
  endfor
endfunction

function D = defsFor (S, T)
  k = docIndex (S, T.uri);
  if (isempty (k))
    D = fileDefs (T.file);
  else
    D = devtools.__parseDefs__ (S.docs(k).text);
  endif
endfunction

function res = hover (S, P)
  res = NaN;
  [T, C, L] = targetsAt (S, P);
  if (isempty (T))
    return;
  endif
  T = locate (S, T);
  if (numel (T) == 1)
    txt = hoverText (S, T);
  else
    names = {T.name};
    txt = sprintf ("%s has %d definitions; the class decides which runs:\n", ...
                   C(1).text, numel (T));
    for ii = 1:numel (T)
      txt = [txt sprintf("  %s\n", names{ii})];
    endfor
    k = find (! strcmp ({T.kind}, 'method'), 1);
    if (! isempty (k))
      txt = [txt "\n" hoverText(S, T(k))];
    endif
  endif
  if (isempty (strtrim (txt)))
    return;
  endif
  res = struct ();
  res.contents = struct ("kind", "plaintext", "value", txt);
  res.range = lspRange (L, C(1).srow, C(1).scol, C(1).erow, C(1).ecol, ...
                        S.encoding);
endfunction

function txt = hoverText (S, T)
  ## The project's own text for its names; the load path's help otherwise
  txt = '';
  if (! isempty (T.file) && isfile (T.file) && T.row >= 0 ...
      && (isempty (T.help) || inProject (S, T.file)))
    txt = fileHelp (S, T);
  endif
  if (isempty (txt) && ! isempty (T.help))
    txt = loadPathHelp (T.help);
  endif
  if (isempty (txt))
    txt = T.name;
  endif
endfunction

function tf = inProject (S, file)
  root = samePath (S.root);
  tf = ! isempty (root) && strncmp (samePath (file), root, numel (root));
endfunction

function txt = fileHelp (S, T)
  ## The texinfo block documenting a definition, rendered as help renders it
  txt = '';
  k = docIndex (S, T.uri);
  if (isempty (k))
    text = fileread (T.file);
  else
    text = S.docs(k).text;
  endif
  L = splitLines (text);
  B = devtools.__texiBlocks__ (L);
  if (isempty (B))
    return;
  endif
  line = T.row + 1;
  ## The block ending just above the definition, blank lines between; else
  ## the first block after it, where a class documents itself
  above = find ([B.last] < line, 1, 'last');
  pick = [];
  if (! isempty (above))
    between = L(B(above).last+1:line-1);
    if (all (cellfun (@(s) isempty (strtrim (s)), between)))
      pick = above;
    endif
  endif
  if (isempty (pick))
    pick = find ([B.first] > line, 1);
    if (! isempty (pick) && ! any (strcmp (T.kind, {'class', 'definition'})))
      gap = L(line+1:B(pick).first-1);
      if (! all (cellfun (@(s) isempty (strtrim (s)), gap)))
        pick = [];
      endif
    endif
  endif
  if (isempty (pick))
    return;
  endif
  raw = L(B(pick).first+1:B(pick).last);
  raw = regexprep (raw, '^\s*(##?|%%?) ?', '');
  body = strjoin (raw, "\n");
  txt = renderTexinfo (body);
endfunction

function txt = renderTexinfo (body)
  persistent keys = {};
  persistent vals = {};
  k = find (strcmp (keys, body), 1);
  if (! isempty (k))
    txt = vals{k};
    return;
  endif
  try
    txt = __makeinfo__ (body, "plain text");
  catch
    txt = body;
  end_try_catch
  keys{end+1} = body;
  vals{end+1} = txt;
endfunction

function txt = loadPathHelp (name)
  ## octave_help's answer, which reads the documentation caches first
  persistent keys = {};
  persistent vals = {};
  k = find (strcmp (keys, name), 1);
  if (! isempty (k))
    txt = vals{k};
    return;
  endif
  meta = ['"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28",' ...
          '"io.modelcontextprotocol/clientCapabilities":{}}'];
  req = ['{"jsonrpc":"2.0","id":1,"method":"tools/call","params":' ...
         '{"name":"octave_help","arguments":{"name":' jsonencode(name) ...
         '},' meta '}}'];
  txt = '';
  try
    RESP = devtools.dispatch (devtools.decodeRequest (req), []);
    if (isfield (RESP, "result") && ! RESP.result.isError)
      txt = RESP.result.content{1}.text;
    endif
  catch
  end_try_catch
  keys{end+1} = name;
  vals{end+1} = txt;
endfunction

function res = definition (S, P)
  res = NaN;
  T = targetsAt (S, P);
  T = locate (S, T);
  T = T(! cellfun (@isempty, {T.uri}));
  if (isempty (T))
    return;
  endif
  locs = cell (1, numel (T));
  for ii = 1:numel (T)
    L = splitLines (docOrFile (S, T(ii)));
    locs{ii} = struct ("uri", T(ii).uri, ...
                       "range", lspRange (L, T(ii).row, T(ii).col, ...
                                          T(ii).erow, T(ii).ecol, S.encoding));
  endfor
  if (numel (locs) == 1)
    res = locs{1};
  else
    res = locs;
  endif
endfunction

function text = docOrFile (S, T)
  k = docIndex (S, T.uri);
  if (isempty (k))
    text = fileread (T.file);
  else
    text = S.docs(k).text;
  endif
endfunction

function res = documentSymbols (S, P)
  text = docText (S, P.textDocument.uri);
  L = splitLines (text);
  D = devtools.__parseDefs__ (text);
  res = symbolChildren (D, 0, L, S.encoding);
endfunction

function out = symbolChildren (D, parent, L, enc)
  out = {};
  for k = find ([D.parent] == parent)
    s = struct ();
    s.name = D(k).name;
    s.kind = symbolKind (D, k);
    s.range = lspRange (L, D(k).srow, D(k).scol, D(k).erow, D(k).ecol, enc);
    s.selectionRange = lspRange (L, D(k).nrow, D(k).ncol, D(k).nerow, ...
                                 D(k).necol, enc);
    s.children = symbolChildren (D, k, L, enc);
    out{end+1} = s;
  endfor
endfunction

function K = symbolKind (D, k)
  ## Class 5, method 6, property 7, constructor 9, function 12
  switch (D(k).type)
    case 'classdef_definition'
      K = 5;
    case 'property'
      K = 7;
    otherwise
      p = D(k).parent;
      if (p > 0 && strcmp (D(p).type, 'classdef_definition'))
        K = 6;
        if (strcmp (D(k).name, D(p).name))
          K = 9;
        endif
      else
        K = 12;
      endif
  endswitch
endfunction

function res = workspaceSymbols (S, P)
  q = '';
  if (isfield (P, "query") && ischar (P.query))
    q = lower (P.query);
  endif
  I = S.project;
  hit = find (cellfun (@(n) isempty (q) || any (strfind (lower (n), q)), ...
                       {I.name}));
  hit = hit(1:min (end, 200));
  res = {};
  for k = hit(:)'
    T = target (I(k).name, I(k).kind, I(k).file, '');
    if (! isfile (T.file))
      continue;
    endif
    T = locate (S, T);
    L = splitLines (fileread (T.file));
    s = struct ();
    s.name = I(k).name;
    s.kind = 12;
    if (strcmp (I(k).kind, 'class'))
      s.kind = 5;
    elseif (strcmp (I(k).kind, 'method'))
      s.kind = 6;
    endif
    rng = lspRange (L, T.row, T.col, T.erow, T.ecol, S.encoding);
    s.location = struct ("uri", T.uri, "range", rng);
    s.containerName = I(k).cls;
    res{end+1} = s;
  endfor
endfunction

function res = completion (S, P)
  uri = P.textDocument.uri;
  text = docText (S, uri);
  L = splitLines (text);
  row = P.position.line;
  line = '';
  if (row + 1 <= numel (L))
    line = L{row+1};
  endif
  b = byteCol (line, P.position.character, S.encoding);
  word = regexp (line(1:b), '[A-Za-z_][\w.]*$', 'match', 'once');
  items = struct ("label", {}, "kind", {});
  if (any (word == '.'))
    k = find (word == '.', 1, 'last');
    head = word(1:k-1);
    part = word(k+1:end);
    C = devtools.__parseAt__ (text, row, max (b - numel (word), 0));
    X = context (C, uriToPath (uri));
    if (! isempty (X.obj) && strcmp (head, X.obj))
      items = memberItems (S, X.cls);
    else
      items = [memberItems(S, head), namespaceItems(S, head)];
    endif
    items = reshape (items(strncmp ({items.label}, part, numel (part))), 1, []);
  elseif (! isempty (word))
    items = plainItems (S, word, text);
  endif
  [~, u] = unique ({items.label}, 'first');
  items = items(sort (u));
  cap = 100;
  res = struct ();
  res.isIncomplete = numel (items) > cap;
  items = items(1:min (end, cap));
  res.items = num2cell (items);
endfunction

function items = memberItems (S, cls)
  ## The methods and properties of a class and its superclasses
  items = struct ("label", {}, "kind", {});
  seen = {};
  queue = {cls};
  while (! isempty (queue))
    c = queue{1};
    queue(1) = [];
    if (any (strcmp (seen, c)))
      continue;
    endif
    seen{end+1} = c;
    ctor = regexprep (c, '^.*\.', '');
    for I = {S.project, S.loaded}
      I = I{1};
      m = strcmp ({I.cls}, c) & strcmp ({I.kind}, 'method');
      for n = regexprep ({I(m).name}, '^.*\.', '')
        if (! strcmp (n{1}, ctor))    # a constructor is no member
          items(end+1) = struct ("label", n{1}, "kind", 2);
        endif
      endfor
    endfor
    [~, D, kc] = classFile (S, c);
    if (kc > 0)
      for k = find ([D.parent] == kc)
        if (strcmp (D(k).name, ctor))
          continue;
        endif
        kind = 2;
        if (strcmp (D(k).type, 'property'))
          kind = 10;
        endif
        items(end+1) = struct ("label", D(k).name, "kind", kind);
      endfor
      queue = [queue, D(kc).supers];
    endif
  endwhile
  items = items(! strncmp ({items.label}, 'get.', 4) ...
                & ! strncmp ({items.label}, 'set.', 4));
  items = reshape (items, 1, []);     # an empty selection comes back 0x1
endfunction

function items = namespaceItems (S, ns)
  ## The functions, classes and namespaces inside a namespace
  items = struct ("label", {}, "kind", {});
  pre = [ns '.'];
  for I = {S.project, S.loaded}
    I = I{1};
    k = strncmp ({I.name}, pre, numel (pre)) & ! strcmp ({I.kind}, 'method');
    for n = {I(k).name}
      rest = n{1}(numel (pre)+1:end);
      if (! any (rest == '.'))
        items(end+1) = struct ("label", rest, "kind", 3);
      endif
    endfor
  endfor
  sub = ['+' strrep(ns, '.', [filesep '+'])];
  for d = strsplit (path (), pathsep)
    f = fullfile (d{1}, sub);
    if (! isfolder (f))
      continue;
    endif
    for e = dir (f)'
      if (e.isdir && numel (e.name) > 1 && e.name(1) == '+')
        items(end+1) = struct ("label", e.name(2:end), "kind", 9);
      elseif (e.isdir && numel (e.name) > 1 && e.name(1) == '@')
        items(end+1) = struct ("label", e.name(2:end), "kind", 7);
      elseif (! e.isdir && ! isempty (regexp (e.name, '\.m$', 'once')))
        items(end+1) = struct ("label", e.name(1:end-2), "kind", 3);
      endif
    endfor
  endfor
endfunction

function items = plainItems (S, word, text)
  items = struct ("label", {}, "kind", {});
  for n = cellstr (completion_matches (word))'
    n = strtrim (n{1});
    if (isempty (n))
      continue;
    endif
    kind = 3;
    if (iskeyword (n))
      kind = 14;
    endif
    items(end+1) = struct ("label", n, "kind", kind);
  endfor
  I = S.project;
  k = strncmp ({I.name}, word, numel (word)) & ! strcmp ({I.kind}, 'method');
  for n = {I(k).name}
    if (! any (n{1} == '.'))
      items(end+1) = struct ("label", n{1}, "kind", 3);
    endif
  endfor
  for n = unique (regexp (text, '[A-Za-z_]\w*', 'match'))
    if (strncmp (n{1}, word, numel (word)) && ! strcmp (n{1}, word))
      items(end+1) = struct ("label", n{1}, "kind", 6);
    endif
  endfor
endfunction

%!shared D
%! D = tempname ();
%! mkdir (D);
%! mkdir (fullfile (D, "inst"));
%! mkdir (fullfile (D, "inst", "+ns"));
%! fid = fopen (fullfile (D, "inst", "K.m"), "w");
%! fputs (fid, ["classdef K < J\n  properties\n    ## -*- texinfo -*-\n", ...
%!   "    ## @deftp {K} {property} P\n    ## The P property.\n", ...
%!   "    ## @end deftp\n    P = 1;\n  endproperties\n  methods\n", ...
%!   "    function obj = K ()\n    endfunction\n    ## -*- texinfo -*-\n", ...
%!   "    ## @deftypefn {K} {@var{y} =} g (@var{obj}, @var{x})\n", ...
%!   "    ## The g of K.\n    ## @end deftypefn\n", ...
%!   "    function y = g (obj, x)\n", ...
%!   "      y = g (obj, x) + obj.P + trace (x) + helper (x) + numel (x);\n", ...
%!   "      z = ns.h (1) + K.s (1);\n    endfunction\n  endmethods\n", ...
%!   "  methods (Static)\n    function r = s (a)\n      r = g (a, 1);\n", ...
%!   "    endfunction\n  endmethods\nendclassdef\n", ...
%!   "function r = helper (x)\n  r = x;\nendfunction\n"]);
%! fclose (fid);
%! fid = fopen (fullfile (D, "inst", "J.m"), "w");
%! fputs (fid, ["classdef J\n  methods\n    function y = g (obj, x)\n", ...
%!              "    endfunction\n  endmethods\nendclassdef\n"]);
%! fclose (fid);
%! fid = fopen (fullfile (D, "inst", "trace.m"), "w");
%! fputs (fid, "function t = trace (x)\n  t = x;\nendfunction\n");
%! fclose (fid);
%! fid = fopen (fullfile (D, "inst", "+ns", "h.m"), "w");
%! fputs (fid, "function y = h (x)\n  y = x;\nendfunction\n");
%! fclose (fid);

%!function R = msg (id, method, params)
%!  m = struct ("jsonrpc", "2.0", "method", method);
%!  if (! isempty (id))
%!    m.id = id;
%!  endif
%!  if (nargin > 2)
%!    m.params = params;
%!  endif
%!  R = devtools.decodeRequest (jsonencode (m));
%!endfunction

%!function U = fileUri (P)
%!  ## As a client writes it: forward slashes, and /C:/ for a drive
%!  P = strrep (P, '\', '/');
%!  if (numel (P) > 1 && P(2) == ':')
%!    P = ['/' P];
%!  endif
%!  U = ["file://" P];
%!endfunction

%!function U = uri (D, name)
%!  U = fileUri (fullfile (D, "inst", name));
%!endfunction

%!function S = session (D, enc)
%!  p = struct ("rootUri", fileUri (D));
%!  p.capabilities = struct ();
%!  if (nargin > 1)
%!    p.capabilities.general = struct ("positionEncodings", {{enc}});
%!  endif
%!  [~, S] = devtools.__lspDispatch__ (msg (1, "initialize", p));
%!endfunction

%!function P = at (U, line, character)
%!  P = struct ("textDocument", struct ("uri", U), ...
%!              "position", struct ("line", line, "character", character));
%!endfunction

%!function res = ask (S, method, P)
%!  REP = devtools.__lspDispatch__ (msg (2, method, P), S);
%!  res = REP{1}.result;
%!endfunction

%!function k = col (D, name, row, needle)
%!  L = strsplit (fileread (fullfile (D, "inst", name)), "\n");
%!  k = strfind (L{row+1}, needle)(1) - 1;
%!endfunction

%!test
%! REP = devtools.__lspDispatch__ (msg (1, "textDocument/hover", ...
%!                                      at ("file:///x.m", 0, 0)));
%! assert_equal (REP{1}.error.code, -32002);

%!test
%! REP = devtools.__lspDispatch__ (msg (1, "initialize", struct ()));
%! assert_equal (REP{1}.result.capabilities.hoverProvider, true);

%!test
%! REP = devtools.__lspDispatch__ (msg (1, "initialize", struct ()));
%! assert_equal (REP{1}.result.capabilities.positionEncoding, "utf-16");

%!test
%! S = session (D, "utf-8");
%! assert_equal (S.encoding, "utf-8");

%!test
%! REP = devtools.__lspDispatch__ (msg (2, "shutdown"), session (D));
%! assert_equal (isnan (REP{1}.result), true);

%!test
%! [~, S] = devtools.__lspDispatch__ (msg (2, "shutdown"), session (D));
%! [~, S] = devtools.__lspDispatch__ (msg ([], "exit"), S);
%! assert_equal (S.exitCode, 0);

%!test
%! [~, S] = devtools.__lspDispatch__ (msg ([], "exit"), session (D));
%! assert_equal (S.exitCode, 1);

%!test
%! [~, S] = devtools.__lspDispatch__ (msg (2, "shutdown"), session (D));
%! REP = devtools.__lspDispatch__ (msg (3, "textDocument/hover", ...
%!                                      at (uri (D, "K.m"), 0, 0)), S);
%! assert_equal (REP{1}.error.code, -32600);

%!test
%! REP = devtools.__lspDispatch__ (msg (2, "textDocument/rename"), session (D));
%! assert_equal (REP{1}.error.code, -32601);

%!test
%! REP = devtools.__lspDispatch__ (msg ([], "$/setTrace"), session (D));
%! assert_equal (REP, {});

%!test
%! REP = devtools.__lspDispatch__ (devtools.decodeRequest ...
%!                                 ('{"jsonrpc":"2.0","id":3}'), session (D));
%! assert_equal (REP{1}.error.code, -32600);

%!test
%! res = ask (session (D), "textDocument/documentSymbol", ...
%!            struct ("textDocument", struct ("uri", uri (D, "K.m"))));
%! assert_equal (cellfun (@(s) s.kind, res), [5, 12]);

%!test
%! res = ask (session (D), "textDocument/documentSymbol", ...
%!            struct ("textDocument", struct ("uri", uri (D, "K.m"))));
%! assert_equal (cellfun (@(s) s.kind, res{1}.children), [7, 9, 6, 6]);

%!test
%! res = ask (session (D), "textDocument/hover", ...
%!            at (uri (D, "K.m"), 16, col (D, "K.m", 16, "g (obj")));
%! assert_equal (any (strfind (res.contents.value, "The g of K.")), true);

%!test
%! res = ask (session (D), "textDocument/definition", ...
%!            at (uri (D, "K.m"), 16, col (D, "K.m", 16, "g (obj")));
%! assert_equal (res.range.start.line, 15);

%!test
%! res = ask (session (D), "textDocument/definition", ...
%!            at (uri (D, "K.m"), 16, col (D, "K.m", 16, "P +")));
%! assert_equal (res.range.start.line, 6);

%!test
%! res = ask (session (D), "textDocument/hover", ...
%!            at (uri (D, "K.m"), 16, col (D, "K.m", 16, "P +")));
%! assert_equal (any (strfind (res.contents.value, "The P property.")), true);

%!test
%! res = ask (session (D), "textDocument/definition", ...
%!            at (uri (D, "K.m"), 17, col (D, "K.m", 17, "s (1)")));
%! assert_equal (res.range.start.line, 21);

%!test
%! res = ask (session (D), "textDocument/definition", ...
%!            at (uri (D, "K.m"), 22, col (D, "K.m", 22, "g (a")));
%! assert_equal (sort (cellfun (@(r) r.uri, res, "UniformOutput", false)), ...
%!               {uri(D, "J.m"), uri(D, "K.m")});

%!test
%! res = ask (session (D), "textDocument/definition", ...
%!            at (uri (D, "K.m"), 16, col (D, "K.m", 16, "trace")));
%! assert_equal (res.uri, uri (D, "trace.m"));

%!test
%! res = ask (session (D), "textDocument/definition", ...
%!            at (uri (D, "K.m"), 16, col (D, "K.m", 16, "helper")));
%! assert_equal (res.range.start.line, 26);

%!test
%! res = ask (session (D), "textDocument/definition", ...
%!            at (uri (D, "K.m"), 16, col (D, "K.m", 16, "numel")));
%! assert_equal (isnan (res), true);

%!test
%! res = ask (session (D), "textDocument/hover", ...
%!            at (uri (D, "K.m"), 16, col (D, "K.m", 16, "numel")));
%! assert_equal (any (strfind (res.contents.value, "numel")), true);

%!test
%! res = ask (session (D), "textDocument/definition", ...
%!            at (uri (D, "K.m"), 17, col (D, "K.m", 17, "h (1)")));
%! assert_equal (res.uri, uri (D, fullfile ("+ns", "h.m")));

%!test
%! res = ask (session (D), "textDocument/definition", ...
%!            at (uri (D, "K.m"), 15, col (D, "K.m", 15, "g (obj")));
%! assert_equal (res.range.start.line, 15);

%!test
%! S = session (D);
%! p = struct ("textDocument", struct ("uri", uri (D, "K.m"), "version", 1, ...
%!                                     "text", "function f ()\nend\n"));
%! [~, S] = devtools.__lspDispatch__ (msg ([], "textDocument/didOpen", p), S);
%! res = ask (S, "textDocument/documentSymbol", ...
%!            struct ("textDocument", struct ("uri", uri (D, "K.m"))));
%! assert_equal (res{1}.name, "f");

%!test
%! S = session (D);
%! p = struct ("textDocument", struct ("uri", uri (D, "K.m"), "version", 1, ...
%!                                     "text", "function f ()\nend\n"));
%! [~, S] = devtools.__lspDispatch__ (msg ([], "textDocument/didOpen", p), S);
%! p = struct ("textDocument", struct ("uri", uri (D, "K.m"), "version", 2));
%! p.contentChanges = {struct("text", "function q ()\nend\n")};
%! [~, S] = devtools.__lspDispatch__ (msg ([], "textDocument/didChange", p), S);
%! res = ask (S, "textDocument/documentSymbol", ...
%!            struct ("textDocument", struct ("uri", uri (D, "K.m"))));
%! assert_equal (res{1}.name, "q");

%!test
%! S = session (D);
%! p = struct ("textDocument", struct ("uri", uri (D, "K.m"), "version", 1, ...
%!                                     "text", "function f ()\nend\n"));
%! [~, S] = devtools.__lspDispatch__ (msg ([], "textDocument/didOpen", p), S);
%! p = struct ("textDocument", struct ("uri", uri (D, "K.m")));
%! [~, S] = devtools.__lspDispatch__ (msg ([], "textDocument/didClose", p), S);
%! res = ask (S, "textDocument/documentSymbol", ...
%!            struct ("textDocument", struct ("uri", uri (D, "K.m"))));
%! assert_equal (res{1}.name, "K");

%!test
%! res = ask (session (D), "workspace/symbol", struct ("query", "tra"));
%! assert_equal (cellfun (@(s) s.name, res, "UniformOutput", false), {"trace"});

%!test
%! res = ask (session (D), "textDocument/completion", ...
%!            at (uri (D, "K.m"), 16, col (D, "K.m", 16, "obj.P") + 4));
%! got = cellfun (@(s) s.label, res.items, "UniformOutput", false);
%! assert_equal (sort (got), {"P", "g", "s"});

%!test
%! res = ask (session (D), "textDocument/completion", ...
%!            at (uri (D, "K.m"), 16, col (D, "K.m", 16, "trace") + 3));
%! got = cellfun (@(s) s.label, res.items, "UniformOutput", false);
%! assert_equal (any (strcmp (got, "trace")), true);

%!test
%! res = ask (session (D), "textDocument/completion", ...
%!            at (uri (D, "K.m"), 17, col (D, "K.m", 17, "ns.") + 3));
%! got = cellfun (@(s) s.label, res.items, "UniformOutput", false);
%! assert_equal (got, {"h"});

%!test
%! S = session (D);
%! p = struct ("textDocument", struct ("uri", uri (D, "U.m"), "version", 1, ...
%!                                     "text", "x = 'αβ'; y = numel (x);\n"));
%! [~, S] = devtools.__lspDispatch__ (msg ([], "textDocument/didOpen", p), S);
%! res = ask (S, "textDocument/hover", at (uri (D, "U.m"), 0, 14));
%! assert_equal (res.range.start.character, 14);

%!test
%! S = session (D, "utf-8");
%! p = struct ("textDocument", struct ("uri", uri (D, "U.m"), "version", 1, ...
%!                                     "text", "x = 'αβ'; y = numel (x);\n"));
%! [~, S] = devtools.__lspDispatch__ (msg ([], "textDocument/didOpen", p), S);
%! res = ask (S, "textDocument/hover", at (uri (D, "U.m"), 0, 16));
%! assert_equal (res.range.start.character, 16);

%!test
%! confirm_recursive_rmdir (false, "local");
%! rmdir (D, "s");

%!error<devtools.__lspDispatch__: invalid number of input arguments.> ...
%! devtools.__lspDispatch__ ()
%!error<devtools.__lspDispatch__: R must be a decoded message.> ...
%! devtools.__lspDispatch__ (5)
