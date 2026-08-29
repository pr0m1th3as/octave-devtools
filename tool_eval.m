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
## @deftypefn  {} {} tool_eval (@var{server}, @var{model})
## @deftypefnx {} {[@var{score}, @var{R}] =} tool_eval (@var{server}, @var{model})
##
## Measure whether a model picks the right tool.
##
## This is the check @file{TOOL_STYLE.md} requires and that nothing in
## @code{pkg test} can perform: a tool description is judged by whether a
## language model, given only the descriptions, chooses the right tool with the
## right arguments.  A description that reads well and scores badly is a bad
## description.
##
## It is @strong{not} a test of the package.  The code is covered by the
## built-in self tests; this measures the prose the tools advertise, which
## nothing else can reach.  It runs against a local model, and it needs one:
## @var{server} is an Ollama endpoint such as
## @qcode{"http://localhost:11434"} and @var{model} a tool-capable model on
## it.
##
## The tools handed to the model are the real ones, taken from this package's
## own @code{tools/list} answer, so what is measured is what ships.  Only
## parameters the schema marks required are registered, since every parameter
## given to a @code{toolFunction} becomes required and forcing an optional one
## would change the question being asked.
##
## Both the choice and the argument are scored, and reported separately.  The
## right tool with a useless argument returns nothing useful, so a measure that
## counts it as a pass flatters the descriptions; such a case is marked
## @qcode{ARGS} rather than @qcode{PASS}.
##
## Nothing is executed: only the choice of tool and its arguments are recorded.
## @end deftypefn

function [score, R] = tool_eval (server, model)

  if (nargin != 2)
    error ("tool_eval: SERVER and MODEL are required.");
  endif

  Q = questions ();
  reg = buildRegistry ();
  sys = serverInstructions ();

  R = {};
  npass = 0;
  ntool = 0;
  ntext = 0;
  for i = 1:numel (Q)

    ## A fresh session per question.  Not merely tidiness: clearHistory raises
    ## on its documented default (llms 0.2.0, ollama.m clearHistory, the 'all'
    ## branch clears the history and then falls through to an index that was
    ## never assigned), and questions that share a history are not independent
    ## measurements anyway.
    llm = ollama (server, model, 'chat');
    llm.tools = reg;
    ## A host puts the server's instructions into the system prompt.  Without
    ## this the harness cannot measure anything the instructions carry, and the
    ## question about the Octave version would be testing nothing at all.
    llm.systemMessage = sys;

    got = "";
    args = struct ();
    via = "";
    try
      out = chat (llm, Q{i}.ask);
      [got, args, via] = pickedTool (llm);
    catch err
      got = ["<error: " err.message ">"];
    end_try_catch

    tool_ok = any (strcmp (got, Q{i}.accept));
    arg_ok = argOK (args, Q{i}.mode, Q{i}.vals);
    ok = tool_ok && arg_ok;
    npass += ok;
    ntool += tool_ok;
    R{end+1} = struct ("ask", Q{i}.ask, "got", got, "args", args, ...
                       "via", via, "tool_ok", tool_ok, "arg_ok", arg_ok, "ok", ok);
    if (strcmp (via, "content"))
      ntext++;
    endif

    if (ok)
      tag = "PASS";
    elseif (tool_ok)
      tag = "ARGS";                   # right tool, argument that answers nothing
    else
      tag = "FAIL";
    endif
    ## The index leads the line so that repeat runs can be aggregated without
    ## parsing question text, which truncation makes unreliable
    printf ("%s %02d  %-52s -> %s%s", tag, i, trim60 (Q{i}.ask), ...
            showTool (got, args), viaMark (via));
    if (! ok)
      printf ("  (wanted %s)", strjoin (Q{i}.accept, " or "));
    endif
    printf ("\n");

  endfor

  score = npass / numel (Q);
  printf ("\ntool choice        %d of %d, %.0f%%\n", ntool, numel (Q), ...
          100 * ntool / numel (Q));
  printf ("choice + argument  %d of %d, %.0f%%\n", npass, numel (Q), 100 * score);
  if (ntext > 0)
    ## A choice written into the message body is not a tool call.  A real MCP
    ## host dispatches the tool_calls field and nothing else, so such a model
    ## would appear to work here and do nothing at all in practice.
    printf (strcat ("\n%d of those choices arrived as text in the message", ...
            " body rather than as a tool call.\nThey are scored as choices", ...
            " but would be INERT through a real MCP host.\n"), ntext);
  endif

  ## Which descriptions are implicated, which is the actionable part
  bad = {};
  for i = 1:numel (R)
    if (! R{i}.tool_ok && ! isempty (R{i}.got) && R{i}.got(1) != "<")
      bad{end+1} = sprintf ("%s taken for %s", R{i}.got, Q{i}.accept{1});
    endif
  endfor
  if (! isempty (bad))
    printf ("\nconfusions to fix:\n");
    u = unique (bad);
    for i = 1:numel (u)
      printf ("  %s\n", u{i});
    endfor
  endif

