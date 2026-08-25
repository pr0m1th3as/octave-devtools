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
## Tools are model-controlled and resources are application-driven, which is
## why constant facts such as the Octave version live in the @code{instructions}
## text sent once at connection rather than in a tool that would charge its
## description against every request.
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
    S = mcp.__newSession__ ("read-only");
  endif
  if (! (isstruct (S) && isscalar (S) && all (isfield (S, {'era', 'version'}))))
    error (strcat ("mcp.dispatch: S must be a session structure, or empty", ...
                   " for a fresh one."));
  endif
  ## A session made before the evaluating surface existed, or by hand, is
  ## read-only.  The safe surface is what a missing field means, never the
  ## other way round.
  if (! isfield (S, "surface"))
    S.surface = "read-only";
  endif
  if (! all (isfield (S, {'ws', 'wsorder', 'wsnext'})))
    S.ws = struct ();
    S.wsorder = {};
    S.wsnext = 1;
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
      [res, S.version] = initializeResult (R.params, S.surface);
      RESP = mkResponse (R.id, res, era);

    case 'ping'
      ## Allowed before initialization completes, in either era
      RESP = mkResponse (R.id, emptyResult (era), era);

    case 'server/discover'
      if (strcmp (era, "legacy"))
        RESP = mcp.jsonrpcError (R.id, -32601, ...
                 "Method not found: server/discover is not part of this session's protocol revision.");
      else
        RESP = mkResponse (R.id, discoverResult (S.surface), era);
      endif

    case 'tools/list'
      RESP = mkResponse (R.id, toolsListResult (era, S.surface), era);

    case 'resources/list'
      RESP = mkResponse (R.id, resourcesListResult (era), era);

    case 'resources/read'
      [res, code, msg, data] = resourcesRead (R.params, era);
      if (code != 0)
        RESP = mcp.jsonrpcError (R.id, code, msg, data);
      else
        RESP = mkResponse (R.id, res, era);
      endif

    case 'tools/call'
      [res, code, msg, S] = toolsCall (R.params, era, S);
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

function V = legacyVersions ()
  ## Answered to a legacy client; the newest handshake-based revision
  V = {'2025-11-25'};
endfunction

function [res, ver] = initializeResult (params, surface)

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
  caps.resources = struct ();

  res = struct ();
  res.protocolVersion = ver;
  res.capabilities = caps;
  res.serverInfo = struct ("name", n, "version", v);
  res.instructions = instructionsText (surface);

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

function T = toolTable (surface)

  T = {};

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
  oprops.state = struct ("type", "string");
  oprops.kind = struct ("type", "string");
  oprops.path = struct ("type", "string");
  oprops.package = struct ("type", "string");
  oprops.shadowed = struct ("type", "integer");
  oprops.matches = struct ("type", "array", "items", mitem);
  osc = struct ();
  osc.type = "object";
  osc.properties = oprops;
  osc.required = {'name', 'found', 'state', 'kind'};
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

  t = struct ();
  t.name = "octave_search";
  t.title = "Search for a Function";
  t.description = strcat ("List Octave functions whose help text mentions a", ...
    " term, with their summary lines, best name matches first. Use this when", ...
    " the name is unknown; octave_which says where a known name lives and", ...
    " octave_help says what it does. Reports the total when the list is capped.");
  props = struct ();
  props.query = struct ("type", "string", "description", ...
    "A word or phrase to look for, such as correlation or eigenvalue");
  isc = struct ();
  isc.type = "object";
  isc.properties = props;
  isc.required = {'query'};
  isc.additionalProperties = false;
  t.inputSchema = isc;
  rprops = struct ();
  rprops.name = struct ("type", "string");
  rprops.summary = struct ("type", "string");
  ritem = struct ();
  ritem.type = "object";
  ritem.properties = rprops;
  oprops = struct ();
  oprops.query = struct ("type", "string");
  oprops.total = struct ("type", "integer");
  oprops.shown = struct ("type", "integer");
  oprops.matches = struct ("type", "array", "items", ritem);
  osc = struct ();
  osc.type = "object";
  osc.properties = oprops;
  osc.required = {'query', 'total', 'shown', 'matches'};
  t.outputSchema = osc;
  T{end+1} = t;

  t = struct ();
  t.name = "octave_pkg";
  t.title = "Installed Packages";
  t.description = strcat ("List the add-on packages installed here, each", ...
    " package's own version, and which ones this server loaded. Name", ...
    " a package to see its dependencies, which the bare listing does not", ...
    " show. It does not report the Octave version, which the server", ...
    " instructions state.");
  props = struct ();
  props.name = struct ("type", "string", "description", ...
    "Optional package name; omit to list every installed package");
  isc = struct ();
  isc.type = "object";
  isc.properties = props;
  isc.additionalProperties = false;
  t.inputSchema = isc;
  pprops = struct ();
  pprops.name = struct ("type", "string");
  pprops.version = struct ("type", "string");
  pprops.loaded = struct ("type", "boolean");
  pprops.title = struct ("type", "string");
  pprops.depends = struct ("type", "array", "items", struct ("type", "string"));
  pprops.dir = struct ("type", "string");
  pitem = struct ();
  pitem.type = "object";
  pitem.properties = pprops;
  oprops = struct ();
  oprops.total = struct ("type", "integer");
  oprops.loaded = struct ("type", "integer");
  oprops.packages = struct ("type", "array", "items", pitem);
  osc = struct ();
  osc.type = "object";
  osc.properties = oprops;
  osc.required = {'total', 'loaded', 'packages'};
  t.outputSchema = osc;
  T{end+1} = t;

  t = struct ();
  t.name = "octave_registry";
  t.title = "The Octave Packages Index";
  t.description = strcat ("Look a name up in the published Octave Packages", ...
    " index: which packages provide it anywhere in the ecosystem, of what", ...
    " kind, and whether more than one does. A dated snapshot of that index,", ...
    " not of this machine, and not callable from here; octave_which reports", ...
    " what is actually present.");
  props = struct ();
  props.name = struct ("type", "string", "description", ...
    "Function, class or method name to look up, such as nanmax or AutoDiff.abs");
  isc = struct ();
  isc.type = "object";
  isc.properties = props;
  isc.required = {'name'};
  isc.additionalProperties = false;
  t.inputSchema = isc;
  rprops = struct ();
  rprops.package = struct ("type", "string");
  rprops.kind = struct ("type", "string");
  rprops.latest = struct ("type", "string");
  rprops.released = struct ("type", "string");
  ritem = struct ();
  ritem.type = "object";
  ritem.properties = rprops;
  oprops = struct ();
  oprops.name = struct ("type", "string");
  oprops.found = struct ("type", "boolean");
  oprops.installedHere = struct ("type", "boolean");
  oprops.snapshot = struct ("type", "string");
  oprops.providers = struct ("type", "array", "items", ritem);
  osc = struct ();
  osc.type = "object";
  osc.properties = oprops;
  osc.required = {'name', 'found', 'snapshot', 'providers'};
  t.outputSchema = osc;
  T{end+1} = t;

  if (! strcmp (surface, "eval"))
    return;
  endif

  ## Everything past here runs code and is reachable only from mcp.serveEval
  t = struct ();
  t.name = "octave_eval";
  t.title = "Evaluate Octave Code";
  t.description = strcat ("Run Octave code in this interpreter and return", ...
    " what it printed. Use this to compute, not to look a name up, which", ...
    " octave_which and octave_help do without running anything. Variables", ...
    " persist in the workspace you name; errors come back as text.");
  props = struct ();
  props.code = struct ("type", "string", "description", ...
    "Octave code to run, one or more statements");
  props.workspace = struct ("type", "string", "description", ...
    "Handle from an earlier call, or new for a fresh workspace");
  isc = struct ();
  isc.type = "object";
  isc.properties = props;
  ## Required, and deliberately so.  A model that omits an argument is the
  ## measured case, not the exotic one, and an omitted handle read as "start
  ## clean" loses a workspace with nothing said: the next call finds its
  ## variable undefined and the model blames its own code.
  isc.required = {'code', 'workspace'};
  isc.additionalProperties = false;
  t.inputSchema = isc;
  ## No outputSchema: the payload is the output of the code, which is prose to
  ## everyone but the interpreter.  The handle leads the text instead, where
  ## truncation cannot take it.
  T{end+1} = t;

endfunction

function t = instructionsText (surface)
  ## The version goes here, not into a tool.  This field is sent once, at
  ## connection, and stays in the model's context; a tool reporting a constant
  ## charges its description against every request for the life of the session.
  t = sprintf (strcat ("This server runs GNU Octave %s on %s. No tool", ...
                       " reports that; it is stated here. "), ...
               version (), computer ());
  t = [t, strcat("Introspects the GNU Octave interpreter this server runs", ...
    " inside. It sees only the packages its own launch command loaded, which", ...
    " may be fewer than an interactive session has; say so rather than", ...
    " concluding a name does not exist. Evaluates no code, runs no user", ...
    " function, and writes nothing.")];
  if (strcmp (surface, "eval"))
    ## Replaced rather than appended: the read-only claim is exactly false here
    ## and a model that reads both sentences is entitled to believe the first.
    t = sprintf (strcat ("This server runs GNU Octave %s on %s. No tool", ...
                         " reports that; it is stated here. "), ...
                 version (), computer ());
    t = [t, strcat("Introspects and evaluates code in the GNU Octave", ...
      " interpreter this server runs inside. It sees only the packages its", ...
      " own launch command loaded, which may be fewer than an interactive", ...
      " session has; say so rather than concluding a name does not exist.", ...
      " Code runs in a workspace named by a handle: pass new to open one and", ...
      " the handle it returns to keep the variables.")];
  endif
endfunction

function res = discoverResult (surface)

  caps = struct ();
  caps.tools = struct ();
  caps.resources = struct ();

  res = struct ();
  res.resultType = "complete";
  res.supportedVersions = supportedVersions ();
  res.capabilities = caps;
  res.instructions = instructionsText (surface);
  res.ttlMs = 3600000;
  res.cacheScope = "public";

endfunction

