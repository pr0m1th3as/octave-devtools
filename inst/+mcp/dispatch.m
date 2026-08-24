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
## @deftypefn {mcp} {@var{RESP} =} mcp.dispatch (@var{R})
##
## Answer one decoded request.
##
## @code{@var{RESP} = mcp.dispatch (@var{R})} takes the structure returned by
## @code{mcp.decodeRequest} and returns the response structure to send, or the
## empty matrix when nothing is to be sent.  A notification and a blank line are
## the two cases that produce no response, and a notification producing one
## would be a protocol violation rather than a nuisance.
##
## This function touches no stream and holds no state between calls.  That is
## what makes the whole protocol surface reachable by a test: every method,
## every error path and every tool result can be obtained by handing this
## function a structure and reading what comes back, with no client, no
## subprocess and no server running.  It is also what the protocol itself
## requires, since a request carries everything needed to answer it and nothing
## may be inferred from the requests that came before.
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

function RESP = dispatch (R)

  ## Input validation
  if (nargin != 1)
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

  RESP = [];

  switch (R.type)
    case 'blank'
      return;
    case 'notification'
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

  ## A legacy client opens with an initialize handshake, which this revision
  ## retired.  Such a client has no way to fall forward, so the error it gets
  ## is the only diagnostic its user will ever see: name the versions we speak.
  if (strcmp (R.method, "initialize"))
    data = struct ();
    data.supported = supportedVersions ();
    RESP = mcp.jsonrpcError (R.id, -32601, strcat ("This server implements", ...
             " MCP 2026-07-28 and later, which has no initialize handshake.", ...
             " Send server/discover with per-request _meta instead."), data);
    return;
  endif

  ## Every request carries its own protocol version and client capabilities
  [code, msg, data] = checkMeta (R.params);
  if (code != 0)
    RESP = mcp.jsonrpcError (R.id, code, msg, data);
    return;
  endif

  switch (R.method)
    case 'server/discover'
      RESP = okResult (R.id, discoverResult ());
    case 'tools/list'
      RESP = okResult (R.id, toolsListResult ());
    case 'tools/call'
      [res, code, msg] = toolsCall (R.params);
      if (code != 0)
        RESP = mcp.jsonrpcError (R.id, code, msg);
      else
        RESP = okResult (R.id, res);
      endif
    otherwise
      RESP = mcp.jsonrpcError (R.id, -32601, ...
                               sprintf ("Method not found: %s", R.method));
  endswitch

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

function RESP = okResult (id, res)
  res._meta = serverMeta ();
  RESP = struct ("jsonrpc", "2.0", "id", id);
  RESP.result = res;
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

endfunction

function res = discoverResult ()

  caps = struct ();
  caps.tools = struct ();

  res = struct ();
  res.resultType = "complete";
  res.supportedVersions = supportedVersions ();
  res.capabilities = caps;
  res.instructions = strcat ("Introspects the GNU Octave installation this", ...
    " server runs inside: the same load path, packages and version that the", ...
    " user's Octave has. Evaluates no code, runs no user function, and", ...
    " writes nothing.");
  res.ttlMs = 3600000;
  res.cacheScope = "public";

endfunction

function res = toolsListResult ()

  res = struct ();
  res.resultType = "complete";
  res.tools = toolTable ();
  ## Fixed at load time and never changing, so a client may cache it for long
  res.ttlMs = 3600000;
  res.cacheScope = "public";

endfunction

function [res, code, msg] = toolsCall (params)

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
      res = callOctaveVersion (args);
  endswitch

endfunction

function res = callOctaveVersion (args)

  res = struct ();
  res.resultType = "complete";

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
%! ## A legacy client gets the only diagnostic it can ever surface.
%! R = mcp.decodeRequest ('{"jsonrpc":"2.0","id":1,"method":"initialize"}');
%! RESP = mcp.dispatch (R);
%! assert_equal (RESP.error.code, -32601);
%! assert_equal (RESP.error.data.supported, {'2026-07-28'});

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
%! RESP = mcp.dispatch (mkreq ("tools/list", ""));
%! assert_equal (numel (RESP.result.tools), 1);
%! assert_equal (RESP.result.tools{1}.name, "octave_version");

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
%! assert_equal (isempty (strfind (s, "installation this server runs")), false);
%! assert_equal (isempty (strfind (s, "version that the user's Octave")), false);
%! assert_equal (isempty (strfind (s, "function, and writes nothing")), false);

%!test
%! ## And in the only diagnostic a legacy client can ever show its user.
%! R = mcp.decodeRequest ('{"jsonrpc":"2.0","id":1,"method":"initialize"}');
%! RESP = mcp.dispatch (R);
%! m = RESP.error.message;
%! assert_equal (isempty (strfind (m, "server implements MCP 2026-07-28")), false);
%! assert_equal (isempty (strfind (m, "handshake. Send server/discover")), false);

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