endfunction

function Q = questions ()

  ## Each question must discriminate: one where the wrong tool gives a visibly
  ## different answer.  The argument is scored as well as the choice, because
  ## the right tool with a useless argument returns nothing useful, and a
  ## measure that cannot see that flatters the descriptions.
  ##
  ## Argument modes: 'exact' equal to one of the values, case-insensitively;
  ## 'has' containing one of them; 'none' no argument at all; 'skip' not scored.
  ## An empty string among the values of 'exact' accepts no argument as well.

  Q = {};
  ## where a name lives, what kind it is, what it shadows
  Q{end+1} = mkq ("Which file defines the function kmeans?", ...
                  'exact', {'kmeans'}, {'octave_which'});
  Q{end+1} = mkq ("Which package provides normcdf here, and is it loaded?", ...
                  'exact', {'normcdf'}, {'octave_which'});
  Q{end+1} = mkq ("Does anything shadow the function mean here?", ...
                  'exact', {'mean'}, {'octave_which'});
  Q{end+1} = mkq ("Is ClassificationKNN a function or a class?", ...
                  'exact', {'ClassificationKNN'}, {'octave_which'});
  Q{end+1} = mkq ("Can I call regress right now, or is its package not loaded?", ...
                  'exact', {'regress'}, {'octave_which'});

  ## what a name does, how to call it
  Q{end+1} = mkq ("What does the function trapz do?", ...
                  'exact', {'trapz'}, {'octave_help'});
  Q{end+1} = mkq ("What arguments does linspace take?", ...
                  'exact', {'linspace'}, {'octave_help'});
  Q{end+1} = mkq ("Explain what the + operator does in Octave.", ...
                  'exact', {'+', 'plus'}, {'octave_help'});
  Q{end+1} = mkq ("Show me the documentation for histc.", ...
                  'exact', {'histc'}, {'octave_help'});

  ## the name is not known
  Q{end+1} = mkq ("What function computes a correlation coefficient?", ...
                  'has', {'correl'}, {'octave_search'});
  Q{end+1} = mkq ("Is there a function that partitions data into clusters?", ...
                  'has', {'cluster', 'partition'}, {'octave_search'});
  Q{end+1} = mkq ("I need to test a sample for normality. What should I use?", ...
                  'has', {'normal'}, {'octave_search'});
  Q{end+1} = mkq ("Which functions deal with eigenvalues?", ...
                  'has', {'eigen'}, {'octave_search'});

  ## packages; listing everything also answers the narrower ones, so an empty
  ## argument is accepted alongside the named package
  ## Not scored on its argument: an empty name is the right answer here and is
  ## unreachable while llms advertises every parameter as required
  Q{end+1} = mkq ("Which Octave packages are installed here?", ...
                  'skip', {}, {'octave_pkg'});
  ## The bare listing carries every package's version and loaded state, so for
  ## those two an omitted name still answers the question and is scored a pass.
  ## Dependencies are the one thing the listing does not show, so that one
  ## genuinely needs the name.  The test is whether the call answers the
  ## question asked, not whether the argument is the tidiest one available.
  Q{end+1} = mkq ("What version of the statistics package is installed?", ...
                  'exact', {'statistics', ''}, {'octave_pkg'});
  Q{end+1} = mkq ("Is the image package loaded?", ...
                  'exact', {'image', ''}, {'octave_pkg'});
  Q{end+1} = mkq ("What does the drafting package depend on?", ...
                  'exact', {'drafting'}, {'octave_pkg'});

  ## the version is in the instructions, so the right move is to call nothing
  Q{end+1} = mkq ("What version of Octave is this server running?", ...
                  'skip', {}, {''});

  ## the published index, not this machine.  Paired deliberately with the
  ## question below it: the same name asked two ways, once about what any
  ## package provides anywhere and once about what can be called here, which is
  ## the distinction octave_registry exists for and the one a model collapses
  ## if the description lets it.
  Q{end+1} = mkq ("Which packages provide a function called nanmax, anywhere in the Octave index?", ...
                  'has', {'nanmax'}, {'octave_registry'});

  ## two-part, either opening is defensible
  Q{end+1} = mkq ("Where does geom.offset come from and what does it do?", ...
                  'exact', {'geom.offset'}, {'octave_which', 'octave_help'});
  ## "Can I use nanmax here right now?" was tried and withdrawn: since
  ## octave_help answers out of the documentation caches it states callability
  ## itself for an unloaded package, so three tools answer that wording and the
  ## question stopped discriminating.  A path on this machine is octave_which's
  ## alone.
  Q{end+1} = mkq ("Where does nanmax live on this machine, and is it loaded?", ...
                  'has', {'nanmax'}, {'octave_which'});

endfunction