function res = toolsListResult (era, surface)

  res = struct ();
  if (strcmp (era, "modern"))
    res.resultType = "complete";
  endif
  res.tools = toolTable (surface);
  if (strcmp (era, "modern"))
    ## Cache hints are a 2026-07-28 addition and have no legacy counterpart
    res.ttlMs = 3600000;
    res.cacheScope = "public";
  endif

endfunction

function [res, code, msg, S] = toolsCall (params, era, S)

  res = [];
  code = 0;
  msg = "";

  if (! (isfield (params, "name") && ischar (params.name) ...
                                  && isrow (params.name)))
    code = -32602;
    msg = "Invalid params: tools/call requires a string name.";
    return;
  endif

  T = toolTable (S.surface);
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
    case 'octave_which'
      res = callOctaveWhich (args, era);
    case 'octave_help'
      res = callOctaveHelp (args, era);
    case 'octave_search'
      res = callOctaveSearch (args, era);
    case 'octave_pkg'
      res = callOctavePkg (args, era);
    case 'octave_registry'
      res = callOctaveRegistry (args, era);
    case 'octave_eval'
      [res, S] = callOctaveEval (args, era, S);
  endswitch

endfunction

function res = callOctaveWhich (args, era)

  res = struct ();
  if (strcmp (era, "modern"))
    res.resultType = "complete";
  endif

  bad = unknownArgs (args, {'name'});
  if (! isempty (bad))
    res.content = {textBlock(strrep (bad, "this tool", "octave_which"))};
    res.isError = true;
    return;
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
      " load path, and no installed package provides it either. Operators", ...
      " resolve by function name, such as plus for +, or ask octave_help,", ...
      " which reads them directly."), W.name))};
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
  W.state = "absent";
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
    W.state = "on the load path";
    W.kind = "built-in function";
    W.path = w_p;
    W.package = "core";
    W.matches = {struct("path", w_p, "package", "core")};
    return;
  endif

  if (strcmp (w_p, "variable"))
    W.found = true;
    W.state = "on the load path";
    W.kind = "variable";
    return;
  endif

  if (isempty (w_p))
    ## Not on the load path.  It may still sit in a package this server did
    ## not load, which is a different answer from "no such function" and is
    ## the one that stops a model concluding the name does not exist.
    w_pk = pkg ("list");
    w_hits = installedFind (nameFragments (w_name), w_pk);
    if (isempty (w_hits))
      return;
    endif
    W.found = true;
    W.state = "installed but not loaded";
    W.path = w_hits{1}.path;
    W.package = w_hits{1}.package;
    W.kind = fileKind (W.path);
    W.matches = w_hits;
    W.shadowed = numel (w_hits) - 1;
    return;
  endif

  W.found = true;
  W.state = "on the load path";
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

  if (strcmp (W.state, "installed but not loaded"))
    L = {sprintf("%s is a %s in %s, installed but NOT loaded by this server", ...
                 W.name, W.kind, W.package)};
    L{end+1} = "  it cannot be called here until that package is loaded";
  else
    L = {sprintf("%s is a %s", W.name, W.kind)};
  endif
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

  bad = unknownArgs (args, {'name'});
  if (! isempty (bad))
    res.content = {textBlock(strrep (bad, "this tool", "octave_help"))};
    res.isError = true;
    return;
  endif

  if (! (isfield (args, "name") && ischar (args.name) && isrow (args.name) ...
         && ! isempty (strtrim (args.name))))
    res.content = {textBlock(strcat ("octave_help needs a name: the", ...
      " function, class, method or operator to describe."))};
    res.isError = true;
    return;
  endif

  h_name = strtrim (args.name);

  ## The documentation caches first.  They hold text makeinfo has already
  ## rendered, so a hit costs a lookup where help costs a process: measured on
  ## 11.2.0, help is 0.32 s for any name, of which 0.31 s is __makeinfo__
  ## shelling out to makeinfo, against 0.001 s here.  A miss falls through to
  ## help unchanged, which is what covers namespaces and classdef methods,
  ## since doc_cache_create reaches neither.  Which cache may answer for a
  ## given name is helpCached's rule, and it is not simply whichever holds it.
  [h_txt, h_note] = helpCached (h_name);

  if (isempty (h_txt))
    h_err = "";
    try
      h_txt = help (h_name);
    catch h_e
      h_txt = "";
      h_err = h_e.message;
    end_try_catch

    if (! isempty (h_err) || isempty (strtrim (h_txt)))
      res.content = {textBlock(sprintf (strcat ("No help for %s on this", ...
        " server's load path. It may exist in a package this server did not", ...
        " load; octave_which reports where a name resolves."), h_name))};
      res.isError = true;
      return;
    endif
  endif

  ## Before the text, never after: the cap cuts from the end, and a note that
  ## truncation can remove is worse than no note at all.
  if (! isempty (h_note))
    h_txt = [h_note "\n\n" h_txt];
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

function [T, N] = helpCached (c_name)

  ## Rendered help text out of the documentation caches, or "" when the name
  ## is in none of them.  N is a note to place before that text, empty unless
  ## the answer comes from a package this server has not loaded.
  ##
  ## Locals are prefixed for the reason given in whichReport: which () resolves
  ## against this function's workspace, so a query for a name this function
  ## also uses would come back as "variable".

  T = "";
  N = "";

  C = helpCacheData ();
  c_i = find (strcmp (C.names, c_name));
  if (isempty (c_i))
    return;
  endif

  ## Where the interpreter would resolve this name.  A cached entry is served
  ## only when it belongs to the same place: a name shadowed by a directory no
  ## cache covers must be rendered rather than recalled, or the tool would
  ## describe a function other than the one that would run.
  c_owner = "";
  c_onpath = true;
  if (exist (c_name) == 5)
    c_owner = "core";                 # a built-in has no file on this machine
  else
    c_p = "";
    try
      c_p = which (c_name);
    catch
      c_p = "";
    end_try_catch
    if (isempty (c_p) || strcmp (c_p, "variable"))
      c_onpath = false;
    else
      c_owner = pathOwner (c_p, C.pkglist);
    endif
  endif

  if (c_onpath)
    ## Whichever cache owns the place the name resolves to answers, core's or
    ## a package's alike.  A release regenerates its cache, so the two travel
    ## in the same tarball; a maintainer's working tree installed over its own
    ## release label is the one case where they part, and that is a property
    ## of that machine rather than of the format.
    c_k = c_i(find (strcmp (C.owners(c_i), c_owner), 1));
  else
    ## Not on the load path, so the only entry that can answer is one from an
    ## installed package this server did not load.  Here the comparison is not
    ## against help, which cannot answer at all, but against nothing, so the
    ## cache is served with a note saying what the text is and what it is not:
    ## a model reading a cached answer as proof the function can be called
    ## here would be wrong, and would have no way to tell.
    c_k = c_i(find (! C.loaded(c_i), 1));
    if (! isempty (c_k))
      N = sprintf (strcat ("[%s is installed but NOT loaded by this", ...
        " server: this help comes from the package's documentation cache,", ...
        " and the function cannot be called until the package is loaded]"), ...
        C.owners{c_k});
    endif
  endif

  if (isempty (c_k))
    return;
  endif

  T = cacheText (C.texts{c_k});

endfunction

function C = helpCacheData ()

  ## Every documentation cache on this machine, read once per process and only
  ## when octave_help is first called: a session that never asks pays nothing,
  ## and one that does pays about two tenths of a second for 2238 entries
  ## across 27 files.  Like the ecosystem index this is a cache of files that
  ## cannot change while the process lives, not state.
  persistent cachedC;

  if (! isempty (cachedC))
    C = cachedC;
    return;
  endif

  C = struct ();
  C.names = {};
  C.texts = {};
  C.owners = {};
  C.loaded = logical ([]);
  C.pkglist = {};

  try
    C.pkglist = pkg ("list");
  catch
    C.pkglist = {};
  end_try_catch

  c_files = {};
  c_owner = {};
  c_load = logical ([]);

  c_core = "";
  try
    c_core = doc_cache_file ();
  catch
    c_core = "";
  end_try_catch
  if (! isempty (c_core) && exist (c_core, "file") == 2)
    c_files{end+1} = c_core;
    c_owner{end+1} = "core";
    c_load(end+1) = true;
  endif

  for c_j = 1:numel (C.pkglist)
    P = C.pkglist{c_j};
    ## The file in the package root must be named on its own: a dir () pattern
    ## with a "**" component matches at least one directory level, so it never
    ## returns d/doc-cache.  Four of the eleven packages installed here keep
    ## their only cache there, so relying on the walk alone loses them.
    c_hits = {fullfile(P.dir, "doc-cache")};
    c_d = dir (fullfile (P.dir, "**", "doc-cache"));
    for c_m = 1:numel (c_d)
      c_hits{end+1} = fullfile (c_d(c_m).folder, c_d(c_m).name);
    endfor
    for c_m = 1:numel (c_hits)
      if (exist (c_hits{c_m}, "file") == 2)
        c_files{end+1} = c_hits{c_m};
        c_owner{end+1} = sprintf ("%s %s", P.name, P.version);
        c_load(end+1) = logical (P.loaded);
      endif
    endfor
  endfor

  for c_m = 1:numel (c_files)
    c_c = {};
    try
      c_s = load (c_files{c_m});
      if (isfield (c_s, "cache"))
        c_c = c_s.cache;
      endif
    catch
      c_c = {};
    end_try_catch
    if (! iscell (c_c) || rows (c_c) < 2 || columns (c_c) < 1)
      continue;
    endif
    c_n = columns (c_c);
    C.names = [C.names, c_c(1,:)];
    C.texts = [C.texts, c_c(2,:)];
    C.owners = [C.owners, repmat(c_owner(c_m), 1, c_n)];
    C.loaded = [C.loaded, repmat(c_load(c_m), 1, c_n)];
  endfor

  cachedC = C;

endfunction

