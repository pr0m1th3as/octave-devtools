## Copyright (C) 2026 Andreas Bertsatos <abertsatos@biol.uoa.gr>
##
## This file is part of the mcp package for GNU Octave.
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
## @deftypefn  {mcp} {@var{RESP} =} mcp.dispatch (@var{R})
## @deftypefnx {mcp} {[@var{RESP}, @var{S}] =} mcp.dispatch (@var{R}, @var{S})
##
## Answer one decoded request.
##
## @code{@var{RESP} = mcp.dispatch (@var{R})} takes the structure returned by
## @code{mcp.decodeRequest} and returns the response structure to send, or the
## empty matrix when nothing is to be sent.  A notification and a blank line are
## the two cases that produce no response, and a notification producing one
## would be a protocol violation rather than a nuisance.
##
## @code{[@var{RESP}, @var{S}] = mcp.dispatch (@var{R}, @var{S})} threads the
## session structure @var{S} through the call and returns it updated.  Pass the
## empty matrix for the first request of a connection.
##
## This function touches no stream.  Every method, every error path and every
## tool result can be obtained by handing it a structure and reading what comes
## back, with no client, no subprocess and no server running, which is what
## makes the whole protocol surface reachable by a test.
##
## @var{S} carries the only state this package keeps, and it keeps it because a
## client may speak either of two protocol eras and the choice is made once:
##
## @table @code
## @item era
## @qcode{"unknown"} until the client opens.  A request carrying per-request
## metadata makes it @qcode{"modern"}, and an @code{initialize} request makes it
## @qcode{"legacy"}.
##
## @item version
## The protocol revision in force, once one has been agreed.
##
## @item initialized
## True once a legacy client has sent its @code{notifications/initialized}.
## @end table
##
## The eras differ in their envelope and in nothing else.  A modern result
## carries @code{resultType} and identifies the server on every reply; a legacy
## result carries neither, having named the server once in its @code{initialize}
## result.  The tools, their schemas and their handlers are the same objects in
## both, which is what keeps supporting two eras cheap.
##
## Two kinds of failure are distinguished, and the difference is not cosmetic.
## A @emph{protocol error} is returned as a JSON-RPC error and says the request
## was malformed or asked for something that does not exist; a model can rarely
## act on it.  A @emph{tool execution error} is a successful response whose
## @code{isError} is true, and it carries text a model can read and correct, so
## that a wrong argument becomes a retry rather than a dead end.
##
## @seealso{mcp.decodeRequest, mcp.encodeResponse, mcp.serve}
## @end deftypefn

function [RESP, S] = dispatch (R, S)

  ## Input validation
  if (nargin < 1 || nargin > 2)
    error ("mcp.dispatch: invalid number of input arguments.");
  endif
  if (! (isstruct (R) && isscalar (R)))
    error ("mcp.dispatch: R must be a scalar structure.");
  endif
  need = {'type', 'method', 'params', 'hasid', 'id', 'code', 'message'};
  if (! all (isfield (R, need)))
    error (strcat ("mcp.dispatch: R must be a structure as returned by", ...
                   " mcp.decodeRequest."));
  endif
  if (nargin < 2 || isempty (S))
    S = newSession ();
  endif
  if (! (isstruct (S) && isscalar (S) && all (isfield (S, {'era', 'version'}))))
    error (strcat ("mcp.dispatch: S must be a session structure, or empty", ...
                   " for a fresh one."));
  endif

  RESP = [];

  switch (R.type)
    case 'blank'
      return;
    case 'notification'
      if (strcmp (R.method, "notifications/initialized"))
        S.initialized = true;
      endif
      ## Never answered, by the letter of the protocol
      return;
    case 'invalid'
      if (R.hasid)
        RESP = mcp.jsonrpcError (R.id, R.code, R.message);
      else
        RESP = mcp.jsonrpcError ([], R.code, R.message);
      endif
      return;
    case 'request'
      ## Handled below
    otherwise
      error ("mcp.dispatch: unknown request type '%s'.", R.type);
  endswitch

  ## The era is chosen by how the client opens and then held for the process.
  ## This is the one piece of state the package keeps, and it exists only
  ## because a legacy session is defined to have one.
  if (strcmp (S.era, "unknown"))
    if (strcmp (R.method, "initialize"))
      S.era = "legacy";
    elseif (! strcmp (R.method, "ping"))
      [code, msg, data] = checkMeta (R.params);
      if (code != 0)
        RESP = mcp.jsonrpcError (R.id, code, msg, data);
        return;
      endif
      S.era = "modern";
      S.version = R.params._meta.io_modelcontextprotocol_protocolVersion;
    endif
  elseif (strcmp (S.era, "modern"))
    [code, msg, data] = checkMeta (R.params);
    if (code != 0)
      RESP = mcp.jsonrpcError (R.id, code, msg, data);
      return;
    endif
  endif

  era = S.era;

  switch (R.method)

    case 'initialize'
      [res, S.version] = initializeResult (R.params);
      RESP = mkResponse (R.id, res, era);

    case 'ping'
      ## Allowed before initialization completes, in either era
      RESP = mkResponse (R.id, emptyResult (era), era);

    case 'server/discover'
      if (strcmp (era, "legacy"))
        RESP = mcp.jsonrpcError (R.id, -32601, ...
                 "Method not found: server/discover is not part of this session's protocol revision.");
      else
        RESP = mkResponse (R.id, discoverResult (), era);
      endif

    case 'tools/list'
      RESP = mkResponse (R.id, toolsListResult (era), era);

    case 'tools/call'
      [res, code, msg] = toolsCall (R.params, era);
      if (code != 0)
        RESP = mcp.jsonrpcError (R.id, code, msg);
      else
        RESP = mkResponse (R.id, res, era);
      endif

    otherwise
      RESP = mcp.jsonrpcError (R.id, -32601, ...
                               sprintf ("Method not found: %s", R.method));

  endswitch

endfunction

function S = newSession ()
  ## era is 'unknown' until the client opens, then 'legacy' or 'modern'
  S = struct ("era", "unknown", "version", "", "initialized", false);
endfunction

function V = legacyVersions ()
  ## Answered to a legacy client; the newest handshake-based revision
  V = {'2025-11-25'};
endfunction

