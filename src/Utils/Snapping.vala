/*
* Copyright (c) 2019 Alecaddd (http://alecaddd.com)
*
* This file is part of Akira.
*
* Akira is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.

* Akira is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.

* You should have received a copy of the GNU General Public License
* along with Akira.  If not, see <https://www.gnu.org/licenses/>.
*
* Authored by: Martin "mbfraga" Fraga <mbfraga@gmail.com>
*/

public class Akira.Utils.Snapping : Object {
    private const string STROKE_COLOR = "#ff0000";
    private const double LINE_WIDTH = 0.5;
    private const double DOT_RADIUS = 2.0;

    // Metadata used in the cosmetic aspects of snap lines and dots
    public class SnapMeta {
        public void add_polarity(int to_add) {
            polarity += to_add;
        }
        public Gee.HashSet<int> normals;
        public int polarity;
    }

    // Grid snaps found for a given selection and set of candidates
    public struct SnapGrid {
        public Gee.HashMap<int, SnapMeta> v_snaps;
        public Gee.HashMap<int, SnapMeta> h_snaps;
    }

    // Type of match that was found for a snap
    public enum MatchType {
        NONE=-1,    //< No match was found
        FUZZY,      //< A match was found, but requires an offset
        EXACT,      //< An exact match was found, no offset is necessary
    }

    // Information used to define a match for a given selection.
    // An instance of this class corresponds to a single direction (vertical or horizontal).
    public struct SnapMatch {
        // Returns true if a match was found
        public bool snap_found () {
            return type != MatchType.NONE;
        }

        // Returns the offset necessary to bring the reference position to the selected items
        public int snap_offset () {
            if (snap_found ()) {
                return snap_position + polarity_offset - reference_position;
            }
            return 0;
        }

        public MatchType type;
        public int snap_position; //< Position of matched snap
        public int polarity_offset; //< Offset incurred by polarity properties. For now it is always zero
        public int reference_position; //< Position relative to the selection used as a reference
        public Gee.HashMap<int, int> exact_matches; //< map of exact matches and their polarities
    }

    // Couple of MatchData used for convenience
    public struct SnapMatchData {
        public bool snap_found () {
            return h_data.snap_found () || v_data.snap_found ();
        }

        SnapMatch h_data;
        SnapMatch v_data;
    }

    public static SnapGrid snap_grid_from_canvas (
        Goo.Canvas canvas,
        List<Lib.Items.CanvasItem> selection,
        int sensitivity
    ) {
        List<weak Goo.CanvasItem> vertical_candidates = null;
        List<weak Goo.CanvasItem> horizontal_candidates = null;

        Goo.CanvasBounds vertical_filter = {0, 0, 0, 0};
        Goo.CanvasBounds horizontal_filter = {0, 0, 0, 0};

        foreach (var item in selection) {
          horizontal_filter.x1 = item.bounds.x1 - sensitivity;
          horizontal_filter.x2 = item.bounds.x2 + sensitivity;
          horizontal_filter.y1 = canvas.y1;
          horizontal_filter.y2 = canvas.y2;

          vertical_filter.x1 = canvas.x1;
          vertical_filter.x2 = canvas.x2;
          vertical_filter.y1 = item.bounds.y1 - sensitivity;
          vertical_filter.y2 = item.bounds.y2 + sensitivity;

          vertical_candidates.concat (canvas.get_items_in_area (vertical_filter, true, true, false));
          horizontal_candidates.concat (canvas.get_items_in_area (horizontal_filter, true, true, false));
        }

        return snap_grid_from_candidates(vertical_candidates, horizontal_candidates, selection, sensitivity);
    }

    public static SnapMatchData generate_snap_matches (
        SnapGrid grid,
        List<Lib.Items.CanvasItem> selection,
        int sensitivity
    ) {
        var matches = defaultMatchData();

        var v_sel_snaps = new Gee.HashMap<int, SnapMeta> ();
        var h_sel_snaps = new Gee.HashMap<int, SnapMeta> ();

        foreach (var item in selection) {
            populate_horizontal_snaps (item, ref h_sel_snaps);
            populate_vertical_snaps (item, ref v_sel_snaps);
        }

        populate_snap_matches_from_list(h_sel_snaps, grid.h_snaps, ref matches.h_data, sensitivity);
        populate_snap_matches_from_list(v_sel_snaps, grid.v_snaps, ref matches.v_data, sensitivity);

        return matches;
    }