function T = cacheText (T)

  ## Core's cache is not the one doc_cache_create writes.  The file shipped
  ## with the interpreter is built by doc/interpreter/mk-doc-cache.pl, which
  ## runs makeinfo at --fill-column=1024 and applies neither of the
  ## substitutions __makeinfo__ makes, so its text keeps the " -- : " deftypefn
  ## prefix (1666 of 1670 entries) and leaks the manual's cross-reference
  ## anchors, as in "see 'dbstop': XREFdbstop for details" (85 entries).  Both
  ## rules below are core's own, taken from __makeinfo__, and with them applied
  ## the entries that differed from help in content stop differing.  The
  ## wrapping is not restored: it carries no information a model can use, and
  ## re-wrapping would mean reimplementing makeinfo's fill.  A package cache is
  ## written through __makeinfo__ and carries neither pattern, measured, which
  ## is why this is safe to run over every entry.
  T = regexprep (T, '^ -- : +', ' -- ', "lineanchors");
  T = regexprep (T, ': XREF[A-Za-z0-9_]+', '');
  T = regexprep (T, '\s+$', '');

endfunction

function res = callOctaveSearch (args, era)

  res = struct ();
  if (strcmp (era, "modern"))
    res.resultType = "complete";
  endif

  bad = unknownArgs (args, {'query'});
  if (! isempty (bad))
    res.content = {textBlock(strrep (bad, "this tool", "octave_search"))};
    res.isError = true;
    return;
  endif

  if (! (isfield (args, "query") && ischar (args.query) && isrow (args.query) ...
         && ! isempty (strtrim (args.query))))
    res.content = {textBlock(strcat ("octave_search needs a query: a word or", ...
      " phrase to look for in the help text."))};
    res.isError = true;
    res.structuredContent = emptySearch ("");
    return;
  endif

  s_q = strtrim (args.query);

  ## Always the whole help text, never the summary line alone.  Measured: for
  ## "correlation" the summary-only search misses kendall, whose summary reads
  ## "Compute Kendall's TAU" and never says correlation, though it is exactly
  ## what such a query wants.  The cost is about a second at worst.
  s_n = {};
  s_h = {};
  try
    [s_n, s_h] = lookfor ("-all", s_q);
  catch
    s_n = {};
    s_h = {};
  end_try_catch

  s_total = numel (s_n);
  if (s_total == 0)
    ## Not a tool error.  A lookup of a name that does not exist is the model
    ## having assumed something wrong and worth correcting; a search returning
    ## nothing is a fact about this installation and the search did its job.
    res.content = {textBlock(sprintf (strcat ("No function on this server's", ...
      " load path mentions \"%s\". Try a broader term, or note that this", ...
      " server sees only the packages its launch command loaded."), s_q))};
    res.isError = false;
    res.structuredContent = emptySearch (s_q);
    return;
  endif

  [s_n, s_h] = rankMatches (s_n, s_h, s_q);

  s_cap = searchCap ();
  s_shown = min (s_cap, s_total);

  s_rows = {};
  s_lines = {};
  for s_i = 1:s_shown
    s_sum = oneLine (s_h{s_i});
    s_rows{end+1} = struct ("name", s_n{s_i}, "summary", s_sum);
    s_lines{end+1} = sprintf ("  %-24s %s", s_n{s_i}, s_sum);
  endfor

  if (s_total > s_shown)
    s_head = sprintf ("%d of %d matches for \"%s\", best name matches first:", ...
                      s_shown, s_total, s_q);
  else
    s_head = sprintf ("%d matches for \"%s\":", s_total, s_q);
  endif

  sc = struct ();
  sc.query = s_q;
  sc.total = s_total;
  sc.shown = s_shown;
  sc.matches = s_rows;

  res.content = {textBlock(strjoin ([{s_head}, s_lines], "\n"))};
  res.isError = false;
  res.structuredContent = sc;

endfunction

function C = searchCap ()
  ## Measured: "matrix" returns 811 matches.  Forty ranked rows is a page a
  ## model can read; forty arbitrary rows of eight hundred is noise, which is
  ## why the ranking below is not decoration.
  C = 40;
endfunction

function S = emptySearch (q)
  S = struct ();
  S.query = q;
  S.total = 0;
  S.shown = 0;
  S.matches = {};
endfunction

function [N, H] = rankMatches (N, H, q)

  ## Alphabetical first, so that the ordering is fully determined and the same
  ## query always returns the same page
  [~, a] = sort (lower (N));
  N = N(a);
  H = H(a);

  ## Scoring on the shared prefix rather than on containment alone.  For the
  ## query "correlation", corr does not contain the query and containment
  ## scoring buried it under barttest and bvtcdf; the prefix it shares is four
  ## characters long and that is exactly the signal wanted.
  n = numel (N);
  lq = lower (q);
  score = zeros (1, n);
  for i = 1:n
    ln = lower (N{i});
    if (strcmp (ln, lq))
      score(i) = 1000;
    elseif (! isempty (strfind (ln, lq)))
      score(i) = 500;
    else
      m = min (numel (ln), numel (lq));
      k = 0;
      while (k < m && ln(k+1) == lq(k+1))
        k++;
      endwhile
      score(i) = k;
    endif
  endfor

  ## The alphabetical rank breaks ties, so the sort is stable by construction
  ## rather than by hoping sort () is
  [~, b] = sort (-score * (n + 1) + (1:n));
  N = N(b);
  H = H(b);

endfunction

function S = oneLine (txt)
  S = strtrim (strrep (strrep (txt, "\n", " "), "\r", " "));
  if (numel (S) > 100)
    S = [S(1:97) "..."];
  endif
endfunction

function res = callOctavePkg (args, era)

  res = struct ();
  if (strcmp (era, "modern"))
    res.resultType = "complete";
  endif

  bad = unknownArgs (args, {'name'});
  if (! isempty (bad))
    res.content = {textBlock(strrep (bad, "this tool", "octave_pkg"))};
    res.isError = true;
    return;
  endif

  L = pkg ("list");
  rows = {};
  for i = 1:numel (L)
    rows{end+1} = pkgRow (L{i});
  endfor

  want = "";
  if (isfield (args, "name") && ischar (args.name) && isrow (args.name))
    want = strtrim (args.name);
  endif

  nloaded = 0;
  for i = 1:numel (rows)
    nloaded += rows{i}.loaded;
  endfor

  if (! isempty (want))
    keep = {};
    for i = 1:numel (rows)
      if (strcmpi (rows{i}.name, want))
        keep{end+1} = rows{i};
      endif
    endfor
    if (isempty (keep))
      sc = struct ();
      sc.total = numel (rows);
      sc.loaded = nloaded;
      sc.packages = {};
      res.content = {textBlock(sprintf (strcat ("%s is not installed. %d", ...
        " packages are installed here; call octave_pkg with no argument to", ...
        " list them."), want, numel (rows)))};
      res.isError = true;
      res.structuredContent = sc;
      return;
    endif
    sc = struct ();
    sc.total = numel (rows);
    sc.loaded = nloaded;
    sc.packages = keep;
    res.content = {textBlock(pkgDetail (keep{1}))};
    res.isError = false;
    res.structuredContent = sc;
    return;
  endif

  lines = {sprintf("%d packages installed, %d loaded by this server:", ...
                   numel (rows), nloaded)};
  for i = 1:numel (rows)
    if (rows{i}.loaded)
      mark = "loaded";
    else
      mark = "-";
    endif
    lines{end+1} = sprintf ("  %-16s %-9s %-7s %s", rows{i}.name, ...
                            rows{i}.version, mark, rows{i}.title);
  endfor

  sc = struct ();
  sc.total = numel (rows);
  sc.loaded = nloaded;
  sc.packages = rows;

  res.content = {textBlock(strjoin (lines, "\n"))};
  res.isError = false;
  res.structuredContent = sc;

endfunction

function R = pkgRow (P)

  R = struct ();
  R.name = P.name;
  R.version = P.version;
  R.loaded = logical (P.loaded);
  R.title = "";
  if (isfield (P, "title") && ischar (P.title))
    R.title = P.title;
  endif
  R.depends = {};
  if (isfield (P, "depends") && iscell (P.depends))
    for i = 1:numel (P.depends)
      d = P.depends{i};
      if (isstruct (d) && isfield (d, "package"))
        R.depends{end+1} = sprintf ("%s%s%s", d.package, d.operator, d.version);
      endif
    endfor
  endif
  R.dir = P.dir;

endfunction

function T = pkgDetail (R)

  if (R.loaded)
    mark = "loaded by this server";
  else
    mark = "installed but not loaded by this server";
  endif
  L = {sprintf("%s %s, %s", R.name, R.version, mark)};
  if (! isempty (R.title))
    L{end+1} = sprintf ("  title:    %s", R.title);
  endif
  if (! isempty (R.depends))
    L{end+1} = sprintf ("  depends:  %s", strjoin (R.depends, ", "));
  endif
  L{end+1} = sprintf ("  dir:      %s", R.dir);
  T = strjoin (L, "\n");

endfunction

function H = installedFind (frags, L)

  ## Look inside packages that are installed but not loaded, by reading the
  ## filesystem only.  Nothing is loaded to answer this: pkg load would run the
  ## package's PKG_ADD, which is code this server does not run, and would
  ## mutate a process that serves unrelated conversations.
  ## One directory walk per distinct leaf name, not per fragment: the
  ## namespace and class-directory fragments share a leaf, so walking per
  ## fragment would double the work for every dotted name.
  leaves = {};
  for j = 1:numel (frags)
    [~, lf] = fileparts (frags{j});
    if (! any (strcmp (lf, leaves)))
      leaves{end+1} = lf;
    endif
  endfor

  H = {};
  for i = 1:numel (L)
    if (L{i}.loaded)
      continue;                       # a miss on the load path is a real miss
    endif
    for j = 1:numel (leaves)
      for e = {'.m', '.oct', '.mex'}
        d = dir (fullfile (L{i}.dir, "**", [leaves{j} e{1}]));
        for k = 1:numel (d)
          pth = fullfile (d(k).folder, d(k).name);
          for f = 1:numel (frags)
            tail = [frags{f} e{1}];
            if (numel (pth) >= numel (tail) ...
                && strcmp (pth(end-numel (tail)+1:end), tail))
              H{end+1} = struct ("path", pth, ...
                         "package", sprintf ("%s %s", L{i}.name, L{i}.version));
              break;
            endif
          endfor
        endfor
      endfor
    endfor
  endfor

endfunction