function [res, ver] = initializeResult (params)

  ## The rule here is not the modern one.  A legacy server does not reject an
  ## unknown version: it answers with one it does support and lets the client
  ## decide whether to continue or disconnect.
  LV = legacyVersions ();
  ver = LV{1};
  if (isfield (params, "protocolVersion") && ischar (params.protocolVersion) ...
      && any (strcmp (params.protocolVersion, LV)))
    ver = params.protocolVersion;
  endif

  [n, v] = serverIdentity ();
  caps = struct ();
  caps.tools = struct ();

  res = struct ();
  res.protocolVersion = ver;
  res.capabilities = caps;
  res.serverInfo = struct ("name", n, "version", v);
  res.instructions = instructionsText ();

endfunction

function res = emptyResult (era)
  res = struct ();
  if (strcmp (era, "modern"))
    res.resultType = "complete";
  endif
endfunction

function RESP = mkResponse (id, res, era)
  ## Only a modern result identifies the server on every reply; a legacy one
  ## carried serverInfo once, in the initialize result
  if (strcmp (era, "modern"))
    res._meta = serverMeta ();
  endif
  RESP = struct ("jsonrpc", "2.0", "id", id);
  RESP.result = res;
endfunction

function V = supportedVersions ()
  V = {'2026-07-28'};
endfunction

function [N, V] = serverIdentity ()
  ## Bumped with DESCRIPTION at every release; there is no path from an
  ## installed package back to its DESCRIPTION that is reliable enough to read
  N = "mcp";
  V = "0.1.0";
endfunction

function M = serverMeta ()
  [n, v] = serverIdentity ();
  M = struct ();
  M.io_modelcontextprotocol_serverInfo = struct ("name", n, "version", v);
endfunction

function [code, msg, data] = checkMeta (params)

  code = 0;
  msg = "";
  data = struct ();

  if (! isfield (params, "_meta"))
    code = -32602;
    msg = strcat ("Invalid params: missing _meta. Every request must carry", ...
                  " io.modelcontextprotocol/protocolVersion and", ...
                  " io.modelcontextprotocol/clientCapabilities in params._meta.");
    return;
  endif
  M = params._meta;

  if (! isfield (M, "io_modelcontextprotocol_protocolVersion"))
    code = -32602;
    msg = "Invalid params: missing io.modelcontextprotocol/protocolVersion.";
    return;
  endif
  if (! isfield (M, "io_modelcontextprotocol_clientCapabilities"))
    code = -32602;
    msg = "Invalid params: missing io.modelcontextprotocol/clientCapabilities.";
    return;
  endif

  ver = M.io_modelcontextprotocol_protocolVersion;
  if (! (ischar (ver) && isrow (ver)))
    code = -32602;
    msg = "Invalid params: io.modelcontextprotocol/protocolVersion must be a string.";
    return;
  endif

  if (! any (strcmp (ver, supportedVersions ())))
    code = -32022;
    msg = "Unsupported protocol version";
    data = struct ();
    data.supported = supportedVersions ();
    data.requested = ver;
  endif

endfunction

function T = toolTable ()

  T = {};

  t = struct ();
  t.name = "octave_version";
  t.title = "Octave Version";
  t.description = strcat ("Report the running GNU Octave version, its", ...
    " platform triplet, and the version of the mcp package serving this", ...
    " session. Use when a version or platform could change the answer; no", ...
    " other tool here reports them. Takes no arguments and cannot fail.");
  t.inputSchema = struct ("type", "object", "additionalProperties", false);
  props = struct ();
  props.version = struct ("type", "string");
  props.platform = struct ("type", "string");
  props.package = struct ("type", "string");
  osc = struct ();
  osc.type = "object";
  osc.properties = props;
  osc.required = {'version', 'platform', 'package'};
  t.outputSchema = osc;
  T{end+1} = t;

  t = struct ();
  t.name = "octave_which";
  t.title = "Resolve a Name";
  t.description = strcat ("Resolve an Octave name to the file that defines", ...
    " it, its kind, and the package that owns it, and list anything it", ...
    " shadows. Prefer this over octave_help when the question is where a name", ...
    " comes from or which package wins. Reports not found for an unknown name.");
  props = struct ();
  props.name = struct ("type", "string", "description", ...
    "Function, class, method or namespaced name, such as kmeans or containers.Map");
  isc = struct ();
  isc.type = "object";
  isc.properties = props;
  isc.required = {'name'};
  isc.additionalProperties = false;
  t.inputSchema = isc;
  mprops = struct ();
  mprops.path = struct ("type", "string");
  mprops.package = struct ("type", "string");
  mitem = struct ();
  mitem.type = "object";
  mitem.properties = mprops;
  oprops = struct ();
  oprops.name = struct ("type", "string");
  oprops.found = struct ("type", "boolean");
  oprops.kind = struct ("type", "string");
  oprops.path = struct ("type", "string");
  oprops.package = struct ("type", "string");
  oprops.shadowed = struct ("type", "integer");
  oprops.matches = struct ("type", "array", "items", mitem);
  osc = struct ();
  osc.type = "object";
  osc.properties = oprops;
  osc.required = {'name', 'found', 'kind'};
  t.outputSchema = osc;
  T{end+1} = t;

  t = struct ();
  t.name = "octave_help";
  t.title = "Read the Help Text";
  t.description = strcat ("Return the help text for an Octave function,", ...
    " class, method or operator, as help renders it. Prefer this over", ...
    " octave_which when the question is what a name does, not where it", ...
    " lives; operators resolve here only. Long text is cut at a line", ...
    " boundary with a marker.");
  props = struct ();
  props.name = struct ("type", "string", "description", ...
    "Function, class, method or operator, such as regress, containers.Map or +");
  isc = struct ();
  isc.type = "object";
  isc.properties = props;
  isc.required = {'name'};
  isc.additionalProperties = false;
  t.inputSchema = isc;
  ## No outputSchema and no structuredContent: the payload of this tool is
  ## prose, and either duplicating it as JSON or splitting metadata out of it
  ## costs tokens on every call for nothing the truncation marker does not
  ## already say.
  T{end+1} = t;

endfunction

function t = instructionsText ()
  t = strcat ("Introspects the GNU Octave interpreter this server runs", ...
    " inside. It sees only the packages its own launch command loaded, which", ...
    " may be fewer than an interactive session has; say so rather than", ...
    " concluding a name does not exist. Evaluates no code, runs no user", ...
    " function, and writes nothing.");
endfunction