function s = mkq (ask, mode, vals, accept)
  s = struct ();
  s.ask = ask;
  s.mode = mode;
  s.vals = vals;
  s.accept = accept;
endfunction

function ok = argOK (args, mode, vals)

  v = "";
  if (isstruct (args) && ! isempty (fieldnames (args)))
    f = fieldnames (args);
    x = args.(f{1});
    if (ischar (x))
      v = x;
    elseif (isnumeric (x) && isscalar (x))
      v = num2str (x);
    endif
  endif
  v = strtrim (v);

  switch (mode)
    case 'skip'
      ok = true;
    case 'none'
      ok = isempty (v);
    case 'exact'
      ok = any (strcmpi (v, vals));
    case 'has'
      ok = false;
      for i = 1:numel (vals)
        if (! isempty (strfind (lower (v), lower (vals{i}))))
          ok = true;
          return;
        endif
      endfor
    otherwise
      ok = true;
  endswitch

endfunction

function sys = serverInstructions ()

  meta = ['"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28",' ...
          '"io.modelcontextprotocol/clientCapabilities":{}}'];
  req = devtools.decodeRequest (['{"jsonrpc":"2.0","id":1,"method":"server/discover",' ...
                            '"params":{' meta '}}']);
  A = devtools.dispatch (req, []);
  sys = A.result.instructions;

endfunction

function reg = buildRegistry ()

  meta = ['"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28",' ...
          '"io.modelcontextprotocol/clientCapabilities":{}}'];
  req = devtools.decodeRequest (['{"jsonrpc":"2.0","id":1,"method":"tools/list",' ...
                            '"params":{' meta '}}']);
  A = devtools.dispatch (req, []);

  tools = {};
  for i = 1:numel (A.result.tools)
    t = A.result.tools{i};
    tf = toolFunction (t.name, t.description, @() "");
    ## Every property, not only the required ones.  Registering only the
    ## required set left octave_pkg with no parameters at all, since its name
    ## is optional, and the model then could not pass one however clearly the
    ## description asked it to.  The reverse distortion is unavoidable here:
    ## toolFunction puts every added parameter into required, so llms 0.2.0 has
    ## no way to express an optional one, and octave_pkg's name is advertised
    ## as required to this harness alone.
    if (isfield (t.inputSchema, "properties"))
      nms = fieldnames (t.inputSchema.properties);
      for j = 1:numel (nms)
        p = t.inputSchema.properties.(nms{j});
        tf = addParameters (tf, nms{j}, p.type, p.description);
      endfor
    endif
    tools{end+1} = tf;
  endfor

  reg = toolRegistry (tools{:});

endfunction

function [name, args, via] = pickedTool (llm)

  name = "";
  args = struct ();
  via = "";
  st = llm.responseStats;
  if (! (isstruct (st) && isfield (st, "message")))
    return;
  endif
  if (! isfield (st.message, "tool_calls"))
    ## Some models express the choice as JSON in the message body instead of
    ## through the tool-call channel.  That is still a choice and worth
    ## measuring, but it is recorded separately because it does not work.
    [name, args] = toolFromText (st);
    if (! isempty (name))
      via = "content";
    endif
    return;
  endif
  via = "tool_calls";
  tc = st.message.tool_calls;
  if (isempty (tc))
    return;
  endif
  if (iscell (tc))
    tc = tc{1};
  else
    tc = tc(1);
  endif
  if (isfield (tc, "function"))
    if (isfield (tc.function, "name"))
      name = tc.function.name;
    endif
    if (isfield (tc.function, "arguments"))
      args = tc.function.arguments;
    endif
  endif

endfunction

function [name, args] = toolFromText (st)

  name = "";
  args = struct ();
  if (! (isfield (st.message, "content") && ischar (st.message.content)))
    return;
  endif
  txt = st.message.content;
  a = strfind (txt, "{");
  b = strfind (txt, "}");
  if (isempty (a) || isempty (b))
    return;
  endif
  try
    J = jsondecode (txt(a(1):b(end)));
  catch
    return;
  end_try_catch
  if (isstruct (J) && isscalar (J) && isfield (J, "name") && ischar (J.name))
    name = J.name;
    if (isfield (J, "arguments") && isstruct (J.arguments))
      args = J.arguments;
    endif
  endif

endfunction

function m = viaMark (via)
  if (strcmp (via, "content"))
    m = " [as text]";
  else
    m = "";
  endif
endfunction

function s = showTool (name, args)
  if (isempty (name))
    s = "(no tool)";
    return;
  endif
  s = name;
  if (isstruct (args) && ! isempty (fieldnames (args)))
    f = fieldnames (args);
    v = args.(f{1});
    if (ischar (v))
      s = sprintf ("%s(%s)", name, v);
    endif
  endif
endfunction

function s = trim60 (s)
  if (numel (s) > 52)
    s = [s(1:49) "..."];
  endif
endfunction
