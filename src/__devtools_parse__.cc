/* Parse Octave source with the vendored tree-sitter grammar.
 *
 * Copyright (C) 2026 Andreas Bertsatos <abertsatos@biol.uoa.gr>
 *
 * This file is part of the devtools package for GNU Octave.
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the GNU Free
 * Software Foundation; either version 3 of the License, or (at your option) any
 * later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program; if not, see <http://www.gnu.org/licenses/>.
 */

#include <octave/oct.h>
#include <octave/ov-struct.h>
#include <tree_sitter/api.h>
#include <string>
#include <vector>

extern "C" const TSLanguage *tree_sitter_octave (void);
extern "C" const TSLanguage *tree_sitter_octave_strict (void);
extern "C" const TSLanguage *tree_sitter_matlab_strict (void);

/* One oct-file carries all three: the parsers export distinct symbols and
   the runtime is shared, so this costs two compilations rather than two more
   builds and two more loads.

   Naming a dialect restricts the parse, so the lenient grammar has no name:
   it is what an omitted argument gets.  The exported names keep their longer
   form because a grammar exporting tree_sitter_matlab would collide with the
   existing MATLAB grammar were both ever linked into one program. */
static const TSLanguage *
language_for (const std::string& dialect)
{
  if (dialect == "octave")
    return tree_sitter_octave_strict ();
  if (dialect == "matlab")
    return tree_sitter_matlab_strict ();
  return nullptr;
}

struct Fault
{
  std::string kind;
  uint32_t row;
  uint32_t column;
};

/* Walk the whole tree once, collecting the nodes that mark a parse the
   grammar could not complete.  A cursor is used rather than recursion: a
   deeply nested file would otherwise be bounded by the C stack. */
static void
collect_faults (TSNode root, std::vector<Fault>& faults)
{
  TSTreeCursor cursor = ts_tree_cursor_new (root);
  bool descended = true;

  for (;;)
    {
      if (descended)
        {
          TSNode node = ts_tree_cursor_current_node (&cursor);
          if (ts_node_is_error (node) || ts_node_is_missing (node))
            {
              TSPoint point = ts_node_start_point (node);
              Fault fault;
              fault.kind = (ts_node_is_missing (node) ? "missing" : "error");
              fault.row = point.row + 1;
              fault.column = point.column + 1;
              faults.push_back (fault);
            }
        }

      if (descended && ts_tree_cursor_goto_first_child (&cursor))
        continue;
      if (ts_tree_cursor_goto_next_sibling (&cursor))
        {
          descended = true;
          continue;
        }
      if (! ts_tree_cursor_goto_parent (&cursor))
        break;
      descended = false;
    }

  ts_tree_cursor_delete (&cursor);
}

/* The source a node spans, or empty past LIMIT bytes: the queries below
   want names and short expressions, never a whole function body. */
static std::string
node_text (const std::string& text, TSNode node, uint32_t limit = 512)
{
  uint32_t a = ts_node_start_byte (node);
  uint32_t b = ts_node_end_byte (node);
  if (b < a || b > text.size () || b - a > limit)
    return "";
  return text.substr (a, b - a);
}

/* The field a node occupies in its parent, or empty. */
static std::string
field_in_parent (TSNode node)
{
  TSNode parent = ts_node_parent (node);
  if (ts_node_is_null (parent))
    return "";
  uint32_t n = ts_node_child_count (parent);
  for (uint32_t i = 0; i < n; i++)
    if (ts_node_eq (ts_node_child (parent, i), node))
      {
        const char *f = ts_node_field_name_for_child (parent, i);
        return (f == nullptr ? "" : f);
      }
  return "";
}

/* One node as the queries report it.  The name, parameter, output and
   superclass fields are filled for the node types that carry them and stay
   empty elsewhere. */
struct Rec
{
  std::string type, field, text, name, arg1;
  uint32_t srow = 0, scol = 0, erow = 0, ecol = 0;
  uint32_t nrow = 0, ncol = 0, nerow = 0, necol = 0;
  std::vector<std::string> params, outputs, supers;
  bool is_static = false;
  double parent = 0;
};