    private static void populate_snap_matches_from_list(
        Gee.HashMap<int, SnapMeta> target_snap_list,
        Gee.HashMap<int, SnapMeta> grid_snap_list,
        ref SnapMatch matches,
        int sensitivity
    ) {
        int diff = 0;
        int polarity_offset = 0;
        var tmpdiff = sensitivity;
        foreach (var target_snap in target_snap_list) {
            foreach (var cand in grid_snap_list) {
                polarity_offset = 0;

                diff = (int)(cand.key - target_snap.key);
                diff = diff.abs ();

                if (diff < sensitivity) {
                    if ((int)(cand.key + polarity_offset - target_snap.key) == 0) {
                        matches.type = MatchType.EXACT;
                        matches.snap_position = cand.key;
                        matches.reference_position = target_snap.key;
                        matches.polarity_offset = polarity_offset;
                        matches.exact_matches[cand.key] = polarity_offset;
                        tmpdiff = diff;
                    }
                    else if (diff < tmpdiff) {
                        matches.type = MatchType.FUZZY;
                        matches.snap_position = cand.key;
                        matches.reference_position = target_snap.key;
                        matches.polarity_offset = polarity_offset;
                        tmpdiff = diff;
                    }
                }
                tmpdiff = diff;
            }
        }

    }


    private static SnapGrid snap_grid_from_candidates (
    List<weak Goo.CanvasItem> v_candidates,
    List<weak Goo.CanvasItem> h_candidates,
    List<Lib.Items.CanvasItem> selection,
    int sensitivity
    ) {
        var grid = SnapGrid();
        grid.v_snaps = new Gee.HashMap<int, SnapMeta>();
        grid.h_snaps = new Gee.HashMap<int, SnapMeta>();

        foreach (var cand in v_candidates) {
          var candidate_item = cand as Lib.Items.CanvasItem;
          if (candidate_item != null && selection.find (candidate_item) == null) {
            populate_vertical_snaps (candidate_item, ref grid.v_snaps);
          }
        }

        foreach (var cand in h_candidates) {
          var candidate_item = cand as Lib.Items.CanvasItem;
          if (candidate_item != null && selection.find (candidate_item) == null) {
            populate_horizontal_snaps (candidate_item, ref grid.h_snaps);
          }
        }

        return grid;
    }

    private static void populate_horizontal_snaps (Lib.Items.CanvasItem item, ref Gee.HashMap<int, SnapMeta> map) {
        int x_1 = (int)item.bounds.x1;
        int x_2 = (int)item.bounds.x2;
        int y_1 = (int)item.bounds.y1;
        int y_2 = (int)item.bounds.y2;
        int center_x = (int)((item.bounds.x2 - item.bounds.x1) / 2.0 + item.bounds.x1);
        int center_y = (int)((item.bounds.y2 - item.bounds.y1) / 2.0 + item.bounds.y1);

        add_to_map (x_1, y_1, y_2, center_y, -1, ref map);
        add_to_map (x_2, y_1, y_2, center_y, 1, ref map);
        add_to_map (center_x, center_y, center_y, center_y, 0, ref map);
    }

    private static void populate_vertical_snaps (Lib.Items.CanvasItem item, ref Gee.HashMap<int, SnapMeta> map) {
        int x_1 = (int)item.bounds.x1;
        int x_2 = (int)item.bounds.x2;
        int y_1 = (int)item.bounds.y1;
        int y_2 = (int)item.bounds.y2;
        int center_x = (int)((item.bounds.x2 - item.bounds.x1) / 2.0 + item.bounds.x1);
        int center_y = (int)((item.bounds.y2 - item.bounds.y1) / 2.0 + item.bounds.y1);

        add_to_map (y_1, x_1, x_2, center_x, -1, ref map);
        add_to_map (y_2, x_1, x_2, center_x, 1, ref map);
        add_to_map (center_y, center_x, center_x, center_x, 0, ref map);
    }

    private static void add_to_map (
        int pos,
        int n1,
        int n2,
        int n3,
        int polarity,
        ref Gee.HashMap<int, Utils.Snapping.SnapMeta> map
    ) {
        if (map.has_key (pos)) {
            SnapMeta k = map.get (pos);
            k.normals.add (n1);
            k.normals.add (n2);
            k.normals.add (n3);
            k.polarity += polarity;
        }
        else {
            var v = new SnapMeta ();
            v.normals = new Gee.HashSet<int> ();
            v.normals.add (n1);
            v.normals.add (n2);
            v.normals.add (n3);
            v.polarity = polarity;
            map.set (pos, v);
        }
    }

    private static SnapMatchData defaultMatchData() {
        var matches = SnapMatchData();
        matches.v_data.type = MatchType.NONE;
        matches.v_data.snap_position = 0;
        matches.v_data.polarity_offset = 0;
        matches.v_data.reference_position = 0;
        matches.v_data.exact_matches = new Gee.HashMap<int, int> ();

        matches.h_data.type = MatchType.NONE;
        matches.h_data.snap_position = 0;
        matches.h_data.polarity_offset = 0;
        matches.h_data.reference_position = 0;
        matches.h_data.exact_matches = new Gee.HashMap<int, int> ();
        return matches;
    }

}
