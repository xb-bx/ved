package ved
import "core:strings"
import "core:slice"
import "core:unicode/utf8"
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
search_in_buf :: proc(search: ^SearchBuffer, buf: ^Buffer) {
    clear(&search.search_results)
    if strings.builder_len(buf.data^) == 0 { return }
    //rawbuffer := slice.bytes_from_ptr(rawptr(&buf.data[0]), len(buf.data) * size_of(rune))
    pattern_str := strings.to_string(search.search_pattern)
    if len(pattern_str) == 0 { return }
    i := 0
    for i < strings.builder_len(buf.data^) - strings.builder_len(search.search_pattern) {
        if strings.has_prefix(buf_slice_to_string(buf, i), pattern_str) {
            append(&search.search_results, SearchResult {start = i, end = i + len(pattern_str)})
            i += len(pattern_str)
        } else {
            i += 1
        }
    }
}