static std::vector<std::string>
identifiers_of (const std::string& text, TSNode node)
{
  std::vector<std::string> out;
  if (ts_node_is_null (node))
    return out;
  if (std::string (ts_node_type (node)) == "identifier")
    {
      out.push_back (node_text (text, node));
      return out;
    }
  uint32_t n = ts_node_named_child_count (node);
  for (uint32_t i = 0; i < n; i++)
    {
      TSNode c = ts_node_named_child (node, i);
      std::string t = ts_node_type (c);
      if (t == "identifier" || t == "qualified_name")
        out.push_back (node_text (text, c));
    }
  return out;
}

/* True where a methods block carries Static, bare or not set to false. */
static bool
block_is_static (const std::string& text, TSNode block)
{
  TSNode attrs = ts_node_child_by_field_name (block, "attributes", 10);
  if (ts_node_is_null (attrs))
    return false;
  uint32_t n = ts_node_named_child_count (attrs);
  for (uint32_t i = 0; i < n; i++)
    {
      TSNode a = ts_node_named_child (attrs, i);
      TSNode nm = ts_node_child_by_field_name (a, "name", 4);
      if (ts_node_is_null (nm) || node_text (text, nm) != "Static")
        continue;
      TSNode val = ts_node_child_by_field_name (a, "value", 5);
      return (ts_node_is_null (val) || node_text (text, val) != "false");
    }
  return false;
}

static Rec
describe (const std::string& text, TSNode node)
{
  Rec r;
  r.type = ts_node_type (node);
  r.field = field_in_parent (node);
  r.text = node_text (text, node);
  TSPoint s = ts_node_start_point (node);
  TSPoint e = ts_node_end_point (node);
  r.srow = s.row;  r.scol = s.column;
  r.erow = e.row;  r.ecol = e.column;

  TSNode name = ts_node_child_by_field_name (node, "name", 4);
  if (! ts_node_is_null (name))
    {
      r.name = node_text (text, name);
      TSPoint ns = ts_node_start_point (name);
      TSPoint ne = ts_node_end_point (name);
      r.nrow = ns.row;  r.ncol = ns.column;
      r.nerow = ne.row;  r.necol = ne.column;
    }

  if (r.type == "function_definition")
    {
      TSNode ps = ts_node_child_by_field_name (node, "parameters", 10);
      r.params = identifiers_of (text, ps);
      TSNode out = ts_node_child_by_field_name (node, "output", 6);
      r.outputs = identifiers_of (text, out);
      TSNode block = ts_node_parent (node);
      if (! ts_node_is_null (block)
          && std::string (ts_node_type (block)) == "methods_block")
        r.is_static = block_is_static (text, block);
    }
  else if (r.type == "classdef_definition")
    {
      TSNode sl = ts_node_child_by_field_name (node, "superclasses", 12);
      r.supers = identifiers_of (text, sl);
    }
  else if (r.type == "methods_block")
    r.is_static = block_is_static (text, node);
  else if (r.type == "index_expression")
    {
      /* The first argument, the one a call dispatches on */
      TSNode value = ts_node_child_by_field_name (node, "value", 5);
      uint32_t n = ts_node_named_child_count (node);
      for (uint32_t i = 0; i < n; i++)
        {
          TSNode c = ts_node_named_child (node, i);
          if (! ts_node_is_null (value) && ts_node_eq (c, value))
            continue;
          if (std::string (ts_node_type (c)) == "identifier")
            r.arg1 = node_text (text, c);
          break;
        }
    }
  return r;
}

static Cell
cellstr (const std::vector<std::string>& v)
{
  Cell c (dim_vector (1, static_cast<octave_idx_type> (v.size ())));
  for (std::size_t i = 0; i < v.size (); i++)
    c(i) = octave_value (v[i]);
  return c;
}

