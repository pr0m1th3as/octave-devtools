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

DEFUN_DLD (__devtools_parse__, args, ,
           "-*- texinfo -*-\n\
@deftypefn {devtools} {@var{R} =} __devtools_parse__ (@var{TEXT})\n\
\n\
Parse @var{TEXT} as Octave source.  Internal; not a supported entry point.\n\
\n\
@var{R} is a scalar structure holding @code{sexp}, the tree written as an\n\
s-expression, @code{ok}, true where the grammar completed the parse, and\n\
@code{faults}, a structure array of the nodes that stopped it, each with\n\
@code{kind}, @qcode{'error'} or @qcode{'missing'}, and a one-based\n\
@code{row} and @code{column}.\n\
\n\
@end deftypefn")
{
  if (args.length () != 1)
    error ("__devtools_parse__: invalid number of input arguments.");
  if (! args(0).is_string ())
    error ("__devtools_parse__: TEXT must be a character vector.");

  std::string text = args(0).string_value ();

  TSParser *parser = ts_parser_new ();
  ts_parser_set_language (parser, tree_sitter_octave ());
  TSTree *tree = ts_parser_parse_string (parser, nullptr, text.c_str (),
                                         static_cast<uint32_t> (text.size ()));
  if (tree == nullptr)
    {
      ts_parser_delete (parser);
      error ("__devtools_parse__: the parser returned no tree.");
    }

  TSNode root = ts_tree_root_node (tree);
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