function res = discoverResult ()

  caps = struct ();
  caps.tools = struct ();

  res = struct ();
  res.resultType = "complete";
  res.supportedVersions = supportedVersions ();
  res.capabilities = caps;
  res.instructions = instructionsText ();
  res.ttlMs = 3600000;
  res.cacheScope = "public";

endfunction

function res = toolsListResult (era)

  res = struct ();
  if (strcmp (era, "modern"))
    res.resultType = "complete";
  endif
  res.tools = toolTable ();
  if (strcmp (era, "modern"))
    ## Cache hints are a 2026-07-28 addition and have no legacy counterpart
    res.ttlMs = 3600000;
    res.cacheScope = "public";
  endif

endfunction

function [res, code, msg] = toolsCall (params, era)

  res = [];
  code = 0;
  msg = "";

  if (! (isfield (params, "name") && ischar (params.name) ...
                                  && isrow (params.name)))
    code = -32602;
    msg = "Invalid params: tools/call requires a string name.";
    return;
  endif

  T = toolTable ();
  names = cellfun (@(t) t.name, T, "UniformOutput", false);
  if (! any (strcmp (params.name, names)))
    code = -32602;
    msg = sprintf ("Unknown tool: %s", params.name);
    return;
  endif

  args = struct ();
  if (isfield (params, "arguments") && isstruct (params.arguments) ...
                                    && isscalar (params.arguments))
    args = params.arguments;
  endif

  switch (params.name)
    case 'octave_version'
      res = callOctaveVersion (args, era);
    case 'octave_which'
      res = callOctaveWhich (args, era);
    case 'octave_help'
      res = callOctaveHelp (args, era);
  endswitch

endfunction