static octave_map
records_map (const std::vector<Rec>& recs)
{
  octave_idx_type n = static_cast<octave_idx_type> (recs.size ());
  const char *names[] = {"type", "field", "text", "name", "arg1", "srow",
                         "scol", "erow", "ecol", "nrow", "ncol", "nerow",
                         "necol", "params", "outputs", "supers", "static",
                         "parent"};
  octave_map m (dim_vector (n, 1));
  std::vector<Cell> cols (18, Cell (dim_vector (n, 1)));
  for (octave_idx_type i = 0; i < n; i++)
    {
      const Rec& r = recs[i];
      cols[0](i) = r.type;
      cols[1](i) = r.field;
      cols[2](i) = r.text;
      cols[3](i) = r.name;
      cols[4](i) = r.arg1;
      cols[5](i) = static_cast<double> (r.srow);
      cols[6](i) = static_cast<double> (r.scol);
      cols[7](i) = static_cast<double> (r.erow);
      cols[8](i) = static_cast<double> (r.ecol);
      cols[9](i) = static_cast<double> (r.nrow);
      cols[10](i) = static_cast<double> (r.ncol);
      cols[11](i) = static_cast<double> (r.nerow);
      cols[12](i) = static_cast<double> (r.necol);
      cols[13](i) = cellstr (r.params);
      cols[14](i) = cellstr (r.outputs);
      cols[15](i) = cellstr (r.supers);
      cols[16](i) = r.is_static;
      cols[17](i) = r.parent;
    }
  for (int k = 0; k < 18; k++)
    m.setfield (names[k], cols[k]);
  return m;
}

/* The named nodes enclosing a point, innermost first.  A cursor just past
   the end of a name, where an editor leaves it after typing, finds the
   enclosing node rather than the name, so one column back is tried then. */
static std::vector<Rec>
chain_at (const std::string& text, TSNode root, uint32_t row, uint32_t col)
{
  TSPoint p = {row, col};
  TSNode node = ts_node_named_descendant_for_point_range (root, p, p);
  if (std::string (ts_node_type (node)) != "identifier" && col > 0)
    {
      TSPoint q = {row, col - 1};
      TSNode back = ts_node_named_descendant_for_point_range (root, q, q);
      if (std::string (ts_node_type (back)) == "identifier")
        node = back;
    }
  std::vector<Rec> recs;
  while (! ts_node_is_null (node))
    {
      Rec r = describe (text, node);
      recs.push_back (r);
      node = ts_node_parent (node);
    }
  for (std::size_t i = 0; i + 1 < recs.size (); i++)
    recs[i].parent = static_cast<double> (i + 2);
  return recs;
}

/* A file's classes, functions, methods and properties.  Only the containers
   are descended, never a statement, so a long body costs its top level. */
static void
collect_defs (const std::string& text, TSNode node, double parent,
              std::vector<Rec>& recs)
{
  uint32_t n = ts_node_named_child_count (node);
  for (uint32_t i = 0; i < n; i++)
    {
      TSNode c = ts_node_named_child (node, i);
      std::string t = ts_node_type (c);
      if (t == "classdef_definition" || t == "function_definition"
          || t == "property")
        {
          Rec r = describe (text, c);
          r.text = "";
          r.parent = parent;
          recs.push_back (r);
          double self = static_cast<double> (recs.size ());
          if (t != "property")
            collect_defs (text, c, self, recs);
        }
      else if (t == "methods_block" || t == "properties_block")
        collect_defs (text, c, parent, recs);
    }
}