function R = resourceTable ()

  ## One resource, not three.  A version resource would duplicate what the
  ## instructions already say for free, and a packages resource would duplicate
  ## octave_pkg; two ways to ask one question is a cost, since the model has to
  ## choose and both descriptions have to explain the difference.
  R = {};
  r = struct ();
  r.uri = "octave://environment";
  r.name = "octave-environment";
  r.title = "This Server's Octave";
  r.description = strcat ("Version, platform, load path size and the", ...
    " packages this server loaded, as one readable snapshot.");
  r.mimeType = "text/plain";
  R{end+1} = r;

endfunction

function res = resourcesListResult (era)

  res = struct ();
  if (strcmp (era, "modern"))
    res.resultType = "complete";
  endif
  res.resources = resourceTable ();
  if (strcmp (era, "modern"))
    res.ttlMs = 3600000;
    res.cacheScope = "public";
  endif

endfunction

function [res, code, msg, data] = resourcesRead (params, era)

  res = [];
  code = 0;
  msg = "";
  data = struct ();

  if (! (isfield (params, "uri") && ischar (params.uri) && isrow (params.uri)))
    code = -32602;
    msg = "Invalid params: resources/read requires a string uri.";
    return;
  endif

  T = resourceTable ();
  hit = 0;
  for i = 1:numel (T)
    if (strcmp (T{i}.uri, params.uri))
      hit = i;
      break;
    endif
  endfor

  if (hit == 0)
    ## Not found is -32602 here, and the contents array must never come back
    ## empty for a resource that does not exist: empty is ambiguous between
    ## "exists and is blank" and "is not there".
    code = -32602;
    msg = "Resource not found";
    data = struct ("uri", params.uri);
    return;
  endif

  c = struct ();
  c.uri = T{hit}.uri;
  c.mimeType = "text/plain";
  c.text = environmentText ();

  res = struct ();
  if (strcmp (era, "modern"))
    res.resultType = "complete";
  endif
  res.contents = {c};

endfunction

function T = environmentText ()

  L = pkg ("list");
  loaded = {};
  for i = 1:numel (L)
    if (L{i}.loaded)
      loaded{end+1} = sprintf ("%s %s", L{i}.name, L{i}.version);
    endif
  endfor

  P = strsplit (path (), pathsep ());

  lines = {sprintf("GNU Octave %s", version ()), ...
           sprintf("platform:        %s", computer ()), ...
           sprintf("OCTAVE_HOME:     %s", OCTAVE_HOME ()), ...
           sprintf("load path:       %d directories", numel (P)), ...
           sprintf("packages:        %d installed, %d loaded", numel (L), ...
                   numel (loaded))};
  if (isempty (loaded))
    lines{end+1} = "loaded packages: none besides this server itself";
  else
    lines{end+1} = sprintf ("loaded packages: %s", strjoin (loaded, ", "));
  endif
  [n, v] = serverIdentity ();
  lines{end+1} = sprintf ("served by:       %s %s", n, v);

  T = strjoin (lines, "\n");

endfunction

function E = unknownArgs (args, allowed)

  ## Every tool here declares additionalProperties false, and a schema nothing
  ## enforces is a claim rather than a contract.  An unexpected argument is a
  ## tool error and not a protocol one: the model can drop it and retry.
  E = "";
  if (! (isstruct (args) && isscalar (args)))
    return;
  endif
  extra = {};
  f = fieldnames (args);
  for i = 1:numel (f)
    if (! any (strcmp (f{i}, allowed)))
      extra{end+1} = f{i};
    endif
  endfor
  if (! isempty (extra))
    E = sprintf ("%s takes only %s, but received: %s.", "this tool", ...
                 strjoin (allowed, ", "), strjoin (extra, ", "));
  endif

endfunction

function res = callOctaveRegistry (args, era)

  res = struct ();
  if (strcmp (era, "modern"))
    res.resultType = "complete";
  endif

  bad = unknownArgs (args, {'name'});
  if (! isempty (bad))
    res.content = {textBlock(strrep (bad, "this tool", "octave_registry"))};
    res.isError = true;
    return;
  endif

  [E, M] = ecosystemData ();
  if (isempty (E))
    res.content = {textBlock(strcat ("The ecosystem index is not present in", ...
      " this installation. It is generated at release time by regen_index;", ...
      " a package built without it cannot answer this."))};
    res.isError = true;
    return;
  endif

  if (! (isfield (args, "name") && ischar (args.name) && isrow (args.name) ...
         && ! isempty (strtrim (args.name))))
    res.content = {textBlock(strcat ("octave_registry needs a name: the", ...
      " function, class or method to look up in the index."))};
    res.isError = true;
    res.structuredContent = emptyRegistry ("", M);
    return;
  endif

  q = strtrim (args.name);
  hit = strcmp (E.names, q);
  if (! any (hit))
    ## A model gets the case wrong more often than the name
    hit = strcmpi (E.names, q);
  endif

  if (! any (hit))
    res.content = {textBlock(registryMiss (q, E, M))};
    res.isError = true;
    res.structuredContent = emptyRegistry (q, M);
    return;
  endif

  idx = find (hit);
  provs = {};
  for i = 1:numel (idx)
    p = struct ();
    p.package = E.packages{idx(i)};
    p.kind = E.kinds{idx(i)};
    [p.latest, p.released] = packageRelease (E, p.package);
    provs{end+1} = p;
  endfor

  sc = struct ();
  sc.name = E.names{idx(1)};
  sc.found = true;
  sc.snapshot = M.captured;
  sc.providers = provs;

  res.content = {textBlock(registryText (sc))};
  res.isError = false;
  res.structuredContent = sc;

endfunction

function [E, M] = ecosystemData ()

  ## Parsed once per process and only when this tool is first called: a session
  ## that never asks pays nothing, and one that does pays about two tenths of a
  ## second.  This is a cache of a file that cannot change while the process
  ## lives, not state: the same request still produces the same answer.
  persistent cachedE cachedM cachedTried;

  if (isempty (cachedTried))
    cachedTried = true;
    cachedE = [];
    cachedM = [];
    root = fileparts (fileparts (mfilename ("fullpath")));
    ef = fullfile (root, "data", "ecosystem.json");
    mf = fullfile (root, "data", "MANIFEST.json");
    if (exist (ef, "file") == 2 && exist (mf, "file") == 2)
      try
        cachedE = jsondecode (fileread (ef));
        cachedM = jsondecode (fileread (mf));
      catch
        cachedE = [];
        cachedM = [];
      end_try_catch
    endif
  endif

  E = cachedE;
  M = cachedM;

endfunction

function S = emptyRegistry (q, M)
  S = struct ();
  S.name = q;
  S.found = false;
  if (isstruct (M) && isfield (M, "captured"))
    S.snapshot = M.captured;
  else
    S.snapshot = "unknown";
  endif
  S.providers = {};
endfunction

function [latest, released] = packageRelease (E, pkg)
  latest = "";
  released = "";
  i = find (strcmp (E.pkgNames, pkg), 1);
  if (! isempty (i))
    latest = E.pkgLatest{i};
    released = E.pkgDate{i};
  endif
endfunction

function T = registryText (S)

  ## Every answer carries the snapshot date.  Without it "no package provides
  ## that" cannot be told from "no package provided that in August", and a
  ## model will read the first meaning into the second.
  if (numel (S.providers) == 1)
    L = {sprintf("%s is provided by one package in the Octave Packages index (snapshot %s):", ...
                 S.name, S.snapshot)};
  else
    L = {sprintf("%s is provided by %d packages in the Octave Packages index (snapshot %s):", ...
                 S.name, numel (S.providers), S.snapshot)};
  endif

  for i = 1:numel (S.providers)
    p = S.providers{i};
    nm = p.package;
    if (strcmp (nm, "__core__"))
      nm = "GNU Octave core";
    endif
    if (isempty (p.latest))
      L{end+1} = sprintf ("  %-24s %s", nm, p.kind);
    else
      L{end+1} = sprintf ("  %-24s %-9s latest %s, released %s", nm, p.kind, ...
                          p.latest, p.released);
    endif
  endfor

  L{end+1} = strcat ("This is the published index, not this server: use", ...
                     " octave_which for what is on its load path.");
  T = strjoin (L, "\n");

endfunction

function T = registryMiss (q, E, M)

  T = sprintf (strcat ("No package in the Octave Packages index provides", ...
                       " %s (snapshot %s)."), q, M.captured);

  ## A near miss is worth more than a bare no
  n = min (4, numel (q));
  near = unique (E.names(strncmpi (E.names, q, n)));
  near = near(! strcmpi (near, q));
  if (! isempty (near))
    if (numel (near) > 5)
      near = near(1:5);
    endif
    T = [T sprintf(" Names beginning similarly: %s.", strjoin (near, ", "))];
  endif

endfunction

