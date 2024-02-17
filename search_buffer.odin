package ved
import "core:strings"
import "core:slice"
import "core:unicode/utf8"
import "core:text/match"
import "core:fmt"
SearchResult :: struct {
    start: int,
    end:   int,
}
SearchBuffer :: struct {
    position:       int,
    search_pattern: strings.Builder,
    search_results: [dynamic]SearchResult,
}
has_prefix :: proc(buf: []rune, prefix: []rune) -> bool {
    if len(prefix) > len(buf) {
        return false
    }
    return slice.equal(buf[:len(prefix)], prefix)
}
pos_of_byte_offset :: proc(str: string, pos: int) -> int {
    sum := 0
    for b,i in str {
        if pos == i {
            return sum
        } else {
            sum += utf8.rune_size(b)
        }
    }
    return -1
}
search_in_buf :: proc(search: ^SearchBuffer, buf: ^Buffer) {
    clear(&search.search_results)
    if strings.builder_len(buf.data^) == 0 { return }
    //rawbuffer := slice.bytes_from_ptr(rawptr(&buf.data[0]), len(buf.data) * size_of(rune))
    pattern_str := strings.to_string(search.search_pattern)
    if len(pattern_str) == 0 { return }
    matcher := match.matcher_init(buf_as_string(buf), pattern_str)
    ok := true
    haystack_ptr := raw_data(matcher.haystack)
    for res, index in match.matcher_match_iter(&matcher) {
        iter_ptr := raw_data(res)
        byte_off := transmute(int)iter_ptr - transmute(int)haystack_ptr
        start := pos_of_byte_offset(buf_as_string(buf), byte_off)
        append(&search.search_results, SearchResult { start = start, end = start + len(res) })
        //matcher.offset += end
    }

    //i := 0
    //for i < strings.builder_len(buf.data^) - strings.builder_len(search.search_pattern) {
        //if strings.has_prefix(buf_slice_to_string(buf, i), pattern_str) {
            //append(&search.search_results, SearchResult {start = i, end = i + len(pattern_str)})
            //i += len(pattern_str)
        //} else {
            //i += 1
        //}
    //}
}