DEFUN_DLD (__devtools_parse__, args, ,
           "-*- texinfo -*-\n\
@deftypefn  {devtools} {@var{R} =} __devtools_parse__ (@var{TEXT})\n\
@deftypefnx {devtools} {@var{R} =} __devtools_parse__ (@var{TEXT}, @var{DIALECT})\n\
\n\
Parse @var{TEXT}.  Internal; not a supported entry point.\n\
\n\
@var{DIALECT} is @qcode{'octave'}, which reads Octave written in its own\n\
spellings alone, or @qcode{'matlab'}, which reads MATLAB.  Omitting it reads\n\
either language, as Octave itself does, accepting the MATLAB spelling of\n\
everything that has two.  The lenient grammar has no name because naming a\n\
dialect is what restricts the parse.\n\
\n\
The exported names stay @code{tree_sitter_octave_strict} and\n\
@code{tree_sitter_matlab_strict}: a grammar exporting\n\
@code{tree_sitter_matlab} would collide with the existing MATLAB grammar\n\
were both ever linked into one program.\n\
\n\
@var{R} is a scalar structure holding @code{sexp}, the tree written as an\n\
s-expression, @code{ok}, true where the grammar completed the parse, and\n\
@code{faults}, a structure array of the nodes that stopped it, each with\n\
@code{kind}, @qcode{'error'} or @qcode{'missing'}, and a one-based\n\
@code{row} and @code{column}.\n\
\n\
Two queries follow the dialect, an empty @var{DIALECT} meaning the lenient\n\
grammar: @code{__devtools_parse__ (@var{TEXT}, @var{DIALECT}, 'at',\n\
@var{ROW}, @var{COL})} returns the named nodes enclosing a zero-based row and\n\
byte column, innermost first, and @code{__devtools_parse__ (@var{TEXT},\n\
@var{DIALECT}, 'defs')} the classes, functions, methods and properties of\n\
the text.  Both return a structure array; positions are zero-based and\n\
columns count bytes.\n\
\n\
@end deftypefn")
{
  int nargs = args.length ();
  if (nargs < 1 || nargs > 5)
    error ("__devtools_parse__: invalid number of input arguments.");
  if (! args(0).is_string ())
    error ("__devtools_parse__: TEXT must be a character vector.");

  const TSLanguage *language = tree_sitter_octave ();
  if (nargs >= 2)
    {
      if (! args(1).is_string ())
        error ("__devtools_parse__: DIALECT must be a character vector.");
      std::string dialect = args(1).string_value ();
      if (! dialect.empty ())
        {
          language = language_for (dialect);
          if (language == nullptr)
            error ("__devtools_parse__: unknown dialect: '%s'",
                   dialect.c_str ());
        }
    }

  std::string mode;
  uint32_t row = 0, col = 0;
  if (nargs >= 3)
    {
      if (! args(2).is_string ())
        error ("__devtools_parse__: MODE must be a character vector.");
      mode = args(2).string_value ();
      if (mode == "at")
        {
          if (nargs != 5)
            error ("__devtools_parse__: 'at' needs a ROW and a COL.");
          double r = args(3).double_value ();
          double c = args(4).double_value ();
          if (! (r >= 0 && c >= 0))
            error ("__devtools_parse__: ROW and COL must be non-negative.");
          row = static_cast<uint32_t> (r);
          col = static_cast<uint32_t> (c);
        }
      else if (mode == "defs")
        {
          if (nargs != 3)
            error ("__devtools_parse__: 'defs' takes no further argument.");
        }
      else
        error ("__devtools_parse__: unknown mode: '%s'", mode.c_str ());
    }

  std::string text = args(0).string_value ();

  TSParser *parser = ts_parser_new ();
  ts_parser_set_language (parser, language);
  TSTree *tree = ts_parser_parse_string (parser, nullptr, text.c_str (),
                                         static_cast<uint32_t> (text.size ()));
  if (tree == nullptr)
    {
      ts_parser_delete (parser);
      error ("__devtools_parse__: the parser returned no tree.");
    }

  TSNode root = ts_tree_root_node (tree);

  if (! mode.empty ())
    {
      std::vector<Rec> recs;
      if (mode == "at")
        recs = chain_at (text, root, row, col);
      else
        collect_defs (text, root, 0, recs);
      octave_map m = records_map (recs);
      ts_tree_delete (tree);
      ts_parser_delete (parser);
      return ovl (octave_value (m));
    }

  char *sexp = ts_node_string (root);
  std::string tree_text (sexp == nullptr ? "" : sexp);
  if (sexp != nullptr)
    free (sexp);

  std::vector<Fault> faults;
  collect_faults (root, faults);

  ts_tree_delete (tree);
  ts_parser_delete (parser);

  octave_idx_type n = static_cast<octave_idx_type> (faults.size ());
  Cell kinds (dim_vector (n, 1));
  Cell rows (dim_vector (n, 1));
  Cell columns (dim_vector (n, 1));
  for (octave_idx_type i = 0; i < n; i++)
    {
      kinds(i) = octave_value (faults[i].kind);
      rows(i) = octave_value (static_cast<double> (faults[i].row));
      columns(i) = octave_value (static_cast<double> (faults[i].column));
    }

  octave_map fault_map;
  fault_map.setfield ("kind", kinds);
  fault_map.setfield ("row", rows);
  fault_map.setfield ("column", columns);

  octave_scalar_map result;
  result.setfield ("sexp", octave_value (tree_text));
  result.setfield ("ok", octave_value (faults.empty ()));
  result.setfield ("faults", octave_value (fault_map));

  return ovl (octave_value (result));
}
