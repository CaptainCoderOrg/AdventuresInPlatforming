#!/usr/bin/env python3
"""
TMX Region Shift Script

Moves content within a specified tile range up or down by a given number of tiles.
Works with infinite Tiled maps that use chunk-based CSV encoding.

Usage:
    python tmx_shift.py <tmx_file> <x1> <y1> <x2> <y2> <shift_y_tiles>

Example:
    python tmx_shift.py Tilemaps/dungeon.tmx 184 2 215 17 -3
    (Shifts tiles in region (184,2)-(215,17) up by 3 tiles)

Note: Negative shift_y moves content UP, positive moves it DOWN.
"""

import sys
import re
import shutil
from pathlib import Path


def parse_args():
    if len(sys.argv) != 7:
        print(__doc__)
        sys.exit(1)

    tmx_file = Path(sys.argv[1])
    x1 = int(sys.argv[2])
    y1 = int(sys.argv[3])
    x2 = int(sys.argv[4])
    y2 = int(sys.argv[5])
    shift_y = int(sys.argv[6])

    if not tmx_file.exists():
        print(f"Error: File not found: {tmx_file}")
        sys.exit(1)

    return tmx_file, x1, y1, x2, y2, shift_y


def shift_chunk_data(chunk_match, x1, y1, x2, y2, shift_y, tile_size=16):
    """
    Process a chunk and shift tiles within the specified region.

    For an upward shift (shift_y < 0), we need to:
    1. Read tiles from source rows (y1 to y2)
    2. Write them to destination rows (y1 + shift_y to y2 + shift_y)
    3. Clear the source rows that are now empty
    """
    chunk_x = int(chunk_match.group(1))
    chunk_y = int(chunk_match.group(2))
    chunk_width = int(chunk_match.group(3))
    chunk_height = int(chunk_match.group(4))
    csv_data = chunk_match.group(5)

    # Parse CSV into 2D array
    lines = csv_data.strip().split('\n')
    rows = []
    for line in lines:
        # Handle trailing comma
        cells = line.rstrip(',').split(',')
        rows.append([int(c) if c.strip() else 0 for c in cells])

    # Check if this chunk overlaps with our region
    chunk_x_end = chunk_x + chunk_width
    chunk_y_end = chunk_y + chunk_height

    # No overlap in X
    if chunk_x_end <= x1 or chunk_x > x2:
        return chunk_match.group(0)

    # Determine Y overlap for source and destination
    dest_y1 = y1 + shift_y
    dest_y2 = y2 + shift_y

    # Check if this chunk is involved (either as source or destination)
    source_overlaps = not (chunk_y_end <= y1 or chunk_y > y2)
    dest_overlaps = not (chunk_y_end <= dest_y1 or chunk_y > dest_y2)

    if not source_overlaps and not dest_overlaps:
        return chunk_match.group(0)

    # Create a working copy
    new_rows = [row[:] for row in rows]

    # For upward shift: first collect data, then clear source, then write to dest
    # This handles the case where source and dest overlap

    # Collect tiles to move (from source region)
    tiles_to_move = {}  # (world_x, world_y) -> tile_value

    if source_overlaps:
        for local_y in range(chunk_height):
            world_y = chunk_y + local_y
            if y1 <= world_y <= y2:
                for local_x in range(chunk_width):
                    world_x = chunk_x + local_x
                    if x1 <= world_x <= x2:
                        tile = rows[local_y][local_x]
                        if tile != 0:
                            tiles_to_move[(world_x, world_y)] = tile
                        # Clear source position
                        new_rows[local_y][local_x] = 0

    # Write tiles to destination positions (if they fall in this chunk)
    for (world_x, world_y), tile in tiles_to_move.items():
        dest_world_y = world_y + shift_y
        # Check if destination is in this chunk
        if chunk_y <= dest_world_y < chunk_y_end:
            dest_local_y = dest_world_y - chunk_y
            dest_local_x = world_x - chunk_x
            if 0 <= dest_local_x < chunk_width:
                new_rows[dest_local_y][dest_local_x] = tile

    # Convert back to CSV (last row has no trailing comma)
    csv_lines = []
    for i, row in enumerate(new_rows):
        line = ','.join(str(t) for t in row)
        if i < len(new_rows) - 1:
            line += ','
        csv_lines.append(line)
    new_csv = '\n'.join(csv_lines)

    return f'<chunk x="{chunk_x}" y="{chunk_y}" width="{chunk_width}" height="{chunk_height}">\n{new_csv}\n</chunk>'


