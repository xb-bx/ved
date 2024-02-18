package ved
import "core:log"
import "core:strings"
import "core:unicode/utf8"
Line :: struct {
    start:      int,
    end:        int,
    rune_start: int,
    rune_end:   int,
    len:        int,
}
Cursor :: struct {
    col: int,
    row: int,
}
Buffer :: struct {
    data:          ^strings.Builder,
    lines:         [dynamic]Line,
    file_name:     string,
    cursor:        Cursor,
    scroll_cursor: Cursor,
    width:         int,
    height:        int,
}
buf_as_string :: proc(buffer: ^Buffer) -> string {
    return strings.to_string(buffer.data^)
}
init_buffer :: proc(data: ^strings.Builder, file_name: string) -> Buffer {
    lines := make([dynamic]Line)
    split_into_lines(data, &lines)
    return Buffer{data = data, lines = lines, file_name = file_name}
}
split_into_lines :: proc(data: ^strings.Builder, lines: ^[dynamic]Line) {
    clear(lines)
    append(lines, Line{})
    line := &lines[0]
    str := strings.to_string(data^)
    runei := 0
    for b, i in str {
        if b == '\n' {
            line.end = i
            line.rune_end = runei + 1
            line.len = line.end - line.start + 1
            append(lines, Line{start = i + 1, rune_start = runei + 1, end = i + 1})
            line = &lines[len(lines) - 1]

        }
        runei += 1
    }
    if len(lines) != 1 {
        unordered_remove(lines, len(lines) - 1)
    }
}
buf_slice_to_string :: proc {
    buf_slice_to_string_from_to,
    buf_slice_to_string_from,
}
buf_slice_to_string_from :: proc(buf: ^Buffer, lo: int) -> string {
    sl := buf.data.buf[lo:]
    return strings.string_from_ptr(&sl[0], len(sl))
}
buf_slice_to_string_from_to :: proc(buf: ^Buffer, lo: int, hi: int) -> string {
    sl := buf.data.buf[lo:hi]
    if len(sl) == 0 do return ""
    return strings.string_from_ptr(&sl[0], len(sl))
}

buf_cursor_col :: proc(buf: ^Buffer, dir: int) {
    line := buf.lines[buf.cursor.row]
    if buf.cursor.col > line.len {
        if dir > 0 {
            return
        } else {
            buf.cursor.col = clamp(line.len - 1 + dir, 0, line.len + 1)
        }
    } else {
        col := clamp(buf.cursor.col + dir, 0, line.len - 1)
        buf.cursor.col = col
        if buf.cursor.col - buf.scroll_cursor.col > buf.width {
            buf.scroll_cursor.col += 1
        } else if buf.cursor.col - buf.scroll_cursor.col < 0 {
            buf.scroll_cursor.col -= 1
        }
    }
}
buf_cursor_row :: proc(buf: ^Buffer, dir: int) {
    row := clamp(buf.cursor.row + dir, 0, len(buf.lines) - 1)
    buf.cursor.row = row
    if buf.cursor.row - buf.scroll_cursor.row >= buf.height {
        buf.scroll_cursor.row += buf.cursor.row - buf.scroll_cursor.row - buf.height + 1
    } else if buf.cursor.row - buf.scroll_cursor.row <= 0 {
        buf.scroll_cursor.row -= buf.scroll_cursor.row - buf.cursor.row
    }
    buf.scroll_cursor.row = clamp(buf.scroll_cursor.row, 0, len(buf.lines))
    line := buf.lines[row]
    if line.len < buf.scroll_cursor.col {
        buf.scroll_cursor.col = (line.len) / 2
        buf.cursor.col = line.end - 1
    }
}
sb_insert_rune :: proc(sb: ^strings.Builder, pos: int, r: rune) {
    bytes, n := utf8.encode_rune(r)
    offset := utf8.rune_offset(strings.to_string(sb^), pos)
    if offset == -1 {
        strings.write_bytes(sb, bytes[:])
    } else {
        inject_at_elems(&sb.buf, offset, ..bytes[:n])
    }
}
sb_remove_at :: proc(sb: ^strings.Builder, pos: int) {
    offset := utf8.rune_offset(strings.to_string(sb^), pos)
    run := utf8.rune_at(strings.to_string(sb^), offset)
    run_size := utf8.rune_size(run)
    remove_range(&sb.buf, offset, offset + run_size)
}
buf_insert :: proc(buf: ^Buffer, r: rune) {
    line := buf.lines[buf.cursor.row]
    buf.cursor.col = clamp(buf.cursor.col, 0, max(0, line.len - 1))
    sb_insert_rune(buf.data, line.start + buf.cursor.col, r)
    split_into_lines(buf.data, &buf.lines)
    buf.cursor.col += 1
}
buf_remove :: proc(buf: ^Buffer) {
    line := buf.lines[buf.cursor.row]
    buf.cursor.col = clamp(buf.cursor.col, 0, line.len - 1)
    if buf.cursor.col == 0 {
        if buf.cursor.row == 0 {
            return
        } else {
            prev_line := buf.lines[buf.cursor.row - 1]
            prev_line_len := prev_line.end - prev_line.start
            sb_remove_at(buf.data, line.start - 1)
            split_into_lines(buf.data, &buf.lines)
            buf_cursor_row(buf, -1)
            buf_cursor_col(buf, prev_line_len)
        }

    } else {
        buf.cursor.col = clamp(buf.cursor.col - 1, 0, line.len - 1)
        sb_remove_at(buf.data, line.start + buf.cursor.col)
        split_into_lines(buf.data, &buf.lines)
    }

}
buf_remove_range :: proc(buf: ^Buffer, lo: int, hi: int) {
    if hi - lo <= 0 {return}
    remove_range(&buf.data.buf, lo, hi)
    split_into_lines(buf.data, &buf.lines)
}
buf_line_as_string :: proc(buf: ^Buffer, line: Line) -> string {
    return buf_slice_to_string_from_to(buf, line.start, line.end)
}
buf_cur_line_string :: proc(buf: ^Buffer) -> string {
    return buf_line_as_string(buf, buf.lines[buf.cursor.row])
}