function res = callOctaveVersion (args, era)

  res = struct ();
  if (strcmp (era, "modern"))
    res.resultType = "complete";
  endif

  ## The schema says this tool takes nothing, so anything passed is a mistake
  ## the model can correct: a tool error rather than a protocol error
  extra = fieldnames (args);
  if (! isempty (extra))
    res.content = {textBlock(sprintf (strcat ("octave_version takes no", ...
                    " arguments, but received: %s. Call it with an empty", ...
                    " arguments object."), strjoin (extra', ", ")))};
    res.isError = true;
    return;
  endif

  [n, v] = serverIdentity ();
  sc = struct ();
  sc.version = version ();
  sc.platform = computer ();
  sc.package = sprintf ("%s %s", n, v);

  txt = sprintf ("GNU Octave %s\nplatform: %s\npackage: %s", ...
                 sc.version, sc.platform, sc.package);
  res.content = {textBlock(txt)};
  res.isError = false;
  res.structuredContent = sc;

endfunction

function res = callOctaveWhich (args, era)

  res = struct ();
  if (strcmp (era, "modern"))
    res.resultType = "complete";
  endif

  if (! (isfield (args, "name") && ischar (args.name) && isrow (args.name) ...
         && ! isempty (strtrim (args.name))))
    res.content = {textBlock(strcat ("octave_which needs a name: the", ...
      " function, class, method or namespaced name to resolve."))};
    res.isError = true;
    ## The declared outputSchema is a promise about every result, error
    ## included, so an error carries a conforming report rather than nothing
    res.structuredContent = whichReport ("");
    return;
  endif

  W = whichReport (strtrim (args.name));

  if (! W.found)
    res.content = {textBlock(sprintf (strcat ("%s is not on this server's", ...
      " load path. It may still exist in a package this server did not load.", ...
      " Operators resolve by function name, such as plus for +, or ask", ...
      " octave_help, which reads them directly."), W.name))};
    res.isError = true;
    res.structuredContent = W;
    return;
  endif

  res.content = {textBlock(whichText (W))};
  res.isError = false;
  res.structuredContent = W;

endfunction

function W = whichReport (w_name)

  ## which () resolves against the calling function's workspace, so a query for
  ## a name this function also uses would come back as "variable".  Every local
  ## here is therefore prefixed, and that is the whole reason for the prefix.

  if (isempty (w_name))
    w_name = "";
  endif

  W = struct ();
  W.name = w_name;
  W.found = false;
  W.kind = "not found";
  W.path = "";
  W.package = "";
  W.shadowed = 0;
  W.matches = {};

  if (isempty (w_name))
    return;
  endif

  w_p = "";
  try
    w_p = which (w_name);
  catch
    w_p = "";
  end_try_catch

  w_ex = 0;
  try
    w_ex = exist (w_name);
  catch
    w_ex = 0;
  end_try_catch

  if (w_ex == 5)
    ## A built-in: what which reports is a source file inside the interpreter,
    ## not a path on this machine, and must not be presented as one
    W.found = true;
    W.kind = "built-in function";
    W.path = w_p;
    W.package = "core";
    W.matches = {struct("path", w_p, "package", "core")};
    return;
  endif

  if (strcmp (w_p, "variable"))
    W.found = true;
    W.kind = "variable";
    return;
  endif

  if (isempty (w_p))
    return;
  endif

  W.found = true;
  W.path = w_p;
  W.kind = fileKind (w_p);

  ## A dotted name resolving to the classdef file named for its next-to-last
  ## part was a request for a method, not for the class
  w_parts = strsplit (w_name, ".");
  if (numel (w_parts) > 1 && strcmp (W.kind, "classdef"))
    [~, w_base] = fileparts (W.path);
    if (strcmp (w_base, w_parts{end-1}))
      W.kind = "method";
    endif
  endif

  w_pk = pkg ("list");
  W.package = pathOwner (W.path, w_pk);

  ## Enumerate every resolution by hand.  Never which (..., "all"): core's
  ## -all is unimplemented (Savannah bug #32088), it warns that only the first
  ## result will be returned, and the function form hands back a character
  ## vector rather than a cell, so a caller gets short data and a wrong type.
  w_hits = {};
  w_frags = nameFragments (w_name);
  for w_i = 1:numel (w_frags)
    for w_e = {'.m', '.oct', '.mex'}
      w_f = file_in_loadpath ([w_frags{w_i} w_e{1}], "all");
      for w_j = 1:numel (w_f)
        if (! any (strcmp (w_f{w_j}, w_hits)))
          w_hits{end+1} = w_f{w_j};
        endif
      endfor
    endfor
  endfor

  ## The resolution the interpreter would actually use leads, whatever order
  ## the enumeration produced
  w_hits = [{W.path}, w_hits(! strcmp (w_hits, W.path))];

  for w_i = 1:numel (w_hits)
    W.matches{end+1} = struct ("path", w_hits{w_i}, ...
                               "package", pathOwner (w_hits{w_i}, w_pk));
  endfor
  W.shadowed = numel (W.matches) - 1;

endfunction

function F = nameFragments (n)

  ## file_in_loadpath resolves a path fragment, not a dotted name: it finds
  ## "+nsx/f.m" and returns nothing at all for "nsx.f.m".

  parts = strsplit (n, ".");
  if (numel (parts) == 1)
    F = {n};
    return;
  endif

  F = {};
  ns = "";                            # every part but the last, as namespaces
  for i = 1:numel (parts) - 1
    ns = catpath (ns, ["+" parts{i}]);
  endfor
  F{end+1} = catpath (ns, parts{end});

  outer = "";                         # every part but the last two
  for i = 1:numel (parts) - 2
    outer = catpath (outer, ["+" parts{i}]);
  endfor
  F{end+1} = catpath (catpath (outer, ["@" parts{end-1}]), parts{end});
  F{end+1} = catpath (outer, parts{end-1});

endfunction

function p = catpath (a, b)
  if (isempty (a))
    p = b;
  else
    p = fullfile (a, b);
  endif
endfunction

function K = fileKind (p)

  K = "function";
  [~, ~, e] = fileparts (p);
  if (any (strcmp (e, {'.oct', '.mex'})))
    K = "compiled function";
    return;
  endif

  fid = fopen (p, "r");
  if (fid < 0)
    return;
  endif
  unwind_protect
    l = fgetl (fid);
    while (ischar (l))
      t = strtrim (l);
      if (! isempty (t) && ! strncmp (t, "#", 1) && ! strncmp (t, "%", 1))
        break;
      endif
      l = fgetl (fid);
    endwhile
  unwind_protect_cleanup
    fclose (fid);
  end_unwind_protect

  if (! ischar (l))
    return;
  endif
  t = strtrim (l);
  if (strncmp (t, "classdef", 8))
    K = "classdef";
  elseif (! strncmp (t, "function", 8))
    K = "script";
  endif

endfunction

function O = pathOwner (p, L)

  O = "";
  for i = 1:numel (L)
    if (strncmp (p, L{i}.dir, numel (L{i}.dir)))
      O = sprintf ("%s %s", L{i}.name, L{i}.version);
      return;
    endif
  endfor

  h = fullfile (OCTAVE_HOME (), "share", "octave");
  if (strncmp (p, h, numel (h)))
    O = "core";
  endif

endfunction

function T = whichText (W)

  L = {sprintf("%s is a %s", W.name, W.kind)};
  if (! isempty (W.path))
    if (strcmp (W.kind, "built-in function"))
      ## Not a path on this machine: it is a source file inside the interpreter
      L{end+1} = sprintf ("  defined in: %s (interpreter source)", W.path);
    else
      L{end+1} = sprintf ("  file:    %s", W.path);
    endif
  endif
  if (! isempty (W.package))
    L{end+1} = sprintf ("  package: %s", W.package);
  endif
  for i = 2:numel (W.matches)
    if (isempty (W.matches{i}.package))
      L{end+1} = sprintf ("  shadows: %s", W.matches{i}.path);
    else
      L{end+1} = sprintf ("  shadows: %s  [%s]", W.matches{i}.path, ...
                          W.matches{i}.package);
    endif
  endfor
  T = strjoin (L, "\n");

endfunction

function res = callOctaveHelp (args, era)

  res = struct ();
  if (strcmp (era, "modern"))
    res.resultType = "complete";
  endif

  if (! (isfield (args, "name") && ischar (args.name) && isrow (args.name) ...
         && ! isempty (strtrim (args.name))))
    res.content = {textBlock(strcat ("octave_help needs a name: the", ...
      " function, class, method or operator to describe."))};
    res.isError = true;
    return;
  endif

  h_name = strtrim (args.name);
  h_txt = "";
  h_err = "";
  try
    h_txt = help (h_name);
  catch h_e
    h_err = h_e.message;
  end_try_catch

  if (! isempty (h_err) || isempty (strtrim (h_txt)))
    res.content = {textBlock(sprintf (strcat ("No help for %s on this", ...
      " server's load path. It may exist in a package this server did not", ...
      " load; octave_which reports where a name resolves."), h_name))};
    res.isError = true;
    return;
  endif

  res.content = {textBlock(capText (h_txt, helpCap ()))};
  res.isError = false;

endfunction

function B = helpCap ()
  ## Measured on 11.2.0: core help is 591 bytes at the median and 7450 at the
  ## 99th percentile; statistics and datatypes are 1447 and 10725.  This cuts
  ## about 1% of core and 3% of package functions.  Doubling it would cut none
  ## and would double the worst single call to roughly 4000 tokens, which the
  ## user pays for, so the last few per cent are not worth buying.
  B = 8192;
endfunction

function T = capText (txt, cap)

  L = strsplit (txt, "\n");
  nl = numel (L);
  nb = numel (txt);

  if (nb <= cap)
    T = txt;
    return;
  endif

  ## Room for the marker, so that the promise of a cap holds for what is
  ## actually sent rather than for the part before the note about it
  room = cap - 96;

  keep = 0;
  used = 0;
  for i = 1:nl
    add = numel (L{i}) + 1;
    if (used + add > room)
      break;
    endif
    used += add;
    keep = i;
  endfor

  if (keep == 0)
    ## One line longer than the whole budget: there is no line boundary to cut
    ## at, so say that rather than pretending the text ended
    T = sprintf ("%s\n[truncated mid-line: 1 line of %d bytes exceeds the %d byte limit]", ...
                 L{1}(1:room), nb, cap);
    return;
  endif

  T = strjoin (L(1:keep), "\n");
  T = sprintf ("%s\n[truncated: %d of %d lines, %d of %d bytes]", T, keep, nl, ...
               numel (T), nb);

endfunction

function B = textBlock (txt)
  B = struct ("type", "text", "text", txt);
endfunction

%!function R = mkreq (method, extra)
%!  meta = ['"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28",' ...
%!          '"io.modelcontextprotocol/clientCapabilities":{}}'];
%!  if (isempty (extra))
%!    p = ['{' meta '}'];
%!  else
%!    p = ['{' extra ',' meta '}'];
%!  endif
%!  R = mcp.decodeRequest (['{"jsonrpc":"2.0","id":1,"method":"' method ...
%!                          '","params":' p '}']);
%!endfunction

%!test
%! ## A blank line is not answered.
%! assert_equal (mcp.dispatch (mcp.decodeRequest ("")), []);

%!test
%! ## A notification is never answered, which is a MUST NOT and not a nicety.
%! R = mcp.decodeRequest ('{"jsonrpc":"2.0","method":"notifications/cancelled"}');
%! assert_equal (mcp.dispatch (R), []);

%!test
%! ## An unparseable line is answered without an identifier, having none.
%! RESP = mcp.dispatch (mcp.decodeRequest ("garbage"));
%! assert_equal (RESP.error.code, -32700);
%! assert_equal (isfield (RESP, "id"), false);

%!test
%! ## An identifier recovered from an invalid message is echoed back.
%! RESP = mcp.dispatch (mcp.decodeRequest ('{"jsonrpc":"2.0","id":9}'));
%! assert_equal (RESP.error.code, -32600);
%! assert_equal (RESP.id, 9);

%!test
%! ## A legacy client opens with initialize and is served, not refused.
%! R = mcp.decodeRequest (['{"jsonrpc":"2.0","id":1,"method":"initialize",' ...
%!      '"params":{"protocolVersion":"2025-11-25","capabilities":{},' ...
%!      '"clientInfo":{"name":"c","version":"1"}}}']);
%! [RESP, S] = mcp.dispatch (R, []);
%! assert_equal (S.era, "legacy");
%! assert_equal (RESP.result.protocolVersion, "2025-11-25");
%! assert_equal (RESP.result.serverInfo.name, "mcp");
%! assert_equal (isfield (RESP.result, "resultType"), false);

%!test
%! ## Metadata is required on every request, not established once per session.
%! R = mcp.decodeRequest ('{"jsonrpc":"2.0","id":1,"method":"tools/list"}');
%! RESP = mcp.dispatch (R);
%! assert_equal (RESP.error.code, -32602);

%!test
%! p = '"_meta":{"io.modelcontextprotocol/clientCapabilities":{}}';
%! R = mcp.decodeRequest (['{"jsonrpc":"2.0","id":1,"method":"tools/list",' ...
%!                         '"params":{' p '}}']);
%! RESP = mcp.dispatch (R);
%! assert_equal (RESP.error.code, -32602);
%! assert_equal (RESP.error.message, ...
%!   "Invalid params: missing io.modelcontextprotocol/protocolVersion.");

%!test
%! p = '"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}';
%! R = mcp.decodeRequest (['{"jsonrpc":"2.0","id":1,"method":"tools/list",' ...
%!                         '"params":{' p '}}']);
%! RESP = mcp.dispatch (R);
%! assert_equal (RESP.error.message, ...
%!   "Invalid params: missing io.modelcontextprotocol/clientCapabilities.");

%!test
%! ## An unsupported version names what we do speak, so the client can retry.
%! p = ['"_meta":{"io.modelcontextprotocol/protocolVersion":"1900-01-01",' ...
%!      '"io.modelcontextprotocol/clientCapabilities":{}}'];
%! R = mcp.decodeRequest (['{"jsonrpc":"2.0","id":1,"method":"tools/list",' ...
%!                         '"params":{' p '}}']);
%! RESP = mcp.dispatch (R);
%! assert_equal (RESP.error.code, -32022);
%! assert_equal (RESP.error.data.supported, {'2026-07-28'});
%! assert_equal (RESP.error.data.requested, "1900-01-01");

%!test
%! RESP = mcp.dispatch (mkreq ("server/discover", ""));
%! assert_equal (RESP.result.resultType, "complete");
%! assert_equal (RESP.result.supportedVersions, {'2026-07-28'});
%! assert_equal (isfield (RESP.result.capabilities, "tools"), true);

%!test
%! ## Every result identifies the server without relying on prior state.
%! RESP = mcp.dispatch (mkreq ("server/discover", ""));
%! si = RESP.result._meta.io_modelcontextprotocol_serverInfo;
%! assert_equal (si.name, "mcp");

%!test
%! ## The advertised set is frozen API: renaming a tool silently breaks every
%! ## configuration and every prompt built on it, with no error anywhere.
%! RESP = mcp.dispatch (mkreq ("tools/list", ""), []);
%! names = cellfun (@(t) t.name, RESP.result.tools, "UniformOutput", false);
%! assert_equal (names, {'octave_version', 'octave_which', 'octave_help'});

%!test
%! ## The tool list is fixed for the life of the process, so it may be cached.
%! RESP = mcp.dispatch (mkreq ("tools/list", ""));
%! assert_equal (RESP.result.cacheScope, "public");

%!test
%! ## A tool taking nothing must still carry a valid schema object.
%! RESP = mcp.dispatch (mkreq ("tools/list", ""));
%! s = RESP.result.tools{1}.inputSchema;
%! assert_equal (s.type, "object");
%! assert_equal (s.additionalProperties, false);

%!test
%! ## TOOL_STYLE caps a description at 300 bytes, paid on every request.
%! RESP = mcp.dispatch (mkreq ("tools/list", ""));
%! for i = 1:numel (RESP.result.tools)
%!   assert_equal (numel (RESP.result.tools{i}.description) <= 300, true);
%! endfor

%!test
%! ## strcat strips trailing whitespace from a char argument, so a description
%! ## assembled across continuation lines loses a space at every join and the
%! ## words either side are glued.  A length check cannot see it; these can.
%! RESP = mcp.dispatch (mkreq ("tools/list", ""));
%! d = RESP.result.tools{1}.description;
%! assert_equal (isempty (strfind (d, "its platform triplet")), false);
%! assert_equal (isempty (strfind (d, "serving this session")), false);
%! assert_equal (isempty (strfind (d, "answer; no other tool")), false);

%!test
%! ## The same trap in the guidance the model reads about the whole server.
%! RESP = mcp.dispatch (mkreq ("server/discover", ""));
%! s = RESP.result.instructions;
%! assert_equal (isempty (strfind (s, "interpreter this server runs inside")), false);
%! assert_equal (isempty (strfind (s, "its own launch command loaded")), false);
%! assert_equal (isempty (strfind (s, "function, and writes nothing")), false);

%!test
%! ## And in the guidance carried by the legacy initialize result.
%! R = mcp.decodeRequest (['{"jsonrpc":"2.0","id":1,"method":"initialize",' ...
%!      '"params":{"protocolVersion":"2025-11-25"}}']);
%! RESP = mcp.dispatch (R, []);
%! s = RESP.result.instructions;
%! assert_equal (isempty (strfind (s, "interpreter this server runs inside")), false);
%! assert_equal (isempty (strfind (s, "function, and writes nothing")), false);

%!test
%! ## And in the tool error a model is expected to read and correct.
%! RESP = mcp.dispatch (mkreq ("tools/call", ...
%!                       '"name":"octave_version","arguments":{"zz":1}'));
%! t = RESP.result.content{1}.text;
%! assert_equal (isempty (strfind (t, "takes no arguments, but received")), false);
%! assert_equal (isempty (strfind (t, "with an empty arguments object")), false);

%!test
%! ## Tool names must hold to the character set the protocol allows.
%! RESP = mcp.dispatch (mkreq ("tools/list", ""));
%! for i = 1:numel (RESP.result.tools)
%!   n = RESP.result.tools{i}.name;
%!   assert_equal (isempty (regexp (n, '^[A-Za-z0-9_.-]{1,128}$', "once")), false);
%! endfor

%!test
%! RESP = mcp.dispatch (mkreq ("tools/call", '"name":"octave_version"'));
%! assert_equal (RESP.result.isError, false);
%! assert_equal (RESP.result.content{1}.type, "text");
%! assert_equal (RESP.result.structuredContent.version, version ());

%!test
%! ## Content must survive encoding as a JSON array, not a bare object.
%! RESP = mcp.dispatch (mkreq ("tools/call", '"name":"octave_version"'));
%! T = mcp.encodeResponse (RESP);
%! assert_equal (isempty (strfind (T, '"content":[{')), false);

%!test
%! ## An unknown tool is a protocol error: the model cannot correct it.
%! RESP = mcp.dispatch (mkreq ("tools/call", '"name":"nope"'));
%! assert_equal (RESP.error.code, -32602);
%! assert_equal (RESP.error.message, "Unknown tool: nope");

%!test
%! RESP = mcp.dispatch (mkreq ("tools/call", ""));
%! assert_equal (RESP.error.code, -32602);
%! assert_equal (RESP.error.message, ...
%!               "Invalid params: tools/call requires a string name.");

%!test
%! ## A bad argument is a tool error carrying text the model can act on.
%! RESP = mcp.dispatch (mkreq ("tools/call", ...
%!                       '"name":"octave_version","arguments":{"x":1}'));
%! assert_equal (isfield (RESP, "error"), false);
%! assert_equal (RESP.result.isError, true);
%! assert_equal (isempty (strfind (RESP.result.content{1}.text, "x")), false);

%!test
%! RESP = mcp.dispatch (mkreq ("no/such/method", ""));
%! assert_equal (RESP.error.code, -32601);
%! assert_equal (RESP.error.message, "Method not found: no/such/method");

%!error <mcp\.dispatch: invalid number of input arguments\.> mcp.dispatch ()
%!error <mcp\.dispatch: R must be a scalar structure\.> mcp.dispatch (5)
%!error <mcp\.dispatch: R must be a structure as returned by mcp\.decodeRequest\.> ...
%! mcp.dispatch (struct ("type", "request"))

%!function S = legacySession ()
%!  R = mcp.decodeRequest (['{"jsonrpc":"2.0","id":0,"method":"initialize",' ...
%!       '"params":{"protocolVersion":"2025-11-25","capabilities":{}}}']);
%!  [~, S] = mcp.dispatch (R, []);
%!endfunction

%!function R = plainreq (method, extra)
%!  if (isempty (extra))
%!    p = '{}';
%!  else
%!    p = ['{' extra '}'];
%!  endif
%!  R = mcp.decodeRequest (['{"jsonrpc":"2.0","id":1,"method":"' method ...
%!                          '","params":' p '}']);
%!endfunction

%!test
%! ## A legacy session needs no per-request metadata and must not be asked for it.
%! S = legacySession ();
%! RESP = mcp.dispatch (plainreq ("tools/list", ""), S);
%! names = cellfun (@(t) t.name, RESP.result.tools, "UniformOutput", false);
%! assert_equal (names, {'octave_version', 'octave_which', 'octave_help'});

%!test
%! ## The legacy envelope carries neither resultType nor the cache hints, both
%! ## of which the 2026-07-28 revision introduced.
%! S = legacySession ();
%! RESP = mcp.dispatch (plainreq ("tools/list", ""), S);
%! assert_equal (isfield (RESP.result, "resultType"), false);
%! assert_equal (isfield (RESP.result, "ttlMs"), false);
%! assert_equal (isfield (RESP.result, "_meta"), false);

%!test
%! ## The tool itself is the same object in both eras.
%! S = legacySession ();
%! RESP = mcp.dispatch (plainreq ("tools/call", '"name":"octave_version"'), S);
%! assert_equal (RESP.result.isError, false);
%! assert_equal (RESP.result.structuredContent.version, version ());
%! assert_equal (isfield (RESP.result, "resultType"), false);

%!test
%! ## An unknown version is answered with one we speak, never refused: that is
%! ## the legacy negotiation rule and it is the opposite of the modern one.
%! R = mcp.decodeRequest (['{"jsonrpc":"2.0","id":1,"method":"initialize",' ...
%!      '"params":{"protocolVersion":"2024-11-05"}}']);
%! RESP = mcp.dispatch (R, []);
%! assert_equal (isfield (RESP, "error"), false);
%! assert_equal (RESP.result.protocolVersion, "2025-11-25");

%!test
%! ## server/discover belongs to the modern era alone.
%! S = legacySession ();
%! RESP = mcp.dispatch (plainreq ("server/discover", ""), S);
%! assert_equal (RESP.error.code, -32601);

%!test
%! ## notifications/initialized is recorded and never answered.
%! S = legacySession ();
%! R = mcp.decodeRequest ('{"jsonrpc":"2.0","method":"notifications/initialized"}');
%! [RESP, S] = mcp.dispatch (R, S);
%! assert_equal (RESP, []);
%! assert_equal (S.initialized, true);

%!test
%! ## ping is allowed before initialization completes, in either era.
%! [RESP, S] = mcp.dispatch (plainreq ("ping", ""), []);
%! assert_equal (isfield (RESP, "error"), false);
%! assert_equal (S.era, "unknown");
%! assert_equal (mcp.encodeResponse (RESP), '{"jsonrpc":"2.0","id":1,"result":{}}');

%!test
%! ## The era is chosen once and held: a modern session stays modern.
%! [~, S] = mcp.dispatch (mkreq ("tools/list", ""), []);
%! assert_equal (S.era, "modern");
%! assert_equal (S.version, "2026-07-28");

%!test
%! ## A modern session keeps demanding its metadata on every request.
%! [~, S] = mcp.dispatch (mkreq ("tools/list", ""), []);
%! RESP = mcp.dispatch (plainreq ("tools/list", ""), S);
%! assert_equal (RESP.error.code, -32602);

%!test
%! ## A legacy session is never asked for a modern protocol version.
%! S = legacySession ();
%! assert_equal (S.era, "legacy");
%! RESP = mcp.dispatch (plainreq ("tools/call", '"name":"nope"'), S);
%! assert_equal (RESP.error.code, -32602);
%! assert_equal (RESP.error.message, "Unknown tool: nope");

%!error <mcp\.dispatch: S must be a session structure, or empty for a fresh one\.> ...
%! mcp.dispatch (mcp.decodeRequest (""), 5)

%!function R = callwhich (name)
%!  meta = ['"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28",' ...
%!          '"io.modelcontextprotocol/clientCapabilities":{}}'];
%!  R = mcp.decodeRequest (['{"jsonrpc":"2.0","id":1,"method":"tools/call",' ...
%!       '"params":{"name":"octave_which","arguments":{"name":"' name '"},' ...
%!       meta '}}']);
%!endfunction

%!test
%! ## A core m-file resolves to its file and is attributed to core.
%! RESP = mcp.dispatch (callwhich ("mean"), []);
%! W = RESP.result.structuredContent;
%! assert_equal (RESP.result.isError, false);
%! assert_equal (W.found, true);
%! assert_equal (W.kind, "function");
%! assert_equal (W.package, "core");

%!test
%! ## A built-in reports a source file inside the interpreter, which is not a
%! ## path on this machine and must not be offered as one.
%! RESP = mcp.dispatch (callwhich ("sin"), []);
%! W = RESP.result.structuredContent;
%! assert_equal (W.kind, "built-in function");
%! t = RESP.result.content{1}.text;
%! assert_equal (isempty (strfind (t, "interpreter source")), false);
%! assert_equal (isempty (strfind (t, "file:")), true);

%!test
%! ## exist () reports 0 for a namespaced name, so the kind cannot come from it.
%! RESP = mcp.dispatch (callwhich ("containers.Map"), []);
%! W = RESP.result.structuredContent;
%! assert_equal (W.found, true);
%! assert_equal (W.kind, "classdef");

%!test
%! ## A dotted name landing on the classdef it belongs to was a method query.
%! RESP = mcp.dispatch (callwhich ("containers.Map.keys"), []);
%! W = RESP.result.structuredContent;
%! assert_equal (W.found, true);
%! assert_equal (W.kind, "method");

%!test
%! ## Not found is a tool error, which a model can act on, never a protocol one.
%! RESP = mcp.dispatch (callwhich ("mcpzznosuchname"), []);
%! assert_equal (isfield (RESP, "error"), false);
%! assert_equal (RESP.result.isError, true);
%! assert_equal (RESP.result.structuredContent.found, false);

%!test
%! ## The hint names the fallback, since an operator never resolves by symbol.
%! RESP = mcp.dispatch (callwhich ("mcpzznosuchname"), []);
%! t = RESP.result.content{1}.text;
%! assert_equal (isempty (strfind (t, "plus for +")), false);
%! assert_equal (isempty (strfind (t, "a package this server did not load")), false);

%!test
%! ## A missing argument is a tool error naming what was wanted.
%! meta = ['"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28",' ...
%!         '"io.modelcontextprotocol/clientCapabilities":{}}'];
%! R = mcp.decodeRequest (['{"jsonrpc":"2.0","id":1,"method":"tools/call",' ...
%!      '"params":{"name":"octave_which","arguments":{},' meta '}}']);
%! RESP = mcp.dispatch (R, []);
%! assert_equal (RESP.result.isError, true);
%! assert_equal (isempty (strfind (RESP.result.content{1}.text, "needs a name")), false);

%!test
%! ## Shadowing is the whole point of this tool, and it is also the guard that
%! ## keeps anyone from reaching for which (..., "all"), which returns one hit.
%! d1 = fullfile (tempdir (), "mcp_shadow_a");
%! d2 = fullfile (tempdir (), "mcp_shadow_b");
%! unwind_protect
%!   mkdir (d1); mkdir (d2);
%!   for d = {d1, d2}
%!     fid = fopen (fullfile (d{1}, "mcpzzfixture.m"), "w");
%!     fprintf (fid, "function y = mcpzzfixture ()\n  y = 1;\nendfunction\n");
%!     fclose (fid);
%!   endfor
%!   addpath (d2); addpath (d1);
%!   RESP = mcp.dispatch (callwhich ("mcpzzfixture"), []);
%!   W = RESP.result.structuredContent;
%!   assert_equal (W.shadowed, 1);
%!   assert_equal (numel (W.matches), 2);
%!   assert_equal (W.matches{1}.path, fullfile (d1, "mcpzzfixture.m"));
%!   assert_equal (W.matches{2}.path, fullfile (d2, "mcpzzfixture.m"));
%!   assert_equal (W.path, W.matches{1}.path);
%! unwind_protect_cleanup
%!   warning ("off", "Octave:rmpath-not-found", "local");
%!   rmpath (d1); rmpath (d2);
%!   confirm_recursive_rmdir (false, "local");
%!   rmdir (d1, "s"); rmdir (d2, "s");
%! end_unwind_protect

%!test
%! ## The description obeys TOOL_STYLE and its joins are not glued.
%! RESP = mcp.dispatch (mkreq ("tools/list", ""), []);
%! d = RESP.result.tools{2}.description;
%! assert_equal (RESP.result.tools{2}.name, "octave_which");
%! assert_equal (numel (d) <= 300, true);
%! assert_equal (isempty (strfind (d, "the file that defines it")), false);
%! assert_equal (isempty (strfind (d, "and list anything it shadows")), false);

%!test
%! ## The legacy envelope reaches the new tool too.
%! S = legacySession ();
%! RESP = mcp.dispatch (plainreq ("tools/call", ...
%!          '"name":"octave_which","arguments":{"name":"mean"}'), S);
%! assert_equal (RESP.result.isError, false);
%! assert_equal (isfield (RESP.result, "resultType"), false);
%! assert_equal (RESP.result.structuredContent.kind, "function");

%!test
%! ## A tool that declares an outputSchema promises structured content on every
%! ## result, an error result included, or the schema is not a contract.
%! RESP = mcp.dispatch (mkreq ("tools/list", ""), []);
%! schemad = {};
%! for i = 1:numel (RESP.result.tools)
%!   if (isfield (RESP.result.tools{i}, "outputSchema"))
%!     schemad{end+1} = RESP.result.tools{i}.name;
%!   endif
%! endfor
%! assert_equal (any (strcmp ("octave_which", schemad)), true);
%! ## Note: no space before the paren would be needed inside {}, so the
%! ## requests are built first rather than inline.
%! good = callwhich ("mean");
%! bad = callwhich ("mcpzznosuchname");
%! A = mcp.dispatch (good, []);
%! B = mcp.dispatch (bad, []);
%! assert_equal (isfield (A.result, "structuredContent"), true);
%! assert_equal (isfield (B.result, "structuredContent"), true);
%! assert_equal (B.result.isError, true);

%!function R = callhelp (name)
%!  meta = ['"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28",' ...
%!          '"io.modelcontextprotocol/clientCapabilities":{}}'];
%!  R = mcp.decodeRequest (['{"jsonrpc":"2.0","id":1,"method":"tools/call",' ...
%!       '"params":{"name":"octave_help","arguments":{"name":"' name '"},' ...
%!       meta '}}']);
%!endfunction

%!test
%! ## The ordinary case: the help of a core function comes back as help wrote it.
%! RESP = mcp.dispatch (callhelp ("mean"), []);
%! assert_equal (RESP.result.isError, false);
%! assert_equal (isempty (strfind (RESP.result.content{1}.text, "mean (X)")), false);

%!test
%! ## An operator has help but does not resolve through which, which is why
%! ## both tools exist and why the description says so.
%! RESP = mcp.dispatch (callhelp ("+"), []);
%! assert_equal (RESP.result.isError, false);
%! assert_equal (isempty (strfind (RESP.result.content{1}.text, "Addition")), false);

%!test
%! ## An unknown name is a tool error naming the fallback, not a protocol error.
%! RESP = mcp.dispatch (callhelp ("mcpzznosuchname"), []);
%! assert_equal (isfield (RESP, "error"), false);
%! assert_equal (RESP.result.isError, true);
%! assert_equal (isempty (strfind (RESP.result.content{1}.text, "octave_which")), false);

%!test
%! ## Help carrying no structuredContent is deliberate: the payload is prose.
%! RESP = mcp.dispatch (callhelp ("mean"), []);
%! assert_equal (isfield (RESP.result, "structuredContent"), false);

%!test
%! ## Truncation, on a fixture built for it rather than on whichever function
%! ## happens to have long help in this installation.
%! d = fullfile (tempdir (), "mcp_help_big");
%! unwind_protect
%!   mkdir (d);
%!   fid = fopen (fullfile (d, "mcpzzbig.m"), "w");
%!   fprintf (fid, "## -*- texinfo -*-\n");
%!   for i = 1:400
%!     fprintf (fid, "## line %03d %s\n", i, repmat ("z", 1, 50));
%!   endfor
%!   fprintf (fid, "function mcpzzbig ()\nendfunction\n");
%!   fclose (fid);
%!   addpath (d);
%!   RESP = mcp.dispatch (callhelp ("mcpzzbig"), []);
%!   t = RESP.result.content{1}.text;
%!   assert_equal (RESP.result.isError, false);
%!   assert_equal (numel (t) <= 8192, true);
%!   assert_equal (isempty (strfind (t, "[truncated:")), false);
%!   L = strsplit (t, "\n");
%!   assert_equal (isempty (strfind (L{end}, "of 4")), false);
%!   assert_equal (isempty (strfind (L{end-1}, "zzz")), false);
%! unwind_protect_cleanup
%!   warning ("off", "Octave:rmpath-not-found", "local");
%!   rmpath (d);
%!   confirm_recursive_rmdir (false, "local");
%!   rmdir (d, "s");
%! end_unwind_protect

%!test
%! ## A single line longer than the whole budget has no boundary to cut at, so
%! ## the marker says mid-line rather than pretending the text ended.
%! d = fullfile (tempdir (), "mcp_help_line");
%! unwind_protect
%!   mkdir (d);
%!   fid = fopen (fullfile (d, "mcpzzline.m"), "w");
%!   fprintf (fid, "## %s\n", repmat ("q", 1, 20000));
%!   fprintf (fid, "function mcpzzline ()\nendfunction\n");
%!   fclose (fid);
%!   addpath (d);
%!   RESP = mcp.dispatch (callhelp ("mcpzzline"), []);
%!   t = RESP.result.content{1}.text;
%!   assert_equal (numel (t) <= 8192, true);
%!   assert_equal (isempty (strfind (t, "truncated mid-line")), false);
%! unwind_protect_cleanup
%!   warning ("off", "Octave:rmpath-not-found", "local");
%!   rmpath (d);
%!   confirm_recursive_rmdir (false, "local");
%!   rmdir (d, "s");
%! end_unwind_protect

%!test
%! ## Short help is returned whole, with no marker to mislead a model into
%! ## thinking something was withheld.
%! RESP = mcp.dispatch (callhelp ("+"), []);
%! assert_equal (isempty (strfind (RESP.result.content{1}.text, "truncated")), true);

%!test
%! ## TOOL_STYLE, and the joins are not glued.
%! RESP = mcp.dispatch (mkreq ("tools/list", ""), []);
%! d = RESP.result.tools{3}.description;
%! assert_equal (RESP.result.tools{3}.name, "octave_help");
%! assert_equal (numel (d) <= 300, true);
%! assert_equal (isempty (strfind (d, "as help renders it")), false);
%! assert_equal (isempty (strfind (d, "operators resolve here only")), false);
%! assert_equal (isempty (strfind (d, "does, not where it lives")), false);