function [res, S] = callOctaveEval (args, era, S)

  ## Locals are prefixed for the same reason as in helpCached and whichReport:
  ## nothing here shares a name with anything the evaluated code might use.

  res = struct ();
  if (strcmp (era, "modern"))
    res.resultType = "complete";
  endif

  e_bad = unknownArgs (args, {'code', 'workspace'});
  if (! isempty (e_bad))
    res.content = {textBlock(strrep (e_bad, "this tool", "octave_eval"))};
    res.isError = true;
    return;
  endif

  if (! (isfield (args, "code") && ischar (args.code) && isrow (args.code) ...
         && ! isempty (strtrim (args.code))))
    res.content = {textBlock(strcat ("octave_eval needs code: one or more", ...
      " Octave statements to run."))};
    res.isError = true;
    return;
  endif

  ## Every call says which workspace it means, and "new" is a thing to say
  ## rather than a thing to leave out.  A named workspace that is gone is a
  ## tool error, never a fresh one: starting clean in silence would answer the
  ## next question with the variables missing and no way to tell why.
  if (! (isfield (args, "workspace") && ischar (args.workspace) ...
         && isrow (args.workspace) && ! isempty (strtrim (args.workspace))))
    res.content = {textBlock(strcat ("octave_eval needs workspace: the", ...
      " handle an earlier call returned, or new for a fresh workspace."))};
    res.isError = true;
    return;
  endif

  e_h = strtrim (args.workspace);
  if (strcmp (e_h, "new"))
    [e_h, S] = newWorkspace (S);
  elseif (! isfield (S.ws, e_h))
    res.content = {textBlock(sprintf (strcat ("No workspace %s here. A", ...
      " handle lives until this server stops, or until it is the oldest of", ...
      " more than %d; pass new to start a fresh one."), e_h, wsCap ()))};
    res.isError = true;
    return;
  endif

  e_W = S.ws.(e_h);

  ## The shadows stand only while the code runs.  Anything this server does
  ## between calls, pkg included, needs the real functions back.
  e_dir = shadowDir ();
  e_on = false;
  unwind_protect
    if (exist (e_dir, "dir") == 7)
      warning ("off", "Octave:shadowed-function", "local");
      addpath (e_dir, "-begin");
      e_on = true;
    endif
    [e_out, e_W, e_err] = mcp.__evalIn__ (e_W, args.code);
  unwind_protect_cleanup
    if (e_on)
      warning ("off", "Octave:rmpath-not-found", "local");
      rmpath (e_dir);
    endif
  end_unwind_protect

  S.ws.(e_h) = e_W;
  S = touchWorkspace (S, e_h);

  ## The handle leads and the error follows it, both before the output, so
  ## that truncation from the end can take neither
  e_L = {sprintf("[workspace %s]", e_h)};
  if (! isempty (e_err))
    e_L{end+1} = sprintf ("[error] %s", e_err);
  endif
  e_names = fieldnames (e_W);
  if (isempty (strtrim (e_out)))
    e_L{end+1} = "[no output]";
  else
    e_L{end+1} = e_out;
  endif
  if (! isempty (e_names))
    e_L{end+1} = sprintf ("[variables] %s", strjoin (e_names', ", "));
  endif

  res.content = {textBlock(capText (strjoin (e_L, "\n"), evalCap ()))};
  res.isError = ! isempty (e_err);

endfunction

function B = evalCap ()
  ## The same budget as octave_help, for the same reason: a single reply worth
  ## roughly two thousand tokens is the most a user should pay without asking.
  ## Code that prints more than this is asking the wrong question of it, and
  ## the truncation marker says so plainly enough for a model to narrow it.
  B = 8192;
endfunction

function n = wsCap ()
  ## Not a resource limit: a workspace costs whatever its variables cost and
  ## eight of them cost eight times that.  It is a bound on how far back a
  ## handle can be reused, so that a session cannot accumulate workspaces for
  ## the life of a process without ever saying which one it means.
  n = 8;
endfunction

function d = shadowDir ()
  d = fullfile (fileparts (mfilename ("fullpath")), "evalshadow");
endfunction

function [h, S] = newWorkspace (S)

  ## Opaque and with entropy behind it, as the specification asks, because the
  ## transport is explicitly not a session: a client may interleave unrelated
  ## conversations on one connection, and a handle that can be guessed is one
  ## conversation reaching into another's variables.
  ##
  ## Deliberately not from rand.  The code this handle separates runs in this
  ## same interpreter and can reset the global random state, so a handle drawn
  ## from it is a handle that code can predict.  The clock, the process and a
  ## temporary name are outside its reach.
  h = "";
  while (isempty (h) || isfield (S.ws, h))
    e_seed = sprintf ("%s|%d|%.15g|%d", tempname (), getpid (), now (), ...
                      S.wsnext);
    e_sum = hash ("sha1", e_seed);
    h = ["ws" e_sum(1:16)];
    S.wsnext++;
  endwhile
  S.ws.(h) = struct ();
  S.wsorder{end+1} = h;

  while (numel (S.wsorder) > wsCap ())
    e_old = S.wsorder{1};
    S.wsorder(1) = [];
    if (isfield (S.ws, e_old))
      S.ws = rmfield (S.ws, e_old);
    endif
  endwhile

endfunction

function S = touchWorkspace (S, h)
  ## Most recently used last, which is the end the eviction does not take
  e_keep = ! strcmp (S.wsorder, h);
  S.wsorder = [S.wsorder(e_keep), {h}];
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
%! assert_equal (names, ...
%!   {'octave_which', 'octave_help', 'octave_search', 'octave_pkg', ...
%!    'octave_registry'});

%!test
%! ## The tool list is fixed for the life of the process, so it may be cached.
%! RESP = mcp.dispatch (mkreq ("tools/list", ""));
%! assert_equal (RESP.result.cacheScope, "public");

%!test
%! ## Every tool carries a valid schema object and closes it, which is the
%! ## declaration the unknown-argument check exists to honour.
%! RESP = mcp.dispatch (mkreq ("tools/list", ""), []);
%! for i = 1:numel (RESP.result.tools)
%!   sc = RESP.result.tools{i}.inputSchema;
%!   assert_equal (sc.type, "object");
%!   assert_equal (sc.additionalProperties, false);
%! endfor

%!test
%! ## TOOL_STYLE caps a description at 300 bytes, paid on every request.
%! RESP = mcp.dispatch (mkreq ("tools/list", ""));
%! for i = 1:numel (RESP.result.tools)
%!   assert_equal (numel (RESP.result.tools{i}.description) <= 300, true);
%! endfor

%!test
%! ## The same trap in the guidance the model reads about the whole server.
%! RESP = mcp.dispatch (mkreq ("server/discover", ""));
%! s = RESP.result.instructions;
%! assert_equal (isempty (strfind (s, "No tool reports that")), false);
%! assert_equal (isempty (strfind (s, "its own launch command loaded")), false);
%! assert_equal (isempty (strfind (s, "function, and writes nothing")), false);

%!test
%! ## And in the guidance carried by the legacy initialize result.
%! R = mcp.decodeRequest (['{"jsonrpc":"2.0","id":1,"method":"initialize",' ...
%!      '"params":{"protocolVersion":"2025-11-25"}}']);
%! RESP = mcp.dispatch (R, []);
%! s = RESP.result.instructions;
%! assert_equal (isempty (strfind (s, "No tool reports that")), false);
%! assert_equal (isempty (strfind (s, "function, and writes nothing")), false);

%!test
%! ## An argument the schema does not allow is a tool error naming it, since
%! ## additionalProperties false has to be enforced and not merely declared.
%! RESP = mcp.dispatch (mkreq ("tools/call", ...
%!                       '"name":"octave_which","arguments":{"name":"mean","zz":1}'), []);
%! t = RESP.result.content{1}.text;
%! assert_equal (RESP.result.isError, true);
%! assert_equal (isempty (strfind (t, "octave_which takes only name")), false);
%! assert_equal (isempty (strfind (t, "received: zz")), false);

%!test
%! ## Tool names must hold to the character set the protocol allows.
%! RESP = mcp.dispatch (mkreq ("tools/list", ""));
%! for i = 1:numel (RESP.result.tools)
%!   n = RESP.result.tools{i}.name;
%!   assert_equal (isempty (regexp (n, '^[A-Za-z0-9_.-]{1,128}$', "once")), false);
%! endfor

%!test
%! RESP = mcp.dispatch (mkreq ("tools/call", ...
%!                       '"name":"octave_which","arguments":{"name":"mean"}'), []);
%! assert_equal (RESP.result.isError, false);
%! assert_equal (RESP.result.content{1}.type, "text");
%! assert_equal (RESP.result.structuredContent.kind, "function");

%!test
%! ## Content must survive encoding as a JSON array, not a bare object.
%! RESP = mcp.dispatch (mkreq ("tools/call", ...
%!                       '"name":"octave_which","arguments":{"name":"mean"}'), []);
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
%! ## A bad argument is a tool error carrying text the model can act on,
%! ## never a protocol error, which a model cannot recover from.
%! RESP = mcp.dispatch (mkreq ("tools/call", ...
%!                       '"name":"octave_search","arguments":{"x":1}'), []);
%! assert_equal (isfield (RESP, "error"), false);
%! assert_equal (RESP.result.isError, true);
%! assert_equal (isempty (strfind (RESP.result.content{1}.text, "octave_search")), false);

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
%! assert_equal (names, ...
%!   {'octave_which', 'octave_help', 'octave_search', 'octave_pkg', ...
%!    'octave_registry'});

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
%! RESP = mcp.dispatch (plainreq ("tools/call", ...
%!          '"name":"octave_which","arguments":{"name":"mean"}'), S);
%! assert_equal (RESP.result.isError, false);
%! assert_equal (RESP.result.structuredContent.kind, "function");
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

%!function T = toolNamed (name)
%!  RESP = mcp.dispatch (mkreq ("tools/list", ""), []);
%!  T = [];
%!  for i = 1:numel (RESP.result.tools)
%!    if (strcmp (RESP.result.tools{i}.name, name))
%!      T = RESP.result.tools{i};
%!      return;
%!    endif
%!  endfor
%!endfunction

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
%! assert_equal (isempty (strfind (t, "no installed package provides it")), false);

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
%! t = toolNamed ("octave_which");
%! d = t.description;
%! assert_equal (t.name, "octave_which");
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
%! ## The cache answers with what help would have rendered, tested on a name
%! ## that proves the normalisation rather than one that never differed:
%! ## core's shipped cache is built by mk-doc-cache.pl, not by
%! ## doc_cache_create, and leaks the manual's cross-reference anchors.
%! RESP = mcp.dispatch (callhelp ("fgets"), []);
%! t = RESP.result.content{1}.text;
%! assert_equal (RESP.result.isError, false);
%! assert_equal (isempty (strfind (t, "XREF")), true);
%! assert_equal (regexprep (strtrim (t), '\s+', " "), ...
%!               regexprep (strtrim (help ("fgets")), '\s+', " "));

%!test
%! ## The deftypefn prefix of that same renderer is core's artefact and does
%! ## not reach a model either.
%! RESP = mcp.dispatch (callhelp ("dbclear"), []);
%! t = RESP.result.content{1}.text;
%! assert_equal (isempty (strfind (t, " -- : ")), true);
%! assert_equal (strncmp (t, " -- dbclear FCN", 15), true);

%!test
%! ## A shadowed name is rendered, never recalled: the cache holds core's
%! ## nthargout, the load path holds this one, and the tool must describe the
%! ## function that would run.  This is the same guard that keeps a loaded
%! ## package's own cache out of its answers.
%! d = fullfile (tempdir (), "mcp_help_shadow");
%! unwind_protect
%!   warning ("off", "Octave:shadowed-function", "local");
%!   mkdir (d);
%!   fid = fopen (fullfile (d, "nthargout.m"), "w");
%!   fprintf (fid, "## mcpzzshadow fixture\nfunction nthargout ()\nendfunction\n");
%!   fclose (fid);
%!   addpath (d);
%!   RESP = mcp.dispatch (callhelp ("nthargout"), []);
%!   t = RESP.result.content{1}.text;
%!   assert_equal (isempty (strfind (t, "mcpzzshadow")), false);
%! unwind_protect_cleanup
%!   warning ("off", "Octave:rmpath-not-found", "local");
%!   rmpath (d);
%!   confirm_recursive_rmdir (false, "local");
%!   rmdir (d, "s");
%! end_unwind_protect

%!test
%! ## A name in an installed package this server did not load is answered from
%! ## that package's cache and labelled, which is an answer help cannot give at
%! ## all.  The fixture is whatever this machine has, so the check asserts
%! ## nothing where every installed package is loaded or none ships a cache.
%! L = pkg ("list");
%! nm = "";
%! for i = 1:numel (L)
%!   if (L{i}.loaded)
%!     continue;
%!   endif
%!   f = fullfile (L{i}.dir, "doc-cache");
%!   if (exist (f, "file") != 2)
%!     continue;
%!   endif
%!   c = load (f);
%!   for j = 1:columns (c.cache)
%!     if (isempty (which (c.cache{1,j})))
%!       nm = c.cache{1,j};
%!       break;
%!     endif
%!   endfor
%!   if (! isempty (nm))
%!     break;
%!   endif
%! endfor
%! if (! isempty (nm))
%!   RESP = mcp.dispatch (callhelp (nm), []);
%!   t = RESP.result.content{1}.text;
%!   assert_equal (RESP.result.isError, false);
%!   assert_equal (strncmp (t, "[", 1), true);
%!   assert_equal (isempty (strfind (t, "installed but NOT loaded")), false);
%! endif

%!test
%! ## TOOL_STYLE, and the joins are not glued.
%! t = toolNamed ("octave_help");
%! d = t.description;
%! assert_equal (t.name, "octave_help");
%! assert_equal (numel (d) <= 300, true);
%! assert_equal (isempty (strfind (d, "as help renders it")), false);
%! assert_equal (isempty (strfind (d, "operators resolve here only")), false);
%! assert_equal (isempty (strfind (d, "does, not where it lives")), false);

%!function R = callsearch (query)
%!  meta = ['"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28",' ...
%!          '"io.modelcontextprotocol/clientCapabilities":{}}'];
%!  R = mcp.decodeRequest (['{"jsonrpc":"2.0","id":1,"method":"tools/call",' ...
%!       '"params":{"name":"octave_search","arguments":{"query":"' query '"},' ...
%!       meta '}}']);
%!endfunction

%!test
%! ## A core query returns the obvious function, and searching the whole help
%! ## text is what finds it: eig's summary sentence does not say "eigenvalue".
%! RESP = mcp.dispatch (callsearch ("eigenvalue"), []);
%! assert_equal (RESP.result.isError, false);
%! names = cellfun (@(m) m.name, RESP.result.structuredContent.matches, ...
%!                  "UniformOutput", false);
%! assert_equal (any (strcmp ("eig", names)), true);

%!test
%! ## Ranking, on a fixture built for it rather than on whatever this
%! ## installation happens to hold: exact name, then name containing the
%! ## query, then a match found only in the body of the help.
%! d = fullfile (tempdir (), "mcp_search_rank");
%! unwind_protect
%!   mkdir (d);
%!   defs = {"mcpzzother", "Compute something using mcpzzterm internally."; ...
%!           "mcpzztermlong", "A longer relative of the operation."; ...
%!           "mcpzzterm", "The basic operation."};
%!   for i = 1:rows (defs)
%!     fid = fopen (fullfile (d, [defs{i,1} ".m"]), "w");
%!     fprintf (fid, "## -*- texinfo -*-\n## @deftypefn {} {} %s ()\n## %s\n", ...
%!              defs{i,1}, defs{i,2});
%!     fprintf (fid, "## @end deftypefn\nfunction %s ()\nendfunction\n", defs{i,1});
%!     fclose (fid);
%!   endfor
%!   addpath (d);
%!   RESP = mcp.dispatch (callsearch ("mcpzzterm"), []);
%!   names = cellfun (@(m) m.name, RESP.result.structuredContent.matches, ...
%!                    "UniformOutput", false);
%!   assert_equal (names, {'mcpzzterm', 'mcpzztermlong', 'mcpzzother'});
%! unwind_protect_cleanup
%!   warning ("off", "Octave:rmpath-not-found", "local");
%!   rmpath (d);
%!   confirm_recursive_rmdir (false, "local");
%!   rmdir (d, "s");
%! end_unwind_protect

%!test
%! ## A broad query is capped, and says so, because a model can act on the
%! ## total by narrowing but cannot act on a silently shortened list.
%! RESP = mcp.dispatch (callsearch ("matrix"), []);
%! sc = RESP.result.structuredContent;
%! assert_equal (sc.shown, 40);
%! assert_equal (sc.total > sc.shown, true);
%! assert_equal (numel (sc.matches), 40);
%! assert_equal (isempty (strfind (RESP.result.content{1}.text, "of")), false);

%!test
%! ## Nothing found is not a tool error: a lookup of a name that does not
%! ## exist is a wrong assumption to correct, an empty search is a fact.
%! RESP = mcp.dispatch (callsearch ("mcpzznothingmatchesthis"), []);
%! assert_equal (RESP.result.isError, false);
%! assert_equal (RESP.result.structuredContent.total, 0);
%! assert_equal (isempty (strfind (RESP.result.content{1}.text, "launch command")), false);

%!test
%! ## A missing query is a tool error, and still conforms to the schema.
%! meta = ['"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28",' ...
%!         '"io.modelcontextprotocol/clientCapabilities":{}}'];
%! R = mcp.decodeRequest (['{"jsonrpc":"2.0","id":1,"method":"tools/call",' ...
%!      '"params":{"name":"octave_search","arguments":{},' meta '}}']);
%! RESP = mcp.dispatch (R, []);
%! assert_equal (RESP.result.isError, true);
%! assert_equal (RESP.result.structuredContent.total, 0);

%!test
%! ## Summaries are one line each: a wrapped help sentence must not become
%! ## several rows in what is presented as a table.
%! RESP = mcp.dispatch (callsearch ("eigenvalue"), []);
%! for i = 1:numel (RESP.result.structuredContent.matches)
%!   s = RESP.result.structuredContent.matches{i}.summary;
%!   assert_equal (any (s == "\n"), false);
%!   assert_equal (numel (s) <= 100, true);
%! endfor

%!test
%! ## The same query twice gives the same page, which is what lets a client
%! ## cache and a model reason about "the first result".
%! A = mcp.dispatch (callsearch ("matrix"), []);
%! B = mcp.dispatch (callsearch ("matrix"), []);
%! assert_equal (A.result.structuredContent.matches, B.result.structuredContent.matches);

%!test
%! ## TOOL_STYLE, and the joins are not glued.
%! t = toolNamed ("octave_search");
%! d = t.description;
%! assert_equal (t.name, "octave_search");
%! assert_equal (numel (d) <= 300, true);
%! assert_equal (isempty (strfind (d, "best name matches first")), false);
%! assert_equal (isempty (strfind (d, "where a known name lives")), false);

%!function R = callpkg (argjson)
%!  meta = ['"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28",' ...
%!          '"io.modelcontextprotocol/clientCapabilities":{}}'];
%!  R = mcp.decodeRequest (['{"jsonrpc":"2.0","id":1,"method":"tools/call",' ...
%!       '"params":{"name":"octave_pkg","arguments":' argjson ',' meta '}}']);
%!endfunction

%!test
%! ## With no argument, every installed package is listed, loaded or not.
%! RESP = mcp.dispatch (callpkg ("{}"), []);
%! sc = RESP.result.structuredContent;
%! assert_equal (RESP.result.isError, false);
%! assert_equal (sc.total, numel (sc.packages));
%! assert_equal (sc.total >= 1, true);

%!test
%! ## mcp is necessarily installed while these tests run.  The loaded count is
%! ## an invariant of the rows, not an assumption about this environment: a
%! ## source tree reached by addpath is on the path without pkg calling it
%! ## loaded, so asserting a count here would fail for the wrong reason.
%! RESP = mcp.dispatch (callpkg ("{}"), []);
%! sc = RESP.result.structuredContent;
%! names = cellfun (@(q) q.name, sc.packages, "UniformOutput", false);
%! assert_equal (any (strcmp ("mcp", names)), true);
%! n = 0;
%! for i = 1:numel (sc.packages)
%!   n += sc.packages{i}.loaded;
%! endfor
%! assert_equal (sc.loaded, n);

%!test
%! ## Naming a package gives its dependencies and directory.
%! RESP = mcp.dispatch (callpkg ('{"name":"mcp"}'), []);
%! sc = RESP.result.structuredContent;
%! assert_equal (numel (sc.packages), 1);
%! assert_equal (sc.packages{1}.name, "mcp");
%! assert_equal (isempty (sc.packages{1}.dir), false);
%! assert_equal (isempty (strfind (RESP.result.content{1}.text, "depends:")), false);

%!test
%! ## A package that is not installed is a wrong assumption to correct.
%! RESP = mcp.dispatch (callpkg ('{"name":"mcpzznosuchpackage"}'), []);
%! assert_equal (RESP.result.isError, true);
%! assert_equal (RESP.result.structuredContent.total >= 1, true);
%! assert_equal (numel (RESP.result.structuredContent.packages), 0);

%!test
%! ## The listing never loads anything: what was loaded before the call is
%! ## still what is loaded after it, which is the whole posture of this server.
%! before = pkg ("list");
%! nb = 0; for i = 1:numel (before), nb += before{i}.loaded; endfor
%! mcp.dispatch (callpkg ("{}"), []);
%! mcp.dispatch (callpkg ('{"name":"statistics"}'), []);
%! after = pkg ("list");
%! na = 0; for i = 1:numel (after), na += after{i}.loaded; endfor
%! assert_equal (na, nb);

%!test
%! ## TOOL_STYLE, and the joins are not glued.
%! t = toolNamed ("octave_pkg");
%! d = t.description;
%! assert_equal (t.name, "octave_pkg");
%! assert_equal (numel (d) <= 300, true);
%! assert_equal (isempty (strfind (d, "which ones this server loaded")), false);
%! assert_equal (isempty (strfind (d, "package's own version")), false);
%! assert_equal (isempty (strfind (d, "bare listing does not show")), false);
%! assert_equal (isempty (strfind (d, "not report the Octave version")), false);

%!test
%! ## The third state: a name that is not on the load path but does sit in an
%! ## installed package. Answering "not found" there is what makes a model
%! ## conclude a function does not exist when it merely is not loaded.
%! L = pkg ("list");
%! target = "";
%! for i = 1:numel (L)
%!   if (! L{i}.loaded)
%!     d = dir (fullfile (L{i}.dir, "**", "*.m"));
%!     if (! isempty (d))
%!       [~, target] = fileparts (d(1).name);
%!       break;
%!     endif
%!   endif
%! endfor
%! if (! isempty (target))
%!   RESP = mcp.dispatch (callwhich (target), []);
%!   W = RESP.result.structuredContent;
%!   assert_equal (W.found, true);
%!   assert_equal (W.state, "installed but not loaded");
%!   assert_equal (RESP.result.isError, false);
%!   assert_equal (isempty (strfind (RESP.result.content{1}.text, "NOT loaded")), false);
%! endif

%!test
%! ## A name in neither place says so plainly, now that both were searched.
%! RESP = mcp.dispatch (callwhich ("mcpzznosuchnameanywhere"), []);
%! assert_equal (RESP.result.structuredContent.state, "absent");
%! assert_equal (RESP.result.isError, true);

%!test
%! ## A resolvable name reports the state it is actually in.
%! RESP = mcp.dispatch (callwhich ("mean"), []);
%! assert_equal (RESP.result.structuredContent.state, "on the load path");

%!test
%! ## The version is carried by the instructions, sent once at connection,
%! ## rather than by a tool charging its description against every request.
%! RESP = mcp.dispatch (mkreq ("server/discover", ""), []);
%! s = RESP.result.instructions;
%! assert_equal (isempty (strfind (s, version ())), false);
%! assert_equal (isempty (strfind (s, computer ())), false);

%!test
%! ## A legacy client is told the same, in the initialize result.
%! R = mcp.decodeRequest (['{"jsonrpc":"2.0","id":1,"method":"initialize",' ...
%!      '"params":{"protocolVersion":"2025-11-25"}}']);
%! RESP = mcp.dispatch (R, []);
%! assert_equal (isempty (strfind (RESP.result.instructions, version ())), false);

%!test
%! ## Both eras declare the resources capability, or a client will never ask.
%! A = mcp.dispatch (mkreq ("server/discover", ""), []);
%! assert_equal (isfield (A.result.capabilities, "resources"), true);
%! R = mcp.decodeRequest (['{"jsonrpc":"2.0","id":1,"method":"initialize",' ...
%!      '"params":{"protocolVersion":"2025-11-25"}}']);
%! B = mcp.dispatch (R, []);
%! assert_equal (isfield (B.result.capabilities, "resources"), true);

%!test
%! ## One resource, and it is the one no tool duplicates.
%! RESP = mcp.dispatch (mkreq ("resources/list", ""), []);
%! assert_equal (numel (RESP.result.resources), 1);
%! assert_equal (RESP.result.resources{1}.uri, "octave://environment");

%!test
%! RESP = mcp.dispatch (mkreq ("resources/read", ...
%!                       '"uri":"octave://environment"'), []);
%! c = RESP.result.contents{1};
%! assert_equal (c.uri, "octave://environment");
%! assert_equal (c.mimeType, "text/plain");
%! assert_equal (isempty (strfind (c.text, version ())), false);
%! assert_equal (isempty (strfind (c.text, "load path:")), false);

%!test
%! ## A resource that does not exist is -32602, and must never come back as an
%! ## empty contents array, which is ambiguous between blank and absent.
%! RESP = mcp.dispatch (mkreq ("resources/read", '"uri":"octave://nope"'), []);
%! assert_equal (RESP.error.code, -32602);
%! assert_equal (RESP.error.data.uri, "octave://nope");
%! assert_equal (isfield (RESP, "result"), false);

%!test
%! RESP = mcp.dispatch (mkreq ("resources/read", ""), []);
%! assert_equal (RESP.error.code, -32602);
%! assert_equal (isempty (strfind (RESP.error.message, "string uri")), false);

%!test
%! ## The legacy envelope reaches resources too, and carries no resultType.
%! S = legacySession ();
%! RESP = mcp.dispatch (plainreq ("resources/read", ...
%!                       '"uri":"octave://environment"'), S);
%! assert_equal (isfield (RESP.result, "resultType"), false);
%! assert_equal (isempty (strfind (RESP.result.contents{1}.text, "platform:")), false);

%!function R = callreg (name)
%!  meta = ['"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28",' ...
%!          '"io.modelcontextprotocol/clientCapabilities":{}}'];
%!  R = mcp.decodeRequest (['{"jsonrpc":"2.0","id":1,"method":"tools/call",' ...
%!       '"params":{"name":"octave_registry","arguments":{"name":"' name '"},' ...
%!       meta '}}']);
%!endfunction

%!test
%! ## A name provided by one package, with that package's newest version.
%! RESP = mcp.dispatch (callreg ("kmeans"), []);
%! sc = RESP.result.structuredContent;
%! assert_equal (RESP.result.isError, false);
%! assert_equal (sc.found, true);
%! assert_equal (numel (sc.providers), 1);
%! assert_equal (sc.providers{1}.package, "statistics");
%! assert_equal (isempty (sc.providers{1}.latest), false);

%!test
%! ## A contested name reports every provider, which is the whole point of
%! ## carrying the index: 193 of its names have more than one.
%! RESP = mcp.dispatch (callreg ("normcdf"), []);
%! sc = RESP.result.structuredContent;
%! p = cellfun (@(x) x.package, sc.providers, "UniformOutput", false);
%! assert_equal (numel (sc.providers) > 1, true);
%! assert_equal (any (strcmp ("statistics", p)), true);

%!test
%! ## Core is a package in this data and must be named as what it is.
%! RESP = mcp.dispatch (callreg ("mean"), []);
%! p = cellfun (@(x) x.package, RESP.result.structuredContent.providers, ...
%!              "UniformOutput", false);
%! assert_equal (any (strcmp ("__core__", p)), true);
%! assert_equal (isempty (strfind (RESP.result.content{1}.text, "GNU Octave core")), false);

%!test
%! ## A dotted method name survives.  Octave's jsondecode mangles an object key
%! ## that is not an identifier, and 44% of these names carry a dot, which is
%! ## why the index is reshaped into arrays at release time rather than shipped
%! ## as an object keyed by name.
%! RESP = mcp.dispatch (callreg ("AutoDiff.abs"), []);
%! sc = RESP.result.structuredContent;
%! assert_equal (sc.found, true);
%! assert_equal (sc.name, "AutoDiff.abs");
%! assert_equal (sc.providers{1}.kind, "method");

%!test
%! ## Every answer carries the snapshot date, found or not: without it a "no"
%! ## cannot be told from "not as of August".
%! A = mcp.dispatch (callreg ("kmeans"), []);
%! B = mcp.dispatch (callreg ("mcpzznosuchnameatall"), []);
%! assert_equal (isempty (A.result.structuredContent.snapshot), false);
%! assert_equal (A.result.structuredContent.snapshot, B.result.structuredContent.snapshot);
%! assert_equal (isempty (strfind (A.result.content{1}.text, "snapshot")), false);
%! assert_equal (isempty (strfind (B.result.content{1}.text, "snapshot")), false);

%!test
%! ## A name in no package is a failed lookup, and the near names make it a
%! ## next step rather than a dead end.
%! RESP = mcp.dispatch (callreg ("nanmaxx"), []);
%! assert_equal (RESP.result.isError, true);
%! assert_equal (RESP.result.structuredContent.found, false);
%! t = RESP.result.content{1}.text;
%! assert_equal (isempty (strfind (t, "No package")), false);
%! assert_equal (isempty (strfind (t, "nanmax")), false);

%!test
%! ## The answer says it is about the index and not about this server, because
%! ## a result that reads as callable is the one trap this tool must avoid.
%! RESP = mcp.dispatch (callreg ("kmeans"), []);
%! t = RESP.result.content{1}.text;
%! assert_equal (isempty (strfind (t, "not this server")), false);
%! assert_equal (isempty (strfind (t, "octave_which")), false);

%!test
%! ## Case is the thing a model gets wrong most often.
%! RESP = mcp.dispatch (callreg ("KMEANS"), []);
%! assert_equal (RESP.result.isError, false);
%! assert_equal (RESP.result.structuredContent.name, "kmeans");

%!test
%! ## TOOL_STYLE, and the joins are not glued.
%! t = toolNamed ("octave_registry");
%! d = t.description;
%! assert_equal (t.name, "octave_registry");
%! assert_equal (numel (d) <= 300, true);
%! assert_equal (isempty (strfind (d, "anywhere in the ecosystem")), false);
%! assert_equal (isempty (strfind (d, "not of this machine")), false);

%!test
%! ## The legacy envelope reaches it too.
%! S = legacySession ();
%! RESP = mcp.dispatch (plainreq ("tools/call", ...
%!          '"name":"octave_registry","arguments":{"name":"kmeans"}'), S);
%! assert_equal (RESP.result.isError, false);
%! assert_equal (isfield (RESP.result, "resultType"), false);

%!function h = wshandle (t)
%!  L = strsplit (t, "\n");
%!  h = strtrim (strrep (strrep (L{1}, "[workspace ", ""), "]", ""));
%!endfunction

%!function [A, S] = evalcall (S, codejson, ws)
%!  meta = ['"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28",' ...
%!          '"io.modelcontextprotocol/clientCapabilities":{}}'];
%!  a = ['{"code":' codejson];
%!  if (! isempty (ws))
%!    a = [a ',"workspace":"' ws '"'];
%!  endif
%!  a = [a '}'];
%!  R = mcp.decodeRequest (['{"jsonrpc":"2.0","id":1,"method":"tools/call",' ...
%!       '"params":{"name":"octave_eval","arguments":' a ',' meta '}}']);
%!  [A, S] = mcp.dispatch (R, S);
%!endfunction

%!test
%! ## The read-only surface does not carry the evaluating tool, which is the
%! ## property that lets a user grant that server blanket permission.
%! RESP = mcp.dispatch (mkreq ("tools/list", ""), []);
%! nms = cellfun (@(t) t.name, RESP.result.tools, "UniformOutput", false);
%! assert_equal (any (strcmp (nms, "octave_eval")), false);
%! assert_equal (numel (nms), 5);

%!test
%! ## And a host configured for it cannot reach the tool by asking: an unknown
%! ## tool is a protocol error, not a tool that quietly runs.
%! S = mcp.__newSession__ ("read-only");
%! [A, S] = evalcall (S, jsonencode ("1 + 1"), "new");
%! assert_equal (isfield (A, "error"), true);
%! assert_equal (A.error.code, -32602);

%!test
%! ## The evaluating surface carries all six.
%! S = mcp.__newSession__ ("eval");
%! [A, S] = mcp.dispatch (mkreq ("tools/list", ""), S);
%! nms = cellfun (@(t) t.name, A.result.tools, "UniformOutput", false);
%! assert_equal (numel (nms), 6);
%! assert_equal (any (strcmp (nms, "octave_eval")), true);

%!test
%! ## A first call opens a workspace and says which, a second one carries the
%! ## variables forward, and clear takes one away.
%! S = mcp.__newSession__ ("eval");
%! [A, S] = evalcall (S, jsonencode ("mcpzza = 6; mcpzzb = 7;"), "new");
%! t = A.result.content{1}.text;
%! assert_equal (A.result.isError, false);
%! h = wshandle (t);
%! [A, S] = evalcall (S, jsonencode ("mcpzzc = mcpzza * mcpzzb"), h);
%! t = A.result.content{1}.text;
%! assert_equal (wshandle (t), h);
%! assert_equal (isempty (strfind (t, "mcpzzc = 42")), false);
%! [A, S] = evalcall (S, jsonencode ("clear mcpzza"), h);
%! t = A.result.content{1}.text;
%! assert_equal (isempty (strfind (t, "[variables] mcpzzb, mcpzzc")), false);

%!test
%! ## The handle is opaque and carries entropy, which the specification asks
%! ## for because a transport may interleave unrelated conversations: a
%! ## guessable handle is one of them reaching into another's variables.
%! S = mcp.__newSession__ ("eval");
%! [A, S] = evalcall (S, jsonencode ("1;"), "new");
%! h1 = wshandle (A.result.content{1}.text);
%! [A, S] = evalcall (S, jsonencode ("1;"), "new");
%! h2 = wshandle (A.result.content{1}.text);
%! assert_equal (numel (h1), 18);
%! assert_equal (strncmp (h1, "ws", 2), true);
%! assert_equal (isempty (regexp (h1(3:end), '^[0-9a-f]{16}$', "once")), false);
%! assert_equal (strcmp (h1, h2), false);

%!test
%! ## Two workspaces do not see each other, which is what makes the handle
%! ## worth passing rather than assuming.
%! S = mcp.__newSession__ ("eval");
%! [A, S] = evalcall (S, jsonencode ("mcpzzd = 1;"), "new");
%! h1 = wshandle (A.result.content{1}.text);
%! [A, S] = evalcall (S, jsonencode ("exist (\"mcpzzd\")"), "new");
%! t = A.result.content{1}.text;
%! assert_equal (strcmp (wshandle (t), h1), false);
%! assert_equal (isempty (strfind (t, "ans = 0")), false);

%!test
%! ## An error is a tool error a model can read, and the workspace survives it.
%! S = mcp.__newSession__ ("eval");
%! [A, S] = evalcall (S, jsonencode ("mcpzze = 5;"), "new");
%! h = wshandle (A.result.content{1}.text);
%! [A, S] = evalcall (S, jsonencode ("mcpzznosuchfunction (1)"), h);
%! t = A.result.content{1}.text;
%! assert_equal (isfield (A, "error"), false);
%! assert_equal (A.result.isError, true);
%! assert_equal (isempty (strfind (t, "[error]")), false);
%! [A, S] = evalcall (S, jsonencode ("mcpzze"), h);
%! assert_equal (isempty (strfind (A.result.content{1}.text, "mcpzze = 5")), false);

%!test
%! ## A handle that is not there is a tool error naming the rule, never a
%! ## fresh workspace: the variables would be missing with nothing said.
%! S = mcp.__newSession__ ("eval");
%! [A, S] = evalcall (S, jsonencode ("1 + 1"), "ws99");
%! t = A.result.content{1}.text;
%! assert_equal (A.result.isError, true);
%! assert_equal (isempty (strfind (t, "No workspace ws99")), false);
%! assert_equal (isempty (strfind (t, "pass new")), false);

%!test
%! ## The workspace argument is required: a model that omits one is told what
%! ## to pass rather than handed a clean workspace without being told.
%! S = mcp.__newSession__ ("eval");
%! [A, S] = evalcall (S, jsonencode ("1 + 1"), "");
%! t = A.result.content{1}.text;
%! assert_equal (A.result.isError, true);
%! assert_equal (isempty (strfind (t, "needs workspace")), false);

%!test
%! ## A subprocess writes past the capture and into the protocol stream, so it
%! ## is refused while a call runs.  Measured, not assumed: evalc takes every
%! ## in-process route to stdout and not this one.
%! S = mcp.__newSession__ ("eval");
%! [A, S] = evalcall (S, jsonencode ("system (\"echo mcpzzleak\")"), "new");
%! t = A.result.content{1}.text;
%! assert_equal (A.result.isError, true);
%! assert_equal (isempty (strfind (t, "protocol stream")), false);

%!test
%! ## The shadows stand only while the call runs; the real function is back
%! ## before the next request is read.
%! S = mcp.__newSession__ ("eval");
%! [A, S] = evalcall (S, jsonencode ("1 + 1"), "new");
%! [st, out] = system ("echo mcpzzback");
%! assert_equal (st, 0);
%! assert_equal (isempty (strfind (out, "mcpzzback")), false);

%!test
%! ## input has no terminal to read from and would wait for ever.
%! S = mcp.__newSession__ ("eval");
%! [A, S] = evalcall (S, jsonencode ("mcpzzf = input (\"give: \");"), "new");
%! assert_equal (A.result.isError, true);
%! assert_equal (isempty (strfind (A.result.content{1}.text, "no terminal")), false);

%!test
%! ## Output is cut at a line boundary with a marker, and the handle leads the
%! ## text so that truncation from the end can never take it.
%! S = mcp.__newSession__ ("eval");
%! [A, S] = evalcall (S, jsonencode ("for i=1:2000, printf (\"%d padding padding padding\\n\", i); end"), "new");
%! t = A.result.content{1}.text;
%! assert_equal (numel (t) <= 8192, true);
%! assert_equal (strncmp (t, "[workspace ws", 13), true);
%! assert_equal (isempty (strfind (t, "[truncated:")), false);

%!test
%! ## Nine workspaces, and the oldest is gone rather than the newest refused.
%! S = mcp.__newSession__ ("eval");
%! H = {};
%! for i = 1:9
%!   [A, S] = evalcall (S, jsonencode ("1;"), "new");
%!   H{end+1} = wshandle (A.result.content{1}.text);
%! endfor
%! [A, S] = evalcall (S, jsonencode ("1;"), H{1});
%! assert_equal (A.result.isError, true);
%! [A, S] = evalcall (S, jsonencode ("1;"), H{9});
%! assert_equal (A.result.isError, false);

%!test
%! ## Unknown arguments are refused by name, as everywhere else.
%! S = mcp.__newSession__ ("eval");
%! meta = ['"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28",' ...
%!         '"io.modelcontextprotocol/clientCapabilities":{}}'];
%! R = mcp.decodeRequest (['{"jsonrpc":"2.0","id":1,"method":"tools/call",' ...
%!      '"params":{"name":"octave_eval","arguments":{"code":"1+1",' ...
%!      '"workspace":"new","timeout":5},' meta '}}']);
%! [A, S] = mcp.dispatch (R, S);
%! assert_equal (A.result.isError, true);
%! assert_equal (isempty (strfind (A.result.content{1}.text, "timeout")), false);

%!test
%! ## Code is required and must say something.
%! S = mcp.__newSession__ ("eval");
%! [A, S] = evalcall (S, jsonencode ("   "), "new");
%! assert_equal (A.result.isError, true);
%! assert_equal (isempty (strfind (A.result.content{1}.text, "needs code")), false);

%!test
%! ## TOOL_STYLE, and the joins are not glued.
%! S = mcp.__newSession__ ("eval");
%! [A, S] = mcp.dispatch (mkreq ("tools/list", ""), S);
%! t = [];
%! for i = 1:numel (A.result.tools)
%!   if (strcmp (A.result.tools{i}.name, "octave_eval"))
%!     t = A.result.tools{i};
%!   endif
%! endfor
%! d = t.description;
%! assert_equal (numel (d) <= 300, true);
%! assert_equal (isempty (strfind (d, "not to look a name up")), false);
%! assert_equal (isempty (strfind (d, "persist in the workspace you name")), false);
%! assert_equal (numel (t.inputSchema.required), 2);

%!test
%! ## The instructions of the evaluating server do not carry the read-only
%! ## claim, which would be exactly false there.
%! S = mcp.__newSession__ ("eval");
%! [A, S] = mcp.dispatch (mkreq ("server/discover", ""), S);
%! t = A.result.instructions;
%! assert_equal (isempty (strfind (t, "Evaluates no code")), true);
%! assert_equal (isempty (strfind (t, "workspace named by a handle")), false);
%! assert_equal (isempty (strfind (t, "pass new to open one")), false);
%! RO = mcp.dispatch (mkreq ("server/discover", ""), []);
%! assert_equal (isempty (strfind (RO.result.instructions, "Evaluates no code")), false);