def shift_object(obj_match, x1, y1, x2, y2, shift_y, tile_size=16):
    """
    Shift an object if it falls within the pixel region.
    """
    full_match = obj_match.group(0)

    # Extract x and y from the object
    x_match = re.search(r'\bx="([^"]+)"', full_match)
    y_match = re.search(r'\by="([^"]+)"', full_match)

    if not x_match or not y_match:
        return full_match

    obj_x = float(x_match.group(1))
    obj_y = float(y_match.group(1))

    # Convert tile region to pixel region
    px_x1 = x1 * tile_size
    px_x2 = (x2 + 1) * tile_size
    px_y1 = y1 * tile_size
    px_y2 = (y2 + 1) * tile_size

    # Check if object is in the region
    if px_x1 <= obj_x < px_x2 and px_y1 <= obj_y < px_y2:
        # Shift the Y coordinate
        new_y = obj_y + (shift_y * tile_size)
        # Replace the y attribute
        new_match = re.sub(r'\by="[^"]+"', f'y="{new_y}"', full_match)
        return new_match

    return full_match


def process_tmx(content, x1, y1, x2, y2, shift_y, tile_size=16):
    """
    Process the TMX content and apply shifts.
    """
    # We need a two-pass approach for chunks:
    # Pass 1: Collect all tiles that need to move
    # Pass 2: Clear sources and write destinations

    # For simplicity, we'll process chunk by chunk but need to handle
    # cross-chunk movement. Let's build a global tile map for the region.

    # First, extract all chunks and build a tile map for the affected region
    chunk_pattern = re.compile(
        r'<chunk x="(-?\d+)" y="(-?\d+)" width="(\d+)" height="(\d+)">\s*\n?([\s\S]*?)\n?\s*</chunk>',
        re.MULTILINE
    )

    # Find all layer sections (not imagelayer)
    layer_pattern = re.compile(r'(<layer[^>]*>)([\s\S]*?)(</layer>)')

    def process_layer(layer_match):
        layer_start = layer_match.group(1)
        layer_content = layer_match.group(2)
        layer_end = layer_match.group(3)

        # Build global tile map for affected region
        tiles_to_move = {}  # (world_x, world_y) -> tile_value

        # Find all chunks in this layer
        chunks = list(chunk_pattern.finditer(layer_content))

        # Pass 1: Collect tiles to move
        for chunk_match in chunks:
            chunk_x = int(chunk_match.group(1))
            chunk_y = int(chunk_match.group(2))
            chunk_width = int(chunk_match.group(3))
            chunk_height = int(chunk_match.group(4))
            csv_data = chunk_match.group(5)

            # Check X overlap
            if chunk_x + chunk_width <= x1 or chunk_x > x2:
                continue

            # Check Y overlap with source region
            if chunk_y + chunk_height <= y1 or chunk_y > y2:
                continue

            # Parse CSV
            lines = csv_data.strip().split('\n')
            for local_y, line in enumerate(lines):
                world_y = chunk_y + local_y
                if not (y1 <= world_y <= y2):
                    continue

                cells = line.rstrip(',').split(',')
                for local_x, cell in enumerate(cells):
                    world_x = chunk_x + local_x
                    if not (x1 <= world_x <= x2):
                        continue

                    tile = int(cell) if cell.strip() else 0
                    if tile != 0:
                        tiles_to_move[(world_x, world_y)] = tile

        # Pass 2: Process each chunk - clear sources and write destinations
        def replace_chunk(chunk_match):
            chunk_x = int(chunk_match.group(1))
            chunk_y = int(chunk_match.group(2))
            chunk_width = int(chunk_match.group(3))
            chunk_height = int(chunk_match.group(4))
            csv_data = chunk_match.group(5)

            # Check if this chunk is involved at all
            dest_y1 = y1 + shift_y
            dest_y2 = y2 + shift_y

            x_overlaps = not (chunk_x + chunk_width <= x1 or chunk_x > x2)
            source_y_overlaps = not (chunk_y + chunk_height <= y1 or chunk_y > y2)
            dest_y_overlaps = not (chunk_y + chunk_height <= dest_y1 or chunk_y > dest_y2)

            if not x_overlaps or (not source_y_overlaps and not dest_y_overlaps):
                return chunk_match.group(0)

            # Parse CSV into 2D array
            lines = csv_data.strip().split('\n')
            rows = []
            for line in lines:
                cells = line.rstrip(',').split(',')
                rows.append([int(c) if c.strip() else 0 for c in cells])

            # Clear source positions
            if source_y_overlaps:
                for local_y in range(chunk_height):
                    world_y = chunk_y + local_y
                    if not (y1 <= world_y <= y2):
                        continue
                    for local_x in range(chunk_width):
                        world_x = chunk_x + local_x
                        if x1 <= world_x <= x2:
                            rows[local_y][local_x] = 0

            # Write destination positions
            if dest_y_overlaps:
                for (world_x, world_y), tile in tiles_to_move.items():
                    dest_world_y = world_y + shift_y
                    # Check if destination is in this chunk
                    if chunk_x <= world_x < chunk_x + chunk_width:
                        if chunk_y <= dest_world_y < chunk_y + chunk_height:
                            dest_local_x = world_x - chunk_x
                            dest_local_y = dest_world_y - chunk_y
                            rows[dest_local_y][dest_local_x] = tile

            # Convert back to CSV (last row has no trailing comma)
            csv_lines = []
            for i, row in enumerate(rows):
                line = ','.join(str(t) for t in row)
                if i < len(rows) - 1:
                    line += ','
                csv_lines.append(line)
            new_csv = '\n'.join(csv_lines)

            return f'<chunk x="{chunk_x}" y="{chunk_y}" width="{chunk_width}" height="{chunk_height}">\n{new_csv}\n</chunk>'

        new_content = chunk_pattern.sub(replace_chunk, layer_content)
        return layer_start + new_content + layer_end

    # Process all tile layers
    content = layer_pattern.sub(process_layer, content)

    # Process object groups (but not imagelayer)
    objectgroup_pattern = re.compile(r'(<objectgroup[^>]*>)([\s\S]*?)(</objectgroup>)')

    def process_objectgroup(og_match):
        og_start = og_match.group(1)
        og_content = og_match.group(2)
        og_end = og_match.group(3)

        # Find and shift objects
        object_pattern = re.compile(r'<object\s[^>]*>')

        def replace_object(obj_match):
            return shift_object(obj_match, x1, y1, x2, y2, shift_y, tile_size)

        new_content = object_pattern.sub(replace_object, og_content)
        return og_start + new_content + og_end

    content = objectgroup_pattern.sub(process_objectgroup, content)

    return content


def main():
    tmx_file, x1, y1, x2, y2, shift_y = parse_args()

    print(f"TMX Region Shift")
    print(f"  File: {tmx_file}")
    print(f"  Region: ({x1}, {y1}) to ({x2}, {y2})")
    print(f"  Shift Y: {shift_y} tiles ({shift_y * 16} pixels)")
    print()

    # Create backup
    backup_file = tmx_file.with_suffix(tmx_file.suffix + '.bak')
    shutil.copy2(tmx_file, backup_file)
    print(f"  Backup created: {backup_file}")

    # Read content
    content = tmx_file.read_text(encoding='utf-8')

    # Process
    new_content = process_tmx(content, x1, y1, x2, y2, shift_y)

    # Write back
    tmx_file.write_text(new_content, encoding='utf-8')
    print(f"  Modified: {tmx_file}")
    print()
    print("Done! Open the TMX in Tiled to verify, then re-export to Lua.")


if __name__ == '__main__':
    main()
