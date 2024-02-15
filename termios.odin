package ved
import "core:c"
import "core:sys/linux"
import "core:sys/unix"
import "core:os"
import "base:intrinsics"
foreign import libc "system:c"

c_lflag :: enum {
    ISIG = 0o0000001,   
    ICANON = 0o0000002,
    XCASE = 0o0000004,
    ECHO = 0o0000010,
    ECHOE = 0o0000020,
    ECHOK = 0o0000040,
    ECHONL = 0o0000100,
    NOFLSH = 0o0000200, 
    TOSTOP = 0o0000400, 
    ECHOCTL = 0o0001000,
    ECHOPRT = 0o0002000,
    ECHOKE = 0o0004000, 
    FLUSHO = 0o0010000,
    PENDIN = 0o0040000,
    IEXTEN = 0o0100000,
    EXTPROC = 0o0200000,
}
tcflag_t :: c.uint
speed_t :: c.uint
cc_t :: c.uchar
NCCS :: 32
termios :: struct {
    c_iflag: tcflag_t,
    c_oflag: tcflag_t,
    c_cflag: tcflag_t,
    c_lflag: tcflag_t,
    c_line: cc_t,
    c_cc: [NCCS]cc_t,
    c_ispeed: speed_t,
    c_ospeed: speed_t,
}
TCSANOW :: 	0
TCSADRAIN :: 1
TCSAFLUSH :: 2
sighandler_t :: proc() -> c.int
foreign libc {
    tcgetattr :: proc (fd: c.int, termios: ^termios) -> c.int ---
    tcsetattr :: proc (fd: c.int, optional_actions: c.int, termios: ^termios) -> c.int ---
    signal :: proc(sig: c.int, handler: sighandler_t) -> sighandler_t ---
}
STDIN_FILENO :: 0
winsize :: struct {
    ws_row: c.ushort,
    ws_col: c.ushort,
    ws_xpixel: c.ushort,
    ws_ypixel: c.ushort,
}
size_changed :: proc "c" () -> c.int {
    context = {}
    ved.size = terminal_size()
    return 0;
}
TIOCGWINSZ :: 0x5413
terminal_size :: proc() -> winsize {
    res := winsize{}
    intrinsics.syscall(linux.SYS_ioctl, STDIN_FILENO, TIOCGWINSZ, uintptr(&res))
    return res
}
