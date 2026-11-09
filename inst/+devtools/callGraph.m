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

classdef callGraph
  ## -*- texinfo -*-
  ## @deftp {devtools} devtools.callGraph
  ##
  ## The call graph of a package.
  ##
  ## A @code{devtools.callGraph} object holds what a package's code can call,
  ## read from its source without running it, and, once @code{trace} has run,
  ## what its BISTs did.  Each function, local function, method, private
  ## function, class and compiled function is a node, and each call site an
  ## edge.  Packages the target depends on are followed as plain nodes, and
  ## core's functions are named end points, which are not followed.  The calling
  ## forms the package's docstrings document are held too.
  ##
  ## @example
  ## @group
  ## G = devtools.callGraph ('~/Octave/statistics');
  ## G = trace (G);                       # runs every BIST: minutes
  ## paths (G, 'To', 'residual_histogram');
  ## paths (G, 'From', 'LinearModel.predict');
  ## paths (G, 'From', 'y = LinearModel.predict (mdl, X)');
  ## paths (G, 'From', subclasses (G, 'PredictiveModel'));
  ## paths (G, 'To', nodes (G, 'Distribution_Classes/'));
  ## paths (G, 'To', 'hist', 'Nargout', 0);
  ## paths (G, 'From', 'fitlm', 'Returns', 'object');
  ## paths (G, 'Around', 'tableToMatrix', 'Depth', 1);
  ## draw (G, paths (G, 'From', 'fitlm'), 'fitlm.svg');
  ## draw (G, 'folders.svg', 'Level', 'folder', 'Scope', 'package', ...
  ##       'Core', false, 'Unresolved', false, 'Weight', 'files');
  ## gaps (G);
  ## write (G, 'graph');
  ## H = devtools.callGraph.read ('graph');
  ## @end group
  ## @end example
  ##
  ## The constructor reads; @code{trace} and @code{traceCall} run; @code{paths},
  ## @code{chains}, @code{nodes} and @code{subclasses} ask; @code{gaps} lists
  ## what is left to do; @code{draw} draws; @code{write} and @code{read} keep a
  ## run.
  ##
  ## @seealso{devtools.callGraph.paths, devtools.callGraph.trace,
  ## devtools.callGraph.gaps, devtools.callGraph.draw}
  ## @end deftp

  properties (SetAccess = private)
    ## -*- texinfo -*-
    ## @deftp {devtools.callGraph} {property} Package
    ##
    ## The name of the package read, a character vector.
    ##
    ## @end deftp
    Package = '';

    ## -*- texinfo -*-
    ## @deftp {devtools.callGraph} {property} Version
    ##
    ## The version of the package read, a character vector.
    ##
    ## @end deftp
    Version = '';

    ## -*- texinfo -*-
    ## @deftp {devtools.callGraph} {property} Nodes
    ##
    ## The nodes of the graph, a scalar structure of column vectors holding
    ## @code{node}, @code{kind}, @code{package}, @code{file}, @code{line},
    ## @code{class} and @code{abstract}, one row per node, sorted by
    ## @code{node}.
    ##
    ## @code{node} is the key: @qcode{'fitlm'}, a local function
    ## @qcode{'fitlm>lm_split_args'}, a private function
    ## @qcode{'Regression/private/foo'}, a method
    ## @qcode{'LinearModel.predict'}, a class @qcode{'LinearModel'}, which is
    ## its constructor too, or a core function @qcode{'sum'}.  @code{kind} is
    ## @qcode{'function'}, @qcode{'local'}, @qcode{'method'},
    ## @qcode{'private'}, @qcode{'compiled'}, @qcode{'class'} or
    ## @qcode{'core'}.  @code{file} is relative to the root of @code{package},
    ## with forward slashes on every system.
    ##
    ## @end deftp
    Nodes = struct ();

    ## -*- texinfo -*-
    ## @deftp {devtools.callGraph} {property} Edges
    ##
    ## The edges of the graph, a scalar structure of column vectors holding
    ## @code{from}, @code{to}, @code{kind}, @code{certainty}, @code{nargout},
    ## @code{guard}, @code{varargin}, @code{test}, @code{file} and @code{line},
    ## one row per call site, sorted by @code{from}, @code{to} and position.
    ##
    ## @code{kind} is @qcode{'call'}, @qcode{'handle'}, @qcode{'string'},
    ## @qcode{'method'}, @qcode{'constructor'}, @qcode{'inherit'},
    ## @qcode{'subsref'}, @qcode{'operator'}, @qcode{'getter'} or
    ## @qcode{'setter'}.  @code{certainty} is @qcode{'certain'},
    ## @qcode{'candidates'} or @qcode{'unresolved'}, where @code{to} is the name
    ## or expression as written.  A site that may reach several things has a
    ## row for each of them, except that a call whose name is also a plain or
    ## core function, with arguments of no settled class, has one row, to that
    ## function: @code{Nodes} says which classes define the name.
    ## @code{nargout} is the output count at the call, @code{NaN}
    ## where the site does not settle it.  @code{guard} is the text of the
    ## enclosing @code{if} and @code{switch} conditions.  @code{varargin} is
    ## true where the call forwards @code{varargin@{:@}}, and @code{test} where
    ## the call stands in a BIST.
    ##
    ## @end deftp
    Edges = struct ();

    ## -*- texinfo -*-
    ## @deftp {devtools.callGraph} {property} Forms
    ##
    ## The functional forms of the package, read from its docstrings, a scalar
    ## structure of column vectors holding @code{form}, @code{node},
    ## @code{nargin}, @code{nargout}, @code{option}, @code{value},
    ## @code{file} and @code{line}, one row per form, sorted by
    ## @code{form}.
    ##
    ## @code{form} is the canonical text and the key, as
    ## @qcode{'[b, r] = fitnlm (x, y, "Weights")'}, a method carrying its class,
    ## as @qcode{'y = LinearModel.predict (mdl, X)'}.  A method a class inherits
    ## is a form of that class, whose @code{node} is where it is defined.
    ## @code{option} and @code{value} are empty for a positional form, and
    ## @code{value} for an option whose values the docstring does not list.
    ##
    ## @end deftp
    Forms = struct ();

    ## -*- texinfo -*-
    ## @deftp {devtools.callGraph} {property} Seen
    ##
    ## What a BIST run called, read from @code{profile}, a scalar structure of
    ## column vectors holding @code{from}, @code{to}, @code{test_file},
    ## @code{block}, the number of the test block in its file, and @code{calls},
    ## how often @code{to} ran in that block.  A row to a core function holds
    ## a @code{block} of @code{NaN} and the file's total.  Only direct callers
    ## count: a call through a core function stays unseen.  Empty until
    ## @code{trace} has run.
    ##
    ## @end deftp
    Seen = struct ();

    ## -*- texinfo -*-
    ## @deftp {devtools.callGraph} {property} Calls
    ##
    ## What the calls written in BISTs returned, a scalar structure of column
    ## vectors holding @code{form}, empty where the call matches no form,
    ## @qcode{'?'} where it names an option whose value the call does not spell
    ## out,
    ## @code{call}, the call as written, @code{output}, the output's position,
    ## 0 for a call asking for none, @code{class}, the class it had,
    ## @code{test_file}, @code{block}, @code{line}, the line of the call, and
    ## @code{count}.  Empty until @code{trace} has run.
    ##
    ## @end deftp
    Calls = struct ();
  endproperties

  properties (SetAccess = private, Hidden)
    Root = '';
    Faults = {};
    Orphans = struct ();
    Index = struct ();
    Depends = {};
    Tested = struct ();
  endproperties

  ## Each table of a graph, empty: a field is a column, its class the class of
  ## the column.  The CSV files follow them.
  properties (Constant, Hidden)
    Tables = struct ( ...
      'nodes', struct ('node', {cell(0, 1)}, 'kind', {cell(0, 1)}, ...
                       'package', {cell(0, 1)}, 'file', {cell(0, 1)}, ...
                       'line', zeros (0, 1), 'class', {cell(0, 1)}, ...
                       'abstract', false (0, 1)), ...
      'edges', struct ('from', {cell(0, 1)}, 'to', {cell(0, 1)}, ...
                       'kind', {cell(0, 1)}, 'certainty', {cell(0, 1)}, ...
                       'nargout', zeros (0, 1), 'guard', {cell(0, 1)}, ...
                       'varargin', false (0, 1), 'test', false (0, 1), ...
                       'file', {cell(0, 1)}, 'line', zeros (0, 1)), ...
      'forms', struct ('form', {cell(0, 1)}, 'node', {cell(0, 1)}, ...
                       'nargin', zeros (0, 1), 'nargout', zeros (0, 1), ...
                       'option', {cell(0, 1)}, 'value', {cell(0, 1)}, ...
                       'file', {cell(0, 1)}, ...
                       'line', zeros (0, 1)), ...
      'seen', struct ('from', {cell(0, 1)}, 'to', {cell(0, 1)}, ...
                      'test_file', {cell(0, 1)}, 'block', zeros (0, 1), ...
                      'calls', zeros (0, 1)), ...
      'calls', struct ('form', {cell(0, 1)}, 'call', {cell(0, 1)}, ...
                       'output', zeros (0, 1), 'class', {cell(0, 1)}, ...
                       'test_file', {cell(0, 1)}, 'block', zeros (0, 1), ...
                       'line', zeros (0, 1), 'count', zeros (0, 1)), ...
      'run', struct ('package', {cell(0, 1)}, 'version', {cell(0, 1)}, ...
                     'octave', {cell(0, 1)}, 'date', {cell(0, 1)}), ...
      'sites', struct ('id', {}, 'name', {}, 'call', {}, 'nin', {}, ...
                       'strings', {}, 'line', {}));
  endproperties

  methods (Hidden)

    function disp (this)
      if (! isfield (this.Nodes, 'node'))
        printf ("  empty devtools.callGraph\n");
        return;
      endif
      printf ("  devtools.callGraph of %s %s: ", this.Package, this.Version);
      printf ("%d nodes, %d edges, %d forms\n", numel (this.Nodes.node), ...
              numel (this.Edges.from), numel (this.Forms.form));
      if (! isempty (this.Faults))
        printf ("  %d files did not parse whole:\n", numel (this.Faults));
        printf ("    %s\n", this.Faults{:});
      endif
      if (isfield (this.Tested, 'passed'))
        printf ("  BISTs: %d of %d passed\n", sum (this.Tested.passed), ...
                sum (this.Tested.total));
      endif
    endfunction

  endmethods

  methods (Access = public)

    ## -*- texinfo -*-
    ## @deftypefn {devtools.callGraph} {@var{G} =} devtools.callGraph (@var{TARGET})
    ##
    ## Read the call graph of a package.
    ##
    ## @var{TARGET} is a package source folder, one holding a
    ## @file{DESCRIPTION} file, or the name of an installed package.  A single
    ## file is refused: names resolve against a whole package.  The packages
    ## under @code{Depends} in its @file{DESCRIPTION} are read too, and must be
    ## installed.  Nothing is run.
    ##
    ## @seealso{devtools.callGraph.write, devtools.callGraph.read}
    ## @end deftypefn
    function this = callGraph (TARGET)

      if (nargin == 0)
        return;
      endif
      if (! (ischar (TARGET) && isrow (TARGET)))
        error ("devtools.callGraph: TARGET must be a character vector.");
      endif

      [this.Nodes, this.Edges, info] = readPackage (this, TARGET);
      this.Package = info.package;
      this.Version = info.version;
      this.Root = info.root;
      this.Faults = info.faults;
      this.Depends = info.depends;
      [this.Forms, this.Orphans] = readForms (this, ...
                                     info.root, info.package, ...
                                     this.Nodes, this.Edges);
      this.Index = graphIndex (this.Nodes, this.Edges, this.Forms, ...
                               this.Seen, this.Calls);

    endfunction

    ## -*- texinfo -*-
    ## @deftypefn  {devtools.callGraph} {@var{G} =} trace (@var{G})
    ## @deftypefnx {devtools.callGraph} {@var{G} =} trace (@var{G}, @var{NAMES})
    ##
    ## Run the package's BISTs and add what they did.
    ##
    ## A temporary copy of the test blocks runs under @code{profile}, block by
    ## block, the working tree staying untouched; the compiled functions of a
    ## source folder must be built.  It fills @code{Seen} and @code{Calls}.  A
    ## call seen proves its edge, which @code{paths} then treats as certain; a
    ## call not seen proves nothing, and a call through a core function is not
    ## seen.  @var{NAMES} is a file name, without folder or extension, or a cell
    ## array of those, whose BISTs alone run, replacing what was seen for them.
    ## BISTs in @file{.m} and @file{.m-tst} files run, and those in compiled
    ## sources do not.  Calls in @code{%!error} blocks are not reported, and
    ## calls with an indexed output target are reported without its class.
    ##
    ## @seealso{devtools.callGraph.paths}
    ## @end deftypefn
    function this = trace (this, NAMES)

      if (! isfield (this.Nodes, 'node'))
        error ("devtools.callGraph.trace: the graph is empty.");
      endif
      if (isempty (this.Root))
        error (strcat ("devtools.callGraph.trace: a graph read back", ...
                       " from files does not know its package."));
      endif
      files = unique (this.Edges.file(this.Edges.test));
      if (nargin > 1)
        if (ischar (NAMES))
          NAMES = {NAMES};
        endif
        if (! iscellstr (NAMES))
          error (strcat ("devtools.callGraph.trace: NAMES must be a cell", ...
                         " array of names."));
        endif
        base = regexprep (files, '^.*[/\\]|\.m(-tst)?$', '');
        unknown = setdiff (NAMES(:), base);
        if (! isempty (unknown))
          error ("devtools.callGraph.trace: no BISTs in: '%s'", unknown{1});
        endif
        files = files(ismember (base, NAMES));
      endif
      [S, C, info] = runTrace (this, files);
      if (isempty (fieldnames (this.Seen)))
        this.Seen = S;
        this.Calls = C;
      else
        this.Seen = replaceFiles (this.Seen, S, files);
        this.Calls = replaceFiles (this.Calls, C, files);
      endif
      this.Tested = info;
      this.Index = graphIndex (this.Nodes, this.Edges, this.Forms, ...
                               this.Seen, this.Calls);

    endfunction

    ## -*- texinfo -*-
    ## @deftypefn  {devtools.callGraph} {} traceCall (@var{G}, @var{FCN})
    ## @deftypefnx {devtools.callGraph} {} traceCall (@var{G}, @var{FCN}, @var{NOUT})
    ## @deftypefnx {devtools.callGraph} {@var{R} =} traceCall (@dots{})
    ##
    ## Run one exact call under @code{profile} and return its path.
    ##
    ## @var{FCN} is a function handle taking no arguments, such as
    ## @code{@@() predict (mdl, X)}, and @var{NOUT} the outputs asked of it, 0
    ## by default.  @var{R} is as @code{paths} returns it, every edge one the
    ## call took, @code{from} holding what the call itself reached and
    ## @code{forms} empty.  Only direct callers count, as for @code{trace}.
    ##
    ## @seealso{devtools.callGraph.paths, devtools.callGraph.trace}
    ## @end deftypefn
    function R = traceCall (this, FCN, NOUT = 0)

      if (nargin < 2)
        error (strcat ("devtools.callGraph.traceCall: invalid number of", ...
                       " input arguments."));
      endif
      if (! (is_function_handle (FCN) && nargin (FCN) <= 0))
        error (strcat ("devtools.callGraph.traceCall: FCN must be a", ...
                       " function handle taking no arguments."));
      endif
      if (! (isnumeric (NOUT) && isscalar (NOUT) && NOUT >= 0
             && NOUT == fix (NOUT)))
        error (strcat ("devtools.callGraph.traceCall: NOUT must be a", ...
                       " non-negative integer."));
      endif
      if (! isfield (this.Nodes, 'node'))
        error ("devtools.callGraph.traceCall: the graph is empty.");
      endif
      if (isempty (this.Root))
        error (strcat ("devtools.callGraph.traceCall: a graph read back", ...
                       " from files does not know its package."));
      endif
      S = runTrace (this, FCN, NOUT);
      r = callResult (S, this.Nodes, this.Edges, this.Index);
      if (nargout == 0)
        printPaths (r);
      else
        R = r;
      endif

    endfunction

    ## -*- texinfo -*-
    ## @deftypefn  {devtools.callGraph} {} paths (@var{G}, @qcode{'From'}, @var{SET})
    ## @deftypefnx {devtools.callGraph} {} paths (@var{G}, @qcode{'To'}, @var{SET})
    ## @deftypefnx {devtools.callGraph} {} paths (@var{G}, @qcode{'From'}, @var{A}, @qcode{'To'}, @var{B})
    ## @deftypefnx {devtools.callGraph} {} paths (@var{G}, @qcode{'Around'}, @var{SET})
    ## @deftypefnx {devtools.callGraph} {} paths (@dots{}, @var{Name}, @var{Value})
    ## @deftypefnx {devtools.callGraph} {@var{R} =} paths (@dots{})
    ##
    ## Follow the paths from a set of nodes, to one, between two, or both ways
    ## around one.
    ##
    ## @var{SET} is a name, a form or a cell array of those.  A name is a node
    ## key, or the last part of one, so that @qcode{'predict'} is every class's
    ## and @qcode{'residual_histogram'} a private function wherever it stands;
    ## a key selects that node alone, so @qcode{'sum'} is core's.
    ## @qcode{'Sub.go'} is the method class @qcode{Sub} reaches, inherited or
    ## not.  A class is its constructor, its methods and those it inherits, and
    ## settles dispatch for that class.  A form is the canonical text in
    ## @code{Forms}.  @code{nodes} and @code{subclasses} return sets.
    ##
    ## Output counts are followed along a path: a call that asks for an output
    ## does not reach a branch that runs only with none, at any depth.  A form
    ## starts from its own counts and leaves out the branches its @code{nargin}
    ## rules out; in the @qcode{'To'} set it counts only at its own outputs.
    ##
    ## A branch is left out only by a condition comparing @code{nargin} or
    ## @code{nargout} with a number, or the negation of one, with no @code{||}
    ## at its top level, and @code{nargin} only in the function the form names.
    ## Option values, computed flags and the data are not judged, so a path can
    ## hold a call that a given option value never makes, and @qcode{'certain'}
    ## says that a call stands in the code, not that the form runs it.
    ## @code{traceCall} shows what one exact call did.
    ##
    ## @qcode{'Around'} is one answer from a walk each way: what depends on the
    ## set and what it depends on.  @code{to} is then empty, and @code{chains}
    ## of such a result lists what lies downstream of the set.
    ##
    ## With no output the result is printed.  @var{R} is a structure holding
    ## @code{from} and @code{to}, the nodes selected, and three structures of
    ## columns: @code{forms}, with @code{form}, @code{node} and @code{status};
    ## @code{files}, with @code{file}, @code{package} and @code{status}; and
    ## @code{edges}, with the columns of @code{Edges}, @code{status} beside
    ## @code{certainty}, and @code{ran}, true for an edge a BIST run took, its
    ## @code{to} being the text as written where @code{status} is
    ## @qcode{'incomplete'}.  A fourth, @code{links}, holds @code{from},
    ## @code{to}, @code{weight} and @code{status}, one row per pair of boxes
    ## joined, heaviest first; it is empty unless @qcode{'Level'} or
    ## @qcode{'Weight'} asks for it.
    ## Where @var{SET} names forms, @code{ran} is limited to the test blocks
    ## that called them, a block calling several forms blurring them; it
    ## leaves nothing out, since a call not seen proves nothing.
    ##
    ## @code{status} is @qcode{'certain'}, where a chain of certain edges joins
    ## the two ends, @qcode{'possible'}, where one needs an edge that is only
    ## a candidate, or @qcode{'incomplete'}, where an unresolved call stands
    ## on the way and so no reading can say.  With no @qcode{'To'}, an
    ## incomplete form or file is one that can reach an unresolved call; with
    ## one, it is one that may reach the target through such a call, and the
    ## unresolved calls are among the edges.  Going forward, the call of a name
    ## that is also a plain function, with arguments of no settled class, ends
    ## at that function: its classes are not followed.  Going backward from a
    ## method, such a call counts as possible.
    ##
    ## @multitable @columnfractions 0.2 0.75
    ## @headitem @var{Name} @tab @var{Value}
    ##
    ## @item @qcode{'Depth'} @tab A positive integer or @code{Inf}: how many
    ## calls to walk from the set, 1 being its direct callers or callees.  The
    ## default is @code{Inf}, the whole chain.  It needs one direction or
    ## @qcode{'Around'}.
    ##
    ## @item @qcode{'Scope'} @tab @qcode{'all'}, the default, goes on through
    ## the packages the target depends on; @qcode{'package'} stops at them, a
    ## call into one staying as an end point.
    ##
    ## @item @qcode{'Core'} @tab A logical scalar: keep the calls of core
    ## functions.  The default is @code{true}.  A core function named in the
    ## @qcode{'To'} set stays.
    ##
    ## @item @qcode{'Certainty'} @tab Which edges to follow: @qcode{'all'}, the
    ## default, candidates included; @qcode{'proven'}, those the reading settled
    ## and those a BIST run took; or @qcode{'certain'}, those the reading
    ## settled alone.  A candidate that dispatch on a class asked about settles
    ## counts as settled.
    ##
    ## @item @qcode{'Unresolved'} @tab A logical scalar: keep the calls no
    ## reading settled among the edges.  The default is @code{true}.  A form or
    ## file that can reach one is still reported as @qcode{'incomplete'}.
    ##
    ## @item @qcode{'Tests'} @tab A logical scalar: follow the calls written in
    ## BISTs too.  The default is @code{false}.
    ##
    ## @item @qcode{'Kinds'} @tab An edge kind, or a cell array of them, as
    ## @code{Edges} names them: follow these alone.  The default is every kind.
    ##
    ## @item @qcode{'Level'} @tab What a box of @code{links} is: @qcode{'node'},
    ## the default, @qcode{'file'}, @qcode{'class'} or @qcode{'folder'}.
    ##
    ## @item @qcode{'Weight'} @tab What the weight of a link counts:
    ## @qcode{'calls'}, the default, or @qcode{'files'}, the distinct files the
    ## calls stand in.
    ##
    ## @item @qcode{'Nargout'} @tab A non-negative integer: count a call into
    ## the @qcode{'To'} set only if it asks for this many outputs, so that a
    ## function that draws only with no output is not counted as drawing.  A
    ## call whose count the reading did not settle counts as possible.  It
    ## needs a @qcode{'To'} set.
    ##
    ## @item @qcode{'Returns'} @tab A class, a cell array of classes, or
    ## @qcode{'object'} for any class not built in: keep the forms a BIST run
    ## saw returning one.  A form no run saw has no reading, so it stays,
    ## @qcode{'incomplete'}.  It needs @code{trace} to have run.
    ## @end multitable
    ##
    ## @seealso{devtools.callGraph.nodes, devtools.callGraph.subclasses,
    ## devtools.callGraph.chains}
    ## @end deftypefn
    function R = paths (this, varargin)

      if (! isfield (this.Nodes, 'node'))
        error ("devtools.callGraph.paths: the graph is empty.");
      endif
      Q = struct ('from', {{}}, 'to', {{}}, 'around', {{}}, 'depth', Inf, ...
                  'nargout', [], 'returns', {{}}, ...
                  'view', viewOption ());
      if (mod (numel (varargin), 2) != 0)
        error ("devtools.callGraph.paths: options come in Name, Value pairs.");
      endif
      for ii = 1:2:numel (varargin)
        name = varargin{ii};
        value = varargin{ii+1};
        if (! (ischar (name) && isrow (name)))
          error (strcat ("devtools.callGraph.paths: an option name must", ...
                         " be a character vector."));
        endif
        switch (lower (name))
          case {'from', 'to', 'around', 'returns'}
            if (ischar (value) && isrow (value))
              value = {value};
            elseif (! (iscellstr (value) && ! isempty (value)))
              error (strcat ("devtools.callGraph.paths: '%s' must be a", ...
                             " name or a form, or a cell array of those,", ...
                             " and not empty."), name);
            endif
            Q.(lower (name)) = value(:)';
          case 'depth'
            if (! (isnumeric (value) && isscalar (value) && value >= 1
                   && (value == fix (value) || isinf (value))))
              error (strcat ("devtools.callGraph.paths: 'Depth' must be a", ...
                             " positive integer or Inf."));
            endif
            Q.depth = value;
          case 'nargout'
            if (! (isnumeric (value) && isscalar (value) && value >= 0
                   && value == fix (value)))
              error (strcat ("devtools.callGraph.paths: 'Nargout' must be", ...
                             " a non-negative integer."));
            endif
            Q.nargout = value;
          otherwise
            [Q.view, msg, known] = viewOption (Q.view, name, value);
            if (! known)
              error ("devtools.callGraph.paths: unknown option: '%s'", name);
            elseif (! isempty (msg))
              error ("devtools.callGraph.paths: %s", msg);
            endif
        endswitch
      endfor
      if (isempty (Q.from) && isempty (Q.to) && isempty (Q.around))
        error (strcat ("devtools.callGraph.paths: give 'From', 'To', both", ...
                       " or 'Around'."));
      endif
      if (! isempty (Q.around) && ! (isempty (Q.from) && isempty (Q.to)))
        error (strcat ("devtools.callGraph.paths: 'Around' goes alone,", ...
                       " without 'From' or 'To'."));
      endif
      if (! isinf (Q.depth) && ! isempty (Q.from) && ! isempty (Q.to))
        error (strcat ("devtools.callGraph.paths: 'Depth' needs one", ...
                       " direction, or 'Around'."));
      endif
      if (! isempty (Q.nargout) && isempty (Q.to))
        error ("devtools.callGraph.paths: 'Nargout' needs a 'To' set.");
      endif
      if (! isempty (Q.returns) && ! isfield (this.Index.calls, 'form'))
        error ("devtools.callGraph.paths: no BIST run yet: use trace first.");
      endif

      N = this.Nodes;

      if (isempty (Q.around))
        r = answer (this, Q);
      else
        A = Q;
        A.from = Q.around;
        [down, inDown] = answer (this, A);
        A = Q;
        A.to = Q.around;
        [up, inUp] = answer (this, A);
        EXTRA = inUp(inUp) & ! inDown(inUp);
        r = struct ();
        r.from = down.from;
        r.to = cell (0, 1);
        r.edges = down.edges;
        for f = fieldnames (down.edges)'
          r.edges.(f{1}) = [down.edges.(f{1}); up.edges.(f{1})(EXTRA)];
        endfor
        r.links = linkRows (N, r.edges, Q.view);
        r.files = surest (down.files, up.files, ...
                          strcat (down.files.package, '|', down.files.file), ...
                          strcat (up.files.package, '|', up.files.file));
        r.forms = surest (down.forms, up.forms, down.forms.form, up.forms.form);
      endif
      if (nargout == 0)
        printPaths (r);
      else
        R = r;
      endif

    endfunction

    ## -*- texinfo -*-
    ## @deftypefn  {devtools.callGraph} {} gaps (@var{G})
    ## @deftypefnx {devtools.callGraph} {@var{R} =} gaps (@var{G})
    ##
    ## What a traced graph leaves to be done.
    ##
    ## @var{R} is a structure array with @code{file}, @code{line}, @code{rule}
    ## and @code{message}, as the linters return it; with no output the count of
    ## each rule is printed.  The rules are:
    ##
    ## @multitable @columnfractions 0.25 0.7
    ## @headitem Rule @tab Meaning
    ##
    ## @item @qcode{'no-bist'} @tab A documented form no BIST called.  A form a
    ## class inherits is covered by a call on another class, unless the method
    ## can dispatch back to its class.
    ##
    ## @item @qcode{'no-form'} @tab A call in a BIST that matches no documented
    ## form.
    ##
    ## @item @qcode{'undocumented-option'} @tab A literal the code reads as an
    ## option and the docstring omits.
    ##
    ## @item @qcode{'unread-option'} @tab A documented option no code names,
    ## following @code{varargin}.
    ##
    ## @item @qcode{'shadow'} @tab A function of the package that hides one of
    ## core's.
    ##
    ## @item @qcode{'no-node'} @tab A docstring header that names nothing in
    ## the package.
    ##
    ## @item @qcode{'unresolved'} @tab A call no reading settled.
    ##
    ## @item @qcode{'uncertain'} @tab A candidate edge no run proved, which may
    ## be dead code or a missing test.
    ## @end multitable
    ##
    ## A @qcode{'no-form'} finding is a call to review by hand, not a defect: a
    ## call naming several options, giving a size as separate dimensions or
    ## expanding its options from a cell array matches no single form.
    ##
    ## Detection of options reads literal strings, so one built at run time or
    ## checked through a shared parser is not seen: no finding does not mean
    ## none exists.
    ##
    ## @seealso{devtools.callGraph.trace}
    ## @end deftypefn
    function R = gaps (this)

      if (! isfield (this.Nodes, 'node'))
        error ("devtools.callGraph.gaps: the graph is empty.");
      endif
      if (isempty (this.Root))
        error (strcat ("devtools.callGraph.gaps: a graph read back", ...
                       " from files does not know its package."));
      endif
      if (! isfield (this.Seen, 'from'))
        error ("devtools.callGraph.gaps: no BIST run yet: use trace first.");
      endif
      ROOT = this.Root;
      PACKAGE = this.Package;
      N = this.Nodes;
      E = this.Edges;
      F = this.Forms;
      C = this.Calls;
      I = this.Index;
      file = line = rule = text = cell (6, 1);
      seen = ismember (F.form, C.form);
      signature = strcat (F.node, '|', num2str (F.nargin), '|', ...
                          num2str (F.nargout), '|', F.option, '|', F.value);
      done = ismember (signature, signature(seen));
      fixed = ! ismember (F.node, E.from(strcmp (E.certainty, 'candidates')));
      noBist = find (! seen & ! (done & fixed));
      n = numel (noBist);
      FILE = F.file(noBist);
      LINE = F.line(noBist);
      RULE = repmat ({'no-bist'}, n, 1);
      TEXT = strcat ({'no BIST calls: '}, F.form(noBist));
      file{1} = FILE;
      line{1} = LINE;
      rule{1} = RULE;
      text{1} = TEXT;
      k = find (strcmp (C.form, ''));
      [~, u] = unique (strcat (C.test_file(k), '|', C.call(k)));
      k = k(u);
      file{2} = C.test_file(k);
      line{2} = C.line(k);
      rule{2} = repmat ({'no-form'}, numel (k), 1);
      text{2} = strcat ({'call matches no documented form: '}, C.call(k));
      [file{3}, line{3}, rule{3}, text{3}] = optionGaps (ROOT, PACKAGE, N, ...
                                                         E, F, I);
      k = find (strcmp (N.package, PACKAGE) & strcmp (N.kind, 'function'));
      k = k(ismember (N.node(k), coreNames ()));
      file{4} = N.file(k);
      line{4} = N.line(k);
      rule{4} = repmat ({'shadow'}, numel (k), 1);
      text{4} = strcat ({'hides core: '}, N.node(k));
      live = ! E.test & strcmp (N.package(I.fromId), PACKAGE);
      a = find (live & strcmp (E.certainty, 'unresolved'));
      b = find (live & strcmp (E.certainty, 'candidates') & ! I.seen);
      file{5} = [E.file(a); E.file(b)];
      line{5} = [E.line(a); E.line(b)];
      rule{5} = [repmat({'unresolved'}, numel (a), 1); ...
                 repmat({'uncertain'}, numel (b), 1)];
      text{5} = [strcat(E.from(a), {' calls '}, E.to(a)); ...
                 strcat(E.from(b), {' may call '}, E.to(b))];
      file{6} = this.Orphans.file;
      line{6} = this.Orphans.line;
      rule{6} = repmat ({'no-node'}, numel (this.Orphans.file), 1);
      text{6} = strcat ({'documents nothing in the package: '}, ...
                        this.Orphans.name);
      file = vertcat (file{:});
      line = num2cell (vertcat (line{:}));
      rule = vertcat (rule{:});
      text = vertcat (text{:});
      r = struct ('file', file, 'line', line, 'rule', rule, 'message', text);
      if (nargout == 0)
        [u, ~, g] = unique ({r.rule});
        count = accumarray (g(:), 1);
        for ii = 1:numel (u)
          printf ("  %-20s %d\n", u{ii}, count(ii));
        endfor
      else
        R = r;
      endif

    endfunction

    ## -*- texinfo -*-
    ## @deftypefn {devtools.callGraph} {@var{C} =} nodes (@var{G}, @var{PATTERN})
    ##
    ## The keys of the nodes matching a regular expression.
    ##
    ## @var{PATTERN} is matched against the file of each node, a slash and its
    ## key, as @qcode{'inst/Regression/fitlm.m/fitlm'}, so that it can name a
    ## folder, a file, a key or a mix: @qcode{'Machine_Learning/.*predict'}.
    ## @var{C} is a cell array, usable as a set in @code{paths}: a group is a
    ## variable holding one.
    ##
    ## @seealso{devtools.callGraph.paths, devtools.callGraph.subclasses}
    ## @end deftypefn
    function C = nodes (this, PATTERN)

      if (nargin != 2)
        error ("devtools.callGraph.nodes: invalid number of input arguments.");
      endif
      if (! (ischar (PATTERN) && isrow (PATTERN)))
        error ("devtools.callGraph.nodes: PATTERN must be a character vector.");
      endif
      if (! isfield (this.Nodes, 'node'))
        error ("devtools.callGraph.nodes: the graph is empty.");
      endif
      text = strcat (this.Nodes.file, '/', this.Nodes.node);
      C = this.Nodes.node(! cellfun (@isempty, regexp (text, PATTERN, 'once')));

    endfunction

    ## -*- texinfo -*-
    ## @deftypefn {devtools.callGraph} {@var{C} =} subclasses (@var{G}, @var{CLASS})
    ##
    ## A class and all its descendants, at any depth.
    ##
    ## @var{C} is a cell array, usable as a set in @code{paths}.
    ##
    ## @seealso{devtools.callGraph.paths, devtools.callGraph.nodes}
    ## @end deftypefn
    function C = subclasses (this, CLASS)

      if (nargin != 2)
        error (strcat ("devtools.callGraph.subclasses: invalid number of", ...
                       " input arguments."));
      endif
      if (! (ischar (CLASS) && isrow (CLASS)))
        error (strcat ("devtools.callGraph.subclasses: CLASS must be a", ...
                       " character vector."));
      endif
      if (! isfield (this.Nodes, 'node'))
        error ("devtools.callGraph.subclasses: the graph is empty.");
      endif
      k = strcmp (this.Nodes.node, CLASS) & strcmp (this.Nodes.kind, 'class');
      if (! any (k))
        error ("devtools.callGraph.subclasses: no such class: '%s'", CLASS);
      endif
      C = {CLASS};
      ii = 1;
      while (ii <= numel (C))
        kids = this.Index.child(strcmp (this.Index.parent, C{ii}));
        C = [C; setdiff(kids, C)];
        ii += 1;
      endwhile

    endfunction

    ## -*- texinfo -*-
    ## @deftypefn  {devtools.callGraph} {} chains (@var{G}, @var{R})
    ## @deftypefnx {devtools.callGraph} {} chains (@var{G}, @var{R}, @var{LIMIT})
    ## @deftypefnx {devtools.callGraph} {[@var{C}, @var{DONE}] =} chains (@dots{})
    ##
    ## List the call chains in a result of @code{paths}.
    ##
    ## A chain runs from a node of @var{R}'s @code{from}, or from one nothing
    ## in the result calls, to a node of its @code{to}, or to one that calls
    ## nothing in the result, core functions and unresolved calls left out
    ## unless they are in @code{to}.  No node repeats in a chain.  @var{C} is a
    ## cell array of texts, the keys joined by @qcode{' > '}.
    ##
    ## The number of chains can grow without limit, so listing stops at
    ## @var{LIMIT}, 1000 by default, and @var{DONE} is false where it did.
    ## With no output the chains are printed.
    ##
    ## @seealso{devtools.callGraph.paths}
    ## @end deftypefn
    function [C, DONE] = chains (this, R, LIMIT = 1000)

      if (nargin < 2)
        error ("devtools.callGraph.chains: invalid number of input arguments.");
      endif
      if (! (isstruct (R) && isfield (R, 'edges') && isfield (R, 'from')))
        error ("devtools.callGraph.chains: R must be a result of paths.");
      endif
      if (! (isnumeric (LIMIT) && isscalar (LIMIT) && LIMIT >= 1))
        error ("devtools.callGraph.chains: LIMIT must be a positive number.");
      endif
      if (! isfield (this.Nodes, 'node'))
        error ("devtools.callGraph.chains: the graph is empty.");
      endif
      core = this.Nodes.node(strcmp (this.Nodes.kind, 'core'));
      isCore = ismember (R.edges.to, core);
      E = R.edges;
      c = cell (0, 1);
      done = true;
      if (! isempty (E.from))
        keep = ! strcmp (E.status, 'incomplete') & ! strcmp (E.kind, 'inherit');
        keep &= ! isCore | ismember (E.to, R.to);
        from = E.from(keep);
        to = E.to(keep);
        pairs = unique (strcat (from, "\t", to));
        sp = regexp (pairs, "\t", 'split');
        from = cellfun (@(c) c{1}, sp, 'UniformOutput', false);
        to = cellfun (@(c) c{2}, sp, 'UniformOutput', false);

        starts = R.from(:);
        if (isempty (starts))
          starts = setdiff (from, to);
        endif
        if (isempty (starts) && ! isempty (from))
          starts = from(1);
        endif

        for ii = 1:numel (starts)
          [c, done] = descend ({starts{ii}}, from, to, R.to, c, LIMIT);
          if (! done)
            break;
          endif
        endfor
      endif
      if (nargout == 0)
        printf ("  %s\n", c{:});
        if (! done)
          printf ("  (stopped at %d chains)\n", LIMIT);
        endif
      else
        C = c;
        DONE = done;
      endif

    endfunction

    ## -*- texinfo -*-
    ## @deftypefn  {devtools.callGraph} {} draw (@var{G}, @var{FILE})
    ## @deftypefnx {devtools.callGraph} {} draw (@var{G}, @var{R}, @var{FILE})
    ## @deftypefnx {devtools.callGraph} {} draw (@dots{}, @var{Name}, @var{Value})
    ##
    ## Draw the graph of the package, or a result of @code{paths}.
    ##
    ## The extension of @var{FILE} decides what is written: @file{.dot} is
    ## Graphviz source and needs nothing installed; @file{.svg} and @file{.pdf}
    ## run Graphviz.  Certain edges are solid, candidates dashed, unresolved
    ## ones dotted red, inheritance a hollow arrow; a node's shape gives its
    ## kind.  Methods are boxed by class, an inherited one once, in the class
    ## defining it, and other nodes by folder.  In an SVG a node's tooltip gives
    ## its file and line.  The calls written in BISTs are not drawn for the
    ## package; a result draws what it holds.
    ##
    ## @multitable @columnfractions 0.2 0.75
    ## @headitem @var{Name} @tab @var{Value}
    ##
    ## @item @qcode{'Level'} @tab What a box is: @qcode{'node'},
    ## @qcode{'file'}, @qcode{'class'}, the class diagram, or @qcode{'folder'}.
    ## Edges merge, their width showing what they carry.  The default is
    ## @qcode{'file'} for the package and @qcode{'node'} for a result.
    ##
    ## @item @qcode{'Weight'} @tab What the width of a merged edge counts:
    ## @qcode{'calls'}, the default, or @qcode{'files'}, the distinct files the
    ## calls stand in.
    ##
    ## @item @qcode{'Scope'} @tab @qcode{'all'}, the default, draws the packages
    ## the target depends on; @qcode{'package'} draws no edge starting in one, a
    ## call into one staying as an end point.
    ##
    ## @item @qcode{'Core'} @tab A logical scalar: draw core functions.  The
    ## default is @code{true}.
    ##
    ## @item @qcode{'Certainty'} @tab Which edges to draw: @qcode{'all'}, the
    ## default, candidates included; @qcode{'proven'}, those the reading settled
    ## and those a BIST run took; or @qcode{'certain'}, those the reading
    ## settled alone.
    ##
    ## @item @qcode{'Unresolved'} @tab A logical scalar: draw the calls no
    ## reading settled.  The default is @code{true}.
    ##
    ## @item @qcode{'Kinds'} @tab An edge kind, or a cell array of them, as
    ## @code{Edges} names them: draw these alone.  With @qcode{'inherit'} alone
    ## and @qcode{'Level'} @qcode{'class'} it is the class diagram.  The default
    ## is every kind.
    ## @end multitable
    ##
    ## @seealso{devtools.callGraph.paths}
    ## @end deftypefn
    function draw (this, varargin)

      if (! isfield (this.Nodes, 'node'))
        error ("devtools.callGraph.draw: the graph is empty.");
      endif
      R = [];
      if (numel (varargin) > 0 && isstruct (varargin{1}))
        R = varargin{1};
        if (! isfield (R, 'edges'))
          error ("devtools.callGraph.draw: R must be a result of paths.");
        endif
        varargin(1) = [];
      endif
      if (isempty (varargin))
        error ("devtools.callGraph.draw: invalid number of input arguments.");
      endif
      file = varargin{1};
      if (! (ischar (file) && isrow (file)))
        error ("devtools.callGraph.draw: FILE must be a character vector.");
      endif
      varargin(1) = [];
      [~, ~, ext] = fileparts (file);
      if (! any (strcmp (ext, {'.dot', '.svg', '.pdf'})))
        error ("devtools.callGraph.draw: unknown file type: '%s'", ext);
      endif
      if (mod (numel (varargin), 2) != 0)
        error ("devtools.callGraph.draw: options come in Name, Value pairs.");
      endif
      opt = viewOption ();
      opt.extra = {};
      if (isempty (R))
        opt.level = 'file';
      else
        opt.tests = true;
      endif
      for ii = 1:2:numel (varargin)
        if (! (ischar (varargin{ii}) && isrow (varargin{ii})))
          error (strcat ("devtools.callGraph.draw: an option name must be", ...
                         " a character vector."));
        endif
        msg = '';
        known = ! strcmpi (varargin{ii}, 'tests');
        if (known)
          [opt, msg, known] = viewOption (opt, varargin{ii}, ...
                                                          varargin{ii+1});
        endif
        if (! known)
          error ("devtools.callGraph.draw: unknown option: '%s'", varargin{ii});
        elseif (! isempty (msg))
          error ("devtools.callGraph.draw: %s", msg);
        endif
      endfor

      if (isempty (R))
        A = this.Edges;
        ran = this.Index.seen;
        status = repmat ({'possible'}, numel (A.from), 1);
        status(strcmp (A.certainty, 'certain') | ran) = {'certain'};
        status(strcmp (A.certainty, 'unresolved')) = {'incomplete'};
        E = struct ('from', {A.from}, 'to', {A.to}, 'kind', {A.kind}, ...
                    'status', {status}, 'certainty', {A.certainty}, ...
                    'test', A.test, 'ran', ran, 'file', {A.file}, ...
                    'line', A.line);
      else
        E = R.edges;
        opt.extra = [R.from(:); R.to(:)];
      endif
      K = keptEdges (opt, this.Nodes, E, this.Package);
      switch (opt.certainty)
        case 'certain'
          K &= ! strcmp (E.certainty, 'candidates');
        case 'proven'
          K &= ! strcmp (E.certainty, 'candidates') | E.ran;
      endswitch
      if (! opt.unresolved)
        K &= ! strcmp (E.certainty, 'unresolved');
      endif
      for f = fieldnames (E)'
        E.(f{1}) = E.(f{1})(K);
      endfor
      [~, idx] = ismember (E.to, this.Nodes.node);
      if (! opt.core)
        isCore = false (size (idx));
        isCore(idx > 0) = strcmp (this.Nodes.kind(idx(idx > 0)), 'core');
        for f = fieldnames (E)'
          E.(f{1}) = E.(f{1})(! isCore);
        endfor
      endif

      switch (opt.level)
        case 'node'
          text = nodeGraph (this.Nodes, E, opt.extra);
        otherwise
          text = mergedGraph (E, this.Nodes, opt);
      endswitch
      source = file;
      if (! strcmp (ext, '.dot'))
        source = [tempname(), '.dot'];
      endif
      fid = fopen (source, 'w');
      if (fid < 0)
        error ("devtools.callGraph.draw: cannot write '%s'.", source);
      endif
      fputs (fid, text);
      fclose (fid);
      if (! strcmp (ext, '.dot'))
        ## dot takes seconds on 2000 edges and minutes on 4000
        program = 'dot';
        if (numel (strfind (text, ' -> ')) > 2000)
          program = 'sfdp';
        endif
        if (isempty (file_in_path (getenv ('PATH'), program)))
          unlink (source);
          error ("devtools.callGraph.draw: Graphviz was not found.");
        endif
        [st, out] = system (sprintf ("%s -T%s -o \"%s\" \"%s\"", program, ...
                                     ext(2:end), file, source));
        unlink (source);
        if (st != 0)
          error ("devtools.callGraph.draw: %s failed: %s", program, ...
                 strtrim (out));
        endif
      endif

    endfunction

    ## -*- texinfo -*-
    ## @deftypefn {devtools.callGraph} {} write (@var{G}, @var{FOLDER})
    ##
    ## Write the graph to @var{FOLDER} as CSV files.
    ##
    ## @file{nodes.csv}, @file{forms.csv} and @file{edges.csv} hold the columns
    ## of the properties @code{Nodes}, @code{Forms} and @code{Edges}, sorted by
    ## key, so that two runs can be compared, and after @code{trace},
    ## @file{seen.csv} and @file{calls.csv} hold @code{Seen} and @code{Calls};
    ## @file{run.csv} holds one row,
    ## @code{package},
    ## @code{version}, @code{octave} and @code{date}.  Quoting is
    ## that of RFC 4180.  @var{FOLDER} is created where it does not exist.
    ##
    ## @seealso{devtools.callGraph.read}
    ## @end deftypefn
    function write (this, FOLDER)

      if (nargin != 2)
        error ("devtools.callGraph.write: invalid number of input arguments.");
      endif
      if (! (ischar (FOLDER) && isrow (FOLDER)))
        error ("devtools.callGraph.write: FOLDER must be a character vector.");
      endif
      if (! isfield (this.Nodes, 'node'))
        error ("devtools.callGraph.write: the graph is empty.");
      endif
      if (! isfolder (FOLDER))
        [ok, msg] = mkdir (FOLDER);
        if (! ok)
          error ("devtools.callGraph.write: cannot create FOLDER: %s.", msg);
        endif
      endif

      T = devtools.callGraph.Tables;
      writeCsv (fullfile (FOLDER, 'nodes.csv'), this.Nodes, T.nodes);
      writeCsv (fullfile (FOLDER, 'edges.csv'), this.Edges, T.edges);
      writeCsv (fullfile (FOLDER, 'forms.csv'), this.Forms, T.forms);
      run = struct ('package', {{this.Package}}, ...
                    'version', {{this.Version}}, ...
                    'octave', {{OCTAVE_VERSION()}}, ...
                    'date', {{strftime('%Y-%m-%d', localtime (time ()))}});
      writeCsv (fullfile (FOLDER, 'run.csv'), run, T.run);
      seen = fullfile (FOLDER, 'seen.csv');
      calls = fullfile (FOLDER, 'calls.csv');
      if (isfield (this.Seen, 'from'))
        writeCsv (seen, this.Seen, T.seen);
        writeCsv (calls, this.Calls, T.calls);
      else
        ## An older run in the folder must not read back as this one's
        if (isfile (seen))
          unlink (seen);
        endif
        if (isfile (calls))
          unlink (calls);
        endif
      endif

    endfunction

  endmethods

  methods (Static)

    ## -*- texinfo -*-
    ## @deftypefn {devtools.callGraph} {@var{G} =} devtools.callGraph.read (@var{FOLDER})
    ##
    ## Reload a graph from the CSV files @code{write} left in @var{FOLDER}.
    ##
    ## The CSV files do not hold where the package is, so @code{paths},
    ## @code{chains}, @code{nodes}, @code{subclasses} and @code{draw} work on
    ## the result, and @code{trace}, @code{traceCall} and @code{gaps} refuse it.
    ##
    ## @seealso{devtools.callGraph.write}
    ## @end deftypefn
    function G = read (FOLDER)

      if (nargin != 1)
        error ("devtools.callGraph.read: invalid number of input arguments.");
      endif
      if (! (ischar (FOLDER) && isrow (FOLDER)))
        error ("devtools.callGraph.read: FOLDER must be a character vector.");
      endif

      G = devtools.callGraph ();
      T = devtools.callGraph.Tables;
      G.Nodes = readCsv (fullfile (FOLDER, 'nodes.csv'), T.nodes);
      G.Edges = readCsv (fullfile (FOLDER, 'edges.csv'), T.edges);
      G.Forms = readCsv (fullfile (FOLDER, 'forms.csv'), T.forms);
      run = readCsv (fullfile (FOLDER, 'run.csv'), T.run);
      G.Package = run.package{1};
      G.Version = run.version{1};
      if (isfile (fullfile (FOLDER, 'seen.csv')))
        G.Seen = readCsv (fullfile (FOLDER, 'seen.csv'), T.seen);
        G.Calls = readCsv (fullfile (FOLDER, 'calls.csv'), T.calls);
      endif
      G.Index = graphIndex (G.Nodes, G.Edges, G.Forms, G.Seen, G.Calls);

    endfunction

  endmethods

  methods (Static, Hidden)

    ## Record what a BIST run does.  trace rewrites a package's test blocks so
    ## that they call this method, by name and from outside the class, which is
    ## why it is public and hidden.  ID says what is asked.  'start' clears the
    ## record and turns the profiler on.  'block' keeps what the profiler saw
    ## for the block before it and opens block number NOUT.  'stop' turns the
    ## profiler off and returns the whole record.  A numeric ID is a call site
    ## that has just returned: NOUT is how many outputs it asked for, or that
    ## count followed by the positions of the outputs given, CLS is the class of
    ## the object it dispatched on, and the other arguments are the values it
    ## returned.  Their classes are recorded, and the first value is handed back
    ## so that the call can stand inside an expression.
    function varargout = shim (ID, NOUT, CLS, varargin)

      persistent profiles = {};
      persistent blocks = [];
      persistent current = 0;
      persistent rows = {};

      if (isnumeric (ID))
        if (isscalar (NOUT))
          pos = 1:numel (varargin);
        else
          pos = NOUT(2:end);
          NOUT = NOUT(1);
        endif
        if (isempty (varargin))
          rows{end+1} = {ID, 0, '', current, NOUT, CLS};
        endif
        for ii = 1:numel (varargin)
          rows{end+1} = {ID, pos(ii), class(varargin{ii}), current, NOUT, CLS};
        endfor
        if (nargout > 0)
          varargout{1} = varargin{1};
        endif
        return;
      endif

      switch (ID)
        case 'start'
          profiles = {};
          blocks = [];
          current = 0;
          rows = {};
          __profiler_reset__ ();
          __profiler_enable__ (true);
        case 'block'
          __profiler_enable__ (false);
          if (current > 0)
            F = __profiler_data__ ();
            profiles{end+1} = struct ('name', {{F.FunctionName}}, ...
                                      'calls', [F.NumCalls], ...
                                      'parents', {{F.Parents}});
            blocks(end+1) = current;
          endif
          current = NOUT;
          __profiler_reset__ ();
          __profiler_enable__ (true);
        case 'stop'
          __profiler_enable__ (false);
          if (current > 0)
            F = __profiler_data__ ();
            profiles{end+1} = struct ('name', {{F.FunctionName}}, ...
                                      'calls', [F.NumCalls], ...
                                      'parents', {{F.Parents}});
            blocks(end+1) = current;
          endif
          __profiler_reset__ ();
          D = struct ('profiles', {profiles}, 'blocks', blocks);
          n = numel (rows);
          D.id = zeros (n, 1);
          D.output = zeros (n, 1);
          D.class = cell (n, 1);
          D.block = zeros (n, 1);
          D.nout = zeros (n, 1);
          D.owner = cell (n, 1);
          for ii = 1:n
            r = rows{ii};
            D.id(ii) = r{1};
            D.output(ii) = r{2};
            D.class{ii} = r{3};
            D.block(ii) = r{4};
            D.nout(ii) = r{5};
            D.owner{ii} = r{6};
          endfor
          varargout{1} = D;
        otherwise
          error ("devtools.callGraph.shim: unknown request: '%s'", ID);
      endswitch

    endfunction

  endmethods

  methods (Access = private)

    ## Read a package and everything it depends on into nodes and edges, running
    ## none of it.  TARGET is a package source folder or the name of an
    ## installed package.  The packages under Depends are followed in turn and
    ## must be installed.  Only the target's tests are read, both the blocks
    ## inside its files and its .m-tst files, a dependency's tests being no
    ## paths of the target.  Inheritance is added as edges of its own.  N and E
    ## are the tables Nodes and Edges document, and INFO holds the package's
    ## name, version, root and dependencies, and in faults the files whose parse
    ## did not complete, a file's tests marked as such.
    function [N, E, INFO] = readPackage (this, TARGET)

      installed = pkg ('list');
      P = describePackage (TARGET, installed, true);
      queue = P.depends;
      while (! isempty (queue))
        depName = queue{1};
        queue(1) = [];
        if (any (strcmp ({P.name}, depName)))
          continue;
        endif
        if (! any (cellfun (@(c) strcmp (c.name, depName), installed)))
          error ("devtools.callGraph: dependency is not installed: '%s'", ...
                 depName);
        endif
        Q = describePackage (depName, installed, false);
        P(end+1) = Q;
        queue = [queue, Q.depends];
      endwhile
      T = inventory (this, P);
      T.core = coreNames ();
      T = returnClasses (T);
      plainValues = struct ('cls', {{}}, 'open', false, 'complete', true);
      T.noClass = T.noObject = struct ();
      for name = fieldnames (T.byName)'
        [Dn.to, Dn.kinds, Dn.cert] = dispatch (T, name{1}, []);
        T.noClass.(name{1}) = Dn;
        [Dn.to, Dn.kinds, Dn.cert] = dispatch (T, name{1}, plainValues);
        T.noObject.(name{1}) = Dn;
      endfor

      rows = cell (numel (T.files) + 1, 1);
      extra = cell (numel (T.files), 1);
      mainPackage = P(1);
      tests = [];
      testPaths = {};
      for folder = ostrsplit (genpath (mainPackage.root), pathsep ())
        found = dir (fullfile (folder{1}, '*.m-tst'));
        for nf = 1:numel (found)
          testPaths{end+1} = fullfile (folder{1}, found(nf).name);
        endfor
      endfor
      for nf = 1:numel (testPaths)
        path = testPaths{nf};
        [~, base] = fileparts (path);
        base = regexprep (base, '\.m-tst$', '');
        if (! any (strcmp (T.N.node, base)))
          continue;
        endif
        rel = strrep (path(numel (mainPackage.root)+2:end), '\', '/');
        G = struct ('rel', rel, ...
                    'pkg', mainPackage.name, ...
                    'text', fileread (path), 'main', base, 'cls', '', ...
                    'declares', false, 'supers', {{}}, 'line', 1, ...
                    'base', fileparts (path), 'fnKey', {cell(0, 1)}, ...
                    'fnObj', {cell(0, 1)}, 'fnCls', {cell(0, 1)}, ...
                    'fnOut', {cell(0, 1)}, 'localName', {{}}, ...
                    'localNode', {{}});
        if (isempty (tests))
          tests = G;
        else
          tests(end+1) = G;
        endif
      endfor
      faults = {};
      for ii = 1:numel (T.files)
        F = T.files(ii);
        [R, ok] = readSource (T, F, F.text, false, {}, {});
        if (! ok)
          faults{end+1} = F.rel;
        endif
        rows{ii} = R;
        ## A dependency is followed, not catalogued: its own tests are no paths
        if (strcmp (F.pkg, P(1).name))
          [Rt, Nt, ok] = readTests (T, F);
          if (! ok)
            faults{end+1} = [F.rel, ' (tests)'];
          endif
          rows{ii} = joinRows (R, Rt);
          extra{ii} = Nt;
        endif
      endfor
      inherited = devtools.callGraph.Tables.edges;
      for c = sort (fieldnames (T.classes))'
        C = T.classes.(c{1});
        for s = C.supers
          inherited = joinRows (inherited, struct ('from', {c}, 'to', {s}, ...
                                   'kind', {{'inherit'}}, ...
                                   'certainty', {{'certain'}}, ...
                                   'nargout', NaN, ...
                                   'guard', {{''}}, 'varargin', false, ...
                                   'test', false, 'file', {{C.file}}, ...
                                   'line', C.line));
        endfor
      endfor
      rows{end} = inherited;
      for ii = 1:numel (tests)
        [rows{end+1,1}, extra{end+1,1}, ok] = readTests (T, tests(ii));
        if (! ok)
          faults{end+1} = [tests(ii).rel, ' (tests)'];
        endif
      endfor

      R = joinRows (rows{:});
      N = assembleNodes (T, R, extra);
      E = assembleEdges (R);
      INFO = struct ('package', P(1).name, 'version', P(1).version, ...
                     'root', P(1).root, 'faults', {faults(:)}, ...
                     'depends', {P(1).depends});

    endfunction

    ## Read the functional forms of a package from its docstrings.  ROOT is the
    ## folder holding the package, PACKAGE its name, and N and E its nodes and
    ## edges.  Every file defining a function, class or method of the package is
    ## read, and a block in the category of private functions is passed over.  F
    ## is the table Forms documents, with the forms of inherited methods added
    ## for each concrete class.  ORPHANS holds the file, line and name of each
    ## header that names no node.
    function [F, ORPHANS] = readForms (this, ROOT, PACKAGE, N, E)

      own = strcmp (N.package, PACKAGE);
      keep = own & ismember (N.kind, {'function', 'class', 'method'});
      files = unique (N.file(keep));

      R = {};
      ORPHANS = struct ('file', {cell(0, 1)}, 'line', zeros (0, 1), ...
                        'name', {cell(0, 1)});
      for ii = 1:numel (files)
        txt = fileread (fullfile (ROOT, files{ii}));
        L = ostrsplit (strrep (txt, "\r", ''), "\n");
        B = devtools.__texiBlocks__ (L);
        for jj = 1:numel (B)
          if (! strcmp (B(jj).kind, 'deftypefn'))
            continue;
          endif
          block = B(jj);
          FILE = files{ii};
          Rb = devtools.callGraph.Tables.forms;
          H = struct ('outs', {}, 'name', {}, 'ins', {}, 'line', {});
          category = '';
          for nh = 1:numel (block.header)
            k = block.header{nh};
            headerText = strjoin (regexprep (L(k), '^\s*##\s?', ''), ' ');
            headerText = regexprep (headerText, '@\s+', ' ');
            LINE = k(1);
            header = struct ('outs', {{}}, 'name', '', 'ins', {{}}, ...
                             'line', LINE);
            c = '';
            t = strtrim (regexprep (headerText, '^@deftypefnx?\s*', ''));
            [c, t] = braceGroup (t);
            [ret, t] = braceGroup (t);
            t = strtrim (plain (t));
            ret = strtrim (regexprep (plain (ret), '=\s*$', ''));
            ret = regexprep (strtrim (ret), '^\[|\]$', '');
            header.outs = splitList (ret);

            paren = find (t == '(', 1);
            if (isempty (paren))
              header.name = strtrim (t);
            else
              header.name = strtrim (t(1:paren-1));
              e = find (t == ')', 1, 'last');
              if (isempty (e))
                e = numel (t) + 1;
              endif
              header.ins = splitList (t(paren+1:e-1));
            endif
            H(end+1) = header;
            if (nh == 1)
              category = c;
            endif
          endfor
          if (isempty (regexp (category, 'Private', 'once')) && ! isempty (H))
            ## A block may document several names, each read on its own lines
            for name = unique ({H.name})
              NAME = name{1};
              key = '';
              text = NAME;
              whole = false;
              catNode = find (strcmp (N.node, category), 1);
              if (! isempty (catNode) && strcmp (N.kind{catNode}, 'class'))
                prefix = ['^', regexptranslate('escape', category), '\.'];
                short = regexprep (NAME, prefix, '');
                last = regexprep (category, '^.*\.', '');
                if (strcmp (short, last) || strcmp (short, category))
                  key = category;
                  text = category;
                  whole = true;
                else
                  NAME = [category, '.', short];
                  text = NAME;
                endif
              endif
              if (! whole && any (strcmp (N.node, NAME)))
                key = NAME;
              endif
              if (isempty (key))
                ORPHANS.file{end+1,1} = FILE;
                ORPHANS.line(end+1,1) = H(strcmp ({H.name}, name{1}))(1).line;
                ORPHANS.name{end+1,1} = name{1};
                continue;
              endif
              Hn = H(strcmp ({H.name}, name{1}));
              Rn = positional (Hn, key, text, FILE);
              Ro = options (Hn, key, text, FILE, L(block.body), block.body);
              Rb = joinForms (Rb, Rn, Ro);
            endfor
          endif
          R{end+1} = Rb;
        endfor
      endfor

      F = devtools.callGraph.Tables.forms;
      if (! isempty (R))
        F = joinForms (R{:});
      endif
      F = classForms (F, N, E, PACKAGE);

      [~, o] = unique (F.form, 'first');
      for f = fieldnames (F)'
        F.(f{1}) = F.(f{1})(o);
      endfor

    endfunction

    ## Run the BISTs of the files FILES, or one call, and record what happened.
    ## FILES is a cell array of files relative to the package root, each of
    ## whose test blocks is rewritten into a temporary file and run by test, the
    ## working tree staying untouched.  S holds what ran and C what the calls
    ## returned, as Seen and Calls document, and INFO holds the counts of test
    ## and the time taken, by file.  With a function handle in place of FILES,
    ## the one call runs under the profiler asking for NOUT outputs, and S holds
    ## from, to and calls, from being empty for what the call itself reached.
    ## The load path, the figures and the profiler are put back afterwards, even
    ## after an error.
    function [S, C, INFO] = runTrace (this, FILES, NOUT = 0)

      N = this.Nodes;
      F = this.Forms;
      I = this.Index;
      S = devtools.callGraph.Tables.seen;
      C = devtools.callGraph.Tables.calls;
      INFO = [];
      oldPath = path ();
      oldVisible = get (0, 'defaultfigurevisible');
      oldFigures = findall (0, 'type', 'figure');
      folder = tempname ();
      log = -1;
      unwind_protect
        set (0, 'defaultfigurevisible', 'off');
        for nd = 1:numel (this.Depends)
          pkg ('load', this.Depends{nd});
        endfor
        if (! isfile (fullfile (this.Root, 'DESCRIPTION')))
          pkg ('load', this.Package);
        else
          loaded = pkg ('list');
          for nd = 1:numel (loaded)
            if (strcmp (loaded{nd}.name, this.Package) && loaded{nd}.loaded)
              pkg ('unload', this.Package);
            endif
          endfor

          ## A package's PKG_ADD says which of its folders go on the path
          inst = fullfile (this.Root, 'inst');
          if (! isfolder (inst))
            inst = this.Root;
          endif
          if (isfile (fullfile (inst, 'PKG_ADD')))
            addpath (inst);
          else
            addpath (genpath (inst));
          endif
          src = fullfile (this.Root, 'src');
          if (isfolder (src))
            addpath (src);
          endif
        endif
        M = struct ();
        M.names = N.node;
        loose = find (ismember (N.kind, {'private', 'local', 'class'}));
        M.looseName = I.tail(loose);
        M.looseId = loose;
        M.ours = ! strcmp (N.package, 'core');
        [~, stems, ext] = cellfun (@fileparts, N.file, 'UniformOutput', false);
        M.base = strcat (stems, ext);
        k = I.toId > 0;
        n = numel (N.node);
        M.edge = sparse (I.fromId(k), I.toId(k), 1, n, n) > 0;
        if (is_function_handle (FILES))
          __profiler_reset__ ();
          __profiler_enable__ (true);
          out = cell (1, NOUT);
          [out{:}] = FILES ();
          __profiler_enable__ (false);
          oneProfile = __profiler_data__ ();
          __profiler_reset__ ();
          P = struct ('name', {{oneProfile.FunctionName}}, ...
                      'calls', [oneProfile.NumCalls], ...
                      'parents', {{oneProfile.Parents}});
          [from, to, ~, callCounts] = profileEdges ({P}, 1, '', M, N);
          key = from * (numel (N.node) + 1) + to;
          [~, first, g] = unique (key, 'first');
          from = from(first);
          callerNames = repmat ({''}, numel (from), 1);
          callerNames(from > 0) = N.node(from(from > 0));
          S = struct ('from', {callerNames}, 'to', {N.node(to(first))}, ...
                      'calls', accumarray (g(:), callCounts));
        else
          names = unique ([I.formName(:); I.formTail(:)]);
          mkdir (folder);
          log = fopen (fullfile (folder, 'test.log'), 'w');
          INFO = struct ('file', {FILES(:)}, ...
                         'passed', zeros (numel (FILES), 1), ...
                         'total', zeros (numel (FILES), 1), ...
                         'seconds', zeros (numel (FILES), 1));
          parts = cell (numel (FILES), 1);
          calls = cell (numel (FILES), 1);
          for ii = 1:numel (FILES)
            rel = FILES{ii};
            text = fileread (fullfile (this.Root, rel));
            [lines, sites] = rewrite (text, names);
            if (isempty (lines))
              continue;
            endif
            [~, base] = fileparts (rel);
            tst = fullfile (folder, [base, '.tst']);
            fid = fopen (tst, 'w');
            fprintf (fid, "%s\n", lines{:});
            fclose (fid);

            t0 = tic ();
            devtools.callGraph.shim ('start');
            [INFO.passed(ii), INFO.total(ii)] = test (tst, 'quiet', log);
            D = devtools.callGraph.shim ('stop');
            INFO.seconds(ii) = toc (t0);
            seenHere = devtools.callGraph.Tables.seen;
            if (! isempty (D.profiles))
              [fromId, toId, block, blockCalls] = profileEdges (D.profiles, ...
                                                          D.blocks, rel, M, N);
              known = fromId > 0;
              fromId = fromId(known);
              toId = toId(known);
              block = block(known);
              blockCalls = blockCalls(known);
              if (! isempty (fromId))
                ## Core is an end point: which block reached it is not kept,
                ## only that the file's run did
                core = ! M.ours(toId);
                span = numel (N.node) + 1;
                [u, coreFirst, coreGroup] = unique (fromId(core) * span ...
                                                    + toId(core), 'first');
                c = find (core);
                keep = ! core;
                seenHere.from = N.node([fromId(keep); fromId(c(coreFirst))]);
                seenHere.to = N.node([toId(keep); toId(c(coreFirst))]);
                seenHere.block = [block(keep); NaN(numel (u), 1)];
                seenHere.calls = [blockCalls(keep);
                                  accumarray(coreGroup(:), blockCalls(core))];
                seenHere.test_file = repmat ({rel}, numel (seenHere.from), 1);

                ## In a stable order, so that two runs compare
                [~, ~, a] = unique (seenHere.from);
                [~, ~, b] = unique (seenHere.to);
                [~, o] = sortrows ([a(:), b(:), seenHere.block]);
                for f = {'from', 'to', 'test_file', 'block', 'calls'}
                  seenHere.(f{1}) = seenHere.(f{1})(o);
                endfor
              endif
            endif
            parts{ii} = seenHere;
            calledHere = devtools.callGraph.Tables.calls;
            nRecords = numel (D.id);
            if (! nRecords == 0)
              [~, ~, cid] = unique (D.class);
              record = [D.id, D.output, cid(:), D.block];
              [~, firstRecord, recordGroup] = unique (record, 'rows', 'first');
              m = numel (firstRecord);
              calledHere.count = accumarray (recordGroup(:), 1);
              calledHere.output = D.output(firstRecord);
              calledHere.class = D.class(firstRecord);
              calledHere.block = D.block(firstRecord);
              calledHere.line = zeros (m, 1);
              calledHere.test_file = repmat ({rel}, m, 1);
              calledHere.form = repmat ({''}, m, 1);
              calledHere.call = repmat ({''}, m, 1);
              drop = false (m, 1);
              for nr = 1:m
                rec = firstRecord(nr);
                s = sites(D.id(rec));
                calledHere.call{nr} = s.call;
                calledHere.line(nr) = s.line;
                calledHere.form{nr} = matchForm (s, D.nout(rec), ...
                                                 D.owner{rec}, F, I, base);
                ## A name no plain form has, on an object of no class we hold
                ## or of no class we could read, says nothing about our forms
                drop(nr) = (isempty (calledHere.form{nr})
                            && ! any (strcmp (I.formName, s.name))
                            && (isempty (D.owner{rec})
                                || ! any (strcmp (I.formClass, D.owner{rec}))));
              endfor
              for field = fieldnames (calledHere)'
                calledHere.(field{1})(drop) = [];
              endfor
            endif
            calls{ii} = calledHere;
            unlink (tst);
          endfor
          S = joinCols (S, parts);
          C = joinCols (C, calls);
        endif
      unwind_protect_cleanup
        __profiler_enable__ (false);
        if (log >= 0)
          fclose (log);
        endif
        path (oldPath);
        set (0, 'defaultfigurevisible', oldVisible);
        close (setdiff (findall (0, 'type', 'figure'), oldFigures));
        if (isfolder (folder))
          confirm_recursive_rmdir (false, 'local');
          rmdir (folder, 's');
        endif
      end_unwind_protect

    endfunction

    ## List every definition of the packages read, before any call is resolved.
    ## P is a structure array of packages in load path order, with name, root
    ## and arch.  Files in demos and tests folders are left out.  Compiled
    ## functions are found from the DEFUN_DLD lines in a package's src folder
    ## or, where it has none, from its oct-files.  T holds N, the node table,
    ## packages, files, what each file defines, and the lookup tables names are
    ## resolved by: plainName and plainKind for what stands on the load path,
    ## privKey and privNode for private functions, byName and methods for
    ## methods, and classes for each class with its superclasses, file, line and
    ## direct children.
    function T = inventory (this, P)

      T = struct ();
      T.packages = P;
      files = {};
      node = kind = pack = file = cls = {};
      line = [];
      abstract = logical ([]);
      plainName = plainKind = {};
      privKey = privNode = {};
      classes = struct ();
      methods_ = struct ();
      byName = struct ();

      for pp = 1:numel (P)
        [~, paths] = devtools.__resolveTarget__ (P(pp).root);
        tail = cellfun (@(c) c(numel (P(pp).root)+1:end), paths, ...
                        'UniformOutput', false);
        skip = regexp (tail, '[/\\](demos|tests)[/\\]', 'once');
        skip = ! cellfun (@isempty, skip);
        paths(skip) = [];
        for ii = 1:numel (paths)
          F = describeFile (paths{ii}, P(pp));
          if (isempty (F))
            continue;
          endif
          n = numel (F.nodes);
          for jj = 1:n
            R = F.nodes(jj);
            node{end+1,1} = R.node;
            kind{end+1,1} = R.kind;
            pack{end+1,1} = P(pp).name;
            file{end+1,1} = F.rel;
            line(end+1,1) = R.line;
            cls{end+1,1} = R.cls;
            abstract(end+1,1) = R.abstract;
            switch (R.kind)
              case {'function', 'class'}
                if (! any (strcmp (plainName, R.node)))
                  plainName{end+1,1} = R.node;
                  plainKind{end+1,1} = R.kind;
                endif
              case 'private'
                privKey{end+1,1} = [F.base, '|', R.short];
                privNode{end+1,1} = R.node;
              case 'method'
                methods_.(R.node) = true;
                if (isfield (byName, R.short))
                  byName.(R.short){end+1} = R.node;
                else
                  byName.(R.short) = {R.node};
                endif
            endswitch
          endfor
          if (F.declares)
            classes.(F.cls) = struct ('supers', {F.supers}, 'file', F.rel, ...
                                      'line', F.line, 'children', {{}});
          endif
          files{end+1,1} = rmfield (F, 'nodes');
        endfor
        pkgInfo = P(pp);
        names = where = {};
        at = [];
        srcdir = fullfile (pkgInfo.root, 'src');
        if (isfolder (srcdir))
          cc = [dir(fullfile (srcdir, '*.cc'));
                dir(fullfile (srcdir, '*.cpp'))];
          for nc = 1:numel (cc)
            txt = fileread (fullfile (srcdir, cc(nc).name));
            [s, m] = regexp (txt, 'DEFUN_DLD\s*\(\s*(\w+)', 'start', 'tokens');
            nl = find (txt == "\n");
            for kk = 1:numel (m)
              names{end+1} = m{kk}{1};
              where{end+1} = ['src/', cc(nc).name];
              at(end+1) = 1 + sum (nl < s(kk));
            endfor
          endfor
        elseif (! isempty (pkgInfo.arch) && isfolder (pkgInfo.arch))
          for folder = ostrsplit (genpath (pkgInfo.arch), pathsep ())
            oct = dir (fullfile (folder{1}, '*.oct'));
            for nc = 1:numel (oct)
              names{end+1} = oct(nc).name(1:end-4);
              where{end+1} = oct(nc).name;
              at(end+1) = 0;
            endfor
          endfor
        endif
        for ii = 1:numel (names)
          if (any (strcmp (plainName, names{ii})))
            continue;
          endif
          node{end+1,1} = names{ii};
          kind{end+1,1} = 'compiled';
          pack{end+1,1} = P(pp).name;
          file{end+1,1} = where{ii};
          line(end+1,1) = at(ii);
          cls{end+1,1} = '';
          abstract(end+1,1) = false;
          plainName{end+1,1} = names{ii};
          plainKind{end+1,1} = 'function';
        endfor
      endfor

      T.files = vertcat (files{:});
      T.N = struct ('node', {node}, 'kind', {kind}, 'package', {pack}, ...
                    'file', {file}, 'line', line, 'class', {cls}, ...
                    'abstract', abstract);
      T.plainName = plainName;
      T.plainKind = plainKind;
      T.privKey = privKey;
      T.privNode = privNode;
      T.byName = byName;
      T.methods = methods_;

      ## Each class's direct children, for the overrides of a method
      names = sort (fieldnames (classes));
      for ii = 1:numel (names)
        for sup = classes.(names{ii}).supers
          if (isfield (classes, sup{1}))
            classes.(sup{1}).children{end+1} = names{ii};
          endif
        endfor
      endfor
      T.classes = classes;

    endfunction

  endmethods

endclassdef

## Build what queries look up from the tables N, E, F, S and C.  The index is
## derived data and is never written to disk, so that read can rebuild it from
## the CSV files.  I holds the numeric node of each end of each edge, the column
## of each output count, which edges a condition on nargout or nargin decides,
## the candidate method rows grouped by call site, and what a BIST run saw.
## Output counts run from 0 to 8, and a tenth column stands for a count that is
## not known.
function I = graphIndex (N, E, F, S, C)

  I.columns = 10;                     # outputs 0 to 8, then a count unknown
  K = I.columns;
  I.nodes = N.node;
  I.core = N.node(strcmp (N.kind, 'core'));
  [~, I.fromId] = ismember (E.from, N.node);
  I.fromId = I.fromId(:);
  [~, I.toId] = ismember (E.to, N.node);
  I.toId = I.toId(:);
  I.tail = regexprep (N.node, '^.*[/>.]', '');
  I.member = I.tail;
  m = find (! cellfun (@isempty, N.class));
  for k = m'
    I.member{k} = N.node{k}(numel (N.class{k})+2:end);
  endfor

  ## Forms
  [~, I.formNode] = ismember (F.node, N.node);
  I.formNode = I.formNode(:);
  name = regexprep (F.form, '^(\[[^\]]*\]|\S+) = ', '');
  name = regexprep (name, ' \(.*$', '');
  I.formClass = repmat ({''}, numel (F.form), 1);
  isClass = strcmp (N.kind, 'class');
  classes = N.node(isClass);
  head = regexprep (name, '\.[^.]*$', '');
  hit = ismember (head, classes);
  hit &= ! cellfun (@isempty, regexp (name, '\.', 'once'));
  I.formClass(hit) = head(hit);
  hit = ismember (name, classes);
  I.formClass(hit) = name(hit);
  I.formName = name;
  I.formTail = regexprep (name, '^.*\.', '');
  I.formColumn = min (F.nargout, K - 2) + 1;
  I.formColumn(isnan (F.nargout)) = K;

  ## Inheritance
  k = strcmp (E.kind, 'inherit');
  I.child = E.from(k);
  I.parent = E.to(k);

  ## Output counts: which edges a guard on nargout decides, by column
  I.edgeColumn = min (E.nargout, K - 2) + 1;
  I.edgeColumn(isnan (E.nargout)) = K;
  g = find (! cellfun (@isempty, strfind (E.guard, 'nargout')));
  I.guardRow = g;
  I.guardOk = true (numel (g), K);
  [u, ~, w] = unique (E.guard(g));
  counts = [0:K-2, NaN];
  ok = true (numel (u), K);
  for ii = 1:numel (u)
    for jj = 1:K
      ok(ii,jj) = guardHolds (u{ii}, NaN, counts(jj));
    endfor
  endfor
  if (! isempty (u))
    I.guardOk = ok(w,:);
  endif
  in = ! cellfun (@isempty, strfind (E.guard, 'nargin'));
  I.narginNodes = unique (I.fromId(in));
  I.narginGuard = in;
  [~, I.outRows] = sort (I.fromId);
  I.outStart = cumsum ([1; accumarray(I.fromId, 1, [numel(N.node), 1])]);

  ## Candidate method rows by call site, for settling dispatch by class
  I.classNames = sort (classes);
  [~, nodeClass] = ismember (N.class, I.classNames);
  [~, own] = ismember (N.node, I.classNames);
  nodeClass(own > 0) = own(own > 0);
  r = find (strcmp (E.kind, 'method') & strcmp (E.certainty, 'candidates'));
  r = r(I.toId(r) > 0);
  I.toClass = zeros (size (E.from));
  I.siteRows = zeros (0, 1);
  I.siteStart = 1;
  I.siteClass = zeros (0, 1);
  if (! isempty (r))
    [~, ~, file] = unique (E.file(r));
    [~, ~, tail] = unique (I.member(I.toId(r)));
    [~, ~, g] = unique ([I.fromId(r), file(:), E.line(r), tail(:)], 'rows');
    [g, o] = sort (g);
    I.siteRows = r(o);
    I.siteStart = [find([true; diff(g) != 0]); numel(g) + 1];
    I.siteClass = nodeClass(I.fromId(I.siteRows(I.siteStart(1:end-1))));
    I.siteClass(I.siteClass == 0) = numel (I.classNames) + 1;
    I.toClass(r) = nodeClass(I.toId(r));
  endif

  ## What a run saw
  I.ran = S;
  I.calls = C;
  I.seen = false (size (E.from));
  if (isfield (S, 'from') && ! isempty (S.from))
    [~, I.seenFrom] = ismember (S.from, N.node);
    [~, I.seenTo] = ismember (S.to, N.node);
    span = numel (N.node) + 1;
    I.seen = ismember (I.fromId(:) * span + I.toId(:), ...
                       I.seenFrom(:) * span + I.seenTo(:));
    [~, I.seenFile] = ismember (S.test_file, unique (S.test_file));
    [~, I.callFile] = ismember (C.test_file, unique (S.test_file));
  endif

endfunction

## Turn the record of one traced call into the structure paths returns, so that
## it can be printed or drawn like any other result.  S holds from, to and
## calls, an empty from marking what the call itself reached.  N, E and I are
## the nodes, the edges and the index.  Each edge ran, so each is certain, and
## it takes its kind, condition, file and line from the matching row of the edge
## table where there is one.  R has no forms and no links.
function R = callResult (S, N, E, I)

  root = strcmp (S.from, '');
  R = struct ('from', {unique(S.to(root))}, 'to', {cell(0, 1)});
  k = find (! root);
  n = numel (k);
  span = numel (N.node) + 1;
  [~, ifrom] = ismember (S.from(k), N.node);
  [~, ito] = ismember (S.to(k), N.node);
  here = ifrom(:) * span + ito(:);
  [tf, j] = ismember (here, I.fromId(:) * span + I.toId(:));
  kind = repmat ({''}, n, 1);
  guard = repmat ({''}, n, 1);
  file = repmat ({''}, n, 1);
  line = NaN (n, 1);
  kind(tf) = E.kind(j(tf));
  guard(tf) = E.guard(j(tf));
  file(tf) = E.file(j(tf));
  line(tf) = E.line(j(tf));
  R.edges = struct ('from', {S.from(k)}, 'to', {S.to(k)}, 'kind', {kind}, ...
                    'status', {repmat({'certain'}, n, 1)}, ...
                    'certainty', {repmat({'certain'}, n, 1)}, ...
                    'nargout', NaN (n, 1), 'guard', {guard}, ...
                    'varargin', false (n, 1), 'test', false (n, 1), ...
                    'file', {file}, 'line', line, 'ran', true (n, 1));
  names = unique ([S.from(! root); S.to]);
  [~, w] = ismember (names, N.node);
  w = w(w > 0);
  w = w(! strcmp (N.file(w), ''));
  [u, first] = unique (strcat (N.package(w), '|', N.file(w)));
  R.files = struct ('file', {N.file(w(first))}, ...
                    'package', {N.package(w(first))}, ...
                    'status', {repmat({'certain'}, numel (u), 1)});
  R.forms = struct ('form', {cell(0, 1)}, 'node', {cell(0, 1)}, ...
                    'status', {cell(0, 1)});
  R.links = struct ('from', {cell(0, 1)}, 'to', {cell(0, 1)}, ...
                    'weight', zeros (0, 1), 'status', {cell(0, 1)});

endfunction

## Print a result of paths.  Forms and files are listed under their status,
## certain first, except that incomplete forms are only counted, there being too
## many to read.  Then come the number of edges of each status and, where the
## query asked for them, the links between boxes with their weights.
function printPaths (R)

  tiers = {'certain', 'possible', 'incomplete'};
  for t = tiers
    k = strcmp (R.forms.status, t{1});
    if (any (k))
      printf ("%s forms (%d):\n", t{1}, sum (k));
      if (strcmp (t{1}, 'incomplete'))
        continue;
      endif
      printf ("  %s\n", R.forms.form(k){:});
    endif
  endfor
  for t = tiers
    k = strcmp (R.files.status, t{1});
    if (any (k))
      printf ("%s files (%d):\n", t{1}, sum (k));
      list = [R.files.package(k), R.files.file(k)]';
      printf ("  %s: %s\n", list{:});
    endif
  endfor
  printf ("edges: %d certain, %d possible, %d incomplete\n", ...
          sum (strcmp (R.edges.status, 'certain')), ...
          sum (strcmp (R.edges.status, 'possible')), ...
          sum (strcmp (R.edges.status, 'incomplete')));
  if (! isempty (R.links.from))
    printf ("links (%d):\n", numel (R.links.from));
    list = [num2cell(R.links.weight), R.links.from, R.links.to]';
    printf ("  %6d  %s -> %s\n", list{:});
  endif

endfunction

## Extend one call chain depth first and collect the chains it leads to.  TRAIL
## is the chain so far, FROM and TO are the edges as two lists, ENDS the nodes a
## chain must stop at, C the chains found so far and LIMIT the most to keep.  A
## node already on the trail is not entered again, so a cycle ends the chain.  A
## chain is kept when it reaches a node of ENDS or, where there are none, when
## it can go no further.  DONE is false once LIMIT has been reached.
function [C, DONE] = descend (TRAIL, FROM, TO, ENDS, C, LIMIT)

  DONE = true;
  here = TRAIL{end};
  next = TO(strcmp (FROM, here));
  next = setdiff (next, TRAIL);
  stop = any (strcmp (ENDS, here));
  if (stop || isempty (next))
    if (numel (TRAIL) > 1 && (stop || isempty (ENDS)))
      if (numel (C) >= LIMIT)
        DONE = false;
        return;
      endif
      C{end+1,1} = strjoin (TRAIL, ' > ');
    endif
    return;
  endif
  for ii = 1:numel (next)
    [C, DONE] = descend ([TRAIL, next(ii)], FROM, TO, ENDS, C, LIMIT);
    if (! DONE)
      return;
    endif
  endfor

endfunction

## Merge a new run of some test files into an older table.  A and B are tables
## with a test_file column, as Seen and Calls are.  The rows of A from the files
## FILES are dropped, the rows of B take their place, and the result is sorted
## by test_file.
function A = replaceFiles (A, B, FILES)

  keep = ! ismember (A.test_file, FILES);
  for f = fieldnames (A)'
    A.(f{1}) = [A.(f{1})(keep); B.(f{1})];
  endfor
  [~, o] = sort (A.test_file);
  for f = fieldnames (A)'
    A.(f{1}) = A.(f{1})(o);
  endfor

endfunction

## Write one table to a CSV file.  FILE is the file, S the columns as a
## structure, and TABLE the empty table from the Tables constant, whose fields
## give the columns and their order and whose classes say which hold text.  Text
## is quoted only where it holds a comma, a quote or a line end, and logical
## columns are written as 0 and 1.
function writeCsv (FILE, S, TABLE)

  names = fieldnames (TABLE);
  n = numel (names);
  m = numel (S.(names{1}));
  C = cell (n, m);
  for ii = 1:n
    v = S.(names{ii});
    if (iscell (TABLE.(names{ii})))
      row = v(:)';
      whole = [row{:}];
      at = find (whole == '"' | whole == ',' | whole == "\n");
      if (! isempty (at))
        stops = cumsum (cellfun ('length', row));
        for jj = unique (lookup (stops, at - 1) + 1)
          row{jj} = ['"', strrep(row{jj}, '"', '""'), '"'];
        endfor
      endif
      C(ii,:) = row;
    else
      C(ii,:) = numbers (double (v));
    endif
  endfor

  fid = fopen (FILE, 'w');
  if (fid < 0)
    error ("devtools.callGraph.write: cannot write '%s'.", FILE);
  endif
  closer = onCleanup (@() fclose (fid));
  fprintf (fid, "%s\n", strjoin (names', ','));
  fmt = [repmat('%s,', 1, n-1), "%s\n"];
  fprintf (fid, fmt, C{:});

endfunction

## Convert a numeric vector to a row of text cells, as whole numbers, a NaN
## becoming an empty cell.  It is what writeCsv writes for a numeric column.
function C = numbers (V)

  C = repmat ({''}, 1, numel (V));
  ok = ! isnan (V);
  if (any (ok))
    t = sprintf ("%d\n", V(ok));
    C(ok) = ostrsplit (t(1:end-1), "\n");
  endif

endfunction

## Read one CSV file back into columns.  FILE is the file and TABLE the empty
## table from the Tables constant, whose fields are the columns the file must
## start with and whose classes give each column's type.  Commas and quotes
## inside a quoted field are set aside first, so that the whole text can be
## split at once.  S is a structure of column vectors.  A missing file or a
## different header is an error.
function S = readCsv (FILE, TABLE)

  if (! isfile (FILE))
    error ("devtools.callGraph.read: no such file: '%s'", FILE);
  endif
  text = fileread (FILE);
  names = fieldnames (TABLE);
  head = [strjoin(names', ','), "\n"];
  if (! strncmp (text, head, numel (head)))
    error ("devtools.callGraph.read: wrong columns in '%s'", FILE);
  endif
  text = text(numel (head)+1:end);

  q = text == '"';
  inside = logical (mod (cumsum (q), 2));
  text(inside & text == ',') = "\x01";
  text([false, q(1:end-1)] & q & inside) = "\x02";
  text(text == '"') = [];
  if (! isempty (text) && text(end) == "\n")
    text(end) = [];
  endif

  n = numel (names);
  if (isempty (text))
    F = cell (n, 0);
  else
    F = reshape (ostrsplit (text, ",\n"), n, []);
    F = strrep (strrep (F, "\x01", ','), "\x02", '"');
  endif

  S = struct ();
  for ii = 1:n
    v = F(ii,:)';
    switch (class (TABLE.(names{ii})))
      case 'double'
        v = str2double (v);
      case 'logical'
        v = strcmp (v, '1');
    endswitch
    S.(names{ii}) = v;
  endfor

endfunction

## Find one package and read its DESCRIPTION.  TARGET is a package name, or a
## source folder where FOLDER is true.  INSTALLED is the list pkg returns.  P
## holds its name, version, root, the folder of its compiled files, and the
## packages it depends on, core Octave left out.  A target that is neither a
## source folder nor an installed package is an error.
function P = describePackage (TARGET, INSTALLED, FOLDER)

  root = '';
  arch = '';
  desc = '';
  if (FOLDER && isfolder (TARGET))
    root = canonicalize_file_name (TARGET);
    desc = fullfile (root, 'DESCRIPTION');
  else
    for ii = 1:numel (INSTALLED)
      if (strcmp (INSTALLED{ii}.name, TARGET))
        root = INSTALLED{ii}.dir;
        arch = INSTALLED{ii}.archprefix;
        desc = fullfile (root, 'packinfo', 'DESCRIPTION');
        break;
      endif
    endfor
  endif
  if (! isfile (desc))
    error (strcat ("devtools.callGraph: TARGET is neither a package source", ...
                   " folder nor an installed package: '%s'"), TARGET);
  endif

  txt = fileread (desc);
  name = regexp (txt, '^Name:\s*(\S+)', 'tokens', 'once', 'lineanchors');
  ver = regexp (txt, '^Version:\s*(\S+)', 'tokens', 'once', 'lineanchors');
  deps = regexp (txt, '^Depends:\s*(.*)$', 'tokens', 'once', ...
                 'lineanchors', 'dotexceptnewline');
  depends = {};
  if (! isempty (deps))
    for item = ostrsplit (deps{1}, ',')
      d = regexp (item{1}, '^\s*([\w.-]+)', 'tokens', 'once');
      if (! isempty (d) && ! strcmpi (d{1}, 'octave'))
        depends{end+1} = lower (d{1});
      endif
    endfor
  endif
  P = struct ('name', name{1}, 'version', ver{1}, 'root', root, ...
              'arch', arch, 'depends', {depends});

endfunction

## Work out the classes each function returns as its first output, from what its
## writes to that output construct or from the functions those writes call.  T
## is the inventory, and the result gains the field returns, holding for each
## function the classes found and, in complete, whether every write was
## accounted for.  It repeats until nothing changes, since factories call
## factories.
function T = returnClasses (T)

  query = ['(function_definition) @fn ', ...
           '(assignment left: (identifier) @pw) ', ...
           '(assignment left: (identifier) @cl right: (index_expression', ...
           ' value: [(identifier) (field_expression)] @cr))'];
  keys_ = {};
  callee = {};
  whole = logical ([]);
  for ii = 1:numel (T.files)
    F = T.files(ii);
    if (all (cellfun (@isempty, F.fnOut)))
      continue;
    endif
    Q = devtools.__parseQuery__ (F.text, query);
    S = tagIndex (Q.capture);
    [fs, o] = sort (Q.sbyte(tagged (S, 'fn')));
    fe = Q.ebyte(tagged (S, 'fn'))(o);
    if (numel (fs) != numel (F.fnOut))
      continue;
    endif
    txt = @(k) cellslices (F.text, Q.sbyte(k)+1, Q.ebyte(k), 2)(:);
    kw = tagged (S, 'pw');
    wn = txt (kw);
    ws = owner (fs, fe, Q.sbyte(kw));
    kl = tagged (S, 'cl');
    kr = tagged (S, 'cr');
    [~, j] = ismember (Q.match(kl), Q.match(kr));
    ln = txt (kl);
    ls = owner (fs, fe, Q.sbyte(kl));
    rn = txt (kr(j));
    for jj = 1:numel (fs)
      out = F.fnOut{jj};
      if (isempty (out) || isempty (F.fnKey{jj}))
        continue;
      endif
      hit = ls == jj & strcmp (ln, out);
      if (any (hit))
        keys_{end+1,1} = F.fnKey{jj};
        callee{end+1,1} = unique (rn(hit));
        whole(end+1,1) = sum (hit) == sum (ws == jj & strcmp (wn, out));
      endif
    endfor
  endfor

  T.returns = struct ();
  changed = true;
  while (changed)
    changed = false;
    for ii = 1:numel (keys_)
      [c, done] = classesOf (T, callee{ii});
      c = unique (c);
      done = done && whole(ii);
      if (isempty (c))
        continue;
      endif
      if (isfield (T.returns, keys_{ii}))
        old = T.returns.(keys_{ii});
        if (isequal (old.cls, c) && old.complete == done)
          continue;
        endif
      endif
      T.returns.(keys_{ii}) = struct ('cls', {c}, 'complete', done);
      changed = true;
    endfor
  endwhile

endfunction

## The classes a list of callees yields.  T is the inventory and CALLEE a cell
## array of names, each one either a class or a function whose returned classes
## are known.  C holds the classes, and DONE is false if any callee could not be
## accounted for fully.
function [C, DONE] = classesOf (T, CALLEE)

  C = {};
  DONE = true;
  for ii = 1:numel (CALLEE)
    if (isfield (T.classes, CALLEE{ii}))
      C{end+1} = CALLEE{ii};
    elseif (isfield (T.returns, CALLEE{ii}))
      r = T.returns.(CALLEE{ii});
      C = [C, r.cls(:)'];
      DONE = DONE && r.complete;
    else
      DONE = false;
    endif
  endfor

endfunction

## Join any number of edge tables into one, column by column.  With no input it
## returns the empty edge table.
function R = joinRows (varargin)
  R = devtools.callGraph.Tables.edges;
  if (nargin == 0)
    return;
  endif
  for f = fieldnames (R)'
    c = cellfun (@(s) s.(f{1}), varargin, 'UniformOutput', false);
    R.(f{1}) = vertcat (c{:});
  endfor
endfunction

## Read the calls written in the test blocks of one file, block by block as test
## runs them.  T is the inventory and F the record of the file.  A demo is left
## out, and the names on a %!shared line count as variables of the blocks
## reading them.  R holds the edge rows, Nt the functions the tests define, and
## OK is false if the parse did not complete.
function [R, Nt, OK] = readTests (T, F)

  R = devtools.callGraph.Tables.edges;
  Nt = [];
  OK = true;
  if (isempty (strfind (F.text, '%!')))
    return;
  endif
  L = ostrsplit (strrep (F.text, "\r", ''), "\n");
  [code, head] = devtools.__testStream__ (L);
  hdr = find (! cellfun (@isempty, head));
  if (isempty (hdr))
    return;
  endif
  last = [hdr(2:end) - 1; numel(L)];

  ## A demo is no test, and the names on a %!shared line are variables of it
  shared = {};
  for ii = 1:numel (hdr)
    if (strcmp (head{hdr(ii)}, 'demo'))
      code(hdr(ii):last(ii)) = {''};
    elseif (strcmp (head{hdr(ii)}, 'shared'))
      w = regexp (L{hdr(ii)}(9:end), '[A-Za-z_]\w*', 'match');
      shared(end+1,:) = {hdr(ii), w};
    endif
  endfor
  text = strjoin (code', "\n");
  blocks = struct ('first', num2cell (hdr), 'last', num2cell (last), ...
                   'kind', head(hdr));
  [R, OK, Nt] = readSource (T, F, text, true, blocks, shared);

endfunction

## Read the calls in one source text and return them as edge rows, one reading
## after another: plain calls, methods, dotted names, handles, names given as
## strings, calls to a superclass, property access, indexing and operators.  T
## is the inventory, F the record of the file and TEXT its text.  TEST says the
## text is the test code of the file, BLOCKS gives the extent of its blocks and
## SHARED their shared variables.  OK is false if the parse did not complete,
## and Nt holds the functions defined in tests.
function [R, OK, Nt] = readSource (T, F, TEXT, TEST, BLOCKS, SHARED)

  R = devtools.callGraph.Tables.edges;
  [X, Nt] = sourceContext (T, F, TEXT, TEST, BLOCKS, SHARED);
  OK = X.Q.ok;

  pPlain = [];
  code = X.code(X.nid);
  plain = X.live & code != 2 & code != 0;
  last = numel (X.fs) + 1;
  plainParts = {};
  if (any (plain))
    plainCode = code(plain);
    plainKinds = repmat ({'call'}, numel (plainCode), 1);
    plainKinds(plainCode == 3) = {'constructor'};
    plainScope = X.scope(plain);
    plainScope(plainScope == 0) = last;
    plainParts{end+1} = X.add (X.fnKey(plainScope), ...
                          X.target(X.nid(plain)), plainKinds, ...
                          repmat ({'certain'}, numel (plainCode), 1), ...
                          X.byte(plain));
  endif

  ## A name nothing defines is a variable, if its scope writes it after this
  ## read, or runs something that can create it
  unk = X.live & code == 0;
  unk(unk) = ! laterVariable (X, unk);
  if (any (unk))
    nUnknown = sum (unk);
    plainScope = X.scope(unk);
    plainScope(plainScope == 0) = last;
    plainParts{end+1} = X.add (X.fnKey(plainScope), ...
                          X.uname(X.nid(unk)), ...
                          repmat ({'call'}, nUnknown, 1), ...
                          repmat ({'unresolved'}, nUnknown, 1), X.byte(unk));
  endif
  if (! isempty (plainParts))
    pPlain = vertcat (plainParts{:});
  endif
  pMethod = [];
  sites = find (X.live & X.code(X.nid) == 2);
  m = numel (sites);
  if (! m == 0)
    methodTo = methodKinds = methodCert = cell (m, 1);
    for ii = 1:m
      k = sites(ii);
      name = X.uname{X.nid(k)};
      CALLEE = X.byte(k);
      SCOPE = X.scope(k);
      ## Nothing but built-in values: no method can be reached
      v = struct ('cls', {{}}, 'open', false, 'complete', true);
      callArgs = X.args;
      a = lookup (callArgs.callee, CALLEE - 0.5) + 1;
      walking = true;
      while (walking && a <= numel (callArgs.callee)
             && callArgs.callee(a) == CALLEE)
        switch (callArgs.type{a})
          case {'number', 'string', 'matrix', 'cell', 'colon', ...
                'ignored_output', 'end_index', 'range_expression'}
            a += 1;
          case 'identifier'
            v = varClass (X.VC, SCOPE, ...
                        X.text(callArgs.s(a)+1:callArgs.e(a)), X.outer);
            walking = false;
          otherwise
            v = [];
            walking = false;
        endswitch
      endwhile
      if (isempty (v))
        D = T.noClass.(name);
      elseif (isempty (v.cls))
        D = T.noObject.(name);
      else
        [D.to, D.kinds, D.cert] = dispatch (T, name, v);
      endif
      methodTo{ii} = D.to;
      methodKinds{ii} = D.kinds;
      methodCert{ii} = D.cert;
    endfor
    r = sites(repelem ((1:m)', cellfun (@numel, methodTo)));
    scp = X.scope(r);
    scp(scp == 0) = numel (X.fs) + 1;
    pMethod = X.add (X.fnKey(scp), ...
               vertcat (methodTo{:}), vertcat (methodKinds{:}), ...
               vertcat (methodCert{:}), ...
               X.byte(r));
  endif
  pSuper = [];
  so = X.at ('so');
  if (! isempty (so))
    sc = X.at ('sc');
    [~, superMatch] = ismember (X.Q.match(so), X.Q.match(sc));
    obj = X.nameOf (so);
    cls = X.nameOf (sc(superMatch));
    superByte = X.Q.sbyte(so);
    superScope = owner (X.fs, X.fe, superByte);
    superScope(superScope == 0) = numel (X.fs) + 1;
    superFrom = X.fnKey(superScope);
    superTo = superKinds = superCert = cell (numel (superByte), 1);
    drop = false (numel (superByte), 1);
    for ns = 1:numel (superByte)
      methodName = regexprep (superFrom{ns}, '^.*\.', '');
      if (strcmp (obj{ns}, methodName))
        superTo{ns} = findMethod (T, cls{ns}, methodName);
        superKinds{ns} = 'method';
      else
        superTo{ns} = cls{ns};
        superKinds{ns} = 'constructor';
      endif
      superCert{ns} = 'certain';
      drop(ns) = isempty (superTo{ns}) || ! isfield (T.classes, cls{ns});
    endfor
    pSuper = X.add (superFrom(! drop), superTo(! drop), superKinds(! drop), ...
                    superCert(! drop), superByte(! drop));
  endif
  pIndex = [];
  if (! numfields (X.VC) == 0)
    indexFrom = indexTo = indexCert = {};
    at_ = [];
    for ni = find (X.paren & X.isVar)'
      varInfo = varClass (X.VC, X.scope(ni), X.uname{X.nid(ni)}, X.outer);
      if (isempty (varInfo))
        continue;
      endif
      [tt, cc] = dotDispatch (T, 'subsref', varInfo);
      indexScope = X.scope(ni);
      indexScope(indexScope == 0) = numel (X.fs) + 1;
      self = X.fnKey{indexScope};
      own = any (cellfun (@(c) strncmp (self, [c, '.'], numel (c) + 1), ...
                          varInfo.cls));
      nHit = numel (tt);
      if (nHit == 0 || own)
        continue;                       # a class's own methods use built-in
      endif
      indexFrom = [indexFrom; repmat({self}, nHit, 1)];
      indexTo = [indexTo; tt];
      indexCert = [indexCert; cc];
      at_ = [at_; repmat(X.byte(ni), nHit, 1)];
    endfor
    if (! isempty (at_))
      pIndex = X.add (indexFrom, indexTo, ...
                      repmat ({'subsref'}, numel (at_), 1), ...
                      indexCert, at_);
    endif
  endif
  parts = {pPlain, pMethod, siteRows(X), handleRows(T, X), ...
           stringRows(T, X), pSuper, dotMethodRows(T, X), ...
           memberRows(T, X), pIndex, operatorRows(T, X)};
  parts = parts(! cellfun (@isempty, parts));
  if (isempty (parts))
    return;
  endif
  A = vertcat (parts{:});
  from = vertcat (A.from);
  to = vertcat (A.to);
  kinds = vertcat (A.kind);
  cert = vertcat (A.certainty);
  b = vertcat (A.byte);
  n = numel (b);
  if (n == 0)
    return;
  endif

  R.from = from;
  R.to = to;
  R.kind = kinds;
  R.certainty = cert;
  [tf, j] = ismember (b, X.out.byte);
  R.nargout = ones (n, 1);
  R.nargout(tf) = X.out.count(j(tf));
  R.nargout(ismember (kinds, {'handle', 'string'})) = NaN;
  R.varargin = ismember (b, X.forward);
  R.test = repmat (TEST, n, 1);
  R.file = repmat ({F.rel}, n, 1);
  R.line = lookup (X.lineStart, b, 'l');
  R.guard = repmat ({''}, n, 1);
  if (! TEST)
    R.guard = guards (X, b);
  endif

endfunction

## Prepare what every reading of one source text needs.  The inputs are those of
## readSource.  X holds the parse and its captures, the function scopes, every
## identifier that may be a reference and what it resolves to, which names are
## variables, the classes those variables hold, the output counts of calls and
## the dotted names.  It also holds X.at, which returns the captures of a tag,
## X.nameOf, which returns the text of captures, and X.add, which builds edge
## rows.  Nt holds the functions defined in tests.
function [X, Nt] = sourceContext (T, F, TEXT, TEST, BLOCKS, SHARED)

  Q = devtools.__parseQuery__ (TEXT, callQuery ());
  S = tagIndex (Q.capture);
  X = struct ();
  X.file = F;
  X.text = TEXT;
  X.Q = Q;
  X.at = @(name) tagged (S, name);
  X.nameOf = @(k) cellslices (TEXT, Q.sbyte(k)+1, Q.ebyte(k), 2)(:);
  X.add = @(from, to, kind, cert, b) struct ('from', {from(:)}, ...
            'to', {to(:)}, 'kind', {kind(:)}, 'certainty', {cert(:)}, ...
            'byte', b(:));
  X.lineStart = [0, find(TEXT == "\n")];
  [X, Nt] = scopesOf (X, TEST, BLOCKS, SHARED);

  ## The identifiers that may be references
  kid = X.at ('id');
  byte = Q.sbyte(kid);
  [byte, o] = sort (byte);
  kid = kid(o);
  skip = false (size (byte));
  xs = Q.sbyte(X.at ('xr'));
  if (! (isempty (xs) || isempty (byte)))
    [xs, xo] = sort (xs(:));
    xe = cummax (Q.ebyte(X.at ('xr'))(:)(xo));
    xk = lookup (xs, byte(:));
    xhit = xk > 0;
    skip(xhit) = byte(xhit) < xe(xk(xhit));
  endif
  skip |= ismember (byte, Q.sbyte(X.at ('fld')));
  kl = X.at ('wl');
  kl = kl(! strcmp (X.Q.type(kl), 'multi_assignment_target'));
  km = X.at ('wm');
  km = km(! ismember (X.Q.type(km), {'line_continuation', 'comment'}));
  km = km(! strcmp (X.Q.type(km), 'ignored_output'));
  ka = X.at ('asg');
  kf = X.at ('wf');
  kf = kf(! strcmp (X.Q.type(kf), 'multi_assignment_target'));
  kd = X.at ('wd');
  [~, j] = ismember (X.Q.match([kl; km]), X.Q.match(ka));
  W = [kl; km; kf; kd];
  WE = [X.Q.ebyte(ka(j)); X.Q.ebyte(kf); X.Q.ebyte(kd)];
  WP = strcmp (X.Q.type(W), 'identifier');
  X.wl = W;
  X.wEnd = WE;
  X.wPlain = WP;
  skip |= ismember (byte, Q.sbyte(X.wl));
  kid = kid(! skip);
  byte = byte(! skip);
  names = X.nameOf (kid);
  isAns = strcmp (names, 'ans');
  names(isAns) = [];
  byte(isAns) = [];
  [X.uname, ~, nid] = unique (names);
  X.nid = nid(:);
  X.byte = byte;
  X.scope = owner (X.fs, X.fe, byte);

  ## Variables: a name a scope writes, from the end of its first write
  X.wName = regexprep (X.nameOf (X.wl), '^\s*([A-Za-z_]\w*).*$', '$1', 'once');
  X.isVar = variableMask (X);

  ## What each class-typed variable holds
  X.VC = variableClasses (T, X);

  ## Output counts and forwarded varargin, keyed by the byte a callee starts at
  X.out = siteOutputs (X);
  va = X.at ('va');
  va = va(strcmp (X.nameOf (va), 'varargin'));
  forward = Q.sbyte(X.at ('vv'));
  X.forward = forward(ismember (Q.match(X.at ('vv')), Q.match(va)));

  X.paren = ismember (byte, Q.sbyte(X.at ('paren')));

  ## Dotted names that start with a name no variable holds
  [X.claimed, X.dotted] = dottedSites (T, X);
  ac = X.at ('ac');
  aa = X.at ('aa');
  [~, jac] = ismember (X.Q.match(aa), X.Q.match(ac));
  named = ! ismember (X.Q.type(aa), {'line_continuation', 'comment'});
  aa = aa(named);
  ac = ac(jac(named));
  [~, ord] = sortrows ([X.Q.sbyte(ac), X.Q.sbyte(aa)]);
  X.args = struct ('callee', X.Q.sbyte(ac)(ord), 's', X.Q.sbyte(aa)(ord), ...
                   'e', X.Q.ebyte(aa)(ord), 'type', {X.Q.type(aa)(ord)});

  ## Names resolved once for this file
  [X.code, X.target] = resolveNames (T, X, X.uname);
  X.live = ! X.isVar & ! ismember (byte, X.claimed);

endfunction

## Find the functions of a text and give each one its key.  X is the context so
## far, TEST says the text is test code, and BLOCKS and SHARED describe its
## blocks.  Each test block is a scope of its own that reads its %!shared block,
## and the last key is the file's own, for code outside any function.  X gains
## the scopes and their keys, and NT holds the functions the tests define.
function [X, NT] = scopesOf (X, TEST, BLOCKS, SHARED)

  NT = [];
  F = X.file;
  Q = X.Q;
  kf = X.at ('fn');
  [fs, o] = sort (Q.sbyte(kf));
  fe = Q.ebyte(kf)(o);
  fnKey = F.fnKey;
  fnObj = F.fnObj;
  fnCls = F.fnCls;
  X.localName = F.localName(:);
  X.localNode = F.localNode(:);
  if (TEST)
    LN = X.localName;
    LK = X.localNode;
    fnKey = cell (numel (fs), 1);
    NT = [];
    testFns = X.at ('fn');
    if (! isempty (testFns))
      nm = X.at ('fname');
      [~, byStart] = sort (X.Q.sbyte(nm));
      names = X.nameOf (nm(byStart));
      [~, byStart] = sort (X.Q.sbyte(testFns));
      fnKey = cellfun (@(s) [X.file.main, '>', s], names, ...
                       'UniformOutput', false);
      [~, u] = unique (fnKey, 'first');
      u = sort (u);
      n = numel (u);
      extra = ! ismember (fnKey(u), LK);
      LN = [LN; names(u(extra))];
      LK = [LK; fnKey(u(extra))];
      sr = X.Q.srow(testFns)(byStart);
      NT = struct ('node', {fnKey(u)}, 'kind', {repmat({'local'}, n, 1)}, ...
                   'package', {repmat({X.file.pkg}, n, 1)}, ...
                   'file', {repmat({X.file.rel}, n, 1)}, 'line', sr(u) + 1, ...
                   'class', {repmat({''}, n, 1)}, 'abstract', false (n, 1));
    endif
    X.localName = LN;
    X.localNode = LK;
    fnObj = repmat ({''}, numel (fs), 1);
    fnCls = fnObj;
  endif
  outer = zeros (numel (fs), 1);
  fnKey = fnKey(:);
  sharedVars = cell (numel (fs), 1);

  if (TEST)
    current = 0;
    for ii = 1:numel (BLOCKS)
      if (any (strcmp (BLOCKS(ii).kind, {'function', 'endfunction'})))
        continue;
      endif
      s = X.lineStart(BLOCKS(ii).first);
      e = numel (X.text);
      if (BLOCKS(ii).last < numel (X.lineStart))
        e = X.lineStart(BLOCKS(ii).last+1);
      endif
      fs(end+1,1) = s;
      fe(end+1,1) = e;
      fnKey{end+1,1} = F.main;
      fnObj{end+1,1} = '';
      fnCls{end+1,1} = '';
      outer(end+1,1) = current;
      sharedVars{end+1,1} = {};
      if (strcmp (BLOCKS(ii).kind, 'shared'))
        outer(end) = 0;
        current = numel (fs);
        hit = [SHARED{:,1}] == BLOCKS(ii).first;
        sharedVars{end} = SHARED{hit,2};
      endif
    endfor
    [fs, o] = sort (fs);
    fe = fe(o);
    fnKey = fnKey(o);
    fnObj = fnObj(o);
    fnCls = fnCls(o);
    sharedVars = sharedVars(o);
    remap = zeros (numel (o), 1);
    remap(o) = 1:numel (o);
    outer = outer(o);
    outer(outer > 0) = remap(outer(outer > 0));
  endif

  X.fs = fs;
  X.fe = fe;
  X.fnObj = fnObj;
  X.fnCls = fnCls;
  X.outer = outer;
  X.sharedVars = sharedVars;
  fnKey{end+1,1} = F.main;
  X.fnKey = fnKey;

endfunction

## Group the captures of a query by tag.  CAPTURE is the tag of each capture,
## and S a structure with one field per tag, holding the indices of its captures
## in order.
function S = tagIndex (CAPTURE)

  [tags, ~, j] = unique (CAPTURE);
  S = struct ();
  if (isempty (tags))
    return;
  endif
  groups = accumarray (j(:), (1:numel (j))', [], @(x) {sort(x)});
  for ii = 1:numel (tags)
    S.(tags{ii}) = groups{ii};
  endfor

endfunction

## The captures of one tag, or an empty column if the query captured none.  S
## comes from tagIndex and NAME is the tag.  It is a function so that X.at can
## hold a handle to it.
function K = tagged (S, NAME)

  K = zeros (0, 1);
  if (isfield (S, NAME))
    K = S.(NAME);
  endif

endfunction

## The tree-sitter query behind every reading of a source text, as one string.
## It captures identifiers, calls and their arguments, assignments, function
## definitions, handles, conditions and operators under the tags the readers ask
## for, and is built once per session.
function q = callQuery ()

  persistent query = '';
  if (isempty (query))
    query = strjoin ({ ...
      '(identifier) @id', ...
      '(index_expression value: (identifier) @paren)', ...
      '(field_expression field: (identifier) @fld)', ...
      '(function_definition name: (_) @xr)', ...
      '(function_definition output: (_) @xr)', ...
      '(parameter_list (identifier) @xr)', ...
      '(parameter_list name: (identifier) @xr)', ...
      '(classdef_definition name: (_) @xr)', ...
      '(classdef_definition superclasses: (_) @xr)', ...
      '(attribute_list) @xr', ...
      '(property name: (_) @xr)', ...
      '(function_handle) @xr @h', ...
      '(superclass_reference) @xr', ...
      '(anonymous_function parameters: (_) @xr)', ...
      '(arguments_block) @xr', ...
      '(enumeration_block) @xr', ...
      '(events_block) @xr', ...
      '(assignment left: (_) @wl) @asg', ...
      '(assignment left: (multi_assignment_target (_) @wm)) @asg', ...
      '(for_statement variable: (_) @wf)', ...
      '(for_statement variable: (multi_assignment_target (_) @wf))', ...
      '(declaration (identifier) @wd)', ...
      '(catch_clause error: (identifier) @wd)', ...
      ['(function_definition parameters: (parameter_list', ...
       ' (identifier) @par)) @fnp'], ...
      ['(function_definition parameters: (parameter_list', ...
       ' name: (identifier) @par)) @fnp'], ...
      '(function_definition output: (identifier) @par) @fnp', ...
      ['(function_definition output: (multi_assignment_target', ...
       ' (identifier) @par)) @fnp'], ...
      '(anonymous_function parameters: (parameter_list (_) @lp)) @lam', ...
      '(function_definition) @fn', ...
      '(function_definition name: (_) @fname)', ...
      '(superclass_reference object: (_) @so class: (_) @sc)', ...
      ['(index_expression value: (field_expression field:', ...
       ' (identifier) @mf) @mv)'], ...
      '(field_expression) @dot', ...
      '(field_expression value: (identifier) @fo field: (identifier) @ff)', ...
      '(index_expression value: (identifier) @ac (_) @aa)', ...
      '(index_expression value: (identifier) @hc . (_) @ha)', ...
      ['(expression_statement (index_expression value:', ...
       ' [(identifier) (field_expression)] @s0))'], ...
      '(expression_statement [(identifier) (field_expression)] @s0)', ...
      '(command_statement name: (identifier) @s0)', ...
      ['(assignment left: (multi_assignment_target (_) @el) right:', ...
       ' (index_expression value: [(identifier) (field_expression)] @mt))'], ...
      ['(assignment left: (multi_assignment_target (_) @el) right:', ...
       ' [(identifier) (field_expression)] @mt)'], ...
      ['(anonymous_function body: (index_expression value:', ...
       ' [(identifier) (field_expression)] @na))'], ...
      '(anonymous_function body: [(identifier) (field_expression)] @na)', ...
      ['(index_expression value: (_) @vv (cell_index_expression value:', ...
       ' (identifier) @va (colon)))'], ...
      '(if_statement condition: (_) @ic) @if', ...
      '(elseif_clause condition: (_) @ec) @elif', ...
      '(else_clause) @els', ...
      '(switch_statement value: (_) @sv) @sw', ...
      '(case_clause value: (_) @cv) @cc', ...
      '(otherwise_clause) @oc', ...
      ['(assignment left: (identifier) @cl right: (index_expression value:', ...
       ' [(identifier) (field_expression)] @cr))'], ...
      '(binary_expression left: (_) @bl right: (_) @br)', ...
      '(unary_expression argument: (identifier) @ua) @un', ...
      '(postfix_expression argument: (identifier) @pa) @pn'}, ' ');
  endif
  q = query;

endfunction

## Find the innermost function scope holding each byte.  FS and FE are the
## sorted start and end bytes of the scopes and B the bytes asked about.  K is
## the number of the scope holding each byte, 0 for none.  A quick lookup
## settles most bytes, and only those in a nested definition are searched for
## one by one.
function K = owner (FS, FE, B)

  B = B(:);
  K = zeros (size (B));
  if (isempty (FS) || isempty (B))
    return;
  endif
  k = lookup (FS, B(:));
  hit = k > 0;
  in = false (size (k));
  in(hit) = B(hit) < FE(k(hit));
  K(in) = k(in);
  ## A definition nested in another closes before the outer one does
  out = find (hit & ! in);
  for ii = out(:)'
    c = find (FS <= B(ii) & B(ii) < FE, 1, 'last');
    if (! isempty (c))
      K(ii) = c;
    endif
  endfor

endfunction

## Mark the identifiers of a text that are variables rather than calls.  X is
## the context.  A name counts as a variable in a scope from the end of its
## first write, and from the start for parameters, outputs and the names on a
## %!shared line.  In a function holding nested functions, a name written
## anywhere in the family holds throughout it.  A test block also reads what its
## %!shared block writes, and an anonymous function's parameters hold only
## within it.  M is a logical vector over the identifiers.
function M = variableMask (X)

  n = numel (X.fs) + 1;
  u = numel (X.uname);
  first = inf (n, u);
  root = (1:n-1)';
  for rs = 2:n-1
    rk = find (X.fs(1:rs-1) <= X.fs(rs) & X.fe(rs) <= X.fe(1:rs-1), 1);
    if (! isempty (rk))
      root(rs) = root(rk);
    endif
  endfor
  root = [root; n];
  nested = root != (1:n)';
  shared = false (n, 1);
  shared(root(nested)) = true;

  ## Written names, by scope, the earliest write first; a nested function
  ## shares its parent's variables, and so writes them at no particular point
  [tf, j] = ismember (X.wName, X.uname);
  if (any (tf))
    s = owner (X.fs, X.fe, X.Q.sbyte(X.wl));
    s(s == 0) = n;
    s = root(s);
    e = accumarray ([s(tf), j(tf)], X.wEnd(tf), [n, u], @min);
    hit = e > 0;
    first(hit) = e(hit);
    sh = first(shared,:);
    sh(sh < inf) = -1;
    first(shared,:) = sh;
  endif

  ## Parameters and outputs hold from the start
  kp = X.at ('par');
  if (! isempty (kp))
    fnp = X.at ('fnp');
    [~, jj] = ismember (X.Q.match(kp), X.Q.match(fnp));
    names = regexprep (X.nameOf (kp), '^\s*([A-Za-z_]\w*).*$', '$1', 'once');
    [tf, j] = ismember (names, X.uname);
    s = owner (X.fs, X.fe, X.Q.sbyte(fnp(jj)));
    s(s == 0) = n;
    s = root(s);
    tf &= s < n;
    first(sub2ind ([n, u], s(tf), j(tf))) = -1;
  endif
  for ii = 1:numel (X.sharedVars)
    if (! isempty (X.sharedVars{ii}))
      [tf, j] = ismember (X.sharedVars{ii}, X.uname);
      first(ii, j(tf)) = -1;
    endif
  endfor

  sc = X.scope;
  sc(sc == 0) = n;
  sc = root(sc);
  idx = sub2ind ([n, u], sc, X.nid);
  M = X.byte(:) >= first(idx)(:);
  in = X.outer(:);
  in(end+1) = 0;
  via = in(sc);
  w = find (via > 0);
  if (! isempty (w))
    M(w) |= X.byte(w) >= first(sub2ind ([n, u], via(w), X.nid(w)));
  endif

  ## An anonymous function's parameters, within it
  kl = X.at ('lp');
  if (! isempty (kl))
    lam = X.at ('lam');
    [~, jj] = ismember (X.Q.match(kl), X.Q.match(lam));
    names = regexprep (X.nameOf (kl), '^\s*([A-Za-z_]\w*).*$', '$1', 'once');
    [tf, j] = ismember (names, X.uname);
    for ii = find (tf)'
      s = X.Q.sbyte(lam(jj(ii)));
      e = X.Q.ebyte(lam(jj(ii)));
      M(X.nid == j(ii) & X.byte >= s & X.byte < e) = true;
    endfor
  endif

endfunction

## Work out which classes each object variable holds, by scope.  T is the
## inventory and X the context.  VC has one field per variable, named by scope
## number and variable, holding cls, the classes, open, true if the object may
## be of a subclass, and complete, true if each plain write to it was accounted
## for.  The object of a method, its first input or a constructor's output,
## holds its class and is open.  A variable assigned from a call holds the
## classes that call yields, and is not open.
function VC = variableClasses (T, X)

  VC = struct ();
  for ii = 1:numel (X.fnObj)
    if (! isempty (X.fnObj{ii}))
      key = sprintf ("%d|%s", ii, X.fnObj{ii});
      VC.(key) = struct ('cls', {X.fnCls(ii)}, 'open', true, 'complete', true);
    endif
  endfor

  kl = X.at ('cl');
  if (isempty (kl))
    return;
  endif
  kr = X.at ('cr');
  [~, j] = ismember (X.Q.match(kl), X.Q.match(kr));
  callee = X.nameOf (kr(j));
  var = X.nameOf (kl);
  sOf = owner (X.fs, X.fe, X.Q.sbyte(kl));
  plainS = owner (X.fs, X.fe, X.Q.sbyte(X.wl(X.wPlain)));
  plainN = X.wName(X.wPlain);
  [u, ~, g] = unique (strcat (num2str (sOf(:)), '|', var(:)));
  for ii = 1:numel (u)
    hit = find (g == ii);
    s = sOf(hit(1));
    v = var{hit(1)};
    key = sprintf ("%d|%s", s, v);
    if (isfield (VC, key))
      continue;
    endif
    [c, done] = classesOf (T, callee(hit));
    if (isempty (c))
      continue;
    endif
    nw = sum (plainS == s & strcmp (plainN, v));
    VC.(key) = struct ('cls', {unique(c)}, 'open', false, ...
                      'complete', done && numel (hit) == nw);
  endfor

endfunction

## Find how many outputs calls ask for.  X is the context.  Out holds byte,
## where a callee starts, and count, its output count: 0 for a call standing as
## a statement, the length of the list on the left of a multiple assignment, and
## NaN where that is not settled, as for a list taking however many a cell holds
## or the body of an anonymous function.
function Out = siteOutputs (X)

  s0 = X.Q.sbyte(X.at ('s0'));
  mt = X.at ('mt');
  el = X.at ('el');
  [~, j] = ismember (X.Q.match(el), X.Q.match(mt));
  keep = find (! ismember (X.Q.type(el), {'line_continuation', 'comment'}));
  b = zeros (0, 1);
  c = zeros (0, 1);
  if (! isempty (keep))
    [b, ~, g] = unique (X.Q.sbyte(mt(j(keep))));
    c = accumarray (g(:), 1);
    ## A list that takes however many a cell holds settles no count
    t = X.nameOf (el(keep));
    open = g(! cellfun (@isempty, regexp (t, '\{[^}]*:[^}]*\}', 'once')));
    c(open) = NaN;
  endif
  na = X.Q.sbyte(X.at ('na'));
  Out = struct ('byte', [s0; b(:); na], ...
                'count', [zeros(numel (s0), 1); c(:); NaN(numel (na), 1)]);

endfunction

## Decide which unknown names are really variables.  X is the context and MASK
## marks the references that nothing defines.  TF is true for a reference whose
## scope writes that name, or where its scope, or the %!shared block it reads,
## runs something that can create variables: load, eval, evalc, evalin or
## assignin.
function TF = laterVariable (X, MASK)

  scope = X.scope(MASK);
  nid = X.nid(MASK);
  TF = false (size (scope));
  if (isempty (scope))
    return;
  endif
  last = numel (X.fs) + 1;
  made = false (last, 1);
  k = X.at ('s0');
  if (! isempty (k))
    makers = {'load', 'eval', 'evalc', 'evalin', 'assignin'};
    k = k(ismember (X.nameOf (k), makers));
    scp = owner (X.fs, X.fe, X.Q.sbyte(k));
    scp(scp == 0) = last;
    made(scp) = true;
  endif
  n = numel (made);
  in = [X.outer(:); 0];
  s = scope;
  s(s == 0) = n;
  TF = made(s) | (in(s) > 0 & made(max (in(s), 1)));
  wscope = owner (X.fs, X.fe, X.Q.sbyte(X.wl));
  for ii = find (! TF(:))'
    TF(ii) = any (strcmp (X.wName(wscope == scope(ii)), X.uname{nid(ii)}));
  endfor

endfunction

## Look up what a variable holds.  VC comes from variableClasses, SCOPE is a
## scope number, NAME the variable and OUTER the enclosing block of each scope.
## A test block that does not write the variable reads it from its %!shared
## block.  V is the record of the variable, or empty if none is known.
function V = varClass (VC, SCOPE, NAME, OUTER)

  V = [];
  key = sprintf ("%d|%s", SCOPE, NAME);
  if (! isfield (VC, key) && SCOPE > 0 && OUTER(SCOPE) > 0)
    key = sprintf ("%d|%s", OUTER(SCOPE), NAME);
  endif
  if (isfield (VC, key))
    V = VC.(key);
  endif

endfunction

## Resolve the names used in one file, in the order core resolves them.  T is
## the inventory, X the context and NAMES the names.  CODE says what each name
## is: 1 local or private, 2 also a method, 3 a class, 4 on the load path, 5
## core, and 0 nothing.  TO holds the node each name reaches, or the name itself
## where there is none.
function [CODE, TO] = resolveNames (T, X, NAMES)

  n = numel (NAMES);
  CODE = zeros (n, 1);
  TO = NAMES(:);

  [tf, j] = ismember (NAMES, T.core);
  CODE(tf) = 5;
  [tf, j] = ismember (NAMES, T.plainName);
  CODE(tf) = 4;
  isCls = false (n, 1);
  isCls(tf) = strcmp (T.plainKind(j(tf)), 'class');
  CODE(isCls) = 3;

  CODE(isfield (T.byName, NAMES(:))) = 2;

  base = X.file.base;
  key = cellfun (@(s) [base, '|', s], NAMES(:), 'UniformOutput', false);
  [tf, j] = ismember (key, T.privKey);
  CODE(tf) = 1;
  TO(tf) = T.privNode(j(tf));

  [tf, j] = ismember (NAMES, X.localName);
  CODE(tf) = 1;
  TO(tf) = X.localNode(j(tf));

endfunction

## Find what a call reaches when its name is also a method.  T is the inventory,
## NAME the name and V what it dispatches on: a variable's classes, a record
## with no classes for built-in values, or empty for nothing known.  TO, KINDS
## and CERT are the edge rows.  Classes that are settled and lack the method
## reach the plain function, certainly so where they are complete.  With nothing
## known, a name that is also a plain function gives one candidate row to it,
## and a name that is only a method gives one row per class defining it, certain
## where only one does.
function [TO, KINDS, CERT] = dispatch (T, NAME, V)

  [fall, fallKind] = fallThrough (T, NAME);
  if (! isempty (V))
    TO = methodsFor (T, V, NAME);
    if (! isempty (TO))
      KINDS = repmat ({'method'}, numel (TO), 1);
      CERT = repmat ({'candidates'}, numel (TO), 1);
      if (isscalar (TO) && V.complete)
        CERT = {'certain'};
      endif
      return;
    endif
  endif

  ## Settled classes that lack the method reach the plain function
  unsettled = isempty (V) || ! V.complete;
  if (! isempty (fall))
    TO = {fall};
    KINDS = {fallKind};
    CERT = {'certain'};
    ## One row: the classes defining the name are in the nodes
    if (unsettled)
      CERT = {'candidates'};
    endif
    return;
  endif

  ## A name that is a method and nothing else: every class defining it
  TO = cell (0, 1);
  if (unsettled || isempty (V.cls))
    TO = T.byName.(NAME)(:);
  endif
  KINDS = repmat ({'method'}, numel (TO), 1);
  CERT = repmat ({'candidates'}, numel (TO), 1);
  if (isscalar (TO))
    CERT = {'certain'};
  endif

endfunction

## Find the nodes a method name reaches on a variable's classes.  T is the
## inventory, V the record of the variable and NAME the method.  Each class's
## own or inherited method is included and, where V is open, the overrides in
## its subclasses too, since the object may be of one of them.  TO is a cell
## array of node keys.
function TO = methodsFor (T, V, NAME)

  TO = {};
  for ii = 1:numel (V.cls)
    base = findMethod (T, V.cls{ii}, NAME);
    if (! isempty (base))
      TO{end+1} = base;
    endif
    if (V.open)
      CLS = V.cls{ii};
      below = {};
      if (isfield (T.classes, CLS))
        queue = T.classes.(CLS).children;
        while (! isempty (queue))
          c = queue{1};
          queue(1) = [];
          k = [c, '.', NAME];
          if (isfield (T.methods, k))
            below{end+1} = k;
          endif
          queue = [queue, T.classes.(c).children];
        endwhile
      endif
      TO = [TO, below];
    endif
  endfor
  TO = unique (TO)(:);

endfunction

## Find the plain function or constructor a name reaches when no method does.  T
## is the inventory and NAME the name.  TO is the name and KIND is 'call' or
## 'constructor', both empty if nothing on the load path or in core has that
## name.
function [TO, KIND] = fallThrough (T, NAME)

  TO = '';
  KIND = '';
  k = find (strcmp (T.plainName, NAME), 1);
  if (! isempty (k))
    TO = NAME;
    KIND = 'call';
    if (strcmp (T.plainKind{k}, 'class'))
      KIND = 'constructor';
    endif
  elseif (any (strcmp (T.core, NAME)))
    TO = NAME;
    KIND = 'call';
  endif

endfunction

## Find the node a class reaches for a method.  T is the inventory, CLS the
## class and NAME the method.  The class and its superclasses are searched
## breadth first, so the nearest definition wins.  KEY is the node, or empty if
## none has it.
function KEY = findMethod (T, CLS, NAME)

  KEY = '';
  queue = {CLS};
  seen = {};
  while (! isempty (queue))
    c = queue{1};
    queue(1) = [];
    if (any (strcmp (seen, c)) || ! isfield (T.classes, c))
      continue;
    endif
    seen{end+1} = c;
    k = [c, '.', NAME];
    if (isfield (T.methods, k))
      KEY = k;
      return;
    endif
    queue = [queue, T.classes.(c).supers];
  endwhile

endfunction

## Find the dotted names in a text that do not start at a variable: a namespace,
## a class or a static call.  T is the inventory and X the context.  Only the
## longest chain from each start is taken, and a class's constant is no call.  A
## chain that resolves to nothing is not claimed, and is read later as an
## ordinary call whose result is indexed.  CLAIMED holds the bytes those names
## start at, so that later readings pass over them, and R their edge rows.
function [CLAIMED, R] = dottedSites (T, X)

  CLAIMED = zeros (0, 1);
  R = struct ('byte', {}, 'to', {}, 'kind', {}, 'certainty', {});
  kd = X.at ('dot');
  if (isempty (kd))
    return;
  endif
  t = X.nameOf (kd);
  pure = ! cellfun (@isempty, regexp (t, ...
    '^[A-Za-z_]\w*(\s*\.\s*[A-Za-z_]\w*)+$', 'once'));
  kd = kd(pure);
  t = strrep (t(pure), ' ', '');
  if (isempty (kd))
    return;
  endif

  ## Only the longest chain from each start, and only if no variable starts it
  [b, o] = sortrows ([X.Q.sbyte(kd), -X.Q.ebyte(kd)]);
  b = b(:,1);
  t = t(o);
  keep = [true; diff(b) != 0];
  b = b(keep);
  t = t(keep);
  [tf, j] = ismember (b, X.byte);
  live = tf;
  live(tf) = ! X.isVar(j(tf));
  CLAIMED = b(live);
  b = b(live);
  t = t(live);
  for ii = 1:numel (b)
    [to, kind, cert] = resolveDotted (T, t{ii});
    if (isempty (to))
      ## A class's constant is no call.  Otherwise the name is not dotted
      ## after all: it is a call, whose result is indexed
      if (! strcmp (kind, 'member'))
        CLAIMED(ii) = -1;
      endif
      continue;
    endif
    R(end+1) = struct ('byte', b(ii), 'to', to, 'kind', kind, ...
                       'certainty', cert);
  endfor
  CLAIMED(CLAIMED < 0) = [];

endfunction

## Resolve one dotted name.  T is the inventory and NAME the name.  It tries the
## whole name and then ever shorter leading parts, so the longest part naming
## something known is what the call reaches, and any parts after it index its
## result.  A last part after a class is looked up as a method of that class,
## and KIND is 'member' with TO empty where the class has none.  TO, KIND and
## CERT describe the edge, TO being empty where the name resolves to nothing.  A
## name in a namespace we know that the namespace does not hold is unresolved.
function [TO, KIND, CERT] = resolveDotted (T, NAME)

  TO = '';
  KIND = '';
  CERT = 'certain';
  parts = ostrsplit (NAME, '.');
  for n = numel (parts):-1:2
    head = strjoin (parts(1:n), '.');
    k = find (strcmp (T.plainName, head), 1);
    if (! isempty (k))
      TO = head;
      KIND = 'call';
      if (strcmp (T.plainKind{k}, 'class'))
        KIND = 'constructor';
      endif
      return;
    endif
    if (any (strcmp (T.core, head)))
      TO = head;
      KIND = 'call';
      return;
    endif
    pre = strjoin (parts(1:n-1), '.');
    if (isfield (T.classes, pre))
      TO = findMethod (T, pre, parts{n});
      KIND = 'member';
      if (! isempty (TO))
        KIND = 'method';
      endif
      return;
    endif
  endfor

  ## A namespace we know, naming something it does not hold
  if (any (strncmp (T.plainName, [parts{1}, '.'], numel (parts{1}) + 1)))
    TO = NAME;
    KIND = 'call';
    CERT = 'unresolved';
  endif

endfunction

## Build the edge rows of the dotted names dottedSites found.  X is the context,
## and P is empty where there are none.
function P = siteRows (X)

  P = [];
  DR = X.dotted;
  if (isempty (DR))
    return;
  endif
  b = [DR.byte]';
  scp = owner (X.fs, X.fe, b);
  scp(scp == 0) = numel (X.fs) + 1;
  P = X.add (X.fnKey(scp), {DR.to}', {DR.kind}', {DR.certainty}', b);

endfunction

## Resolve a name given as text, by a function handle or a string, in the same
## way a call is resolved.  T is the inventory, X the context, NAME the name and
## KIND the kind its edge takes.  A dotted name goes through resolveDotted, a
## method name is dispatched with nothing known, and a name nothing defines is
## unresolved.  TO, KINDS and CERT are the edge rows.
function [TO, KINDS, CERT] = resolveText (T, X, NAME, KIND)

  if (any (NAME == '.'))
    [to, k, c] = resolveDotted (T, NAME);
    TO = {NAME};
    CERT = {'unresolved'};
    if (! isempty (to))
      TO = {to};
      CERT = {c};
    endif
    KINDS = {KIND};
    return;
  endif
  [code, target] = resolveNames (T, X, {NAME});
  switch (code)
    case 0
      TO = {NAME};
      CERT = {'unresolved'};
    case 2
      [TO, ~, CERT] = dispatch (T, NAME, []);
    otherwise
      TO = target;
      CERT = {'certain'};
  endswitch
  KINDS = repmat ({KIND}, numel (TO), 1);

endfunction

## Build the edge rows of the function handles in a text.  T is the inventory
## and X the context.  Each distinct name is resolved once.  P is empty where
## there are none.
function P = handleRows (T, X)

  P = [];
  kh = X.at ('h');
  if (isempty (kh))
    return;
  endif
  t = regexprep (X.nameOf (kh), '^@\s*', '');
  [ut, ~, j] = unique (t);
  cache = cell (numel (ut), 3);
  for ii = 1:numel (ut)
    [cache{ii,:}] = resolveText (T, X, ut{ii}, 'handle');
  endfor
  sz = cellfun (@numel, cache(:,1));
  counts = sz(j);
  r = repelem ((1:numel (kh))', counts)(:);
  to = vertcat (cache{j,1});
  kinds = vertcat (cache{j,2});
  cert = vertcat (cache{j,3});
  b = X.Q.sbyte(kh)(r);
  scp = owner (X.fs, X.fe, b);
  scp(scp == 0) = numel (X.fs) + 1;
  P = X.add (X.fnKey(scp), to, kinds, cert, b);

endfunction

## Build the edge rows of the names given as literal strings to the functions
## that call by name, such as feval or cellfun.  T is the inventory and X the
## context.  For the functions that run what they are given, an argument no
## reading can settle gives an unresolved row holding it as written.  P is empty
## where there are none.
function P = stringRows (T, X)

  P = [];
  hc = X.at ('hc');
  if (isempty (hc))
    return;
  endif
  byName = {'feval', 'str2func', 'cellfun', 'arrayfun', 'bsxfun', ...
            'structfun', 'fzero', 'fminbnd', 'fminsearch', 'fminunc', ...
            'quad', 'quadgk', 'quadl', 'quadv', 'integral', 'integral2', ...
            'integral3', 'builtin'};
  dynamic = {'feval', 'str2func', 'eval', 'evalc', 'evalin'};
  t = X.nameOf (hc);
  keep = find (ismember (t, [byName, dynamic]));
  if (isempty (keep))
    return;
  endif
  ha = X.at ('ha');
  [~, j] = ismember (X.Q.match(hc), X.Q.match(ha));
  to = {};
  kinds = {};
  cert = {};
  b = [];
  for ii = keep(:)'
    site = X.Q.sbyte(hc(ii));
    [tf, k] = ismember (site, X.byte);
    if (! tf || X.isVar(k))
      continue;
    endif
    if (any (strcmp (X.Q.type{ha(j(ii))}, {'function_handle', ...
                                         'anonymous_function'})))
      continue;                       # the handle's own edge says it all
    endif
    arg = X.text(X.Q.sbyte(ha(j(ii)))+1:X.Q.ebyte(ha(j(ii))));
    isStr = strcmp (X.Q.type{ha(j(ii))}, 'string');
    name = '';
    if (isStr)
      name = arg(2:end-1);
    endif
    if (isStr && ! isempty (regexp (name, '^[A-Za-z_][\w.]*$', 'once'))
        && any (strcmp (t{ii}, byName)))
      [tt, kk, cc] = resolveText (T, X, name, 'string');
    elseif (any (strcmp (t{ii}, dynamic)))
      tt = {regexprep(arg, '\s+', ' ')};
      kk = {'string'};
      cc = {'unresolved'};
    else
      continue;
    endif
    n = numel (tt);
    to = [to; tt(:)];
    kinds = [kinds; kk(:)];
    cert = [cert; cc(:)];
    b = [b; repmat(site, n, 1)];
  endfor
  if (! isempty (b))
    scp = owner (X.fs, X.fe, b);
    scp(scp == 0) = numel (X.fs) + 1;
    P = X.add (X.fnKey(scp), to, kinds, cert, b);
  endif

endfunction

## Build the edge rows of calls written x.name (...) that no dotted name
## claimed, for names some class defines as a method.  T is the inventory and X
## the context.  The method is looked up on what x holds where x is a plain
## variable of known class, and on every class defining it otherwise.  P is
## empty where there are none.
function P = dotMethodRows (T, X)

  P = [];
  mf = X.at ('mf');
  if (isempty (mf))
    return;
  endif
  mv = X.at ('mv');
  [~, j] = ismember (X.Q.match(mf), X.Q.match(mv));
  names = X.nameOf (mf);
  keep = find (isfield (T.byName, names(:)));
  b = X.Q.sbyte(mv(j));
  to = kinds = cert = {};
  at_ = [];
  sc = owner (X.fs, X.fe, b);
  for ii = keep(:)'
    if (any (X.claimed == b(ii)))
      continue;
    endif
    t = X.text(X.Q.sbyte(mv(j(ii)))+1:X.Q.ebyte(mv(j(ii))));
    root = regexp (t, '^([A-Za-z_]\w*)\s*\.\s*[A-Za-z_]\w*$', 'tokens', 'once');
    v = [];
    if (! isempty (root))
      v = varClass (X.VC, sc(ii), root{1}, X.outer);
    endif
    [tt, cc] = dotDispatch (T, names{ii}, v);
    if (isempty (tt))
      continue;
    endif
    n = numel (tt);
    to = [to; tt];
    kinds = [kinds; repmat({'method'}, n, 1)];
    cert = [cert; cc];
    at_ = [at_; repmat(b(ii), n, 1)];
  endfor
  if (! isempty (at_))
    scp = owner (X.fs, X.fe, at_);
    scp(scp == 0) = numel (X.fs) + 1;
    P = X.add (X.fnKey(scp), to, kinds, cert, at_);
  endif

endfunction

## Find what a method name reaches when called on an object.  T is the
## inventory, NAME the method and V the record of the variable, or empty.  With
## no record every class defining the method is a candidate.  With one, the
## method is certain if it is the only one reached and the variable's classes
## are complete.  TO and CERT are the edge rows.
function [TO, CERT] = dotDispatch (T, NAME, V)

  if (isempty (V))
    TO = T.byName.(NAME)(:);
    CERT = repmat ({'candidates'}, numel (TO), 1);
  else
    TO = methodsFor (T, V, NAME);
    CERT = repmat ({'candidates'}, numel (TO), 1);
    if (isscalar (TO) && V.complete)
      CERT = {'certain'};
    endif
  endif

endfunction

## Build the edge rows of property reads and writes on objects of a settled
## class, where the class has a getter or a setter.  T is the inventory and X
## the context.  Inside the accessor itself the name is the property and makes
## no edge.  P is empty where there are none.
function P = memberRows (T, X)

  P = [];
  fo = X.at ('fo');
  if (isempty (fo) || numfields (X.VC) == 0)
    return;
  endif
  ff = X.at ('ff');
  [~, j] = ismember (X.Q.match(fo), X.Q.match(ff));
  obj = X.nameOf (fo);
  fld = X.nameOf (ff(j));
  b = X.Q.sbyte(fo);
  sc = owner (X.fs, X.fe, b);
  isWrite = ismember (b, X.Q.sbyte(X.wl));
  to = kinds = cert = from = {};
  at_ = [];
  for ii = 1:numel (b)
    v = varClass (X.VC, sc(ii), obj{ii}, X.outer);
    if (isempty (v))
      continue;
    endif
    pre = 'get.';
    kind = 'getter';
    if (isWrite(ii))
      pre = 'set.';
      kind = 'setter';
    endif
    [tt, cc] = dotDispatch (T, [pre, fld{ii}], v);
    scp = owner (X.fs, X.fe, b(ii));
    scp(scp == 0) = numel (X.fs) + 1;
    self = X.fnKey(scp);
    inside = strcmp (tt, self{1});    # inside the accessor it is the property
    tt(inside) = [];
    cc(inside) = [];
    n = numel (tt);
    if (n == 0)
      continue;
    endif
    to = [to; tt];
    cert = [cert; cc];
    kinds = [kinds; repmat({kind}, n, 1)];
    from = [from; repmat(self, n, 1)];
    at_ = [at_; repmat(b(ii), n, 1)];
  endfor
  if (! isempty (at_))
    P = X.add (from, to, kinds, cert, at_);
  endif

endfunction

## Build the edge rows of operators applied to objects of a settled class that
## overloads them, binary, unary and postfix, including the transposes.  T is
## the inventory and X the context.  An operand counts only if it is a plain
## variable of known class, and in a binary expression the first such operand
## decides.  P is empty where there are none.
function P = operatorRows (T, X)

  P = [];
  if (numfields (X.VC) == 0)
    return;
  endif
  from = to = cert = {};
  at_ = [];

  bl = X.at ('bl');
  br = X.at ('br');
  [~, j] = ismember (X.Q.match(bl), X.Q.match(br));
  names = struct ('o', {'+', '-', '.*', '*', './', '/', '.\', '\', '.^', ...
                        '^', '<', '<=', '==', '!=', '~=', '>', '>=', '&', ...
                        '|'}, ...
                  'm', {'plus', 'minus', 'times', 'mtimes', 'rdivide', ...
                        'mrdivide', 'ldivide', 'mldivide', 'power', ...
                        'mpower', 'lt', 'le', 'eq', 'ne', 'ne', 'gt', 'ge', ...
                        'and', 'or'});
  sc = owner (X.fs, X.fe, X.Q.sbyte(bl));
  for ii = 1:numel (bl)
    for side = [bl(ii), br(j(ii))]
      if (! strcmp (X.Q.type{side}, 'identifier'))
        continue;
      endif
      name = X.text(X.Q.sbyte(side)+1:X.Q.ebyte(side));
      v = varClass (X.VC, sc(ii), name, X.outer);
      if (isempty (v))
        continue;
      endif
      op = strtrim (X.text(X.Q.ebyte(bl(ii))+1:X.Q.sbyte(br(j(ii)))));
      m = names(strcmp ({names.o}, op));
      if (isempty (m))
        break;
      endif
      [tt, cc] = dotDispatch (T, m.m, v);
      n = numel (tt);
      scp = sc(ii);
      scp(scp == 0) = numel (X.fs) + 1;
      from = [from; repmat(X.fnKey(scp), n, 1)];
      to = [to; tt];
      cert = [cert; cc];
      at_ = [at_; repmat(X.Q.sbyte(bl(ii)), n, 1)];
      break;
    endfor
  endfor

  ## -x, !x, x' and x.'
  single = {'-', 'uminus'; '+', 'uplus'; '!', 'not'; '~', 'not'; ...
            '''', 'ctranspose'; '.''', 'transpose'};
  kv = [X.at('ua'); X.at('pa')];
  kn = [X.at('un'); X.at('pn')];
  [~, j] = ismember (X.Q.match(kv), X.Q.match(kn));
  sc = owner (X.fs, X.fe, X.Q.sbyte(kv));
  for ii = 1:numel (kv)
    var = X.text(X.Q.sbyte(kv(ii))+1:X.Q.ebyte(kv(ii)));
    v = varClass (X.VC, sc(ii), var, X.outer);
    if (isempty (v))
      continue;
    endif
    node = kn(j(ii));
    op = strtrim (strrep (X.text(X.Q.sbyte(node)+1:X.Q.ebyte(node)), var, ''));
    m = single(strcmp (single(:,1), op), 2);
    if (isempty (m))
      continue;
    endif
    [tt, cc] = dotDispatch (T, m{1}, v);
    n = numel (tt);
    scp = sc(ii);
    scp(scp == 0) = numel (X.fs) + 1;
    from = [from; repmat(X.fnKey(scp), n, 1)];
    to = [to; tt];
    cert = [cert; cc];
    at_ = [at_; repmat(X.Q.sbyte(node), n, 1)];
  endfor

  if (! isempty (at_))
    P = X.add (from, to, repmat ({'operator'}, numel (at_), 1), cert, at_);
  endif

endfunction

## Give each call the conditions it runs under.  X is the context and B the
## bytes of the calls.  G holds, for each byte, the text of the if and switch
## conditions enclosing it, outermost first, joined with &&.
function G = guards (X, B)

  G = repmat ({''}, numel (B), 1);
  [s, e, t] = guardClauses (X);
  if (isempty (s))
    return;
  endif
  [sb, o] = sort (B);
  i1 = lookup (sb, s - 0.5) + 1;
  i2 = lookup (sb, e - 0.5);
  [s, c] = sort (s);
  i1 = i1(c);
  i2 = i2(c);
  t = t(c);
  n = max (i2 - i1 + 1, 0);
  r = zeros (sum (n), 1);
  k = zeros (sum (n), 1);
  p = 0;
  for ii = find (n > 0)'
    r(p+1:p+n(ii)) = i1(ii):i2(ii);
    k(p+1:p+n(ii)) = ii;
    p += n(ii);
  endfor
  if (isempty (r))
    return;
  endif
  r = sortrows ([r, k]);
  k = r(:,2);
  r = r(:,1);
  edges = [0; find(diff (r) != 0); numel(r)];
  for ii = 1:numel (edges) - 1
    idx = edges(ii)+1:edges(ii+1);
    G{o(r(idx(1)))} = strjoin (t(k(idx))', ' && ');
  endfor

endfunction

## Find each branch of every if and switch in a text.  X is the context.  S and
## E are the bytes each branch runs between, and T the condition it runs on.  An
## elseif or else branch carries the negation of what came before it.  A case
## branch reads as the switch value == its label, and an otherwise branch as the
## switch value otherwise.
function [S, E, T] = guardClauses (X)

  S = E = zeros (0, 1);
  T = cell (0, 1);
  clean = @(k) cellfun (@cleanCondition, X.nameOf (k), 'UniformOutput', false);

  ki = X.at ('if');
  if (! isempty (ki))
    ic = X.at ('ic');
    [~, j] = ismember (X.Q.match(ki), X.Q.match(ic));
    ic = ic(j);
    cond = clean (ic);
    ke = X.at ('elif');
    ec = X.at ('ec');
    [~, j] = ismember (X.Q.match(ke), X.Q.match(ec));
    ec = ec(j);
    econd = clean (ec);
    kl = X.at ('els');
    is = X.Q.sbyte(ki);
    ie = X.Q.ebyte(ki);
    eo = owner2 (is, ie, X.Q.sbyte(ke));
    lo = owner2 (is, ie, X.Q.sbyte(kl));
    for ii = 1:numel (ki)
      ee = ke(eo == ii);
      ll = kl(lo == ii);
      stops = sort ([X.Q.sbyte(ee); X.Q.sbyte(ll); ie(ii)]);
      S(end+1,1) = X.Q.ebyte(ic(ii));
      E(end+1,1) = stops(1);
      T{end+1,1} = cond{ii};
      neg = ['! (', cond{ii}, ')'];
      [~, oe] = sort (X.Q.sbyte(ee));
      ee = ee(oe);
      for jj = 1:numel (ee)
        c = econd{ke == ee(jj)};
        S(end+1,1) = X.Q.ebyte(ec(ke == ee(jj)));
        E(end+1,1) = X.Q.ebyte(ee(jj));
        T{end+1,1} = [neg, ' && ', c];
        neg = [neg, ' && ! (', c, ')'];
      endfor
      if (! isempty (ll))
        S(end+1,1) = X.Q.sbyte(ll(1));
        E(end+1,1) = X.Q.ebyte(ll(1));
        T{end+1,1} = neg;
      endif
    endfor
  endif

  ks = X.at ('sw');
  if (! isempty (ks))
    sv = X.at ('sv');
    [~, j] = ismember (X.Q.match(ks), X.Q.match(sv));
    val = clean (sv(j));
    kc = X.at ('cc');
    cv = X.at ('cv');
    [~, j] = ismember (X.Q.match(kc), X.Q.match(cv));
    cval = clean (cv(j));
    ko = X.at ('oc');
    kw = owner2 (X.Q.sbyte(ks), X.Q.ebyte(ks), X.Q.sbyte(kc));
    for ii = 1:numel (kc)
      S(end+1,1) = X.Q.ebyte(cv(j(ii)));
      E(end+1,1) = X.Q.ebyte(kc(ii));
      T{end+1,1} = [val{kw(ii)}, ' == ', cval{ii}];
    endfor
    kw = owner2 (X.Q.sbyte(ks), X.Q.ebyte(ks), X.Q.sbyte(ko));
    for ii = 1:numel (ko)
      S(end+1,1) = X.Q.sbyte(ko(ii));
      E(end+1,1) = X.Q.ebyte(ko(ii));
      T{end+1,1} = [val{kw(ii)}, ' otherwise'];
    endfor
  endif

endfunction

## Tidy the text of one condition: on one line, its outer parentheses removed
## where they match each other, and put back around an || so that it can be
## joined to others with && without changing its meaning.  It is passed to
## cellfun as a handle.
function T = cleanCondition (T)

  T = strtrim (regexprep (T, '\s+', ' '));
  if (numel (T) > 1 && T(1) == '(')
    depth = cumsum ((T == '(') - (T == ')'));
    if (find (depth == 0, 1) == numel (T))
      T = strtrim (T(2:end-1));
    endif
  endif
  if (! isempty (strfind (T, '||')))
    T = ['(', T, ')'];
  endif

endfunction

## Find the innermost range holding each byte, where the ranges may be nested.
## S and E are the start and end bytes of the ranges and B the bytes asked
## about, each of which must lie in some range.  K holds the number of the
## range.
function K = owner2 (S, E, B)

  K = zeros (size (B));
  for ii = 1:numel (B)
    c = find (S <= B(ii) & B(ii) < E);
    [~, m] = max (S(c));
    K(ii) = c(m);
  endfor

endfunction

## Complete the node table.  T is the inventory, R the edge rows and EXTRA the
## functions tests define.  Whatever an edge settles on that is not yet a node
## is added as a core end point.  N is the Nodes table, sorted by node, one row
## per name.
function N = assembleNodes (T, R, EXTRA)

  N = T.N;
  for ii = 1:numel (EXTRA)
    X = EXTRA{ii};
    if (! isempty (X))
      N.node = [N.node; X.node];
      N.kind = [N.kind; X.kind];
      N.package = [N.package; X.package];
      N.file = [N.file; X.file];
      N.line = [N.line; X.line];
      N.class = [N.class; X.class];
      N.abstract = [N.abstract; X.abstract];
    endif
  endfor

  ## Core names reached, each an end point
  isCore = ! strcmp (R.certainty, 'unresolved') & ! ismember (R.to, N.node);
  core = unique (R.to(isCore));
  n = numel (core);
  N.node = [N.node; core];
  N.kind = [N.kind; repmat({'core'}, n, 1)];
  N.package = [N.package; repmat({'core'}, n, 1)];
  N.file = [N.file; repmat({''}, n, 1)];
  N.line = [N.line; NaN(n, 1)];
  N.class = [N.class; repmat({''}, n, 1)];
  N.abstract = [N.abstract; false(n, 1)];

  [~, o] = unique (N.node, 'first');
  for f = fieldnames (N)'
    N.(f{1}) = N.(f{1})(o);
  endfor

endfunction

## Sort the edge rows R into their final order, by from, to, file, line and
## kind, so that two reads of the same tree give the same table.
function E = assembleEdges (R)

  [~, ~, a] = unique (R.from);
  [~, ~, b] = unique (R.to);
  [~, ~, c] = unique (R.file);
  [~, ~, d] = unique (R.kind);
  [~, o] = sortrows ([a(:), b(:), c(:), R.line, d(:)]);
  E = R;
  for f = fieldnames (R)'
    E.(f{1}) = R.(f{1})(o);
  endfor

endfunction

## Join any number of form tables into one, column by column.
function F = joinForms (varargin)
  F = devtools.callGraph.Tables.forms;
  for f = fieldnames (F)'
    c = cellfun (@(s) s.(f{1}), varargin, 'UniformOutput', false);
    F.(f{1}) = vertcat (c{:});
  endfor
endfunction

## Split a Texinfo header at its first brace group.  T is the text, G the text
## inside the leading braces and REST what follows them.  G is empty and REST
## unchanged where T does not start with a balanced brace group.
function [G, REST] = braceGroup (T)

  G = '';
  REST = T;
  T = strtrim (T);
  if (isempty (T) || T(1) != '{')
    return;
  endif
  depth = cumsum ((T == '{') - (T == '}'));
  e = find (depth == 0, 1);
  if (isempty (e))
    return;
  endif
  G = strtrim (T(2:e-1));
  REST = T(e+1:end);

endfunction

## Remove Texinfo markup from a header or a table cell: @dots{} becomes three
## dots, @var and its relatives leave their text, and escaped braces and at
## signs are unescaped.
function T = plain (T)

  T = regexprep (T, '@dots\{\}', '...');
  T = regexprep (T, '@(?:var|code|qcode|samp|asis)\{([^{}]*)\}', '$1');
  T = strrep (strrep (strrep (T, '@{', '{'), '@}', '}'), '@@', '@');

endfunction

## Split a comma separated list into a cell array, leaving alone the commas
## inside brackets or quotes.  T is the text and C the trimmed items, empty for
## an empty text.
function C = splitList (T)

  C = {};
  T = strtrim (T);
  if (isempty (T))
    return;
  endif
  depth = cumsum ((T == '(' | T == '[' | T == '{') ...
                  - (T == ')' | T == ']' | T == '}'));
  q = T == '"' | T == '''';
  inq = logical (mod (cumsum (q), 2));
  cut = find (T == ',' & depth == 0 & ! inq);
  s = [1, cut + 1];
  e = [cut - 1, numel(T)];
  C = arrayfun (@(a, b) strtrim (T(a:b)), s, e, 'UniformOutput', false);

endfunction

## Remove a Name, Value pair from the end of a list of inputs.  INS is the list,
## a trailing ... being allowed after the pair.  NV is true where a pair was
## removed.
function [INS, NV] = stripPairs (INS)

  ## Name, Value at the end of the inputs, a trailing ... after it included
  NV = false;
  m = numel (INS);
  if (m > 0 && strcmp (INS{m}, '...'))
    m -= 1;
  endif
  if (m >= 2
      && ! isempty (regexpi (INS{m-1}, '^(\w*name|param\w*|prop\w*|option)\d*$',
                             'once'))
      && ! isempty (regexpi (INS{m}, '^(\w*value|\w*val)\d*$', 'once')))
    NV = true;
    INS = INS(1:m-2);
  endif

endfunction

## Build the forms each header of a docstring gives by its positional inputs.  H
## holds the headers, KEY is the node, TEXT the name forms are written with and
## FILE the file.  A header with outputs gives a form for each output count from
## one up to its own, and one without gives a single form with none.  @dots{}
## among the inputs stands for the lines above it, and among the outputs for the
## longest list so far.  A form left open has a nargin of NaN.  R is a form
## table.
function R = positional (H, KEY, TEXT, FILE)

  bases = {};
  lastOuts = {};
  R = devtools.callGraph.Tables.forms;
  for ii = 1:numel (H)
    [ins, ~] = stripPairs (H(ii).ins);
    o = H(ii).outs;
    if (any (strcmp (o, '...')))
      o = lastOuts;
    endif
    if (numel (o) >= numel (lastOuts))
      lastOuts = o;
    endif
    sigs = signatures (ins, bases);
    for jj = 1:numel (sigs)
      s = sigs{jj};
      if (isempty (bases) || ! any (cellfun (@(b) isequal (b, s), bases)))
        bases{end+1} = s;
      endif
      counts = 0;
      if (! isempty (o))
        counts = 1:numel (o);
      endif
      for n = counts
        nin = numel (s);
        if (any (strcmp (s, '...')))
          nin = NaN;                  # an open form has no one count
        endif
        R = addForm (R, formText (o(1:n), TEXT, s, '', ''), KEY, nin, n, ...
                     '', '', FILE, H(ii).line);
      endfor
    endfor
  endfor

endfunction

## Work out what the inputs of one header line stand for, given the lines above
## it.  INS is the list of inputs and BASES the signatures so far.  Alone, ...
## stands for each of them.  First, it stands for each of them followed by what
## comes after it.  Last, after a prefix no line above starts with, it stands
## for that prefix on each of them.  Anywhere else it stays, as an open form.  S
## is a cell array of input lists.
function S = signatures (INS, BASES)

  dots = strcmp (INS, '...');
  if (! any (dots))
    S = {INS};
  elseif (isscalar (INS))
    S = BASES;
    if (isempty (S))
      S = {{}};
    endif
  elseif (dots(1))
    tail = INS(2:end);
    S = {};
    for ii = 1:numel (BASES)
      S{end+1} = [BASES{ii}, tail];
    endfor
    if (isempty (S))
      S = {tail};
    endif
  elseif (dots(end) && sum (dots) == 1)
    head = INS(1:end-1);
    open = false;
    for ii = 1:numel (BASES)
      b = BASES{ii};
      open |= numel (b) >= numel (head) && isequal (b(1:numel (head)), head);
    endfor
    S = {INS};
    if (! open && ! isempty (BASES))
      S = {};
      for ii = 1:numel (BASES)
        S{end+1} = [head, BASES{ii}];
      endfor
    endif
  else
    S = {INS};
  endif

endfunction

## Write a form in its canonical text, which is its key, such as [b, r] = fitnlm
## (x, y, "Weights").  OUTS, NAME and INS are its parts, and OPTION and VALUE
## are empty for a positional form.
function T = formText (OUTS, NAME, INS, OPTION, VALUE)

  args = strjoin (INS, ', ');
  if (! isempty (OPTION))
    tail = ['"', OPTION, '"'];
    if (! isempty (VALUE))
      tail = [tail, ', "', VALUE, '"'];
    endif
    if (isempty (args))
      args = tail;
    else
      args = [args, ', ', tail];
    endif
  endif
  T = [NAME, ' (', args, ')'];
  if (isscalar (OUTS))
    T = [OUTS{1}, ' = ', T];
  elseif (numel (OUTS) > 1)
    T = ['[', strjoin(OUTS, ', '), '] = ', T];
  endif

endfunction

## Append one form to the form table R.  The other inputs are the columns of the
## new row.
function R = addForm (R, FORM, KEY, NIN, NOUT, OPTION, VALUE, FILE, LINE)

  R.form{end+1,1} = FORM;
  R.node{end+1,1} = KEY;
  R.nargin(end+1,1) = NIN;
  R.nargout(end+1,1) = NOUT;
  R.option{end+1,1} = OPTION;
  R.value{end+1,1} = VALUE;
  R.file{end+1,1} = FILE;
  R.line(end+1,1) = LINE;

endfunction

## Build the forms a docstring gives by its options: one for each option, or one
## for each listed value of it.  H holds the headers, KEY is the node, TEXT the
## name forms are written with, FILE the file, BODY the lines of the docstring
## and ROWS their line numbers.  Each form uses the inputs of the first header
## holding a Name, Value pair, or the first signature where those are empty or
## open, and the longest outputs.  R is a form table, empty where no header
## holds a pair.
function R = options (H, KEY, TEXT, FILE, BODY, ROWS)

  R = devtools.callGraph.Tables.forms;
  k = 0;
  for ii = 1:numel (H)
    [~, nv] = stripPairs (H(ii).ins);
    if (nv)
      k = ii;
      break;
    endif
  endfor
  if (k == 0)
    return;
  endif

  ## The first signature the pair can follow, and the longest outputs
  bases = {};
  outs = {};
  for ii = 1:numel (H)
    [ins, ~] = stripPairs (H(ii).ins);
    o = H(ii).outs;
    if (! any (strcmp (o, '...')) && numel (o) >= numel (outs))
      outs = o;
    endif
    s = signatures (ins, bases);
    bases = [bases, s];
  endfor
  base = H(k).ins;
  [base, ~] = stripPairs (base);
  if (isempty (base) || strcmp (base{1}, '...'))
    base = bases{1};
  endif

  T = optionRows (BODY, ROWS);
  for ii = 1:numel (T)
    vals = T(ii).values;
    if (isempty (vals))
      vals = {''};
    endif
    for jj = 1:numel (vals)
      text = formText (outs, TEXT, base, T(ii).name, vals{jj});
      R = addForm (R, text, KEY, numel (base) + 2, numel (outs), T(ii).name, ...
                   vals{jj}, FILE, T(ii).line);
    endfor
  endfor

endfunction

## Read the options listed in the tables of a docstring.  BODY holds the lines
## and ROWS their line numbers.  Only a table whose first heading is name,
## option, parameter or property lists options.  O has one element per option,
## with name, values and line.  An option's values are the quoted names in
## sentences of its description saying what it must be.  A table of values right
## after an option table replaces them for its last option.
function O = optionRows (BODY, ROWS)

  O = struct ('name', {}, 'values', {}, 'line', {});
  text = regexprep (BODY(:)', '^\s*##\s?', '');
  table = find (! cellfun (@isempty, regexp (text, '^@multitable', 'once')));
  stop = find (! cellfun (@isempty, regexp (text, '^@end multitable', 'once')));
  lastOption = 0;
  lastEnd = 0;
  for ii = 1:numel (table)
    e = stop(find (stop > table(ii), 1));
    if (isempty (e))
      break;
    endif
    t = strjoin (text(table(ii)+1:e-1), ' ');
    h = regexp (t, '@headitem\s+(.*?)(?=@item|$)', 'tokens', 'once');
    first = '';
    if (! isempty (h))
      c = strsplit (h{1}, '@tab');
      first = strtrim (plain (c{1}));
    endif
    rows = strsplit (regexprep (t, '^.*?(?=@item)', ''), '@item');
    rows(1) = [];
    pat = '^(name|option|parameter|property)$';
    if (! isempty (regexpi (first, pat, 'once')))
      lines = text(table(ii)+1:e-1);
      at = table(ii) + find (! cellfun (@isempty, regexp (lines, '^@item', ...
                                                          'once')));
      for jj = 1:numel (rows)
        c = strsplit (rows{jj}, '@tab');
        names = quotedNames (c{1});
        desc = strjoin (c(2:end), ' ');
        for kk = 1:numel (names)
          line = 0;
          if (jj <= numel (at))
            line = ROWS(at(jj));
          endif
          vals = {};
          says = ['\<(must be|either|one of|can be|may be|options are', ...
                  '|values? (are|is))\>'];
          for sen = strsplit (desc, '. ')
            if (! isempty (regexpi (sen{1}, says, 'once')))
              vals = [vals, quotedNames(sen{1})];
            endif
          endfor
          O(end+1) = struct ('name', names{kk}, ...
                             'values', {unique(vals)}, ...
                             'line', line);
        endfor
      endfor
      lastOption = numel (O);
      lastEnd = e;
    elseif (lastOption > 0 && ! isempty (rows)
            && all (cellfun (@isempty, strtrim (text(lastEnd+1:table(ii)-1)))))
      ## A value table right after an option belongs to the last of them
      v = {};
      for jj = 1:numel (rows)
        c = strsplit (rows{jj}, '@tab');
        v = [v, quotedNames(c{1})];
      endfor
      O(lastOption).values = v;
      lastEnd = e;
    endif
  endfor

endfunction

## Find the quoted names at the start of a table cell or in its @code groups.  T
## is the text and C a cell array of names.
function C = quotedNames (T)

  m = regexp (T, '@q?code\{[''"]([^''"{}]+)[''"]\}', 'tokens');
  if (isempty (m))
    m = regexp (T, '^\s*[''"]([^''"{}]+)[''"]', 'tokens');
  endif
  C = cellfun (@(x) x{1}, m, 'UniformOutput', false);

endfunction

## Give each class of the package its forms.  F is the form table, N and E the
## nodes and edges and PACKAGE the package.  A concrete class gets its own forms
## and those of every method it inherits, the nearest definition hiding what its
## ancestors define.  An abstract class gets none.
function F = classForms (F, N, E, PACKAGE)

  isClass = strcmp (N.kind, 'class') & strcmp (N.package, PACKAGE);
  classes = N.node(isClass);
  abstract = classes(N.abstract(isClass));
  k = strcmp (E.kind, 'inherit');
  child = E.from(k);
  parent = E.to(k);

  drop = false (size (F.form));
  for ii = 1:numel (abstract)
    c = abstract{ii};
    drop |= strncmp (F.node, [c, '.'], numel (c) + 1) | strcmp (F.node, c);
  endfor

  add = {};
  for ii = 1:numel (classes)
    c = classes{ii};
    if (any (strcmp (abstract, c)))
      continue;
    endif
    seen = {};
    have = N.node(strcmp (N.class, c));
    have = cellfun (@(s) s(numel (c)+2:end), have, 'UniformOutput', false);
    queue = parent(strcmp (child, c))';
    while (! isempty (queue))
      p = queue{1};
      queue(1) = [];
      if (any (strcmp (seen, p)))
        continue;
      endif
      seen{end+1} = p;
      queue = [queue, parent(strcmp (child, p))'];
      n = numel (p) + 1;
      m = find (strncmp (F.node, [p, '.'], n));

      ## The nearest definition wins: what a class on the way defines hides
      ## what its ancestors define
      gone = false (size (m));
      if (! isempty (m))
        member = cellfun (@(s) s(n+1:end), F.node(m), 'UniformOutput', false);
        gone = ismember (member, have);
      endif
      more = N.node(strcmp (N.class, p));
      more = cellfun (@(s) s(numel (p)+2:end), more, 'UniformOutput', false);
      have = [have; more];
      m = m(! gone);
      if (isempty (m))
        continue;
      endif
      A = devtools.callGraph.Tables.forms;
      for f = fieldnames (A)'
        A.(f{1}) = F.(f{1})(m);
      endfor
      A.form = strrep (A.form, [p, '.'], [c, '.']);
      add{end+1} = A;
    endwhile
  endfor

  for f = fieldnames (F)'
    F.(f{1})(drop) = [];
  endfor
  if (! isempty (add))
    F = joinForms (F, add{:});
  endif

endfunction

## Join the non-empty tables in PARTS into the table A, column by column.  A is
## returned as it is if none has rows.
function A = joinCols (A, PARTS)

  PARTS = PARTS(! cellfun (@isempty, PARTS));
  if (isempty (PARTS))
    return;
  endif
  for f = fieldnames (A)'
    c = cellfun (@(p) p.(f{1}), PARTS, 'UniformOutput', false);
    A.(f{1}) = vertcat (c{:});
  endfor

endfunction

## Rewrite the test blocks of one file so that they report what they do.  TEXT
## is the file and NAMES the names that have forms.  OUT holds the lines of the
## rewritten test file, in which each block opens by telling shim its number and
## each call of a documented function reports what it returned.  A demo is left
## out and %!function blocks stay as they are.  A one-line assert becomes a test
## block so that it can report, unless it expects a failure.  SITES describes
## each reporting call.  OUT is empty where the file has no tests.
function [OUT, SITES] = rewrite (TEXT, NAMES)

  OUT = {};
  SITES = devtools.callGraph.Tables.sites;
  if (isempty (strfind (TEXT, '%!')))
    return;
  endif
  L = ostrsplit (strrep (TEXT, "\r", ''), "\n");
  [code, head] = devtools.__testStream__ (L);
  hdr = find (! cellfun (@isempty, head));
  if (isempty (hdr))
    return;
  endif
  last = [hdr(2:end) - 1; numel(L)];
  kinds = head(hdr);

  ## A demo does not run
  demo = strcmp (kinds, 'demo');
  for ii = find (demo)'
    code(hdr(ii):last(ii)) = {''};
  endfor

  ## Where each line starts, in the stream the parser reads
  plainCode = code;
  text = strjoin (code', "\n");
  starts = [0, find(text == "\n")];
  blockOf = zeros (numel (L), 1);
  blockOf(hdr) = 1:numel (hdr);
  blockOf = cummax (blockOf);

  [ins, SITES] = instrument (text, starts, blockOf, kinds, NAMES);
  text = apply (text, ins);
  code = ostrsplit (text, "\n");

  OUT = cell (0, 1);
  for ii = 1:numel (hdr)
    r = hdr(ii);
    e = last(ii);
    kind = kinds{ii};
    raw = L{r};
    open = ['%! devtools.callGraph.shim (''block'', ', sprintf("%d", ii), ');'];
    body = code(r+1:e);
    body = body(strncmp (L(r+1:e), '%!', 2));
    body = cellfun (@(s) ['%!', s(3:end)], body, 'UniformOutput', false);
    body = body(:);
    switch (kind)
      case 'demo'
        continue;
      case {'function', 'endfunction'}
        OUT = [OUT; L(r:e)(strncmp (L(r:e), '%!', 2))(:)];
      case 'shared'
        OUT = [OUT; {raw}; {open}; body];
      case {'test', 'xtest', 'testif', 'error', 'warning'}
        at = find (plainCode{r} != ' ', 1);
        if (isempty (at))
          OUT = [OUT; {raw}; {open}; body];
        else
          OUT = [OUT; {raw(1:at-1)}; {open}; {['%! ', strtrim(code{r})]}; body];
        endif
      case {'assert', 'fail'}
        if (! isempty (regexp (raw, '^%!\w+\s*<', 'once')))
          OUT = [OUT; L(r:e)(strncmp (L(r:e), '%!', 2))(:)];
        else
          OUT = [OUT; {'%!test'}; {open}; {['%! ', strtrim(code{r})]}; body];
        endif
    endswitch
  endfor

endfunction

## Work out where to write into a stream of test code, and what each call site
## is.  TEXT is the stream the parser reads, STARTS the byte each line starts
## at, BLOCKOF the block of each line, KINDS the type of each block and NAMES
## the names that have forms.  INS holds the insertions, with at, order and
## text.  A whole statement reports after itself and a call inside an expression
## is wrapped.  A variable sharing a function's name is no call, and %!error,
## %!function and demo blocks report nothing.  A call is passed over where it is
## an assignment inside an expression, or where its several outputs have no
## plain name to read.  SITES describes each call that reports.
function [INS, SITES] = instrument (TEXT, STARTS, BLOCKOF, KINDS, NAMES)

  SITES = devtools.callGraph.Tables.sites;
  INS = struct ('at', {}, 'order', {}, 'text', {});
  query = strjoin ({ ...
    ['(assignment left: (_) @lhs right: (index_expression value:', ...
     ' [(identifier) (field_expression)] @rc)) @stmt'], ...
    ['(expression_statement (index_expression value:', ...
     ' [(identifier) (field_expression)] @rc)) @stmt0'], ...
    '(index_expression value: [(identifier) (field_expression)] @c) @call', ...
    ['(index_expression value: [(identifier) (field_expression)] @ac', ...
     ' (_) @aa)'], ...
    '(assignment left: (_) @w)', ...
    '(assignment left: (multi_assignment_target (_) @w))', ...
    '(multi_assignment_target (_) @el)', ...
    '(index_expression value: (_) (assignment) @inner)', ...
    '(parenthesized_expression (assignment) @inner)'}, ' ');
  Q = devtools.__parseQuery__ (TEXT, query);
  cap = Q.capture;
  get = @(tag) find (strcmp (cap, tag));
  txt = @(k) TEXT(Q.sbyte(k)+1:Q.ebyte(k));

  kc = get ('c');
  kcall = get ('call');
  [~, j] = ismember (Q.match(kc), Q.match(kcall));
  kcall = kcall(j);
  callee = arrayfun (txt, kc, 'UniformOutput', false);
  callee = regexprep (callee, '\s+', '');
  tail = regexprep (callee, '^.*\.', '');
  keep = find (ismember (callee, NAMES) | ismember (tail, NAMES));
  if (isempty (keep))
    return;
  endif

  ## A variable that shares a name is no call, in its block or from %!shared
  w = get ('w');
  w = w(! ismember (Q.type(w), {'multi_assignment_target', 'ignored_output', ...
                                'line_continuation', 'comment'}));
  wNames = regexprep (arrayfun (txt, w, 'UniformOutput', false), ...
                      '^\s*([A-Za-z_]\w*).*$', '$1', 'once');
  wBlock = BLOCKOF(lookup (STARTS, Q.sbyte(w), 'l'));
  wShared = strcmp (KINDS(max (wBlock, 1)), 'shared');

  ac = get ('ac');
  aa = get ('aa');
  [~, j] = ismember (Q.match(aa), Q.match(ac));
  keepArg = ! ismember (Q.type(aa), {'line_continuation', 'comment'});
  aa = aa(keepArg);
  argc = Q.sbyte(ac(j(keepArg)));

  stmt = get ('stmt');
  rc = get ('rc');
  lhs = get ('lhs');
  stmt0 = get ('stmt0');
  el = get ('el');
  el = el(! ismember (Q.type(el), {'line_continuation', 'comment'}));
  inner = get ('inner');

  objectTypes = {'identifier', 'cell_index_expression', 'field_expression'};
  id = 0;
  for ii = keep(:)'
    name = callee{ii};
    root = regexprep (name, '\..*$', '');
    k = kc(ii);
    line = lookup (STARTS, Q.sbyte(k), 'l');
    b = BLOCKOF(line);
    skip = {'error', 'function', 'endfunction', 'demo'};
    if (b == 0 || any (strcmp (KINDS{b}, skip)))
      continue;
    endif
    written = wNames(wBlock == b | wShared);
    if (any (strcmp (written, name)))
      continue;
    endif

    ## Its arguments
    these = aa(argc == Q.sbyte(k));
    [~, o] = sort (Q.sbyte(these));
    these = these(o);
    nin = numel (these);
    strs = {};
    for jj = 1:nin
      if (strcmp (Q.type{these(jj)}, 'string'))
        t = txt (these(jj));
        strs{end+1} = t(2:end-1);
      else
        strs{end+1} = '';
      endif
    endfor

    ## The class of the object it dispatches on, where a variable holds it
    cls = '''''';
    object = '';
    dotted = any (name == '.');
    if (dotted && any (strcmp (written, root)))
      cls = ['class(', root, ')'];
      object = root;
      name = tail{ii};
      nin += 1;
      strs = [{''}, strs];
    elseif (nin > 0 && any (strcmp (Q.type{these(1)}, objectTypes)))
      v = txt (these(1));
      own = regexprep (v, '^\s*(\w+).*$', '$1', 'once');
      if (any (strcmp (written, own)) && isempty (strfind (v, '{:}')))
        cls = ['class(', v, ')'];
        object = own;
      endif
    endif

    id += 1;
    s = Q.sbyte(kcall(ii));
    e = Q.ebyte(kcall(ii));
    SITES(end+1) = struct ('id', id, 'name', name, ...
                           'call', regexprep (TEXT(s+1:e), '\s+', ' '), ...
                           'nin', nin, 'strings', {strs}, 'line', line);

    ## A whole statement reports after itself, a call in an expression around
    ## itself
    m = find (Q.sbyte(rc) == Q.sbyte(k), 1);
    if (! isempty (m) && any (Q.match(stmt) == Q.match(rc(m))))
      st = stmt(Q.match(stmt) == Q.match(rc(m)));
      lh = lhs(Q.match(lhs) == Q.match(rc(m)));
      ## An assignment inside an expression takes no statement after it
      if (any (Q.sbyte(inner) == Q.sbyte(st)))
        SITES(end) = [];
        id -= 1;
        continue;
      endif
      [nout, pos, vars] = targets (TEXT, Q, lh, el);
      if (Q.ebyte(st) == e && ! isempty (vars)
          && (isempty (object) || ! any (strcmp (vars, object))))
        count = sprintf ("%d", nout);
        if (numel (pos) != nout)
          count = ['[', sprintf("%d ", [nout, pos]), ']'];
        endif
        tailText = sprintf ("; devtools.callGraph.shim(%d,%s,%s", id, ...
                            count, cls);
        tailText = [tailText, sprintf(",%s", vars{:}), ')'];
        INS(end+1) = struct ('at', e, 'order', 2, 'text', tailText);
        continue;
      endif
      if (nout > 1)                   # no plain place to look at its outputs
        SITES(end) = [];
        id -= 1;
        continue;
      endif
    endif
    if (any (Q.ebyte(stmt0) == e & Q.sbyte(stmt0) == s))
      tailText = sprintf ("; devtools.callGraph.shim(%d,0,%s)", id, cls);
      INS(end+1) = struct ('at', e, 'order', 2, 'text', tailText);
      continue;
    endif
    INS(end+1) = struct ('at', s, 'order', 1, 'text', ...
                         sprintf ("devtools.callGraph.shim(%d,1,%s,", id, cls));
    INS(end+1) = struct ('at', e, 'order', 0, 'text', ')');
  endfor

endfunction

## Read the left side of an assignment to see what it takes.  TEXT is the
## source, Q the parse, LH the left side and EL the elements of a list of
## targets.  NOUT is how many outputs are taken, POS the positions of those held
## by plain names, and VARS those names.  Only a plain name can be looked at
## after the statement, so an indexed target only counts towards NOUT.
function [NOUT, POS, VARS] = targets (TEXT, Q, LH, EL)

  k = LH;
  if (strcmp (Q.type{LH}, 'multi_assignment_target'))
    k = EL(Q.sbyte(EL) >= Q.sbyte(LH) & Q.ebyte(EL) <= Q.ebyte(LH));
    [~, o] = sort (Q.sbyte(k));
    k = k(o);
  endif
  NOUT = numel (k);
  plain = strcmp (Q.type(k), 'identifier');
  POS = find (plain)';
  POS = POS(:)';
  VARS = arrayfun (@(j) TEXT(Q.sbyte(j)+1:Q.ebyte(j)), k(plain), ...
                   'UniformOutput', false);
  VARS = VARS(:)';

endfunction

## Write a list of insertions into a text.  T is the text and INS holds at, the
## byte, order, which goes first at one byte, and text.  The result is the text
## with each insertion in place.
function T = apply (T, INS)

  if (isempty (INS))
    return;
  endif
  [~, o] = sortrows ([[INS.at]', [INS.order]']);
  INS = INS(o);
  parts = cell (1, 2 * numel (INS) + 1);
  p = 0;
  for ii = 1:numel (INS)
    a = INS(ii).at;
    parts{2*ii-1} = T(p+1:a);
    parts{2*ii} = INS(ii).text;
    p = a;
  endfor
  parts{end} = T(p+1:end);
  T = [parts{:}];

endfunction

## Turn the profiles of one test file into edges between node numbers.  PROFILES
## holds one profile per block, BLOCKS their numbers, FILE the file, and M and N
## the name table and the nodes.  FROM, TO, BLOCK and CALLS are the edges, a
## FROM of 0 meaning the test block itself.  Only direct callers count, since a
## flat profile cannot tell who called through a core function and a call not
## seen proves nothing.  An anonymous function stands for the node of its file
## that has the edge.  Each distinct name and each distinct pair of names is
## worked out once.
function [FROM, TO, BLOCK, CALLS] = profileEdges (PROFILES, BLOCKS, FILE, M, N)

  main = find (strcmp (N.file, FILE)
               & ismember (N.kind, {'function', 'class'}), 1);
  if (isempty (main))
    [~, testBase] = fileparts (FILE);     # a test file names what it tests
    main = find (strcmp (N.node, testBase), 1);
  endif
  if (isempty (main))
    main = 0;
  endif
  count = cellfun (@(p) numel (p.name), PROFILES(:));
  shift = [0; cumsum(count)];
  names = cell (shift(end), 1);
  calls = zeros (shift(end), 1);
  owner = repelem (BLOCKS(:), count)(:);
  child = cell (numel (PROFILES), 1);
  parent = cell (numel (PROFILES), 1);
  for ii = 1:numel (PROFILES)
    P = PROFILES{ii};
    r = shift(ii)+1:shift(ii+1);
    names(r) = P.name(:);
    calls(r) = P.calls(:);
    links = cellfun (@numel, P.parents(:));
    c = repelem (r(:), links)(:);
    q = cellfun (@(x) x(:), P.parents(:), 'UniformOutput', false);
    q = vertcat (q{:}, zeros (0, 1)) + shift(ii);
    root = r(links == 0)(:);
    child{ii} = [c; root];
    parent{ii} = [q; zeros(numel (root), 1)];
  endfor
  child = vertcat (child{:});
  parent = vertcat (parent{:});

  ## Each name once
  [u, ~, id] = unique (names);
  ids = cell (numel (u), 1);
  for ii = 1:numel (u)
    NAME = u{ii};
    K = [];
    if (NAME(1) == '@')
      t = regexp (NAME, '^@(.*?)(?:/(.*))?$', 'tokens', 'once');
      if (isscalar (t) || isempty (t{2}))
        K = lookup (M.names, t{1}, 'm');
        K = K(K > 0);
        if (isempty (K))
          K = M.looseId(strcmp (M.looseName, t{1}))(:)';
        endif
      else
        K = lookup (M.names, [t{1}, '.', t{2}], 'm');
        K = K(K > 0);
      endif
    elseif (! strncmp (NAME, 'anonymous@', 10))
      K = lookup (M.names, NAME, 'm');
      K = K(K > 0);
      if (! (any (NAME == '>') && ! isempty (K)))
        base = regexprep (NAME, '^.*>', '');
        K = [K, M.looseId(strcmp (M.looseName, base))(:)'];
      endif
    endif
    ids{ii} = K;
  endfor

  ## Each pair of names once
  cn = id(child);
  pn = zeros (size (parent));
  pn(parent > 0) = id(parent(parent > 0));
  [pairs, ~, g] = unique ([pn, cn], 'rows');
  a = zeros (rows (pairs), 1);
  b = zeros (rows (pairs), 1);
  for ii = 1:rows (pairs)
    [a(ii), b(ii)] = resolvePair (pairs(ii,1), pairs(ii,2), u, ids, main, M, N);
  endfor

  hit = find (b(g) > 0);
  FROM = a(g(hit))(:);
  TO = b(g(hit))(:);
  BLOCK = owner(child(hit))(:);
  CALLS = calls(child(hit))(:);
  [~, first] = unique ([FROM, TO, BLOCK], 'rows', 'first');
  first = sort (first);
  FROM = FROM(first);
  TO = TO(first);
  BLOCK = BLOCK(first);
  CALLS = CALLS(first);

endfunction

## Work out which edge a caller's profile name and a callee's stand for.  P and
## C are positions in NAMES, P being 0 for the test block itself, IDS holds the
## nodes each name may be, MAIN is the main node of the file, and M and N are
## the name table and the nodes.  A and B are the two nodes, B being 0 where
## there is no edge.  A call from the test block is charged to MAIN, if the
## callee is ours.  An anonymous caller stands for the nodes of its file.  An
## edge the static graph already has is preferred, then for a named caller a
## pair in one file, then the first of each.
function [A, B] = resolvePair (P, C, NAMES, IDS, MAIN, M, N)

  A = 0;
  B = 0;
  t = IDS{C};
  if (isempty (t))
    return;
  endif
  ours = any (M.ours(t));
  if (P == 0)
    if (ours)
      A = MAIN;
      B = t(1);
    endif
    return;
  endif
  f = IDS{P};
  anon = false;
  if (isempty (f))
    if (! strncmp (NAMES{P}, 'anonymous@', 10))
      return;
    endif
    anon = true;
    file = regexp (NAMES{P}, '([^/\\]+):\d+:\d+$', 'tokens', 'once');
    if (! isempty (file))
      f = find (strcmp (M.base, file{1}) & M.ours)';
    endif
    if (isempty (f))
      if (ours)
        A = MAIN;
        B = t(1);
      endif
      return;
    endif
  endif
  f = f(M.ours(f));
  if (! isempty (f))
    A = 0;
    B = 0;
    [i, j] = find (M.edge(f,t), 1);
    if (! isempty (i))
      A = f(i);
      B = t(j);
    elseif (! anon)
      A = f(1);
      B = t(1);
      if (! (isscalar (f) && isscalar (t)))
        for ii = 1:numel (f)
          same = find (strcmp (N.file(t), N.file{f(ii)}), 1);
          if (! isempty (same))
            A = f(ii);
            B = t(same);
            break;
          endif
        endfor
      endif
    endif
  endif

endfunction

## Find the documented form a call in a BIST is.  S is the call site, NOUT its
## output count, OWNER the class of the object it was called on, F and I the
## forms and the index, and BASE the name of the test's file.  A method is
## sought on the class of the object.  Where no class could be read, because the
## object is built in the call itself, it is sought on the class the test's file
## is named after, unless core defines the name, in which case it is most likely
## core's.  An option the call names then decides first, and where the docstring
## lists that option's values the value decides.  Otherwise its inputs and
## outputs do.  T is the text of the form, empty where none matches, and '?'
## where the call names such an option and its value is not written in the call,
## which leaves the form undecided.
function T = matchForm (S, NOUT, OWNER, F, I, BASE)

  T = '';
  k = find (strcmp (I.formTail, S.name) & strcmp (I.formClass, OWNER));
  if (isempty (k) || isempty (OWNER))
    k = find (strcmp (I.formName, S.name));
  endif
  if (isempty (k) && isempty (OWNER) && ! any (strcmp (I.core, S.name)))
    ## An object built in the call itself has no class to read
    named = find (strcmp (I.formTail, S.name) & ! strcmp (I.formClass, ''));
    k = named(strcmp (regexprep (I.formClass(named), '^.*\.', ''), BASE));
  endif
  if (isempty (k))
    return;
  endif
  low = lower (F.option(k));
  for ii = 1:numel (S.strings)
    if (isempty (S.strings{ii}))
      continue;
    endif
    hit = k(strcmp (low, lower (S.strings{ii})));
    if (isempty (hit))
      continue;
    endif
    ## Where the docstring lists an option's values, the value decides
    if (any (! strcmp (F.value(hit), '')))
      v = '';
      if (ii < numel (S.strings))
        v = S.strings{ii+1};
        if (isempty (v))
          T = '?';                    # the value is not written in the call
          return;
        endif
      endif
      hit = hit(strcmp (lower (F.value(hit)), lower (v)));
    endif
    if (! isempty (hit))
      T = F.form{hit(1)};
    endif
    return;
  endfor
  plain = k(strcmp (F.option(k), '') & F.nargout(k) == NOUT);
  hit = plain(F.nargin(plain) == S.nin);
  if (isempty (hit))
    hit = plain(isnan (F.nargin(plain)));   # an open form takes any count
  endif
  if (! isempty (hit))
    T = F.form{hit(1)};
  endif

endfunction

## Answer one query.  G is the graph and Q the parsed arguments.  It walks
## forward from the 'From' set and backward from the 'To' set, each form or
## class on its own, keeping the output counts along the way and walking again
## over certain edges alone to tell certain results from possible ones.  It then
## keeps the edges between the two ends, applies what was selected and builds
## the rows paths documents.  R is that result and KEEP marks the rows of the
## edge table it holds.
function [R, KEEP] = answer (G, Q)

  N = G.Nodes;
  E = G.Edges;
  F = G.Forms;
  I = G.Index;
  V = Q.view;
  chosen = keptEdges (V, N, E, G.Package);
  base = chosen & ! strcmp (E.kind, 'inherit');
  certain = strcmp (E.certainty, 'certain');
  if (! strcmp (V.certainty, 'certain'))
    certain |= I.seen;
  endif
  allowed = true (size (base));
  if (! strcmp (V.certainty, 'all'))
    allowed = certain | I.toId == 0;
  endif
  n = numel (N.node);
  K = I.columns;
  hasFrom = ! isempty (Q.from);
  hasTo = ! isempty (Q.to);

  ## Forward, each context on its own
  fwdAll = false (n, K);
  fwdSure = false (n, K);
  edgeAll = false (size (base));
  edgeSure = false (size (base));
  seeds = false (n, 1);
  selected = struct ('forms', false (numel (F.form), 1), 'named', {{}});
  if (hasFrom)
    selected = selection (Q.from, N, F, I);
    for ii = 1:numel (selected.contexts)
      C = selected.contexts(ii);
      [m, c] = contextMasks (C, base, certain, E, I);
      m &= allowed | c;
      seeds(C.seeds) = true;
      S = false (n, K);
      col = min (C.nout, K - 2) + 1;
      col(isnan (C.nout)) = K;
      S(C.seeds,col) = true;
      [a, ea] = forward (S, m, I, Q.depth);
      [b, eb] = forward (S, m & c, I, Q.depth);
      fwdAll |= a;
      fwdSure |= b;
      edgeAll |= ea;
      edgeSure |= eb;
    endfor
  endif

  ## Backward from the targets
  targets = false (n, 1);
  liveTo = base;
  sureTo = base & certain;
  backAll = false (n, K);
  backSure = false (n, K);
  into = false (size (base));
  intoSure = false (size (base));
  if (hasTo)
    T = selection (Q.to, N, F, I);
    for ii = 1:numel (T.contexts)
      C = T.contexts(ii);
      targets(C.seeds) = true;
      if (! isnan (C.nout))
        col = min (C.nout, K - 2) + 1;
        backAll(C.seeds,col) = true;
        backSure(C.seeds,col) = true;
      elseif (! isempty (Q.nargout))
        col = min (Q.nargout, K - 2) + 1;
        backAll(C.seeds,col) = true;
        backSure(C.seeds,col) = true;
        backAll(C.seeds,K) = true;
      else
        backAll(C.seeds,:) = true;
        backSure(C.seeds,:) = true;
      endif
    endfor
    aliases = false (size (targets));
    meth = find (targets & strcmp (N.kind, 'method'));
    if (! isempty (meth))
      onName = ! strcmp (N.kind, 'method') ...
               & ismember (N.node, unique (I.member(meth)));
      aliases(onName & ! targets) = true;
    endif
    k = I.toId > 0;
    onAlias = false (size (k));
    onAlias(k) = aliases(I.toId(k));
    liveTo &= ! onAlias | strcmp (E.certainty, 'candidates');
    sureTo &= ! onAlias;
    liveTo &= allowed;
    backAll(aliases,:) = true;
    [backAll, into] = backward (backAll, liveTo, I, Q.depth);
    [backSure, intoSure] = backward (backSure, sureTo, I, Q.depth);
  endif

  ## What can reach an unresolved call, at each count
  loose = base & I.toId == 0;
  open = false (n, K);
  open(I.fromId(loose),:) = true;
  open = backward (open, base & allowed, I);

  ## The part of the graph between the two ends
  if (hasFrom && hasTo)
    keep = edgeAll & into;
    solid = edgeSure & intoSure;
  elseif (hasFrom)
    keep = edgeAll;
    solid = edgeSure;
  else
    keep = into;
    solid = intoSure;
  endif
  undone = false (size (keep));
  if (! hasFrom || ! hasTo)
    if (hasFrom)
      undone = edgeAll & I.toId == 0;
    elseif (isinf (Q.depth))
      undone = loose & any (open(I.fromId,:), 2);
    endif
    keep |= undone;
  endif
  if (hasFrom)
    family = strcmp (E.kind, 'inherit');
    reached = any (fwdAll, 2);
    k = family & I.toId > 0;
    k(k) = reached(I.toId(k)) & reached(I.fromId(k));
    keep |= k;
    solid |= k;
  endif

  ## What is left out of the answer without changing what it says
  keep &= chosen;
  if (! V.core)
    isCore = false (size (keep));
    w = I.toId > 0;
    isCore(w) = strcmp (N.kind(I.toId(w)), 'core') & ! targets(I.toId(w));
    keep &= ! isCore;
  endif
  if (! V.unresolved)
    keep &= I.toId > 0;
  endif

  R = struct ();
  R.from = N.node(seeds);
  R.to = N.node(targets);
  ranRows = I.seen;
  if (! (isempty (selected.named) || ! isfield (I.calls, 'form')))
    wanted = ismember (I.calls.form, selected.named);
    big = max (I.ran.block(:)) + 1;
    here = ismember (I.seenFile * big + I.ran.block, ...
                     I.callFile(wanted) * big + I.calls.block(wanted));
    here |= isnan (I.ran.block) & ismember (I.seenFile, I.callFile(wanted));
    span = numel (I.tail) + 1;
    ranRows = ismember (I.fromId * span + I.toId, ...
                        I.seenFrom(here) * span + I.seenTo(here));
  endif
  edgeStatus = repmat ({'possible'}, numel (E.from), 1);
  edgeStatus(solid) = {'certain'};
  edgeStatus(undone) = {'incomplete'};
  certainty = E.certainty;
  certainty(solid & strcmp (certainty, 'candidates') & ! I.seen) = {'certain'};
  edgeTable = struct ('from', {E.from(keep)}, 'to', {E.to(keep)}, ...
              'kind', {E.kind(keep)}, 'status', {edgeStatus(keep)}, ...
              'certainty', {certainty(keep)}, 'nargout', E.nargout(keep), ...
              'guard', {E.guard(keep)}, ...
              'varargin', E.varargin(keep), 'test', E.test(keep), ...
              'file', {E.file(keep)}, 'line', E.line(keep), ...
              'ran', ranRows(keep));
  R.edges = edgeTable;
  R.links = linkRows (N, R.edges, V);

  ## Nodes on the result, and their files
  on = seeds | targets;
  on(I.fromId(keep)) = true;
  w = keep & I.toId > 0;
  on(I.toId(w)) = true;
  good = true (n, 1);
  if (hasFrom)
    good &= any (fwdSure, 2);
  endif
  if (hasTo)
    good &= any (backSure, 2);
  endif
  R.files = fileRows (N, on, good, any (open, 2), hasTo);

  ## Forms, each at its own count
  cols = I.formColumn;
  at = sub2ind ([n, K], I.formNode(:), cols(:));
  isOpen = open(at)(:);
  if (hasTo)
    LIVE = base & allowed;
    reach = backAll(at)(:);
    sure = backSure(at)(:);
    [nNodes, nCols] = size (backAll);
    nodes = intersect (I.formNode(reach), I.narginNodes);
    for v = nodes(:)'
      forms = find (I.formNode == v & reach);
      out = I.outRows(I.outStart(v):I.outStart(v+1)-1);
      out = out(I.toId(out) > 0 & LIVE(out));
      outAt = sub2ind ([nNodes, nCols], I.toId(out), I.edgeColumn(out));
      outReach = backAll(outAt);
      outSure = backSure(outAt);
      [pairs, ~, g] = unique ([F.nargin(forms), F.nargout(forms)], 'rows');
      for np = 1:size (pairs, 1)
        holds = true (size (out));
        guarded = find (I.narginGuard(out));
        for jj = guarded(:)'
          holds(jj) = guardHolds (E.guard{out(jj)}, ...
                                                   pairs(np,1), pairs(np,2));
        endfor
        sameForms = forms(g == np);
        reach(sameForms) = any (outReach & holds);
        sure(sameForms) = any (outSure & holds);
      endfor
    endfor
  endif
  if (hasFrom)
    pool = selected.forms;
    status = repmat ({'certain'}, numel (F.form), 1);
    if (hasTo)
      pool &= reach | isOpen;
      status(! sure) = {'possible'};
      status(isOpen & ! reach) = {'incomplete'};
    else
      status(isOpen) = {'incomplete'};
    endif
  else
    pool = reach;
    if (isinf (Q.depth))
      pool |= isOpen;
    endif
    status = repmat ({'incomplete'}, numel (F.form), 1);
    status(reach) = {'possible'};
    status(sure) = {'certain'};
  endif
  if (! isempty (Q.returns))
    callTable = I.calls;
    hit = callTable.output >= 1;
    if (any (strcmp (Q.returns, 'object')))
      plain = {'double', 'single', 'logical', 'char', 'cell', 'struct', ...
               'function_handle', 'int8', 'int16', 'int32', 'int64', ...
               'uint8', 'uint16', 'uint32', 'uint64', ''};
      hit &= ! ismember (callTable.class, plain);
    else
      hit &= ismember (callTable.class, Q.returns);
    endif
    seen = ismember (F.form, callTable.form);
    match = ismember (F.form, callTable.form(hit));
    pool &= match | ! seen;
    status(! seen) = {'incomplete'};
  endif
  R.forms = struct ('form', {F.form(pool)}, 'node', {F.node(pool)}, ...
                    'status', {status(pool)});
  KEEP = keep;

endfunction

## Join two tables of forms or files, one row per key.  A and B are the tables,
## each with a status column, and KEYA and KEYB their keys.  Where a key is in
## both, the surer status wins, certain before possible before incomplete.
function S = surest (A, B, KEYA, KEYB)

  S = A;
  for f = fieldnames (A)'
    S.(f{1}) = [A.(f{1}); B.(f{1})];
  endfor
  [~, rank] = ismember (S.status, {'certain', 'possible', 'incomplete'});
  [~, o] = sort (rank);
  key = [KEYA; KEYB](o);
  [~, first] = unique (key, 'first');
  k = sort (o(first));
  for f = fieldnames (S)'
    S.(f{1}) = S.(f{1})(k);
  endfor

endfunction

## Read and check the Name, Value arguments of paths.  ARGS is the cell array
## and I the index.  Q holds from, to and around, the sets asked about, depth,
## nargout, returns, and view, the selection.  The combinations paths refuses
## are errors here, and the selection options are read by viewOption.
## Work out what a set of names or forms selects.  ITEMS is the set and N, F and
## I are the nodes, the forms and the index.  S.contexts holds the walks to
## make: each form and each class is one of its own, as it settles its own
## output counts or dispatch, and the plain names are one together.  S.forms
## marks the forms selected and S.named lists the forms named outright.  A name
## nothing matches is an error.
function S = selection (ITEMS, N, F, I)

  n = numel (N.node);
  plain = false (n, 1);
  ctx = struct ('seeds', {}, 'cls', {}, 'nin', {}, 'nout', {});
  forms = false (numel (F.form), 1);
  named = {};
  for ii = 1:numel (ITEMS)
    item = ITEMS{ii};
    k = find (strcmp (F.form, item));
    if (! isempty (k))
      forms(k) = true;
      named{end+1} = item;
      ctx(end+1) = struct ('seeds', I.formNode(k), 'cls', {I.formClass{k}}, ...
                           'nin', F.nargin(k), 'nout', F.nargout(k));
      continue;
    endif
    k = find (strcmp (N.node, item));
    if (isempty (k))
      m = [];
      c = '';
      dots = find (item == '.');
      for nd = numel (dots):-1:1
        head = item(1:dots(nd)-1);
        if (! any (strcmp (N.node, head)))
          continue;
        endif
        method = item(dots(nd)+1:end);
        for ancestor = lineage (head, I)
          w = find (strcmp (N.node, [ancestor{1}, '.', method]), 1);
          if (! isempty (w))
            m = w;
            c = head;
            break;
          endif
        endfor
        break;
      endfor
      if (! isempty (m))
        forms |= strcmp (I.formClass, c) & I.formNode == m;
        ctx(end+1) = struct ('seeds', m, 'cls', c, 'nin', NaN, 'nout', NaN);
        continue;
      endif
      k = find (strcmp (I.tail, item));
    endif
    if (isempty (k))
      error ("devtools.callGraph.paths: no such name in the graph: '%s'", item);
    endif
    for jj = k(:)'
      if (strcmp (N.kind{jj}, 'class'))
        c = N.node{jj};
        seeds = find (strcmp (N.node, c));
        have = cell (0, 1);
        for up = lineage (c, I)
          mk = find (strcmp (N.class, up{1}));
          tail = I.member(mk);
          fresh = ! ismember (tail, have);
          seeds = [seeds; mk(fresh)];
          have = [have; tail(fresh)];
        endfor
        ctx(end+1) = struct ('seeds', seeds, 'cls', c, 'nin', NaN, 'nout', NaN);
        forms |= strcmp (I.formClass, c);
      else
        plain(jj) = true;
      endif
    endfor
  endfor
  forms(ismember (I.formNode, find (plain))) = true;
  if (any (plain))
    ctx(end+1) = struct ('seeds', find (plain), 'cls', '', 'nin', NaN, ...
                         'nout', NaN);
  endif
  S = struct ('contexts', ctx, 'forms', forms, 'named', {named});

endfunction

## List a class and its ancestors, nearest first.  C is the class and I the
## index, whose child and parent columns hold the inheritance.
function L = lineage (C, I)

  L = {C};
  ii = 1;
  while (ii <= numel (L))
    L = [L, setdiff(I.parent(strcmp (I.child, L{ii})), L)(:)'];
    ii += 1;
  endwhile

endfunction

## List a class and every class below it, nearest first.  C is the class and I
## the index.
function D = descendants (C, I)

  D = {C};
  ii = 1;
  while (ii <= numel (D))
    D = [D, setdiff(I.child(strcmp (I.parent, D{ii})), D)(:)'];
    ii += 1;
  endwhile

endfunction

## Work out which edges one context of a query may walk.  C is the context, BASE
## and CERTAIN mark the edges the query allows and those that are certain, and E
## and I are the edges and the index.  A form leaves out the branches its nargin
## and nargout rule out.  A class settles dispatch: among the candidate rows of
## one call site within the class's own family, only the method that class
## reaches stays, and it counts as certain.  M marks the edges to walk and S the
## certain ones.
function [M, S] = contextMasks (C, BASE, CERTAIN, E, I)

  M = BASE;
  S = CERTAIN;

  ## A form runs the branches its inputs allow
  if (! isnan (C.nin))
    for k = find (ismember (I.fromId, C.seeds) & ! strcmp (E.guard, ''))'
      M(k) = M(k) && guardHolds (E.guard{k}, C.nin, C.nout);
    endfor
  endif
  if (isempty (C.cls))
    return;
  endif

  ## Dispatch on an object of the class settles: a candidate row among a
  ## method's own family keeps the method the class reaches
  line = lineage (C.cls, I);
  mark = false (numel (I.classNames) + 1, 1);
  [~, ids] = ismember (line, I.classNames);
  ids = ids(ids > 0);
  mark(ids) = true;
  wide = cell (numel (I.classNames), 1);
  for g = find (mark(I.siteClass))'
    rows = I.siteRows(I.siteStart(g):I.siteStart(g+1)-1);
    from = I.siteClass(g);
    if (isempty (wide{from}))
      name = I.classNames{from};
      wide{from} = [descendants(name, I), lineage(name, I)];
    endif
    cls = I.toClass(rows);
    if (any (cls == 0) || ! all (ismember (I.classNames(cls), wide{from})))
      continue;
    endif
    for jj = 1:numel (ids)
      hit = rows(cls == ids(jj));
      if (! isempty (hit))
        allowed = M(hit);
        M(rows) = false;
        M(hit) = allowed;
        S(hit) = true;
        break;
      endif
    endfor
  endfor

endfunction

## Walk forward through the graph.  S is a matrix of nodes by output counts
## marking where the walk starts, MASK the edges allowed, I the index and DEPTH
## the most calls to walk.  A condition on nargout decides by the count its node
## was reached at.  S returns with every node reached and at which counts, and A
## marks the edges taken.
function [S, A] = forward (S, MASK, I, DEPTH)

  [n, K] = size (S);
  A = false (size (MASK));
  g = I.guardRow;
  g = g(MASK(g));
  ok = I.guardOk(MASK(I.guardRow),:);
  step = 0;
  while (step < DEPTH)
    step += 1;
    live = any (S, 2);
    act = MASK & live(I.fromId);
    act(g) = any (S(I.fromId(g),:) & ok, 2);
    fresh = act & ! A;
    if (! any (fresh))
      break;
    endif
    A |= fresh;
    t = fresh & I.toId > 0;
    S(sub2ind ([n, K], I.toId(t), I.edgeColumn(t))) = true;
  endwhile

endfunction

## Walk backward through the graph.  T is a matrix of nodes by output counts
## marking the targets, MASK the edges allowed, I the index and DEPTH the most
## calls to walk, by default all of them.  T returns marking the counts at which
## each node reaches a target, and A marks the edges on the way.
function [T, A] = backward (T, MASK, I, DEPTH = Inf)

  [n, K] = size (T);
  A = false (size (MASK));
  isGuard = false (size (MASK));
  isGuard(I.guardRow) = true;
  gid = zeros (size (MASK));
  gid(I.guardRow) = 1:numel (I.guardRow);
  w = find (MASK & I.toId > 0);
  at = sub2ind ([n, K], I.toId(w), I.edgeColumn(w));
  step = 0;
  while (step < DEPTH)
    step += 1;
    fresh = T(at) & ! A(w);
    if (! any (fresh))
      break;
    endif
    r = w(fresh);
    A(r) = true;
    p = r(! isGuard(r));
    T(I.fromId(p),:) = true;
    q = r(isGuard(r));
    for ii = 1:numel (q)
      T(I.fromId(q(ii)),:) |= I.guardOk(gid(q(ii)),:);
    endfor
  endwhile

endfunction

## Build the links table of a result of paths.  N is the node table, E the edge
## rows of the result and V the selection.  L holds from, to, weight and status,
## the heaviest first.  It is empty unless the selection asked for a level above
## node or for a weight other than calls.
function L = linkRows (N, E, V)

  L = struct ('from', {cell(0, 1)}, 'to', {cell(0, 1)}, ...
              'weight', zeros (0, 1), 'status', {cell(0, 1)});
  if (strcmp (V.level, 'node') && strcmp (V.weight, 'calls'))
    return;
  endif
  M = linksBetween (N, E, V.level, V.core);
  [w, k] = sort (M.(V.weight), 'descend');
  L = struct ('from', {M.from(k)}, 'to', {M.to(k)}, 'weight', w, ...
              'status', {M.status(k)});

endfunction

## Build the files table of a result of paths.  N is the node table, ON marks
## the nodes on the result, GOOD those reached by certain edges, OPEN those that
## can reach an unresolved call, and HASTO says the query had a 'To' set.  R has
## one row per file with file, package and status.
function R = fileRows (N, ON, GOOD, OPEN, HASTO)

  has = ON & ! strcmp (N.file, '');
  key = strcat (N.package, '|', N.file);
  [u, ~, g] = unique (key(has));
  idx = find (has);
  file = pack = out = cell (numel (u), 1);
  for ii = 1:numel (u)
    k = idx(g == ii);
    file{ii} = N.file{k(1)};
    pack{ii} = N.package{k(1)};
    out{ii} = 'possible';
    if (any (GOOD(k)))
      out{ii} = 'certain';
    endif
    if (any (OPEN(k)) && (! HASTO || ! any (GOOD(k))))
      out{ii} = 'incomplete';
    endif
  endfor
  R = struct ('file', {file}, 'package', {pack}, 'status', {out});

endfunction

## Compare the options the code reads with those its docstrings list, for the
## gaps method.  ROOT and PACKAGE locate the package, and N, E, F and I are the
## nodes, edges, forms and index.  A label in a switch over an option's name
## that no form lists is undocumented, unless the switch is over one of the
## node's documented positional inputs, whose labels are that input's values and
## no options.  A documented option that no string names, in its file or in
## anything it forwards varargin to or constructs, is unread.  The four outputs
## are the columns of the findings.
function [FILE, LINE, RULE, TEXT] = optionGaps (ROOT, PACKAGE, N, E, F, I)

  FILE = RULE = TEXT = cell (0, 1);
  LINE = zeros (0, 1);
  [cases, strings] = optionReads (ROOT, PACKAGE, N);
  fwd = (E.varargin | strcmp (E.kind, 'constructor')) & ! E.test & I.toId > 0;
  n = numel (N.node);
  A = sparse (I.fromId(fwd), I.toId(fwd), 1, n, n) > 0;

  values = unique (lower (F.value));
  own = unique (I.formNode(! strcmp (F.option, '')));
  for ii = own(:)'
    mine = I.formNode == ii & ! strcmp (F.option, '');
    known = unique (lower (F.option(mine)));

    ## Undocumented: what the node itself switches on
    k = cases.node == ii;
    pos = I.formNode == ii & strcmp (F.option, '');
    args = regexp (F.form(pos), '\(([^()]*)\)\s*$', 'tokens', 'once');
    args = cellfun (@(a) a{1}, args, 'UniformOutput', false);
    inputs = unique (regexp (lower (strjoin (args, ',')), '\w+', 'match'));
    for w = find (k)'
      k(w) = ! any (ismember (regexp (cases.value{w}, '\w+', 'match'), inputs));
    endfor
    extra = setdiff (cases.name(k), [known; values]);
    for jj = 1:numel (extra)
      w = find (k & strcmp (cases.name, extra{jj}), 1);
      FILE{end+1,1} = N.file{ii};
      LINE(end+1,1) = cases.line(w);
      RULE{end+1,1} = 'undocumented-option';
      TEXT{end+1,1} = sprintf ("%s reads option '%s'", N.node{ii}, extra{jj});
    endfor

    ## Unread: documented, and named nowhere it forwards to
    seen = false (n, 1);
    seen(ii) = true;
    front = seen;
    while (any (front))
      next = any (A(front,:), 1)';
      front = next & ! seen;
      seen |= front;
    endwhile
    files = unique (N.file(seen));
    got = {};
    for jj = 1:numel (files)
      if (isKey (strings, files{jj}))
        got = [got; strings(files{jj})];
      endif
    endfor
    for jj = find (! ismember (known, got))'
      FILE{end+1,1} = N.file{ii};
      LINE(end+1,1) = N.line(ii);
      RULE{end+1,1} = 'unread-option';
      TEXT{end+1,1} = sprintf ("no code read by %s names option '%s'", ...
                               N.node{ii}, known{jj});
    endfor
  endfor

endfunction

## Collect the strings of a package's files for optionGaps.  ROOT, PACKAGE and N
## locate the files.  CASES holds node, line, name and value for each label of a
## switch whose value looks like an option's name: value is the text being
## switched on, in lower case, and each label belongs to the node defined last
## above it.  STRINGS maps each file to its strings, in lower case.
function [CASES, STRINGS] = optionReads (ROOT, PACKAGE, N)

  query = ['(switch_statement value: (_) @v (case_clause value: (_) @c)) ', ...
           '(string) @s'];
  own = strcmp (N.package, PACKAGE) & ! strcmp (N.file, '');
  files = unique (N.file(own));
  node = line = zeros (0, 1);
  name = value = cell (0, 1);
  STRINGS = containers.Map ('KeyType', 'char', 'ValueType', 'any');
  for ii = 1:numel (files)
    if (isempty (regexp (files{ii}, '\.m$', 'once')))
      continue;
    endif
    text = fileread (fullfile (ROOT, files{ii}));
    Q = devtools.__parseQuery__ (text, query);
    txt = @(k) text(Q.sbyte(k)+1:Q.ebyte(k));
    ks = find (strcmp (Q.capture, 's'));
    all = arrayfun (txt, ks, 'UniformOutput', false);
    STRINGS(files{ii}) = unique (lower (regexprep (all, '^.(.*).$', '$1')));

    b = [];
    lit = over = {};
    kv = find (strcmp (Q.capture, 'v'));
    kc = find (strcmp (Q.capture, 'c'));
    [~, j] = ismember (Q.match(kv), Q.match(kc));
    for k = 1:numel (kv)
      v = txt (kv(k));
      pat = 'name|opt|param|key|prop|varargin\{\w+\}';
      if (isempty (regexpi (v, pat, 'once')))
        continue;
      endif
      tok = regexp (txt (kc(j(k))), '[''"]([^''"]+)[''"]', 'tokens');
      for w = cellfun (@(x) x{1}, tok, 'UniformOutput', false)
        lit{end+1,1} = w{1};
        over{end+1,1} = lower (v);
        b(end+1,1) = Q.srow(kv(k)) + 1;
      endfor
    endfor
    if (isempty (lit))
      continue;
    endif

    ## Each literal belongs to the node defined last above it
    here = find (strcmp (N.file, files{ii}) & own);
    [at, o] = sort (N.line(here));
    here = here(o);
    w = lookup (at, b);
    ok = w > 0;
    node = [node; here(w(ok))];
    line = [line; b(ok)];
    name = [name; lower(lit(ok))];
    value = [value; over(ok)];
  endfor
  CASES = struct ('node', node, 'line', line, 'name', {name}, 'value', {value});

endfunction

## Put a text in double quotes for Graphviz, escaping the backslashes and quotes
## inside it.
function S = quote (T)
  S = ['"', strrep(strrep (T, '\', '\\'), '"', '\"'), '"'];
endfunction

## The Graphviz attributes of an edge.  STATUS is its status and KIND its kind.
## A possible edge is dashed, an incomplete one dotted and red, and inheritance
## a hollow arrow whatever its status.
function A = edgeLook (STATUS, KIND)

  A = '';
  switch (STATUS)
    case 'possible'
      A = 'style=dashed';
    case 'incomplete'
      A = 'style=dotted, color=red';
  endswitch
  if (strcmp (KIND, 'inherit'))
    A = 'arrowhead=onormal';
  endif

endfunction

## The Graphviz shape of a node.  KIND is its kind, each kind having its own
## shape, and an unknown kind is plain red text, for what no reading settled.
function A = shapeOf (KIND)

  switch (KIND)
    case 'function'
      A = 'shape=box';
    case 'method'
      A = 'shape=ellipse';
    case 'local'
      A = 'shape=ellipse, style=dashed';
    case 'private'
      A = 'shape=note';
    case 'compiled'
      A = 'shape=component';
    case 'class'
      A = 'shape=box3d';
    case 'core'
      A = 'shape=plaintext';
    otherwise
      A = 'shape=plaintext, fontcolor=red';
  endswitch

endfunction

## The Graphviz source of a graph with one box per node.  N is the node table, E
## the edges and EXTRA the nodes to draw though no edge names them.  Methods are
## boxed by class, and other nodes by folder and package.  Each pair of nodes is
## drawn once for each status and kind it has.  T is the text.
function T = nodeGraph (N, E, EXTRA)

  names = unique ([E.from; E.to; EXTRA(:)]);
  [~, k] = ismember (names, N.node);
  group = cell (numel (names), 1);
  for ii = 1:numel (names)
    group{ii} = '';
    if (k(ii) == 0 || strcmp (N.kind{k(ii)}, 'core'))
      continue;
    endif
    c = '';
    if (strcmp (N.kind{k(ii)}, 'class'))
      c = N.node{k(ii)};
    elseif (! isempty (N.class{k(ii)}))
      c = N.class{k(ii)};
    endif
    if (isempty (c))
      c = fileparts (N.file{k(ii)});
    endif
    group{ii} = [N.package{k(ii)}, ': ', c];
  endfor

  lines = {'digraph callGraph {'; '  rankdir=LR;'; ...
           '  node [fontname="sans-serif", fontsize=10];'};
  [u, ~, g] = unique (group);
  for ii = 1:numel (u)
    open = ! isempty (u{ii});
    if (open)
      lines{end+1,1} = sprintf ("  subgraph \"cluster_%d\" {", ii);
      lines{end+1,1} = sprintf ("    label=%s;", quote (u{ii}));
    endif
    for jj = find (g == ii)'
      kind = '';
      tip = names{jj};
      if (k(jj) > 0)
        kind = N.kind{k(jj)};
        if (! isempty (N.file{k(jj)}))
          tip = sprintf ("%s:%d", N.file{k(jj)}, N.line(k(jj)));
        endif
      endif
      lines{end+1,1} = sprintf ("    %s [%s, tooltip=%s];", ...
                                quote (names{jj}), shapeOf (kind), quote (tip));
    endfor
    if (open)
      lines{end+1,1} = '  }';
    endif
  endfor

  key = strcat (E.from, "\t", E.to, "\t", E.status, "\t", E.kind);
  [~, u] = unique (key);
  for ii = u(:)'
    look = edgeLook (E.status{ii}, E.kind{ii});
    if (! isempty (look))
      look = [' [', look, ']'];
    endif
    lines{end+1,1} = sprintf ("  %s -> %s%s;", quote (E.from{ii}), ...
                              quote (E.to{ii}), look);
  endfor
  lines{end+1,1} = '}';
  T = [strjoin(lines', "\n"), "\n"];

endfunction

## The Graphviz source of a graph whose boxes are files, classes or folders.  E
## holds the edges, N is the node table and OPT the options of draw.
## Each edge is as wide as what it carries, a core function stands for itself,
## and what no reading settled stands in red for itself.  T is the text.
function T = mergedGraph (E, N, OPT)

  [L, B] = linksBetween (N, E, OPT.level, OPT.core);

  ## The boxes, and what is in them
  [~, e] = ismember (OPT.extra, N.node);
  e = e(e > 0);
  names = unique ([L.from; L.to; B.name(e)]);
  names(strcmp (names, '')) = [];
  [tf, w] = ismember (names, B.name);
  where = what = repmat ({''}, numel (names), 1);
  where(tf) = B.where(w(tf));
  what(tf) = B.tip(w(tf));
  red = ! tf;

  lines = {'digraph callGraph {'; '  rankdir=LR;'; ...
           '  node [shape=box, fontname="sans-serif", fontsize=10];'};
  [u, ~, g] = unique (where);
  for ii = 1:numel (u)
    open = ! isempty (u{ii});
    if (open)
      lines{end+1,1} = sprintf ("  subgraph \"cluster_%d\" {", ii);
      lines{end+1,1} = sprintf ("    label=%s;", quote (u{ii}));
    endif
    for jj = find (g(:) == ii)'
      look = sprintf ("tooltip=%s", quote (what{jj}));
      if (red(jj))
        look = shapeOf ('');
      endif
      lines{end+1,1} = sprintf ("    %s [%s];", quote (names{jj}), look);
    endfor
    if (open)
      lines{end+1,1} = '  }';
    endif
  endfor

  weight = L.(OPT.weight);
  for ii = 1:numel (L.from)
    if (L.inherit(ii))
      look = 'arrowhead=onormal';
    elseif (strcmp (L.status{ii}, 'incomplete'))
      look = edgeLook ('incomplete', 'call');
    else
      look = sprintf ("penwidth=%.2f", 1 + log10 (weight(ii)));
      if (! strcmp (L.status{ii}, 'certain'))
        look = [look, ', style=dashed'];
      endif
    endif
    lines{end+1,1} = sprintf ("  %s -> %s [%s];", quote (L.from{ii}), ...
                              quote (L.to{ii}), look);
  endfor
  lines{end+1,1} = '}';
  T = [strjoin(lines', "\n"), "\n"];

endfunction

## Read the definitions of one file.  PATH is the file and P its package.  The
## node's key comes from the file's place in the package: namespaces prefix it,
## a private function is keyed by its folder, and a function in an @class folder
## is a method of that class.  F holds nodes, what the file defines, and what
## readSource needs to name them: its relative path and text, its package, main
## key, class and superclasses, the folder its private functions are looked up
## from, the key, object, class and first output of each function, and its local
## functions.  F is empty for an empty file.
function F = describeFile (PATH, P)

  F = [];
  text = fileread (PATH);
  if (! isrow (text))
    return;
  endif
  D = devtools.__parseDefs__ (text);
  rel = strrep (PATH(numel (P.root)+2:end), '\', '/');
  [folder, base] = fileparts (rel);
  parts = ostrsplit (strrep (folder, '\', '/'), '/');
  parts(cellfun (@isempty, parts)) = [];
  isNs = strncmp (parts, '+', 1);
  ns = strjoin (cellfun (@(s) [s(2:end), '.'], parts(isNs), ...
                         'UniformOutput', false), '');
  isPrivate = any (strcmp (parts, 'private'));
  atdir = parts(strncmp (parts, '@', 1));
  scope = regexprep (folder, '^inst[/\\]?', '');
  key = [ns, base];
  if (isPrivate)
    key = regexprep (fullfile (scope, base), '\\', '/');
  endif

  isFn = strcmp ({D.type}, 'function_definition');
  kc = find (strcmp ({D.type}, 'classdef_definition'), 1);
  cls = '';
  supers = {};
  abstract = false;
  line = 1;
  N = struct ('node', {}, 'short', {}, 'kind', {}, 'line', {}, 'cls', {}, ...
              'abstract', {});
  fnKey = repmat ({''}, sum (isFn), 1);
  fnObj = repmat ({''}, sum (isFn), 1);
  fnCls = repmat ({''}, sum (isFn), 1);
  fn = find (isFn);

  if (! isempty (kc))
    cls = key;
    supers = D(kc).supers(:)';
    line = D(kc).srow + 1;
    abstract = ! isempty (regexp (text, ...
      '^\s*classdef\s*\([^)]*\<Abstract\>(?!\s*=\s*false)', ...
      'once', 'lineanchors'));
    N(end+1) = struct ('node', key, 'short', base, ...
                       'kind', 'class', 'line', line, ...
                       'cls', '', 'abstract', abstract);
    for ii = 1:numel (fn)
      k = fn(ii);
      name = D(k).name;
      if (D(k).parent == kc)
        fnCls{ii} = cls;
        if (strcmp (name, D(kc).name))
          fnKey{ii} = key;
          if (! isempty (D(k).outputs))
            fnObj{ii} = D(k).outputs{1};
          endif
        else
          fnKey{ii} = [key, '.', name];
          N(end+1) = struct ('node', fnKey{ii}, 'short', name, ...
                             'kind', 'method', 'line', D(k).srow + 1, ...
                             'cls', cls, 'abstract', false);
          if (! D(k).static && ! isempty (D(k).params))
            fnObj{ii} = D(k).params{1};
          endif
        endif
      else
        fnKey{ii} = [key, '>', name];
        N(end+1) = struct ('node', fnKey{ii}, 'short', name, ...
                           'kind', 'local', 'line', D(k).srow + 1, ...
                           'cls', '', 'abstract', false);
      endif
    endfor
  else
    mainKind = 'function';
    if (isPrivate)
      mainKind = 'private';
    endif
    if (! isempty (atdir) && ! isPrivate)
      cls = [ns, atdir{1}(2:end)];
      if (strcmp (base, atdir{1}(2:end)))
        mainKind = 'class';
      else
        key = [cls, '.', base];
        mainKind = 'method';
      endif
    endif
    if (! isempty (fn))
      line = D(fn(1)).srow + 1;
    endif
    ownerClass = '';
    if (strcmp (mainKind, 'method'))
      ownerClass = cls;
    endif
    N(end+1) = struct ('node', key, 'short', base, ...
                       'kind', mainKind, 'line', line, ...
                       'cls', ownerClass, 'abstract', false);
    for ii = 1:numel (fn)
      k = fn(ii);
      if (ii == 1)
        fnKey{ii} = key;
        if (strcmp (mainKind, 'method') && ! isempty (D(k).params))
          fnObj{ii} = D(k).params{1};
          fnCls{ii} = cls;
        endif
      else
        fnKey{ii} = [key, '>', D(k).name];
        N(end+1) = struct ('node', fnKey{ii}, 'short', D(k).name, ...
                           'kind', 'local', 'line', D(k).srow + 1, ...
                           'cls', '', 'abstract', false);
      endif
    endfor
  endif

  fnOut = repmat ({''}, numel (fn), 1);
  for ii = 1:numel (fn)
    if (! isempty (D(fn(ii)).outputs))
      fnOut{ii} = D(fn(ii)).outputs{1};
    endif
  endfor
  isLocal = strcmp ({N.kind}, 'local');
  F = struct ('rel', rel, 'pkg', P.name, 'text', text, 'main', key, ...
              'cls', cls, 'declares', any (strcmp ({N.kind}, 'class')), ...
              'supers', {supers}, 'line', line, ...
              'base', strrep (regexprep (fullfile (P.root, folder), ...
                                         '[/\\]private$', ''), '\', '/'), ...
              'fnKey', {fnKey}, 'fnObj', {fnObj}, 'fnCls', {fnCls}, ...
              'fnOut', {fnOut}, ...
              'localName', {{N(isLocal).short}}, ...
              'localNode', {{N(isLocal).node}}, 'nodes', N);

endfunction

## Decide whether a condition can hold for given output and input counts.  G is
## the text of the condition, conditions being joined by &&, NIN the input count
## and NOUT the output count.  Only a clause comparing nargin or nargout with a
## number is judged, or the negation of one.  Anything else may hold, and so may
## a count of NaN.  A condition with an || at its top level is not judged at
## all.  TF is false only if some clause certainly fails.
function TF = guardHolds (G, NIN, NOUT)

  TF = true;
  depth = cumsum ((G == '(') - (G == ')'));

  ## Parentheses around the whole condition say nothing
  while (numel (G) > 1 && G(1) == '(' && G(end) == ')'
         && all (depth(1:end-1) > 0))
    G = strtrim (G(2:end-1));
    depth = cumsum ((G == '(') - (G == ')'));
  endwhile
  top = depth == 0;
  if (! isempty (strfind (G, '||')) && any (top(strfind (G, '||'))))
    return;
  endif
  cut = strfind (G, ' && ');
  cut = cut(top(cut));
  s = [1, cut + 4];
  e = [cut - 1, numel(G)];
  for ii = 1:numel (s)
    t = strtrim (G(s(ii):e(ii)));
    wrapped = false;
    neg = regexp (t, '^!\s*\((.*)\)$', 'tokens', 'once');
    if (! isempty (neg))
      wrapped = true;
      t = strtrim (neg{1});
    endif
    m = regexp (t, '^(nargin|nargout)\s*(==|!=|~=|>=|<=|>|<)\s*(\d+)$', ...
                'tokens', 'once');
    if (isempty (m))
      continue;
    endif
    v = NIN;
    if (strcmp (m{1}, 'nargout'))
      v = NOUT;
    endif
    if (isnan (v))
      continue;
    endif
    r = str2double (m{3});
    switch (m{2})
      case '=='
        h = v == r;
      case {'!=', '~='}
        h = v != r;
      case '>='
        h = v >= r;
      case '<='
        h = v <= r;
      case '>'
        h = v > r;
      case '<'
        h = v < r;
    endswitch
    if (h == wrapped)
      TF = false;
      return;
    endif
  endfor

endfunction

## Read one option selecting what paths and draw show.  With no input, V is the
## default selection: everything the code does.  Otherwise V is the selection so
## far, and NAME and VALUE the option.  MSG says what is wrong with VALUE, being
## empty if nothing is, so that the caller can raise it under its own name.
## KNOWN is false where NAME selects nothing, for the caller to deal with.
function [V, MSG, KNOWN] = viewOption (V, NAME, VALUE)

  if (nargin == 0)
    V = struct ('scope', 'all', 'core', true, 'certainty', 'all', ...
                'unresolved', true, 'tests', false, 'kinds', {{}}, ...
                'level', 'node', 'weight', 'calls');
    return;
  endif
  MSG = '';
  KNOWN = true;
  switch (lower (NAME))
    case 'scope'
      if (! (ischar (VALUE) && isrow (VALUE)))
        MSG = "'Scope' must be a character vector.";
      elseif (! any (strcmp (VALUE, {'all', 'package'})))
        MSG = sprintf ("unknown scope: '%s'.", VALUE);
      else
        V.scope = VALUE;
      endif
    case 'core'
      if (! (islogical (VALUE) && isscalar (VALUE)))
        MSG = "'Core' must be a logical scalar.";
      else
        V.core = VALUE;
      endif
    case 'certainty'
      if (! (ischar (VALUE) && isrow (VALUE)))
        MSG = "'Certainty' must be a character vector.";
      elseif (! any (strcmp (VALUE, {'all', 'proven', 'certain'})))
        MSG = sprintf ("unknown certainty: '%s'.", VALUE);
      else
        V.certainty = VALUE;
      endif
    case 'unresolved'
      if (! (islogical (VALUE) && isscalar (VALUE)))
        MSG = "'Unresolved' must be a logical scalar.";
      else
        V.unresolved = VALUE;
      endif
    case 'tests'
      if (! (islogical (VALUE) && isscalar (VALUE)))
        MSG = "'Tests' must be a logical scalar.";
      else
        V.tests = VALUE;
      endif
    case 'kinds'
      if (ischar (VALUE) && isrow (VALUE))
        VALUE = {VALUE};
      endif
      if (! (iscellstr (VALUE) && ! isempty (VALUE)))
        MSG = "'Kinds' must be an edge kind or a cell array of them.";
      else
        known = {'call', 'handle', 'string', 'method', 'constructor', ...
                 'inherit', 'subsref', 'operator', 'getter', 'setter'};
        bad = setdiff (VALUE, known);
        if (isempty (bad))
          V.kinds = VALUE(:);
        else
          MSG = sprintf ("unknown edge kind: '%s'.", bad{1});
        endif
      endif
    case 'level'
      if (! (ischar (VALUE) && isrow (VALUE)))
        MSG = "'Level' must be a character vector.";
      elseif (! any (strcmp (VALUE, {'node', 'file', 'class', 'folder'})))
        MSG = sprintf ("unknown level: '%s'.", VALUE);
      else
        V.level = VALUE;
      endif
    case 'weight'
      if (! (ischar (VALUE) && isrow (VALUE)))
        MSG = "'Weight' must be a character vector.";
      elseif (! any (strcmp (VALUE, {'calls', 'files'})))
        MSG = sprintf ("unknown weight: '%s'.", VALUE);
      else
        V.weight = VALUE;
      endif
    otherwise
      KNOWN = false;
  endswitch

endfunction

## Mark the edges a selection allows.  V is the selection, N the node table, E a
## table with from, kind and test, and PACKAGE the name of the package read.  K
## marks the rows that the scope, the BIST calls and the edge kinds allow.  A
## row leaving PACKAGE is kept, its end being named, and one starting outside it
## is not.
function K = keptEdges (V, N, E, PACKAGE)

  K = true (size (E.from));
  if (strcmp (V.scope, 'package'))
    [~, a] = ismember (E.from, N.node);
    here = false (size (a));
    here(a > 0) = strcmp (N.package(a(a > 0)), PACKAGE);
    K &= here;
  endif
  if (! V.tests)
    K &= ! E.test;
  endif
  if (! isempty (V.kinds))
    K &= ismember (E.kind, V.kinds);
  endif

endfunction

## Gather edges into links between boxes.  N is the node table, E holds from,
## to, kind, status and file, LEVEL says what a box is, and CORE whether a core
## function counts as a box.  L has one row per pair of boxes joined, with from,
## to, calls, the call sites it carries, files, the distinct files they stand
## in, status, and inherit, true if one of them is inheritance.  A call within
## one box makes no link.  B holds each node's box, what encloses that box, and
## the tip of the node.
function [L, B] = linksBetween (N, E, LEVEL, CORE)

  n = numel (N.node);
  name = where = tip = repmat ({''}, n, 1);
  for ii = 1:n
    if (strcmp (N.kind{ii}, 'core'))
      if (CORE && ! strcmp (LEVEL, 'class'))
        name{ii} = N.node{ii};
      endif
    elseif (! isempty (N.file{ii}))
      [name{ii}, where{ii}] = boxOf (N, ii, LEVEL);
      tip{ii} = sprintf ("%s:%d", N.file{ii}, N.line(ii));
    endif
  endfor
  B = struct ('name', {name}, 'where', {where}, 'tip', {tip});

  [~, a] = ismember (E.from, N.node);
  [~, b] = ismember (E.to, N.node);
  ga = gb = repmat ({''}, numel (b), 1);
  ga(a > 0) = name(a(a > 0));
  gb(b > 0) = name(b(b > 0));
  loose = b == 0;
  gb(loose) = E.to(loose);
  keep = ! strcmp (ga, '') & ! strcmp (gb, '') & ! strcmp (ga, gb);
  ga = ga(keep);
  gb = gb(keep);
  rows = find (keep);
  L = struct ('from', {cell(0, 1)}, 'to', {cell(0, 1)}, ...
              'calls', zeros (0, 1), 'files', zeros (0, 1), ...
              'status', {cell(0, 1)}, 'inherit', false (0, 1));
  if (isempty (rows))
    return;
  endif

  [u, ~, g] = unique (strcat (ga, "\t", gb));
  groups = accumarray (g(:), (1:numel (g))', [], @(x) {x});
  m = numel (u);
  from = to = status = cell (m, 1);
  calls = files = zeros (m, 1);
  inherit = false (m, 1);
  for ii = 1:m
    k = groups{ii};
    from{ii} = ga{k(1)};
    to{ii} = gb{k(1)};
    calls(ii) = numel (k);
    files(ii) = numel (unique (E.file(rows(k))));
    s = E.status(rows(k));
    status{ii} = 'possible';
    if (any (strcmp (s, 'certain')))
      status{ii} = 'certain';
    elseif (all (strcmp (s, 'incomplete')))
      status{ii} = 'incomplete';
    endif
    inherit(ii) = any (strcmp (E.kind(rows(k)), 'inherit'));
  endfor
  L = struct ('from', {from}, 'to', {to}, 'calls', calls, 'files', files, ...
              'status', {status}, 'inherit', inherit);

endfunction

## The box a node belongs to at a level, and what encloses that box.  N is the
## node table, K the node and LEVEL the level.  At class level a node of no
## class has an empty name and so makes no box.
function [NAME, WHERE] = boxOf (N, K, LEVEL)

  folder = fileparts (N.file{K});
  switch (LEVEL)
    case 'node'
      NAME = N.node{K};
      WHERE = folder;
    case 'file'
      NAME = N.file{K};
      WHERE = folder;
    case 'folder'
      NAME = folder;
      WHERE = N.package{K};
    case 'class'
      NAME = '';
      if (strcmp (N.kind{K}, 'class'))
        NAME = N.node{K};
      elseif (! isempty (N.class{K}))
        NAME = N.class{K};
      endif
      WHERE = N.package{K};
  endswitch

endfunction

## List the names core Octave defines, whatever is loaded: its built-in
## functions, autoloads, and the functions and classes in its function folder.
## C is a sorted column cell array.
function C = coreNames ()

  C = __builtins__ ();
  C = [C(:); {'handle'}];
  a = autoload ();
  if (! isempty (a))
    C = [C; {a.function}(:)];
  endif
  I = devtools.__pkgInventory__ (__octave_config_info__ ('fcnfiledir'));
  keep = ! strcmp ({I.kind}, 'method') & ! strcmp ({I.kind}, 'property');
  C = [C; {I(keep).name}(:)];
  oct = dir (fullfile (__octave_config_info__ ('octfiledir'), '*.oct'));
  C = [C; strrep({oct.name}(:), '.oct', '')];
  C = unique (C);

endfunction

%!function write_file (D, NAME, TEXT)
%!  file = fullfile (D, NAME);
%!  folder = fileparts (file);
%!  if (! isfolder (folder))
%!    mkdir (folder);
%!  endif
%!  fid = fopen (file, 'w');
%!  fputs (fid, TEXT);
%!  fclose (fid);
%!endfunction

%!function D = fixture ()
%!  D = tempname ();
%!  mkdir (D);
%!  write_file (D, 'DESCRIPTION', sprintf (strcat ("Name: tiny\n", ...
%!              "Version: 1.2.3\nDepends: octave (>= 11.1.0)\n")));
%!  write_file (D, 'src/both.cc', "DEFUN_DLD (compiledfn, args, ,\n  \"\")\n");
%!  write_file (D, 'inst/+ns/inner.m', "function y = inner (x)\nend\n");
%!  write_file (D, 'inst/private/hidden.m', ...
%!    ["## -*- texinfo -*-\n", ...
%!     "## @deftypefn {Private Function} {@var{y} =} hidden (@var{x})\n", ...
%!     "## @end deftypefn\n", "function y = hidden (x)\nend\n"]);
%!  write_file (D, 'inst/Abs.m', ...
%!    ["classdef (Abstract) Abs\n  methods\n", ...
%!     "    ## -*- texinfo -*-\n", ...
%!     "    ## @deftypefn {Abs} {@var{y} =} zap (@var{this})\n", ...
%!     "    ## @end deftypefn\n", ...
%!     "    function y = zap (this)\n    end\n  end\nend\n"]);
%!  write_file (D, 'inst/docd.m', ...
%!    ["## -*- texinfo -*-\n", ...
%!     "## @deftypefn  {tiny} {@var{r} =} docd (@var{x})\n", ...
%!     "## @deftypefnx {tiny} {@var{r} =} docd (@var{x}, @var{y})\n", ...
%!     "## @deftypefnx {tiny} {[@var{r}, @var{s}] =} docd (@dots{})\n", ...
%!     "## @deftypefnx {tiny} {@var{r} =} docd (@dots{}, @var{w})\n", ...
%!     '## @deftypefnx {tiny} {@var{r} =} docd (@dots{}, @var{Name}, ', ...
%!     "@var{Value})\n", ...
%!     "## @deftypefnx {tiny} {} docd (@var{ax}, @dots{})\n##\n", ...
%!     "## @multitable @columnfractions 0.5 0.5\n", ...
%!     "## @headitem @var{Name} @tab @var{Value}\n", ...
%!     "## @item @qcode{'Weights'} @tab A vector.\n", ...
%!     '## @item @qcode{''Mode''} @tab Must be @qcode{''on''} or ', ...
%!     "@qcode{'off'}.\n", ...
%!     "## @item @qcode{'Tol'} @tab Used only when @qcode{'Mode'} is on.\n", ...
%!     "## @item @qcode{'Kind'} @tab as specified below:\n", ...
%!     "## @end multitable\n##\n", ...
%!     "## @multitable @columnfractions 0.5 0.5\n", ...
%!     "## @headitem Value @tab Meaning\n", ...
%!     "## @item @qcode{'a'} @tab One.\n", ...
%!     "## @item @qcode{'b'} @tab Two.\n", ...
%!     "## @end multitable\n## @end deftypefn\n", ...
%!     "function [r, s] = docd (varargin)\n", ...
%!     "  if (nargout == 0)\n    plot (1);\n  endif\n  nosuch ();\n", ...
%!     "endfunction\n"]);
%!  write_file (D, 'inst/Sub.m', ...
%!    ["classdef Sub < Base\n  methods\n    function this = Sub (x)\n", ...
%!     "      this@Base (x);\n    end\n    function y = spin (this)\n", ...
%!     "      y = spin@Base (this);\n    end\n  end\nend\n"]);
%!  write_file (D, 'inst/Base.m', ...
%!    ["classdef Base\n  properties\n    Val = 1;\n  end\n  methods\n", ...
%!     "    ## -*- texinfo -*-\n", ...
%!     "    ## @deftypefn {Base} {@var{o} =} Base (@var{x})\n", ...
%!     "    ## @end deftypefn\n", ...
%!     "    function this = Base (x)\n    end\n", ...
%!     "    ## -*- texinfo -*-\n", ...
%!     "    ## @deftypefn {Base} {@var{y} =} go (@var{this})\n", ...
%!     "    ## @end deftypefn\n", ...
%!     "    function y = go (this)\n      y = spin (this);\n    end\n", ...
%!     "    function y = spin (this)\n      y = 1;\n    end\n", ...
%!     "    function y = get.Val (this)\n      y = 2;\n    end\n", ...
%!     "    function this = set.Val (this, v)\n    end\n", ...
%!     "    function y = plus (a, b)\n      y = 1;\n    end\n", ...
%!     "    function y = columns (this)\n      y = 1;\n    end\n", ...
%!     "    function y = subsref (this, s)\n      y = 1;\n    end\n", ...
%!     "  end\n  methods (Static)\n", ...
%!     "    function y = make (x)\n      y = 1;\n    end\n  end\nend\n"]);
%!  write_file (D, 'inst/nest.m', ...
%!    ["function y = nest ()\n  setup ();\n  y = w + 1;\n", ...
%!     "  function setup ()\n    w = 2;\n  endfunction\nendfunction\n"]);
%!  write_file (D, 'inst/factory.m', ...
%!    "function M = factory ()\n  M = Sub (1);\nendfunction\n");
%!  write_file (D, 'inst/outer.m', ...
%!    ["function [a, b] = outer (x, varargin)\n", ...
%!     "  hist = 1;\n  a = hist (1);\n  numel (x);\n", ...
%!     "  [b, c] = size (x);\n  d = localfn (x);\n  e = hidden (x);\n", ...
%!     "  f = @sin;\n  g = feval ('cos', x);\n  h = feval (x, 1);\n", ...
%!     "  if (isempty (x))\n    a = floor (x);\n  else\n", ...
%!     "    a = ceil (x);\n  endif\n  switch (x)\n    case 1\n", ...
%!     "      a = round (x);\n", ...
%!     "  endswitch\n  t = abs (x, varargin{:});\n  m = Base (1);\n", ...
%!     "  n = go (m);\n  o = ns.inner (x);\n  p = Base.make (1);\n", ...
%!     "  q = nope (x);\n  r = m.Val;\n  m.Val = 2;\n  s = m + 1;\n", ...
%!     "  u = m(1);\n  v = compiledfn (x);\n  w = spin (x);\n", ...
%!     "  y = max (1);\n  max = 2;\n  k = factory ();\n  l = spin (k);\n", ...
%!     "  i = columns (x);\n  j = columns (3);\n  error ('stop');\n", ...
%!     "endfunction\n", ...
%!     "function y = localfn (x)\n  y = fix (x);\nendfunction\n", ...
%!     "%!test\n%! z = outer (1);\n", ...
%!     "%!test\n%! load foo\n%! y = zork + 1;\n"]);
%!endfunction

%!function tf = edge (G, FROM, TO, CERT)
%!  E = G.Edges;
%!  tf = any (strcmp (E.from, FROM) & strcmp (E.to, TO)
%!            & strcmp (E.certainty, CERT));
%!endfunction

%!function r = row (G, FROM, TO, FIELD)
%!  E = G.Edges;
%!  k = find (strcmp (E.from, FROM) & strcmp (E.to, TO), 1);
%!  r = E.(FIELD)(k);
%!endfunction

%!function D = pack (varargin)
%!  D = tempname ();
%!  mkdir (D);
%!  write_file (D, 'DESCRIPTION', "Name: small\nVersion: 1\n");
%!  for ii = 1:2:numel (varargin)
%!    write_file (D, ['inst/', varargin{ii}], varargin{ii+1});
%!  endfor
%!endfunction

%!function G = read_pack (varargin)
%!  D = pack (varargin{:});
%!  G = devtools.callGraph (D);
%!  confirm_recursive_rmdir (false, 'local');
%!  rmdir (D, 's');
%!endfunction

%!function G = run_pack (varargin)
%!  D = pack (varargin{:});
%!  G = trace (devtools.callGraph (D));
%!  confirm_recursive_rmdir (false, 'local');
%!  rmdir (D, 's');
%!endfunction

%!function D = traced ()
%!  D = tempname ();
%!  mkdir (D);
%!  write_file (D, 'DESCRIPTION', "Name: tr\nVersion: 1\n");
%!  write_file (D, 'inst/tobj.m', ...
%!    ["classdef tobj\n  methods\n", ...
%!     "    ## -*- texinfo -*-\n", ...
%!     "    ## @deftypefn {tobj} {@var{o} =} tobj (@var{x})\n", ...
%!     "    ## @end deftypefn\n", ...
%!     "    function this = tobj (x)\n    endfunction\n", ...
%!     "    ## -*- texinfo -*-\n", ...
%!     "    ## @deftypefn {tobj} {@var{v} =} val (@var{this})\n", ...
%!     "    ## @end deftypefn\n", ...
%!     "    function v = val (this)\n      v = 1;\n    endfunction\n", ...
%!     "  endmethods\nendclassdef\n", ...
%!     "%!test\n%! o = tobj (1);\n%! y = val (o);\n"]);
%!  write_file (D, 'inst/uobj.m', ...
%!    ["classdef uobj\n  methods\n", ...
%!     "    function v = val (this)\n      v = 2;\n    endfunction\n", ...
%!     "  endmethods\nendclassdef\n"]);
%!  write_file (D, 'inst/tfun.m', ...
%!    ["## -*- texinfo -*-\n", ...
%!     "## @deftypefn  {tr} {@var{r} =} tfun (@var{x})\n", ...
%!     '## @deftypefnx {tr} {[@var{r}, @var{s}] =} tfun (@var{x}, ', ...
%!     "@var{y})\n", ...
%!     "## @end deftypefn\n", ...
%!     "function [r, s] = tfun (x, y = 2)\n  r = helper (x);\n", ...
%!     "  s = val (r);\nendfunction\n", ...
%!     "function o = helper (x)\n  o = tobj (x);\nendfunction\n", ...
%!     "%!shared q\n%! q = 3;\n", ...
%!     "%!test\n%! r = tfun (1);\n%! assert_equal (class (r), 'tobj');\n", ...
%!     "%!test\n%! [~, s] = tfun (q, 1);\n%! assert_equal (s, 1);\n", ...
%!     "%!assert_equal (class (tfun (1)), 'tobj')\n", ...
%!     "%!test\n%! tfun (1);\n", ...
%!     "%!error <called with too many inputs> tfun (1, 2, 3, 4, 5, 6)\n"]);
%!endfunction

%!shared G, T, P, Q
%! D = fixture ();
%! G = devtools.callGraph (D);
%! confirm_recursive_rmdir (false, 'local');
%! rmdir (D, 's');
%! D = traced ();
%! P = path ();
%! T = trace (devtools.callGraph (D));
%! rmdir (D, 's');
%! Q = read_pack ('pl.m', ["## -*- texinfo -*-\n", ...
%!                         "## @deftypefn  {small} {} pl (@var{x})\n", ...
%!                         '## @deftypefnx {small} {@var{r} =} ', ...
%!                         "pl (@var{x})\n", ...
%!                         "## @end deftypefn\n", ...
%!                         "function r = pl (x)\n  if (nargout == 0)\n", ...
%!                         "    plot (x);\n  endif\nend\n"], ...
%!                'caller.m', ["## -*- texinfo -*-\n", ...
%!                             '## @deftypefn {small} {@var{y} =} ', ...
%!                             "caller (@var{x})\n", ...
%!                             "## @end deftypefn\n", ...
%!                             "function y = caller (x)\n", ...
%!                             "  y = pl (x);\nend\n"]);


## Reading a package
%!test
%! assert_equal (G.Package, 'tiny');
%!test
%! assert_equal (G.Version, '1.2.3');
%!test
%! assert_equal (issorted (G.Nodes.node), true);
%!test
%! assert_equal (numel (unique (G.Nodes.node)), numel (G.Nodes.node));

## Nodes
%!test
%! k = strcmp (G.Nodes.node, 'outer>localfn');
%! assert_equal (G.Nodes.kind{k}, 'local');
%!test
%! k = strcmp (G.Nodes.node, 'private/hidden');
%! assert_equal (G.Nodes.kind{k}, 'private');
%!test
%! k = strcmp (G.Nodes.node, 'ns.inner');
%! assert_equal (G.Nodes.kind{k}, 'function');
%!test
%! k = strcmp (G.Nodes.node, 'Base.go');
%! assert_equal (G.Nodes.class{k}, 'Base');
%!test
%! k = strcmp (G.Nodes.node, 'compiledfn');
%! assert_equal (G.Nodes.kind{k}, 'compiled');
%!test
%! k = strcmp (G.Nodes.node, 'compiledfn');
%! assert_equal (G.Nodes.file{k}, 'src/both.cc');
%!test
%! k = strcmp (G.Nodes.node, 'sum');
%! assert_equal (any (k), false);
%!test
%! k = strcmp (G.Nodes.node, 'fix');
%! assert_equal (G.Nodes.package{k}, 'core');
%!test
%! k = strcmp (G.Nodes.node, 'Abs');
%! assert_equal (G.Nodes.abstract(k), true);
%!test
%! k = strcmp (G.Nodes.node, 'Base');
%! assert_equal (G.Nodes.abstract(k), false);

## Names resolve as core's xfind
%!test
%! assert_equal (edge (G, 'outer', 'hist', 'certain'), false);
%!test
%! assert_equal (edge (G, 'outer', 'max', 'certain'), true);
%!test
%! assert_equal (edge (G, 'outer', 'outer>localfn', 'certain'), true);
%!test
%! assert_equal (edge (G, 'outer', 'private/hidden', 'certain'), true);
%!test
%! assert_equal (edge (G, 'outer', 'compiledfn', 'certain'), true);
%!test
%! assert_equal (edge (G, 'outer>localfn', 'fix', 'certain'), true);
%!test
%! assert_equal (edge (G, 'outer', 'ns.inner', 'certain'), true);
%!test
%! assert_equal (edge (G, 'outer', 'Base.make', 'certain'), true);
%!test
%! assert_equal (edge (G, 'outer', 'nope', 'unresolved'), true);
%!test
%! assert_equal (any (strcmp (G.Edges.to, 'w')), false);

## Kinds of edge
%!test
%! assert_equal (row (G, 'outer', 'sin', 'kind'), {'handle'});
%!test
%! assert_equal (row (G, 'outer', 'cos', 'kind'), {'string'});
%!test
%! assert_equal (row (G, 'outer', 'Base', 'kind'), {'constructor'});
%!test
%! assert_equal (row (G, 'outer', 'Base.go', 'kind'), {'method'});
%!test
%! assert_equal (row (G, 'outer', 'Base.get.Val', 'kind'), {'getter'});
%!test
%! assert_equal (row (G, 'outer', 'Base.set.Val', 'kind'), {'setter'});
%!test
%! assert_equal (row (G, 'outer', 'Base.plus', 'kind'), {'operator'});
%!test
%! assert_equal (row (G, 'outer', 'Base.subsref', 'kind'), {'subsref'});
%!test
%! k = strcmp (G.Edges.from, 'Sub') & strcmp (G.Edges.kind, 'constructor');
%! assert_equal (G.Edges.to(k), {'Base'});
%!test
%! assert_equal (row (G, 'Sub.spin', 'Base.spin', 'kind'), {'method'});
%!test
%! k = strcmp (G.Edges.from, 'Sub') & strcmp (G.Edges.kind, 'inherit');
%! assert_equal (G.Edges.to(k), {'Base'});
%!test
%! assert_equal (edge (G, 'outer', 'x', 'unresolved'), true);

## Dispatch
%!test
%! assert_equal (edge (G, 'Base.go', 'Base.spin', 'candidates'), true);
%!test
%! assert_equal (edge (G, 'Base.go', 'Sub.spin', 'candidates'), true);
%!test
%! assert_equal (edge (G, 'outer', 'Sub.spin', 'candidates'), true);
%!test
%! k = strcmp (G.Edges.from, 'outer') & strcmp (G.Edges.to, 'Sub.spin');
%! assert_equal (sort (G.Edges.certainty(k))', {'candidates', 'certain'});
%!test
%! assert_equal (edge (G, 'outer', 'columns', 'candidates'), true);
%!test
%! assert_equal (any (strcmp (G.Edges.to, 'Base.columns')), false);
%!test
%! assert_equal (edge (G, 'outer', 'columns', 'certain'), true);

## Attributes of an edge
%!test
%! assert_equal (row (G, 'outer', 'numel', 'nargout'), 0);
%!test
%! assert_equal (row (G, 'outer', 'size', 'nargout'), 2);
%!test
%! assert_equal (row (G, 'outer', 'isempty', 'nargout'), 1);
%!test
%! assert_equal (isnan (row (G, 'outer', 'sin', 'nargout')), true);
%!test
%! assert_equal (row (G, 'outer', 'abs', 'varargin'), true);
%!test
%! assert_equal (row (G, 'outer', 'floor', 'varargin'), false);
%!test
%! assert_equal (row (G, 'outer', 'floor', 'guard'), {'isempty (x)'});
%!test
%! assert_equal (row (G, 'outer', 'ceil', 'guard'), {'! (isempty (x))'});
%!test
%! assert_equal (row (G, 'outer', 'round', 'guard'), {'x == 1'});
%!test
%! assert_equal (row (G, 'outer', 'abs', 'guard'), {''});
%!test
%! assert_equal (row (G, 'outer', 'floor', 'line'), 12);
%!test
%! assert_equal (row (G, 'outer', 'floor', 'file'), {'inst/outer.m'});

## Tests
%!test
%! assert_equal (row (G, 'outer', 'outer', 'test'), true);
%!test
%! assert_equal (row (G, 'outer', 'floor', 'test'), false);
%!test
%! assert_equal (any (strcmp (G.Edges.to, 'zork')), false);

## Forms
%!function tf = form (G, TEXT)
%!  tf = any (strcmp (G.Forms.form, TEXT));
%!endfunction

%!function r = formField (G, TEXT, FIELD)
%!  r = G.Forms.(FIELD)(strcmp (G.Forms.form, TEXT));
%!endfunction

%!test
%! assert_equal (form (G, 'r = docd (x)'), true);
%!test
%! assert_equal (form (G, 'r = docd (x, y)'), true);
%!test
%! assert_equal (form (G, '[r, s] = docd (x, y)'), true);
%!test
%! assert_equal (form (G, 'r = docd (x, y, w)'), true);
%!test
%! assert_equal (form (G, 'r = docd (x, w)'), true);
%!test
%! assert_equal (form (G, 'docd (ax, x, y)'), true);
%!test
%! assert_equal (formField (G, '[r, s] = docd (x, y)', 'nargin'), 2);
%!test
%! assert_equal (formField (G, '[r, s] = docd (x, y)', 'nargout'), 2);
%!test
%! assert_equal (formField (G, 'docd (ax, x, y)', 'nargout'), 0);
%!test
%! assert_equal (formField (G, 'r = docd (x)', 'node'), {'docd'});
%!test
%! assert_equal (formField (G, 'r = docd (x)', 'file'), {'inst/docd.m'});
%!test
%! assert_equal (form (G, '[r, s] = docd (x, "Weights")'), true);
%!test
%! F = '[r, s] = docd (x, "Weights")';
%! assert_equal (formField (G, F, 'option'), {'Weights'});
%!test
%! assert_equal (formField (G, '[r, s] = docd (x, "Weights")', 'value'), {''});
%!test
%! assert_equal (formField (G, '[r, s] = docd (x, "Mode", "on")', 'value'), ...
%!               {'on'});
%!test
%! assert_equal (form (G, '[r, s] = docd (x, "Mode", "off")'), true);
%!test
%! assert_equal (form (G, '[r, s] = docd (x, "Kind", "b")'), true);
%!test
%! assert_equal (formField (G, 'o = Base (x)', 'node'), {'Base'});
%!test
%! assert_equal (form (G, 'y = Base.go (this)'), true);
%!test
%! assert_equal (formField (G, 'y = Sub.go (this)', 'node'), {'Base.go'});
%!test
%! assert_equal (any (strcmp (G.Forms.node, 'Abs.zap')), false);
%!test
%! assert_equal (any (strcmp (G.Forms.node, 'private/hidden')), false);
%!test
%! assert_equal (issorted (G.Forms.form), true);

## Paths
%!function tf = hasRow (R, FROM, TO)
%!  tf = any (strcmp (R.edges.from, FROM) & strcmp (R.edges.to, TO));
%!endfunction

%!function s = rowStatus (R, FROM, TO)
%!  s = R.edges.status(strcmp (R.edges.from, FROM) & strcmp (R.edges.to, TO));
%!endfunction

%!function s = formStatus (R, TEXT)
%!  s = R.forms.status(strcmp (R.forms.form, TEXT));
%!endfunction

%!test
%! R = paths (G, 'To', 'hidden');
%! assert_equal (R.to, {'private/hidden'});
%!test
%! R = paths (G, 'To', 'hidden');
%! assert_equal (hasRow (R, 'outer', 'private/hidden'), true);
%!test
%! R = paths (G, 'To', 'hidden');
%! assert_equal (ismember ('inst/outer.m', R.files.file), true);
%!test
%! R = paths (G, 'From', 'go');
%! assert_equal (R.from, {'Base.go'});
%!test
%! R = paths (G, 'From', {'go', 'outer'});
%! assert_equal (sort (R.from), {'Base.go'; 'outer'});
%!test
%! R = paths (G, 'From', 'Base.go');
%! assert_equal (rowStatus (R, 'Base.go', 'Sub.spin'), {'possible'});
%!test
%! R = paths (G, 'From', 'Base.go');
%! assert_equal (formStatus (R, 'y = Base.go (this)'), {'certain'});
%!test
%! R = paths (G, 'From', 'Base');
%! assert_equal (rowStatus (R, 'Base.go', 'Base.spin'), {'certain'});
%!test
%! R = paths (G, 'From', 'Base');
%! assert_equal (hasRow (R, 'Base.go', 'Sub.spin'), false);
%!test
%! R = paths (G, 'From', 'Sub');
%! assert_equal (rowStatus (R, 'Base.go', 'Sub.spin'), {'certain'});
%!test
%! R = paths (G, 'From', 'Sub');
%! assert_equal (hasRow (R, 'Base.go', 'Base.spin'), false);
%!test
%! R = paths (G, 'From', 'Sub');
%! assert_equal (ismember ('Base.go', R.from), true);
%!test
%! R = paths (G, 'From', 'Sub');
%! assert_equal (formStatus (R, 'y = Sub.go (this)'), {'certain'});
%!test
%! R = paths (G, 'From', 'Sub');
%! assert_equal (hasRow (R, 'Sub', 'Base'), true);
%!test
%! R = paths (G, 'From', 'y = Sub.go (this)');
%! assert_equal (rowStatus (R, 'Base.go', 'Sub.spin'), {'certain'});
%!test
%! R = paths (G, 'To', 'Sub.spin');
%! assert_equal (formStatus (R, 'y = Base.go (this)'), {'possible'});
%!test
%! R = paths (G, 'From', 'Base.go', 'To', 'Base.spin');
%! assert_equal (hasRow (R, 'Base.go', 'Base.spin'), true);
%!test
%! R = paths (G, 'From', 'Base.go', 'To', 'Base.spin');
%! assert_equal (hasRow (R, 'Sub.spin', 'Base.spin'), true);
%!test
%! R = paths (G, 'From', 'docd', 'To', 'Base.spin');
%! assert_equal (isempty (R.edges.from), true);

## A form narrows its node by its counts
%!test
%! R = paths (G, 'From', 'docd (ax, x, y)');
%! assert_equal (hasRow (R, 'docd', 'plot'), true);
%!test
%! R = paths (G, 'From', 'r = docd (x)');
%! assert_equal (hasRow (R, 'docd', 'plot'), false);
%!test
%! R = paths (G, 'From', 'docd');
%! assert_equal (hasRow (R, 'docd', 'plot'), true);

## Nargout, tests, a call whose class is not settled, an unresolved call
%!test
%! R = paths (G, 'To', 'numel', 'Nargout', 0);
%! assert_equal (hasRow (R, 'outer', 'numel'), true);
%!test
%! R = paths (G, 'To', 'numel', 'Nargout', 1);
%! assert_equal (hasRow (R, 'outer', 'numel'), false);
%!test
%! R = paths (G, 'To', 'outer');
%! assert_equal (hasRow (R, 'outer', 'outer'), false);
%!test
%! R = paths (G, 'To', 'outer', 'Tests', true);
%! assert_equal (hasRow (R, 'outer', 'outer'), true);
%!test
%! R = paths (G, 'To', 'Base.columns');
%! assert_equal (rowStatus (R, 'outer', 'columns'), {'possible'});
%!test
%! R = paths (G, 'To', 'columns');
%! assert_equal (R.to, {'columns'});
%!test
%! R = paths (G, 'From', 'docd');
%! assert_equal (rowStatus (R, 'docd', 'nosuch'), {'incomplete'});
%!test
%! R = paths (G, 'From', 'docd');
%! assert_equal (formStatus (R, 'r = docd (x)'), {'incomplete'});
%!test
%! R = paths (G, 'To', 'floor');
%! assert_equal (formStatus (R, 'r = docd (x)'), {'incomplete'});
%!test
%! s = evalc ('paths (G, ''From'', ''Base.go'')');
%! assert_equal (! isempty (strfind (s, 'y = Base.go (this)')), true);

## Sets
%!test
%! C = nodes (G, '^inst/Base.m/Base\.go$');
%! assert_equal (C, {'Base.go'});
%!test
%! C = nodes (G, 'private/');
%! assert_equal (C, {'private/hidden'});
%!test
%! C = nodes (G, 'zznothing');
%! assert_equal (isempty (C), true);
%!test
%! assert_equal (sort (subclasses (G, 'Base')), {'Base'; 'Sub'});
%!test
%! assert_equal (subclasses (G, 'Sub'), {'Sub'});

## Chains
%!test
%! R = paths (G, 'From', 'Base.go', 'To', 'Base.spin');
%! C = chains (G, R);
%! assert_equal (sort (C), {'Base.go > Base.spin'; ...
%!                          'Base.go > Sub.spin > Base.spin'});
%!test
%! R = paths (G, 'From', 'Base.go', 'To', 'Base.spin');
%! [~, done] = chains (G, R);
%! assert_equal (done, true);
%!test
%! R = paths (G, 'From', 'Base.go', 'To', 'Base.spin');
%! [C, done] = chains (G, R, 1);
%! assert_equal (numel (C), 1);
%!test
%! R = paths (G, 'From', 'Base.go', 'To', 'Base.spin');
%! [~, done] = chains (G, R, 1);
%! assert_equal (done, false);

## What a run did
%!function n = seenCount (T, FROM, TO)
%!  n = sum (strcmp (T.Seen.from, FROM) & strcmp (T.Seen.to, TO));
%!endfunction

%!function n = callCount (T, FORM, OUT, CLS)
%!  n = sum (strcmp (T.Calls.form, FORM) & T.Calls.output == OUT
%!           & strcmp (T.Calls.class, CLS));
%!endfunction

%!test
%! assert_equal (P, path ());
%!test
%! assert_equal (seenCount (T, 'tfun', 'tfun>helper') > 0, true);
%!test
%! assert_equal (seenCount (T, 'tfun>helper', 'tobj') > 0, true);
%!test
%! assert_equal (seenCount (T, 'tfun', 'tobj.val') > 0, true);
%!test
%! assert_equal (seenCount (T, 'tfun', 'tfun') > 0, true);
%!test
%! assert_equal (seenCount (T, 'tobj', 'tobj.val') > 0, true);
%!test
%! assert_equal (callCount (T, 'r = tfun (x)', 1, 'tobj') > 0, true);
%!test
%! assert_equal (callCount (T, '[r, s] = tfun (x, y)', 2, 'double'), 1);
%!test
%! assert_equal (callCount (T, '[r, s] = tfun (x, y)', 1, 'tobj'), 0);
%!test
%! assert_equal (callCount (T, 'v = tobj.val (this)', 1, 'double'), 1);
%!test
%! assert_equal (callCount (T, 'o = tobj (x)', 1, 'tobj'), 1);
%!test
%! k = strcmp (T.Calls.call, 'tfun (1)') & T.Calls.output == 0;
%! assert_equal (T.Calls.form(k), {''});
%!test
%! R = paths (T, 'From', 'tfun');
%! assert_equal (rowStatus (R, 'tfun', 'tobj.val'), {'certain'});
%!test
%! R = paths (T, 'From', 'tfun');
%! assert_equal (rowStatus (R, 'tfun', 'uobj.val'), {'possible'});
%!test
%! F = tempname ();
%! write (T, F);
%! H = devtools.callGraph.read (F);
%! confirm_recursive_rmdir (false, 'local');
%! rmdir (F, 's');
%! assert_equal (isequaln (H.Seen, T.Seen), true);
%!test
%! F = tempname ();
%! write (T, F);
%! H = devtools.callGraph.read (F);
%! confirm_recursive_rmdir (false, 'local');
%! rmdir (F, 's');
%! assert_equal (isequaln (H.Calls, T.Calls), true);
%!test
%! F = tempname ();
%! write (T, F);
%! H = devtools.callGraph.read (F);
%! confirm_recursive_rmdir (false, 'local');
%! rmdir (F, 's');
%! R = paths (H, 'From', 'tfun');
%! assert_equal (rowStatus (R, 'tfun', 'tobj.val'), {'certain'});

## Narrowed by the blocks that ran a form
%!test
%! R = paths (T, 'From', '[r, s] = tfun (x, y)');
%! k = strcmp (R.edges.from, 'tfun') & strcmp (R.edges.to, 'tobj.val');
%! assert_equal (R.edges.ran(k), true);
%!test
%! R = paths (T, 'From', 'tobj.val');
%! assert_equal (isfield (R.edges, 'ran'), true);

## Gaps
%!function n = gapCount (R, RULE, TEXT)
%!  k = strcmp ({R.rule}, RULE);
%!  n = sum (! cellfun (@isempty, strfind ({R(k).message}, TEXT)));
%!endfunction

%!test
%! D = traced ();
%! H = trace (devtools.callGraph (D));
%! R = gaps (H);
%! confirm_recursive_rmdir (false, 'local');
%! rmdir (D, 's');
%! assert_equal (gapCount (R, 'no-form', 'tfun (1)'), 1);
%!test
%! D = traced ();
%! H = trace (devtools.callGraph (D));
%! R = gaps (H);
%! confirm_recursive_rmdir (false, 'local');
%! rmdir (D, 's');
%! assert_equal (gapCount (R, 'uncertain', 'uobj.val'), 1);
%!test
%! D = traced ();
%! H = trace (devtools.callGraph (D));
%! R = gaps (H);
%! confirm_recursive_rmdir (false, 'local');
%! rmdir (D, 's');
%! assert_equal (gapCount (R, 'no-bist', 'tobj'), 0);

## One call
%!test
%! D = traced ();
%! G2 = devtools.callGraph (D);
%! R = traceCall (G2, @() tfun (1));
%! confirm_recursive_rmdir (false, 'local');
%! rmdir (D, 's');
%! assert_equal (R.from, {'tfun'});
%!test
%! D = traced ();
%! G2 = devtools.callGraph (D);
%! R = traceCall (G2, @() tfun (1));
%! confirm_recursive_rmdir (false, 'local');
%! rmdir (D, 's');
%! k = strcmp (R.edges.from, 'tfun') & strcmp (R.edges.to, 'tfun>helper');
%! assert_equal (R.edges.kind(k), {'call'});
%!test
%! D = traced ();
%! G2 = devtools.callGraph (D);
%! P2 = path ();
%! traceCall (G2, @() tfun (1));
%! assert_equal (path (), P2);
%! confirm_recursive_rmdir (false, 'local');
%! rmdir (D, 's');

## Drawing
%!function T = dotText (G, varargin)
%!  F = [tempname(), '.dot'];
%!  draw (G, varargin{:}, F);
%!  T = fileread (F);
%!  unlink (F);
%!endfunction

%!function T = dotOption (G, varargin)
%!  F = [tempname(), '.dot'];
%!  draw (G, F, varargin{:});
%!  T = fileread (F);
%!  unlink (F);
%!endfunction

%!test
%! txt = dotText (G);
%! assert_equal (strncmp (txt, 'digraph callGraph {', 19), true);
%!test
%! txt = dotText (G);
%! k = strfind (txt, '"inst/outer.m" -> "inst/Base.m"');
%! assert_equal (! isempty (k), true);
%!test
%! txt = dotOption (G, 'Level', 'class');
%! assert_equal (! isempty (strfind (txt, '"Sub" -> "Base"')), true);
%!test
%! txt = dotOption (G, 'Level', 'folder');
%! assert_equal (! isempty (strfind (txt, '"inst" -> "inst/+ns"')), true);
%!test
%! R = paths (G, 'From', 'Base.go');
%! txt = dotText (G, R);
%! k = strfind (txt, '"Base.go" -> "Sub.spin" [style=dashed]');
%! assert_equal (! isempty (k), true);
%!test
%! R = paths (G, 'From', 'Base.go');
%! txt = dotText (G, R);
%! assert_equal (! isempty (strfind (txt, 'subgraph')), true);
%!test
%! R = paths (G, 'From', 'docd');
%! txt = dotText (G, R);
%! assert_equal (! isempty (strfind (txt, 'style=dotted, color=red')), true);
%!test
%! R = paths (G, 'From', 'docd');
%! txt = dotText (G, R);
%! assert_equal (! isempty (strfind (txt, '"plot"')), true);
%!test
%! R = paths (G, 'From', 'docd');
%! F = [tempname(), '.dot'];
%! draw (G, R, F, 'Core', false);
%! txt = fileread (F);
%! unlink (F);
%! assert_equal (isempty (strfind (txt, '"plot"')), true);

## Each of these is a small package of its own
## A continuation line is no element of a list
%!test
%! H = read_pack ('ml.m', "function [a, b, c] = ml (x)\nendfunction\n", ...
%!                'c1.m', ["function c1 ()\n  [p, q, ...\n", ...
%!                         "   r] = ml (1);\nend\n"]);
%! assert_equal (row (H, 'c1', 'ml', 'nargout'), 3);
%!test
%! H = read_pack ('K.m', ["classdef K\n  methods\n", ...
%!                        "    function y = fit (a, b)\n    end\n", ...
%!                        "  end\nend\n"], ...
%!                'c2.m', ["function c2 (x)\n  o = K ();\n", ...
%!                         "  y = fit ('x', ...\n           o);\nend\n"]);
%! assert_equal (edge (H, 'c2', 'K.fit', 'certain'), true);

## Output counts no site settles
%!test
%! H = read_pack ('a2.m', "function y = a2 (x)\nend\n", ...
%!                'c3.m', ["function varargout = c3 (x)\n", ...
%!                         "  [varargout{1:nargout}] = a2 (x);\nend\n"]);
%! assert_equal (isnan (row (H, 'c3', 'a2', 'nargout')), true);

## Guards
%!test
%! H = read_pack ('c4.m', ["function y = c4 (x)\n", ...
%!                         "  if ((nargin == 1) && (x > 0))\n  else\n", ...
%!                         "    floor (x);\n  endif\nend\n"]);
%! assert_equal (row (H, 'c4', 'floor', 'guard'), ...
%!               {'! ((nargin == 1) && (x > 0))'});
%!test
%! H = read_pack ('c5.m', ["function y = c5 (x)\n", ...
%!                         "  if ((nargin == 1) && (x > 0))\n", ...
%!                         "    floor (x);\n  endif\nend\n"]);
%! assert_equal (row (H, 'c5', 'floor', 'guard'), {'(nargin == 1) && (x > 0)'});

## Output counts along a path
%!test
%! R = paths (Q, 'To', 'plot');
%! assert_equal (R.forms.form, {'pl (x)'});
%!test
%! R = paths (Q, 'From', 'r = pl (x)');
%! assert_equal (hasRow (R, 'pl', 'plot'), false);
%!test
%! R = paths (Q, 'From', 'caller');
%! assert_equal (hasRow (R, 'pl', 'plot'), false);
%!test
%! R = paths (Q, 'From', 'pl');
%! assert_equal (hasRow (R, 'pl', 'plot'), true);

## Option forms count their pair
%!test
%! H = read_pack ('opt.m', ["## -*- texinfo -*-\n", ...
%!                          "## @deftypefn  {small} {@var{y} =} opt (x)\n", ...
%!                          '## @deftypefnx {small} {@var{y} =} opt (x, ', ...
%!                          "@var{Name}, @var{Value})\n", ...
%!                          "## @multitable @columnfractions 0.5 0.5\n", ...
%!                          "## @headitem Name @tab Value\n", ...
%!                          "## @item @qcode{'Alpha'} @tab A number.\n", ...
%!                          "## @end multitable\n## @end deftypefn\n", ...
%!                          "function y = opt (x, varargin)\n", ...
%!                          "  if (nargin > 1)\n    sum (x);\n  endif\nend\n"]);
%! assert_equal (H.Forms.nargin(strcmp (H.Forms.option, 'Alpha')), 3);
%!test
%! H = read_pack ('opt2.m', ["## -*- texinfo -*-\n", ...
%!                           "## @deftypefn  {small} {y =} opt2 (x)\n", ...
%!                           '## @deftypefnx {small} {@var{y} =} opt2 (x, ', ...
%!                           "@var{Name}, @var{Value})\n", ...
%!                           "## @multitable @columnfractions 0.5 0.5\n", ...
%!                           "## @headitem Name @tab Value\n", ...
%!                           "## @item @qcode{'Alpha'} @tab A number.\n", ...
%!                           "## @end multitable\n## @end deftypefn\n", ...
%!                           "function y = opt2 (x, varargin)\n", ...
%!                           "  if (nargin > 1)\n    sum (x);\n", ...
%!                           "  endif\nend\n"]);
%! R = paths (H, 'From', 'y = opt2 (x, "Alpha")');
%! assert_equal (hasRow (R, 'opt2', 'sum'), true);

## Inheritance
%!test
%! assert_equal (paths (G, 'From', 'Sub.go').from, {'Base.go'});
%!test
%! H = read_pack ('A.m', ["classdef A\n  methods\n", ...
%!                        "    ## -*- texinfo -*-\n", ...
%!                        "    ## @deftypefn {A} {@var{y} =} mm (this)\n", ...
%!                        "    ## @end deftypefn\n", ...
%!                        "    function y = mm (this)\n    end\n", ...
%!                        "  end\nend\n"], ...
%!                'B.m', ["classdef B < A\n  methods\n", ...
%!                        "    function y = mm (this)\n    end\n", ...
%!                        "  end\nend\n"], ...
%!                'C.m', "classdef C < B\nend\n");
%! assert_equal (any (strcmp (H.Forms.form, 'y = C.mm (this)')), false);

## A package with no forms, a result with no edges
%!test
%! H = read_pack ('plain.m', "function plain ()\nend\n");
%! R = paths (H, 'From', 'plain');
%! assert_equal (R.from, {'plain'});
%!test
%! H = read_pack ('plain.m', "function plain ()\nend\n");
%! assert_equal (chains (H, paths (H, 'To', 'plain')), cell (0, 1));

## A handle given to feval settles the call
%!test
%! H = read_pack ('a2.m', "function y = a2 (x)\nend\n", ...
%!                'c6.m', "function c6 ()\n  feval (@a2, 1);\nend\n");
%! assert_equal (any (strcmp (H.Edges.certainty, 'unresolved')), false);

## A file can reach what no reading settled
%!test
%! R = paths (G, 'From', 'docd');
%! k = strcmp (R.files.file, 'inst/docd.m');
%! assert_equal (R.files.status(k), {'incomplete'});

## Accessors on a variable of more than one class
%!test
%! H = read_pack ('Ba.m', ["classdef Ba\n  properties\n    Val = 1;\n", ...
%!                         "  end\n  methods\n", ...
%!                         "    function y = get.Val (this)\n    end\n", ...
%!                         "  end\nend\n"], ...
%!                'Ot.m', ["classdef Ot\n  properties\n    Val = 1;\n", ...
%!                         "  end\n  methods\n", ...
%!                         "    function y = get.Val (this)\n    end\n", ...
%!                         "  end\nend\n"], ...
%!                'c7.m', ["function c7 (f)\n  if (f)\n    o = Ba ();\n", ...
%!                         "  else\n    o = Ot ();\n  endif\n", ...
%!                         "  y = o.Val;\nend\n"]);
%! assert_equal (edge (H, 'c7', 'Ot.get.Val', 'candidates'), true);

## What a form returned
%!test
%! R = paths (T, 'From', 'tfun', 'Returns', 'tobj');
%! assert_equal (ismember ('r = tfun (x)', R.forms.form), true);
%!test
%! R = paths (T, 'From', 'tfun', 'Returns', 'object');
%! assert_equal (ismember ('r = tfun (x)', R.forms.form), true);
%!test
%! R = paths (T, 'From', 'tfun', 'Returns', 'cell');
%! assert_equal (ismember ('r = tfun (x)', R.forms.form), false);

## The rewriting holds where a target or an argument is not plain
%!function H = rewritten ()
%!  H = run_pack ('tf.m', ["## -*- texinfo -*-\n", ...
%!                         "## @deftypefn  {small} {@var{y} =} tf (x)\n", ...
%!                         '## @deftypefnx {small} {@var{y} =} tf (x, ', ...
%!                         "@var{Name}, @var{Value})\n", ...
%!                         "## @multitable @columnfractions 0.5 0.5\n", ...
%!                         "## @headitem Name @tab Value\n", ...
%!                         '## @item @qcode{''Mode''} @tab Must be ', ...
%!                         "@qcode{'on'} or @qcode{'off'}.\n", ...
%!                         "## @end multitable\n## @end deftypefn\n", ...
%!                         "function [y, z] = tf (x, varargin)\n  y = x;\n", ...
%!                         "  z = 2;\nendfunction\n", ...
%!                         "%!test\n%! a = [];\n%! a(end+1) = tf (1);\n", ...
%!                         "%!test\n%! c = {1};\n%! y = tf (c{:});\n", ...
%!                         "%!test\n%! x = 1;\n%! x = tf (x);\n", ...
%!                         "%!test\n%! [p, ...\n%!  q] = tf (1);\n", ...
%!                         "%!test\n%! y = tf (1, 'Mode', 'on');\n", ...
%!                         "%!test\n%! tf = 3;\n", ...
%!                         "%!test\n%! y = tf (2);\n", ...
%!                         "%!warning <zz> warning ('zz');\n"]);
%!endfunction

%!test
%! H = rewritten ();
%! assert_equal (sum (H.Tested.passed), sum (H.Tested.total));
%!test
%! H = rewritten ();
%! assert_equal (any (strcmp (H.Calls.form, 'y = tf (x, "Mode", "on")')), true);
%!test
%! H = rewritten ();
%! k = strcmp (H.Calls.form, 'y = tf (x, "Mode", "off")');
%! assert_equal (any (k), false);
%!test
%! H = rewritten ();
%! assert_equal (any (strcmp (H.Calls.call, 'tf (2)')), true);
%!test
%! H = rewritten ();
%! assert_equal (H.Calls.line(strcmp (H.Calls.call, 'tf (2)')), 30);

## Test files, and folders with no PKG_ADD
%!test
%! D = pack ('sub/foo.m', "function y = foo ()\n  y = 1;\nendfunction\n", ...
%!           'tests/foo.m-tst', "%!test\n%! assert_equal (foo (), 1);\n");
%! H = trace (devtools.callGraph (D));
%! confirm_recursive_rmdir (false, 'local');
%! rmdir (D, 's');
%! assert_equal (H.Tested.passed, 1);
%!test
%! D = pack ('sub/foo.m', "function y = foo ()\n  y = 1;\nendfunction\n", ...
%!           'tests/foo.m-tst', "%!test\n%! assert_equal (foo (), 1);\n");
%! H = trace (devtools.callGraph (D));
%! confirm_recursive_rmdir (false, 'local');
%! rmdir (D, 's');
%! assert_equal (seenCount (H, 'foo', 'foo') > 0, true);

## Every edge a run saw is in the graph
%!test
%! n = numel (T.Nodes.node);
%! k = strcmp (T.Seen.from, 'tfun') | strcmp (T.Seen.from, 'tfun>helper');
%! seen = unique (strcat (T.Seen.from(k), '>', T.Seen.to(k)));
%! read = unique (strcat (T.Edges.from, '>', T.Edges.to));
%! assert_equal (all (ismember (seen, read)), true);

## One call
%!test
%! D = pack ('pl.m', ["function r = pl (x)\n  r = 1;\n", ...
%!                    "  if (nargout == 0)\n    floor (x);\n  endif\nend\n"]);
%! H = devtools.callGraph (D);
%! R0 = traceCall (H, @() pl (1));
%! R1 = traceCall (H, @() pl (1), 1);
%! confirm_recursive_rmdir (false, 'local');
%! rmdir (D, 's');
%! assert_equal ([hasRow(R0, 'pl', 'floor'), hasRow(R1, 'pl', 'floor')], ...
%!               [true, false]);
%!test
%! D = pack ('bad.m', "function bad ()\n  error ('stop');\nend\n");
%! H = devtools.callGraph (D);
%! before = {path(), get(0, 'defaultfigurevisible')};
%! try
%!   traceCall (H, @() bad ());
%! catch
%! end_try_catch
%! after = {path(), get(0, 'defaultfigurevisible')};
%! confirm_recursive_rmdir (false, 'local');
%! rmdir (D, 's');
%! assert_equal (after, before);

## Chains that end exactly at the limit are complete
%!test
%! R = paths (G, 'From', 'Sub.spin', 'To', 'Base.spin');
%! [C, done] = chains (G, R, 1);
%! assert_equal (done, true);

## A folder written over holds this run only
%!test
%! F = tempname ();
%! write (T, F);
%! write (G, F);
%! H = devtools.callGraph.read (F);
%! confirm_recursive_rmdir (false, 'local');
%! rmdir (F, 's');
%! assert_equal (isfield (H.Seen, 'from'), false);

## Merged levels
%!test
%! F = [tempname(), '.dot'];
%! draw (G, F, 'Core', true);
%! txt = fileread (F);
%! unlink (F);
%! assert_equal (! isempty (strfind (txt, '"floor"')), true);
%!test
%! F = [tempname(), '.dot'];
%! draw (G, F);
%! txt = fileread (F);
%! unlink (F);
%! assert_equal (! isempty (strfind (txt, 'color=red')), true);
%!test
%! F = [tempname(), '.dot'];
%! draw (G, F);
%! txt = fileread (F);
%! unlink (F);
%! assert_equal (! isempty (strfind (txt, 'tooltip="inst/outer.m:')), true);

## Selecting what is shown
%!function H = two_packages (G)
%!  F = tempname ();
%!  write (G, F);
%!  name = fullfile (F, 'nodes.csv');
%!  txt = strrep (fileread (name), ',tiny,inst/Base.m', ',dep,inst/Base.m');
%!  fid = fopen (name, 'w');
%!  fputs (fid, txt);
%!  fclose (fid);
%!  H = devtools.callGraph.read (F);
%!  confirm_recursive_rmdir (false, 'local');
%!  rmdir (F, 's');
%!endfunction

%!function H = two_classes ()
%!  c = ["  methods\n    function y = mm (this)\n      y = 1;\n", ...
%!       "    end\n  end\nend\n"];
%!  H = run_pack ('A.m', ["classdef A\n", c], 'B.m', ["classdef B\n", c], ...
%!                'f.m', ["function y = f (x)\n  y = mm (x);\nend\n", ...
%!                        "%!test\n%! z = f (A ());\n"]);
%!endfunction

%!function H = stray_calls ()
%!  H = read_pack ('A/a.m', "function a ()\n  c ();\n  c ();\nend\n", ...
%!                 'C/c.m', "function c ()\nend\n");
%!endfunction

%!test
%! R = paths (G, 'From', 'outer');
%! assert_equal (hasRow (R, 'outer', 'floor'), true);
%!test
%! R = paths (G, 'From', 'outer', 'Core', false);
%! assert_equal (hasRow (R, 'outer', 'floor'), false);
%!test
%! R = paths (G, 'To', 'floor', 'Core', false);
%! assert_equal (hasRow (R, 'outer', 'floor'), true);
%!test
%! R = paths (G, 'From', 'docd');
%! assert_equal (any (strcmp (R.edges.to, 'nosuch')), true);
%!test
%! R = paths (G, 'From', 'docd', 'Unresolved', false);
%! assert_equal (any (strcmp (R.edges.to, 'nosuch')), false);
%!test
%! R = paths (G, 'From', 'docd', 'Unresolved', false);
%! assert_equal (any (strcmp (R.forms.status, 'incomplete')), true);
%!test
%! R = paths (G, 'From', 'outer', 'Kinds', 'call');
%! assert_equal (unique (R.edges.kind), {'call'});
%!test
%! R = paths (G, 'From', {'Sub', 'Base'}, 'Kinds', 'inherit');
%! assert_equal (hasRow (R, 'Sub', 'Base'), true);
%!test
%! R = paths (G, 'From', {'Sub', 'Base'}, 'Kinds', 'inherit');
%! assert_equal (unique (R.edges.kind), {'inherit'});
%!test
%! R = paths (G, 'From', 'Base.go');
%! assert_equal (hasRow (R, 'Base.go', 'Sub.spin'), true);
%!test
%! R = paths (G, 'From', 'Base.go', 'Certainty', 'certain');
%! assert_equal (hasRow (R, 'Base.go', 'Sub.spin'), false);
%!test
%! R = paths (G, 'From', 'Base', 'Certainty', 'certain');
%! assert_equal (hasRow (R, 'Base.go', 'Base.spin'), true);
%!test
%! R = paths (two_classes (), 'From', 'f', 'Certainty', 'proven');
%! assert_equal (hasRow (R, 'f', 'A.mm'), true);
%!test
%! R = paths (two_classes (), 'From', 'f', 'Certainty', 'proven');
%! assert_equal (hasRow (R, 'f', 'B.mm'), false);
%!test
%! R = paths (two_classes (), 'From', 'f', 'Certainty', 'certain');
%! assert_equal (hasRow (R, 'f', 'A.mm'), false);
%!test
%! R = paths (two_classes (), 'To', 'B.mm', 'Certainty', 'proven');
%! assert_equal (hasRow (R, 'f', 'B.mm'), false);
%!test
%! R = paths (two_packages (G), 'From', 'outer');
%! assert_equal (hasRow (R, 'Base.go', 'Base.spin'), true);
%!test
%! R = paths (two_packages (G), 'From', 'outer', 'Scope', 'package');
%! assert_equal (hasRow (R, 'Base.go', 'Base.spin'), false);
%!test
%! R = paths (two_packages (G), 'From', 'outer', 'Scope', 'package');
%! assert_equal (hasRow (R, 'outer', 'Base.go'), true);
%!test
%! R = paths (G, 'From', 'outer');
%! assert_equal (isempty (R.links.from), true);
%!test
%! R = paths (G, 'From', 'outer', 'Level', 'folder');
%! k = strcmp (R.links.from, 'inst') & strcmp (R.links.to, 'inst/+ns');
%! assert_equal (R.links.weight(k), 1);
%!test
%! R = paths (stray_calls (), 'From', 'a', 'Level', 'folder');
%! assert_equal (R.links.weight, 2);
%!test
%! R = paths (stray_calls (), 'From', 'a', 'Level', 'folder', ...
%!            'Weight', 'files');
%! assert_equal (R.links.weight, 1);
%!test
%! R = paths (stray_calls (), 'From', 'a', 'Weight', 'files');
%! assert_equal ([R.links.from, R.links.to], {'a', 'c'});
%!test
%! txt = evalc ("paths (stray_calls (), 'From', 'a', 'Level', 'folder')");
%! assert_equal (! isempty (strfind (txt, '2  inst/A -> inst/C')), true);
%!test
%! txt = dotOption (G);
%! assert_equal (! isempty (strfind (txt, '"floor"')), true);
%!test
%! txt = dotOption (G, 'Core', false);
%! assert_equal (isempty (strfind (txt, '"floor"')), true);
%!test
%! txt = dotOption (G, 'Level', 'node');
%! assert_equal (isempty (strfind (txt, '"outer" -> "outer"')), true);
%!test
%! txt = dotText (G, paths (G, 'To', 'outer', 'Tests', true));
%! assert_equal (! isempty (strfind (txt, '"outer" -> "outer"')), true);
%!test
%! txt = dotOption (G, 'Level', 'node', 'Certainty', 'certain');
%! assert_equal (isempty (strfind (txt, '"Base.go" -> "Sub.spin"')), true);
%!test
%! F = [tempname(), '.dot'];
%! draw (two_classes (), F, 'Level', 'node', 'Certainty', 'proven');
%! txt = fileread (F);
%! unlink (F);
%! assert_equal (! isempty (strfind (txt, '"f" -> "A.mm"')), true);
%!test
%! F = [tempname(), '.dot'];
%! draw (two_classes (), F, 'Level', 'node', 'Certainty', 'proven');
%! txt = fileread (F);
%! unlink (F);
%! assert_equal (isempty (strfind (txt, '"f" -> "B.mm"')), true);
%!test
%! txt = dotOption (G, 'Unresolved', false);
%! assert_equal (isempty (strfind (txt, 'color=red')), true);
%!test
%! txt = dotOption (G, 'Level', 'class', 'Kinds', 'inherit');
%! assert_equal (! isempty (strfind (txt, '"Sub" -> "Base" [arrowhead')), true);
%!test
%! txt = dotOption (G, 'Level', 'class', 'Kinds', 'inherit');
%! assert_equal (isempty (strfind (txt, 'penwidth')), true);
%!test
%! txt = dotOption (two_packages (G), 'Level', 'node');
%! assert_equal (! isempty (strfind (txt, '"Base.go" -> ')), true);
%!test
%! txt = dotOption (two_packages (G), 'Level', 'node', 'Scope', 'package');
%! assert_equal (isempty (strfind (txt, '"Base.go" -> ')), true);
%!test
%! txt = dotOption (two_packages (G), 'Level', 'node', 'Scope', 'package');
%! assert_equal (! isempty (strfind (txt, '"outer" -> "Base.go"')), true);
%!test
%! txt = dotOption (stray_calls (), 'Level', 'folder');
%! assert_equal (! isempty (strfind (txt, 'penwidth=1.30')), true);
%!test
%! txt = dotOption (stray_calls (), 'Level', 'folder', 'Weight', 'files');
%! assert_equal (! isempty (strfind (txt, 'penwidth=1.00')), true);
%!test
%! R = paths (G, 'From', 'Base.go');
%! F = [tempname(), '.dot'];
%! draw (G, R, F, 'Certainty', 'certain');
%! txt = fileread (F);
%! unlink (F);
%! assert_equal (isempty (strfind (txt, '"Base.go" -> "Sub.spin"')), true);
%!test
%! R = paths (G, 'From', 'Base');
%! F = [tempname(), '.dot'];
%! draw (G, R, F, 'Certainty', 'certain');
%! txt = fileread (F);
%! unlink (F);
%! assert_equal (! isempty (strfind (txt, '"Base.go" -> "Base.spin"')), true);

## Which branches a form leaves out
%!function H = guarded ()
%!  H = read_pack ('gd.m', ...
%!    ["## -*- texinfo -*-\n", ...
%!     "## @deftypefn  {small} {} gd (@var{x})\n", ...
%!     "## @deftypefnx {small} {@var{y} =} gd (@var{x})\n", ...
%!     "## @deftypefnx {small} {@var{y} =} gd (@var{x}, @var{z})\n", ...
%!     "## @end deftypefn\n", ...
%!     "function y = gd (x, z)\n", ...
%!     "  if (nargout == 0)\n    floor (1);\n  endif\n", ...
%!     "  if (! (nargin > 1))\n    ceil (1);\n  endif\n", ...
%!     "  if (x > 0 && nargin > 1)\n    round (1);\n  endif\n", ...
%!     "  if (nargin == 2 && x > 0 || isempty (x))\n", ...
%!     "    fix (1);\n  endif\n", ...
%!     "  if ((nargin == 2 || x) && nargout > 1)\n    abs (1);\n  endif\n", ...
%!     "  if (! (nargin == 1 && x))\n    sign (1);\n  endif\nend\n"]);
%!endfunction

%!test
%! R = paths (guarded (), 'From', 'y = gd (x)');
%! assert_equal (hasRow (R, 'gd', 'floor'), false);
%!test
%! R = paths (guarded (), 'From', 'gd (x)');
%! assert_equal (hasRow (R, 'gd', 'floor'), true);
%!test
%! R = paths (guarded (), 'From', 'gd');
%! assert_equal (hasRow (R, 'gd', 'floor'), true);
%!test
%! R = paths (guarded (), 'From', 'y = gd (x, z)');
%! assert_equal (hasRow (R, 'gd', 'ceil'), false);
%!test
%! R = paths (guarded (), 'From', 'y = gd (x)');
%! assert_equal (hasRow (R, 'gd', 'ceil'), true);
%!test
%! R = paths (guarded (), 'From', 'y = gd (x)');
%! assert_equal (hasRow (R, 'gd', 'round'), false);
%!test
%! R = paths (guarded (), 'From', 'y = gd (x)');
%! assert_equal (hasRow (R, 'gd', 'fix'), true);
%!test
%! R = paths (guarded (), 'From', 'y = gd (x)');
%! assert_equal (hasRow (R, 'gd', 'abs'), false);
%!test
%! R = paths (guarded (), 'From', 'y = gd (x)');
%! assert_equal (hasRow (R, 'gd', 'sign'), true);
%!test
%! H = read_pack ('gw.m', ...
%!   ["## -*- texinfo -*-\n", ...
%!    "## @deftypefn {small} {@var{y} =} gw (@var{x})\n", ...
%!    "## @end deftypefn\n", ...
%!    "function y = gw (x)\n", ...
%!    "  if (((nargout > 1)))\n    abs (1);\n  endif\nend\n"]);
%! R = paths (H, 'From', 'y = gw (x)');
%! assert_equal (hasRow (R, 'gw', 'abs'), false);

## A name core defines, however it is defined
%!test
%! H = read_pack ('a.m', "function a ()\n  p = inputParser ();\nend\n");
%! assert_equal (H.Nodes.kind{strcmp (H.Nodes.node, 'inputParser')}, 'core');

## Options in any case, and what a link says
%!test
%! R = paths (G, 'From', 'outer', 'SCOPE', 'package');
%! assert_equal (hasRow (R, 'outer', 'floor'), true);
%!test
%! R = paths (G, 'From', 'docd', 'Level', 'file');
%! assert_equal (R.links.status(strcmp (R.links.to, 'nosuch')), {'incomplete'});
%!test
%! R = paths (G, 'From', 'Base.go', 'Weight', 'files');
%! k = strcmp (R.links.from, 'Base.go') & strcmp (R.links.to, 'Sub.spin');
%! assert_equal (R.links.status(k), {'possible'});
%!test
%! R = paths (G, 'From', 'docd', 'Level', 'file');
%! assert_equal (any (strcmp (R.links.to, 'plot')), true);
%!test
%! R = paths (G, 'From', 'docd', 'Level', 'file', 'Core', false);
%! assert_equal (any (strcmp (R.links.to, 'plot')), false);

## Both ways around a set, and how far
%!function H = chain_pack ()
%!  H = read_pack ('a.m', "function a ()\n  b ();\nend\n", ...
%!                 'b.m', "function b ()\n  c ();\nend\n", ...
%!                 'c.m', "function c ()\n  d ();\nend\n", ...
%!                 'd.m', "function d ()\n  e ();\nend\n", ...
%!                 'e.m', "function e ()\nend\n", ...
%!                 'u.m', "function u ()\n  nosuch ();\nend\n", ...
%!                 'r.m', "function r ()\n  r ();\nend\n");
%!endfunction

%!test
%! R = paths (chain_pack (), 'Around', 'c');
%! assert_equal (hasRow (R, 'a', 'b') && hasRow (R, 'd', 'e'), true);
%!test
%! R = paths (chain_pack (), 'Around', 'c');
%! assert_equal (R.from, {'c'});
%!test
%! R = paths (chain_pack (), 'Around', 'c');
%! assert_equal (isempty (R.to), true);
%!test
%! R = paths (chain_pack (), 'Around', 'r');
%! assert_equal (numel (R.edges.from(strcmp (R.edges.to, 'r'))), 1);
%!test
%! R = paths (chain_pack (), 'Around', 'c', 'Depth', 1);
%! assert_equal (hasRow (R, 'b', 'c') && hasRow (R, 'c', 'd'), true);
%!test
%! R = paths (chain_pack (), 'Around', 'c', 'Depth', 1);
%! assert_equal (hasRow (R, 'a', 'b') || hasRow (R, 'd', 'e'), false);
%!test
%! R = paths (chain_pack (), 'From', 'a', 'Depth', 2);
%! assert_equal (hasRow (R, 'b', 'c'), true);
%!test
%! R = paths (chain_pack (), 'From', 'a', 'Depth', 2);
%! assert_equal (hasRow (R, 'c', 'd'), false);
%!test
%! R = paths (chain_pack (), 'To', 'e', 'Depth', 1);
%! assert_equal (hasRow (R, 'd', 'e'), true);
%!test
%! R = paths (chain_pack (), 'To', 'e', 'Depth', 1);
%! assert_equal (hasRow (R, 'c', 'd'), false);
%!test
%! R = paths (chain_pack (), 'To', 'e');
%! assert_equal (any (strcmp (R.edges.to, 'nosuch')), true);
%!test
%! R = paths (chain_pack (), 'To', 'e', 'Depth', 1);
%! assert_equal (any (strcmp (R.edges.to, 'nosuch')), false);
%!test
%! R = paths (G, 'To', 'floor');
%! assert_equal (any (strcmp (R.forms.status, 'incomplete')), true);
%!test
%! R = paths (G, 'To', 'floor', 'Depth', 1);
%! assert_equal (any (strcmp (R.forms.status, 'incomplete')), false);
%!test
%! R = paths (chain_pack (), 'From', 'a', 'Depth', Inf);
%! assert_equal (hasRow (R, 'd', 'e'), true);
%!test
%! R = paths (G, 'Around', 'Base.go');
%! assert_equal (numel (unique (R.forms.form)), numel (R.forms.form));
%!test
%! R = paths (G, 'Around', 'Base.go');
%! assert_equal (numel (unique (R.files.file)), numel (R.files.file));
%!test
%! H = chain_pack ();
%! txt = dotText (H, paths (H, 'Around', 'c', 'Depth', 1));
%! assert_equal (! isempty (strfind (txt, '"b" -> "c"')), true);
%!test
%! H = chain_pack ();
%! txt = dotText (H, paths (H, 'Around', 'c', 'Depth', 1));
%! assert_equal (isempty (strfind (txt, '"a" -> "b"')), true);
%!test
%! H = chain_pack ();
%! C = chains (H, paths (H, 'Around', 'c'));
%! assert_equal (numel (C), 1);
%!test
%! R = paths (chain_pack (), 'Around', 'c', 'Level', 'file', ...
%!            'Unresolved', false);
%! assert_equal (numel (R.links.from), 4);

## A header naming nothing, and a file that does not parse
%!function R = orphanGaps (NAME)
%!  D = pack ('a.m', ["## -*- texinfo -*-\n", ...
%!                    "## @deftypefn {small} {} ", NAME, " (@var{x})\n", ...
%!                    "## @end deftypefn\n", ...
%!                    "function a ()\nend\n%!test\n%! a ();\n"]);
%!  R = gaps (trace (devtools.callGraph (D)));
%!  confirm_recursive_rmdir (false, 'local');
%!  rmdir (D, 's');
%!endfunction

%!test
%! R = orphanGaps ('zork');
%! assert_equal (gapCount (R, 'no-node', 'zork'), 1);
%!test
%! R = orphanGaps ('zork');
%! k = strcmp ({R.rule}, 'no-node');
%! assert_equal ({R(k).file, R(k).line}, {'inst/a.m', 2});
%!test
%! R = orphanGaps ('a');
%! assert_equal (any (strcmp ({R.rule}, 'no-node')), false);
%!test
%! H = read_pack ('bad.m', "function y = (((\n");
%! txt = evalc ("disp (H)");
%! assert_equal (! isempty (strfind (txt, 'inst/bad.m')), true);

## A method on an object built in the call, and a switch over an input
%!function H = builtInPlace ()
%!  doc = ["    ## -*- texinfo -*-\n", ...
%!         "    ## @deftypefn {KA} {@var{y} =} go (@var{this})\n", ...
%!         "    ## @end deftypefn\n"];
%!  H = run_pack ('KA.m', ["classdef KA\n  methods\n", doc, ...
%!                         "    function y = go (this)\n      y = 1;\n", ...
%!                         "    end\n  end\nend\n", ...
%!                         "%!test\n%! z = go (KA ());\n"]);
%!endfunction

%!test
%! H = builtInPlace ();
%! assert_equal (any (strcmp (H.Calls.form, 'y = KA.go (this)')), true);

%!function R = optionsAndInput (LABEL)
%!  D = pack ('f.m', ["## -*- texinfo -*-\n", ...
%!                    "## @deftypefn  {s} {@var{y} =} f (@var{kind})\n", ...
%!                    "## @deftypefnx {s} {@var{y} =} f (@var{kind}, ", ...
%!                    "@var{Name}, @var{Value})\n##\n", ...
%!                    "## @multitable @columnfractions 0.5 0.5\n", ...
%!                    "## @headitem @var{Name} @tab @var{Value}\n", ...
%!                    "## @item @qcode{'Tol'} @tab A number.\n", ...
%!                    "## @end multitable\n## @end deftypefn\n", ...
%!                    "function y = f (kind, name, value)\n  y = 1;\n", ...
%!                    "  switch (kind)\n    case 'aa'\n      y = 2;\n", ...
%!                    "  endswitch\n  if (nargin > 1)\n", ...
%!                    "    switch (name)\n      case '", LABEL, "'\n", ...
%!                    "        y = 3;\n    endswitch\n  endif\nend\n", ...
%!                    "%!test\n%! y = f ('aa');\n"]);
%!  R = gaps (trace (devtools.callGraph (D)));
%!  confirm_recursive_rmdir (false, 'local');
%!  rmdir (D, 's');
%!endfunction

%!test
%! R = optionsAndInput ('hidden');
%! assert_equal (gapCount (R, 'undocumented-option', "'hidden'"), 1);
%!test
%! R = optionsAndInput ('hidden');
%! assert_equal (gapCount (R, 'undocumented-option', "'aa'"), 0);

## What a call does not settle
%!function H = callsAbsOfAnExpression ()
%!  doc = ["    ## -*- texinfo -*-\n", ...
%!         "    ## @deftypefn {KB} {@var{y} =} abs (@var{this})\n", ...
%!         "    ## @end deftypefn\n"];
%!  H = run_pack ('KB.m', ["classdef KB\n  methods\n", doc, ...
%!                         "    function y = abs (this)\n      y = 1;\n", ...
%!                         "    end\n  end\nend\n", ...
%!                         "%!test\n%! z = abs (floor (-1));\n"]);
%!endfunction

%!function H = optionFromAVariable ()
%!  H = run_pack ('g.m', ["## -*- texinfo -*-\n", ...
%!                        "## @deftypefn  {s} {@var{y} =} g (@var{x})\n", ...
%!                        "## @deftypefnx {s} {@var{y} =} g (@var{x}, ", ...
%!                        "@var{Name}, @var{Value})\n##\n", ...
%!                        "## @multitable @columnfractions 0.5 0.5\n", ...
%!                        "## @headitem @var{Name} @tab @var{Value}\n", ...
%!                        "## @item @qcode{'Mode'} @tab Must be ", ...
%!                        "@qcode{'on'} or @qcode{'off'}.\n", ...
%!                        "## @end multitable\n## @end deftypefn\n", ...
%!                        "function y = g (x, varargin)\n  y = 1;\nend\n", ...
%!                        "%!test\n%! v = 'on';\n", ...
%!                        "%! y = g (1, 'Mode', v);\n", ...
%!                        "%!test\n%! y = g (1, 'Mode', 'off');\n"]);
%!endfunction

%!test
%! H = callsAbsOfAnExpression ();
%! k = ! cellfun (@isempty, strfind (H.Calls.call, 'abs'));
%! assert_equal (any (k), false);
%!test
%! H = optionFromAVariable ();
%! assert_equal (sum (strcmp (H.Calls.form, '?')), 1);
%!test
%! H = optionFromAVariable ();
%! assert_equal (any (strcmp (H.Calls.form, 'y = g (x, "Mode", "off")')), true);

## Writing and reading
%!test
%! F = tempname ();
%! write (G, F);
%! H = devtools.callGraph.read (F);
%! confirm_recursive_rmdir (false, 'local');
%! rmdir (F, 's');
%! assert_equal (isequaln (H.Edges, G.Edges), true);
%!test
%! F = tempname ();
%! write (G, F);
%! H = devtools.callGraph.read (F);
%! confirm_recursive_rmdir (false, 'local');
%! rmdir (F, 's');
%! assert_equal (isequaln (H.Nodes, G.Nodes), true);
%!test
%! F = tempname ();
%! write (G, F);
%! H = devtools.callGraph.read (F);
%! confirm_recursive_rmdir (false, 'local');
%! rmdir (F, 's');
%! assert_equal (isequaln (H.Forms, G.Forms), true);
%!test
%! F = tempname ();
%! write (G, F);
%! H = devtools.callGraph.read (F);
%! confirm_recursive_rmdir (false, 'local');
%! rmdir (F, 's');
%! assert_equal (H.Package, G.Package);
%!test
%! F = tempname ();
%! write (G, F);
%! t = fileread (fullfile (F, 'run.csv'));
%! confirm_recursive_rmdir (false, 'local');
%! rmdir (F, 's');
%! assert_equal (strncmp (t, "package,version,octave,date\n", 28), true);

%!error<devtools.callGraph: TARGET must be a character vector.> ...
%! devtools.callGraph (5)
%!error<devtools.callGraph: TARGET is neither a package source folder nor an installed package: 'zznope'> ...
%! devtools.callGraph ('zznope')
%!error<devtools.callGraph: TARGET is neither a package source folder nor an installed package: '.*docLint.m'> ...
%! devtools.callGraph (which ('devtools.docLint'))
%!error<devtools.callGraph: dependency is not installed: 'zzmissing'> ...
%! D = tempname ();
%! mkdir (D);
%! write_file (D, 'DESCRIPTION', ...
%!             "Name: t\nVersion: 1\nDepends: zzmissing (>= 1)\n");
%! unwind_protect
%!   devtools.callGraph (D);
%! unwind_protect_cleanup
%!   confirm_recursive_rmdir (false, 'local');
%!   rmdir (D, 's');
%! end_unwind_protect
%!error<devtools.callGraph.write: invalid number of input arguments.> ...
%! write (devtools.callGraph ())
%!error<devtools.callGraph.write: FOLDER must be a character vector.> ...
%! write (devtools.callGraph (), 5)
%!error<devtools.callGraph.trace: the graph is empty.> ...
%! trace (devtools.callGraph ())
%!error<devtools.callGraph.trace: NAMES must be a cell array of names.> ...
%! trace (T, 5)
%!error<devtools.callGraph.trace: no BISTs in: 'zznope'> ...
%! trace (T, {'zznope'})
%!error<devtools.callGraph.gaps: no BIST run yet: use trace first.> ...
%! gaps (G)
%!error<devtools.callGraph.traceCall: invalid number of input arguments.> ...
%! traceCall (G)
%!error<devtools.callGraph.traceCall: FCN must be a function handle taking no arguments.> ...
%! traceCall (G, 5)
%!error<devtools.callGraph.traceCall: the graph is empty.> ...
%! traceCall (devtools.callGraph (), @() 1)
%!error<devtools.callGraph.traceCall: NOUT must be a non-negative integer.> ...
%! traceCall (G, @() 1, -1)
%!error<devtools.callGraph.nodes: the graph is empty.> ...
%! nodes (devtools.callGraph (), 'x')
%!error<devtools.callGraph.write: the graph is empty.> ...
%! write (devtools.callGraph (), 'x')
%!error<devtools.callGraph.draw: an option name must be a character vector.> ...
%! draw (G, 'x.dot', 5, 1)
%!error<devtools.callGraph.paths: 'Nargout' needs a 'To' set.> ...
%! paths (G, 'From', 'outer', 'Nargout', 1)
%!error<devtools.callGraph.paths: no BIST run yet: use trace first.> ...
%! paths (G, 'From', 'outer', 'Returns', 'object')
%!error<devtools.callGraph.draw: invalid number of input arguments.> ...
%! draw (G)
%!error<devtools.callGraph.draw: R must be a result of paths.> ...
%! draw (G, struct ('a', 1), 'x.dot')
%!error<devtools.callGraph.draw: FILE must be a character vector.> ...
%! draw (G, 5)
%!error<devtools.callGraph.draw: unknown file type: '.png'> ...
%! draw (G, 'x.png')
%!error<devtools.callGraph.draw: options come in Name, Value pairs.> ...
%! draw (G, 'x.dot', 'Level')
%!error<devtools.callGraph.draw: unknown level: 'zap'> ...
%! draw (G, 'x.dot', 'Level', 'zap')
%!error<devtools.callGraph.draw: 'Core' must be a logical scalar.> ...
%! draw (G, 'x.dot', 'Core', 1)
%!error<devtools.callGraph.draw: unknown option: 'Zap'> ...
%! draw (G, 'x.dot', 'Zap', 1)
%!error<devtools.callGraph.paths: give 'From', 'To', both or 'Around'.> ...
%! paths (G)
%!error<devtools.callGraph.paths: options come in Name, Value pairs.> ...
%! paths (G, 'From')
%!error<devtools.callGraph.paths: an option name must be a character vector.> ...
%! paths (G, 5, 'x')
%!error<devtools.callGraph.paths: unknown option: 'Zap'> ...
%! paths (G, 'Zap', 'x')
%!error<devtools.callGraph.paths: 'From' must be a name or a form, or a cell array of those, and not empty.> ...
%! paths (G, 'From', 5)
%!error<devtools.callGraph.paths: 'To' must be a name or a form, or a cell array of those, and not empty.> ...
%! paths (G, 'To', {})
%!error<devtools.callGraph.paths: 'Tests' must be a logical scalar.> ...
%! paths (G, 'From', 'outer', 'Tests', 1)
%!error<devtools.callGraph.paths: 'Around' goes alone, without 'From' or 'To'.> ...
%! paths (G, 'Around', 'outer', 'From', 'outer')
%!error<devtools.callGraph.paths: 'Around' goes alone, without 'From' or 'To'.> ...
%! paths (G, 'Around', 'outer', 'To', 'outer')
%!error<devtools.callGraph.paths: 'Around' must be a name or a form, or a cell> ...
%! paths (G, 'Around', 5)
%!error<devtools.callGraph.paths: 'Depth' needs one direction, or 'Around'.> ...
%! paths (G, 'From', 'outer', 'To', 'floor', 'Depth', 1)
%!error<devtools.callGraph.paths: 'Depth' must be a positive integer or Inf.> ...
%! paths (G, 'From', 'outer', 'Depth', 0)
%!error<devtools.callGraph.paths: 'Depth' must be a positive integer or Inf.> ...
%! paths (G, 'From', 'outer', 'Depth', 1.5)
%!error<devtools.callGraph.paths: 'Depth' must be a positive integer or Inf.> ...
%! paths (G, 'From', 'outer', 'Depth', 'a')
%!error<devtools.callGraph.paths: 'Nargout' needs a 'To' set.> ...
%! paths (G, 'Around', 'outer', 'Nargout', 1)
%!error<devtools.callGraph.paths: 'Scope' must be a character vector.> ...
%! paths (G, 'From', 'outer', 'Scope', 1)
%!error<devtools.callGraph.paths: unknown scope: 'zap'.> ...
%! paths (G, 'From', 'outer', 'Scope', 'zap')
%!error<devtools.callGraph.paths: 'Core' must be a logical scalar.> ...
%! paths (G, 'From', 'outer', 'Core', 1)
%!error<devtools.callGraph.paths: 'Certainty' must be a character vector.> ...
%! paths (G, 'From', 'outer', 'Certainty', 1)
%!error<devtools.callGraph.paths: unknown certainty: 'zap'.> ...
%! paths (G, 'From', 'outer', 'Certainty', 'zap')
%!error<devtools.callGraph.paths: 'Unresolved' must be a logical scalar.> ...
%! paths (G, 'From', 'outer', 'Unresolved', 1)
%!error<devtools.callGraph.paths: 'Kinds' must be an edge kind or a cell> ...
%! paths (G, 'From', 'outer', 'Kinds', 1)
%!error<devtools.callGraph.paths: unknown edge kind: 'zap'.> ...
%! paths (G, 'From', 'outer', 'Kinds', {'call', 'zap'})
%!error<devtools.callGraph.paths: 'Level' must be a character vector.> ...
%! paths (G, 'From', 'outer', 'Level', 1)
%!error<devtools.callGraph.paths: unknown level: 'zap'.> ...
%! paths (G, 'From', 'outer', 'Level', 'zap')
%!error<devtools.callGraph.paths: 'Weight' must be a character vector.> ...
%! paths (G, 'From', 'outer', 'Weight', 1)
%!error<devtools.callGraph.paths: unknown weight: 'zap'.> ...
%! paths (G, 'From', 'outer', 'Weight', 'zap')
%!error<devtools.callGraph.draw: unknown option: 'Tests'> ...
%! draw (G, 'x.dot', 'Tests', true)
%!error<devtools.callGraph.draw: unknown scope: 'zap'.> ...
%! draw (G, 'x.dot', 'Scope', 'zap')
%!error<devtools.callGraph.draw: unknown weight: 'zap'.> ...
%! draw (G, 'x.dot', 'Weight', 'zap')
%!error<devtools.callGraph.paths: 'Nargout' must be a non-negative integer.> ...
%! paths (G, 'To', 'outer', 'Nargout', -1)
%!error<devtools.callGraph.paths: no such name in the graph: 'zznope'> ...
%! paths (G, 'From', 'zznope')
%!error<devtools.callGraph.paths: the graph is empty.> ...
%! paths (devtools.callGraph (), 'From', 'x')
%!error<devtools.callGraph.nodes: invalid number of input arguments.> ...
%! nodes (G)
%!error<devtools.callGraph.nodes: PATTERN must be a character vector.> ...
%! nodes (G, 5)
%!error<devtools.callGraph.subclasses: invalid number of input arguments.> ...
%! subclasses (G)
%!error<devtools.callGraph.subclasses: CLASS must be a character vector.> ...
%! subclasses (G, 5)
%!error<devtools.callGraph.subclasses: no such class: 'outer'> ...
%! subclasses (G, 'outer')
%!error<devtools.callGraph.chains: invalid number of input arguments.> ...
%! chains (G)
%!error<devtools.callGraph.chains: R must be a result of paths.> ...
%! chains (G, 5)
%!error<devtools.callGraph.chains: LIMIT must be a positive number.> ...
%! chains (G, paths (G, 'From', 'outer'), 0)
%!error<devtools.callGraph.read: invalid number of input arguments.> ...
%! devtools.callGraph.read ()
%!error<devtools.callGraph.read: FOLDER must be a character vector.> ...
%! devtools.callGraph.read (5)
%!error<devtools.callGraph.read: no such file: '.*nodes.csv'> ...
%! devtools.callGraph.read (tempname ())
%!error<devtools.callGraph.read: wrong columns in '.*nodes.csv'> ...
%! F = tempname ();
%! mkdir (F);
%! write_file (F, 'nodes.csv', "a,b\n1,2\n");
%! unwind_protect
%!   devtools.callGraph.read (F);
%! unwind_protect_cleanup
%!   confirm_recursive_rmdir (false, 'local');
%!   rmdir (F, 's');
%! end_unwind_protect
