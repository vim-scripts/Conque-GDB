
" dependency
if !exists('g:plugin_conque_gdb_loaded')
    runtime! plugin/conque_gdb.vim
endif

if exists('g:autoload_conque_gdb_loaded') || g:ConqueGdb_Disable
    finish
endif

let g:autoload_conque_gdb_loaded = 1

" Path to gdb python scripts
let s:SCRIPT_DIR = expand("<sfile>:h") . '/conque_gdb/'

" Conque term terminal object
let s:gdb = {'idx': 1, 'active': 0, 'buffer_number': -1}

" Buffer number of the current source file, opened by gdb
let s:src_buf = -1

" Window number of the current source file, opened by gdb
let s:src_bufwin = -1

" True if the terminal being opened currently is a gdb terminal
let s:is_gdb_startup = 0

" Name of the sign showing up when a break point has been reached
let s:SIGN_POINTER = 'conque_gdb_sign_pointer'

" Sign name of enabled break points
let s:SIGN_ENABLED = 'conque_gdb_break_enabled'

" Sign name of disabled break points
let s:SIGN_DISABLED = 'conque_gdb_break_disabled'

" Start pointer sign from this value
let s:SIGN_POINTER_VAL = 15605

" Current id of the break point pointer sign
let s:sign_pointer_id = s:SIGN_POINTER_VAL

" Name of the file containing the sign which will be removed next
let s:sign_file = ''

" Line number of current sign
let s:sign_line = -1

" List of buffers opened by ConqueGdb
let s:opened_buffers = {}

" OS platform ('unix') or ('win')
let s:platform = ''

" Python version
let s:py = ''

" How to execute gdb
let s:gdb_command = ''

" true if gdb supports python
let g:conque_gdb_gdb_py_support = 0

" Which python object to use for terminal emulating ('ConqueGdb()') for Unix
" and ('ConqueSoleGdb()') for Windows
let s:term_object = ''

" Define the current gdb break point sign
sil exe 'sign define ' . s:SIGN_POINTER . ' linehl=Search'

" Define sign for enabled break points
sil exe 'sign define ' . s:SIGN_ENABLED . ' text=>> texthl=ErrorMsg'

" Define sign for disabled break points
sil exe 'sign define ' . s:SIGN_DISABLED . ' text=>> texthl=WarningMsg'

" How to escape file names before passing them to python.
function! s:escape_to_py_file(fname)
    let l:fname = a:fname
    let l:fname = substitute(l:fname, '\\', '\\\\\\\\', 'g')
    let l:fname = substitute(l:fname, '"', '\\"', 'g')
    return l:fname
endfunction

" Heuristic attempt to escape file names before opening them for edit/view
function! s:escape_to_shell_file(fname)
    if s:platform != 'win'
        let l:fname = substitute(a:fname, '\\', '\\\\', 'g')
        let l:fname = substitute(l:fname, '"', '\\"', 'g')
        let l:fname = substitute(l:fname, '`', '\\`', 'g')
        let l:fname = substitute(l:fname, ' ', '\\ ', 'g')
        let l:fname = substitute(l:fname, '*', '\\*', 'g')
        let l:fname = substitute(l:fname, '#', '\\#', 'g')
        let l:fname = substitute(l:fname, '{', '\\{', 'g')
        let l:fname = substitute(l:fname, '}', '\\}', 'g')
        let l:fname = substitute(l:fname, '[', '\\[', 'g')
        let l:fname = substitute(l:fname, ']', '\\]', 'g')
    else
        let l:fname = a:fname
    endif
    return l:fname
endfunction

" Python substitutes the "'" character with "\n" before calling vim functions.
" Use this function to substitute it back again!
function! s:file_from_python(fname)
    return substitute(a:fname, "\n", "'", 'g')
endfunction

" Place a break point sign indicating there is a gdb break point at
" file a:fname, line number a:lineno.
" a:enabled == 0 if the break point should be marked as disabled.
function! conque_gdb#set_breakpoint_sign(id, fname, lineno, enabled)
    let l:fname = s:file_from_python(a:fname)

    let l:bufname = bufname(l:fname)
    if l:bufname == ""
        return
    endif

    if a:enabled == 'y'
        let l:name = s:SIGN_ENABLED
    else
        let l:name = s:SIGN_DISABLED
    endif
    try
        sil exe 'sign place ' . a:id . ' line=' . a:lineno . ' name=' . l:name . ' buffer=' . bufnr(l:bufname)
    catch
    endtry
endfunction

" Remove the break point sign with id a:id in file a:fname.
function! conque_gdb#remove_breakpoint_sign(id, fname)
    let l:fname = s:file_from_python(a:fname)
    
    let l:bufname = bufname(l:fname)
    if l:bufname == ""
        return
    endif

    try
        sil exe 'sign unplace ' . a:id . ' buffer=' . bufnr(l:bufname)
    catch
    endtry
endfunction

" Place sign indication a break point has been hit and the execution has
" stopped in file a:fname, line number a:lineno.
function! s:set_pointer(id, fname, lineno)
    let l:bufname = bufname(a:fname)
    if l:bufname == ""
        return
    endif
    try
        sil exe 'sign place ' . a:id . ' line=' . a:lineno . ' name=' . s:SIGN_POINTER . ' buffer=' . bufnr(l:bufname)
    catch
        echohl WarningMsg | echomsg 'ConqueGdb: Unable to place sign in source file ' . a:fname | echohl None
    endtry
endfunction

" Remove previous sign that indicated where the execution was stopped.
function! conque_gdb#remove_prev_pointer()
    if s:sign_file != ''
        let l:bufname = bufname(s:sign_file)
        if l:bufname == ""
            return
        endif

        try
            sil exe 'sign unplace ' . s:sign_pointer_id . ' buffer=' . bufnr(l:bufname)
        catch
        endtry

		let s:sign_file = ''
    endif
endfunction

" Set a new sign in file a:fname at line number a:lineno.
" And remove the previous sign
function! conque_gdb#update_pointer(fname, lineno)
    let l:next_pointer_id = s:sign_pointer_id % 2 + s:SIGN_POINTER_VAL
    if a:fname != ''
        call s:set_pointer(l:next_pointer_id, a:fname, a:lineno)
    endif
    call conque_gdb#remove_prev_pointer()
    let s:sign_pointer_id = l:next_pointer_id
    let s:sign_file = a:fname
    let s:sign_line = a:lineno
endfunction

function! s:buf_update()
    if s:platform != 'win'
        if col(".") == col("$")
            call feedkeys("\<Right>")
        else
            call feedkeys("\<Right>\<Left>")
        endif
    endif
endfunction

" Remove a written buffer from the list of buffers ConqueGdb has opened
function! s:src_buf_written()
    try
        sil autocmd! conque_gdb_src_write_augroup BufWritePre <buffer>
        if has_key(s:opened_buffers, bufnr("%"))
            call remove(s:opened_buffers, bufnr("%"))
        endif
    catch
    endtry
endfunction

" Open file a:fname at line number a:lineno.
" a:perm specifies how to open the file 
" read only ('r') or read-write ('w').
function! s:open_file(fname, lineno, perm)
    let l:fbufname = bufname(a:fname)
    if l:fbufname == "" || !bufloaded(bufnr(l:fbufname))
        let l:opened_by_gdb = 1
    else
        let l:opened_by_gdb = 0
    endif

    if bufexists(a:fname)
        let l:method = 'buffer ' . bufnr(bufname(a:fname))
    elseif a:perm == 'w'
        let l:method = 'edit ' . a:fname
    else
        let l:method = 'view ' . a:fname
    endif

    if bufwinnr(s:src_buf) == bufwinnr(s:gdb.buffer_number)
        if !l:opened_by_gdb && bufwinnr(l:fbufname) != -1
            sil exe bufwinnr(l:fbufname) . 'wincmd w'
        else
            sil exe get(g:conque_gdb_src_splits, g:ConqueGdb_SrcSplit, g:conque_gdb_default_split)
        endif
    elseif bufwinnr(s:src_buf) == -1
        sil exe get(g:conque_gdb_src_splits, g:ConqueGdb_SrcSplit, g:conque_gdb_default_split)
    elseif winbufnr(s:src_bufwin) == s:src_buf
        sil exe s:src_bufwin . 'wincmd w'
    else
        sil exe bufwinnr(s:src_buf) . 'wincmd w'
    endif

    sil exe 'noautocmd ' . l:method

    let s:src_buf = bufnr("%")
    let s:src_bufwin = winnr()

    if l:opened_by_gdb
        let s:opened_buffers[s:src_buf] = 1
        augroup conque_gdb_src_write_augroup
        autocmd conque_gdb_src_write_augroup BufWritePre <buffer> call s:src_buf_written()
        augroup END
        if g:conque_gdb_gdb_py_support
            sil exe s:py . ' ' . s:gdb.var . '.place_file_breakpoints("' . s:escape_to_py_file(expand('%:p')) . '")'
        endif
    endif

    " For some reason vim doesn't always detect the file type.
    " So we do it manually here if we have opened the file.
    if l:opened_by_gdb
        sil filetype detect
    else
        sil exe 'set filetype=' . &filetype
    endif
endfunction

" Move the gdb break point sign to file a:fname, line number a:lineno
" The "\n" character is interpreted as "'".
function! conque_gdb#breakpoint(fname, lineno)
    let l:fname_py = s:file_from_python(a:fname)
    let l:lineno = a:lineno

    if filewritable(l:fname_py)
        let l:perm = 'w'
    elseif filereadable(l:fname_py)
        let l:perm = 'r'
    else
        let l:perm = ''
    endif

    let l:fname = s:escape_to_shell_file(l:fname_py)

    if l:perm != ''
        call s:open_file(l:fname, l:lineno, l:perm)

        sil exe 'noautocmd ' . s:src_bufwin . 'wincmd w'
        sil exe ':' . a:lineno
        sil normal! zz

        call conque_gdb#update_pointer(l:fname_py, l:lineno) 
        call s:buf_update()

        sil exe 'noautocmd wincmd p'
    else
        " Gdb should detect that the file can't be opened. This should not happen.
        echohl WarningMsg | echomsg 'ConqueGdb: Unable to open file ' . a:fname | echohl None
        let l:fname = ''
        let l:lineno = 0
    endif
endfunction

" Get command to execute gdb on Unix
function! s:get_unix_gdb()
    if g:ConqueGdb_GdbExe != ''
        let l:gdb_exe = g:ConqueGdb_GdbExe
    else
        let l:gdb_exe = 'gdb'
    endif
    if !executable(l:gdb_exe)
        return ''
    endif

    sil let l:gdb_py_support = system(l:gdb_exe . ' -q -batch -ex "python print(\"PYYES\")"')
    if l:gdb_py_support =~ ".*PYYES\n.*"
        " Gdb has python support
        let g:conque_gdb_gdb_py_support = 1
        return l:gdb_exe . ' -f -x ' . s:SCRIPT_DIR . 'conque_gdb_gdb.py'
    else
        " No python pupport
        let g:conque_gdb_gdb_py_support = 0
        return l:gdb_exe . ' -f'
    endif
endfunction

" Get command to execute gdb on Windows
function! s:get_win_gdb()
    let g:conque_gdb_gdb_py_support = 0

    if g:ConqueGdb_GdbExe != ''
        if executable(g:ConqueGdb_GdbExe)
            return g:ConqueGdb_GdbExe
        else
            return ''
        endif
    endif

    let sys_paths = split($PATH, ';')

    " Try to add path to MinGW gdb.exe
    call add(sys_paths, 'C:\MinGW\bin')
    call reverse(sys_paths)

    " check if gdb.exe is in paths
    for path in sys_paths
        let cand = path . '\gdb.exe'
        if executable(cand)
            return cand . ' -f'
        endif
    endfor

    return ''
endfunction

" Return command to execute gdb
function! s:get_gdb_command()
    if s:platform != 'win'
        return s:get_unix_gdb()
    endif
    return s:get_win_gdb()
endfunction

" Open a new gdb terminal.
" If a gdb terminal is already running then open this and do not open a new one.
function! conque_gdb#open(...)
    let s:src_buf = bufnr("%")
    let l:start_cmds = get(a:000, 1, [])

    if bufloaded(s:gdb.buffer_number) && s:gdb.active
        echohl WarningMsg | echomsg "GDB already running" | echohl None

        if bufwinnr(s:gdb.buffer_number) == -1
            " Open the existing gdb buffer with the start commands
            for c in l:start_cmds
                sil exe c
            endfor 
            sil exe 'buffer ' . s:gdb.buffer_number
        else
            " Move cursor to the visible gdb window
            sil exe bufwinnr(s:gdb.buffer_number) . 'wincmd w'
        endif

        if g:ConqueTerm_InsertOnEnter == 1
            startinsert!
        endif
    else
        " Find out if gdb was found on the system
        if s:gdb_command == ''
            echohl WarningMsg
            echomsg "ConqueGdb: Unable to find gdb executable, see :help ConqueGdb_GdbExe for more information."
            echohl None
            return
        endif

        " Find out which gdb command script gdb should execute on startup.
        sil let l:enable_confirm = system(s:gdb_command . ' -q -batch -ex "show confirm"')
        if l:enable_confirm =~ '.*\s\+[Oo][Nn]\W.*'
            let l:extra = ' -x ' . s:SCRIPT_DIR . 'gdbinit_confirm.gdb '
        else
            let l:extra = ' -x ' . s:SCRIPT_DIR . 'gdbinit_no_confirm.gdb '
        endif

        " Don't let user use the TUI feature. It does not work with ConqueGdb.
        let l:user_args = get(a:000, 0, '')
        if l:user_args =~ '\(.*\s\+\|^\)-\+tui\($\|\s\+.*\)'
            echohl WarningMsg
            echomsg 'ConqueGdb: GDB Text User Interface (--tui) is not supported'
            echohl None
            return
        endif

        let l:gdb_cmd = s:gdb_command . l:extra . l:user_args
        let s:is_gdb_startup = 1
        try
            let s:gdb = conque_term#open(l:gdb_cmd, l:start_cmds, get(a:000, 2, 0), get(a:000, 3, 1), s:term_object)
			sil exe 'file ConqueGDB\#' . s:gdb.idx
        catch
        endtry
        let s:is_gdb_startup = 0
    endif
	let s:src_bufwin = winnr("#")
endfunction

" Send a command to the gdb subprocess.
function! conque_gdb#command(cmd)
    if !(bufloaded(s:gdb.buffer_number) && s:gdb.active)
        echohl WarningMsg | echomsg "GDB is not running" | echohl None
        return
    endif

    if bufwinnr(s:gdb.buffer_number) == -1
        let s:src_buf = bufnr("%")
        let s:src_bufwin = winnr()
        sil exe 'noautocmd ' . get(g:conque_gdb_src_splits, g:ConqueGdb_SrcSplit, g:conque_gdb_default_split)
        sil exe 'noautocmd wincmd w'
        sil exe 'noautocmd buffer ' . s:gdb.buffer_number
        sil exe 'noautocmd wincmd p'
    endif
    
    sil exe 'noautocmd ' . bufwinnr(s:gdb.buffer_number) . 'wincmd w'
    call s:gdb.writeln(a:cmd)
    if s:platform == 'win'
        sleep 50ms
    endif
    call s:gdb.read(50)
	sil exe 'noautocmd wincmd p'
endfunction

" print word under cursor.
" Only supported on Unix where gdb supports the python API.
function! conque_gdb#print_word(cword)
    if a:cword != ''
        call conque_gdb#command("print " . a:cword)
    endif
endfunction

" Set/Clear break point in file a:fullfile, line a:line
" Note that this is only supported on Unix where gdb has support for the
" python API.
function! conque_gdb#toggle_breakpoint(fullfile, line)
	let l:command = "clear "
    if bufloaded(s:gdb.buffer_number) || s:gdb.active
        sil exe s:py . ' ' . s:gdb.var . '.vim_toggle_breakpoint("' . s:escape_to_py_file(a:fullfile) .'","'. a:line .'")'
    endif
    call conque_gdb#command(l:command . a:fullfile . ':' . a:line)
endfunction

" Restore state of script to indicate gdb has terminated
function! s:restore()
    try
        autocmd! conque_gdb_augroup
        call conque_gdb#remove_prev_pointer()
        if g:conque_gdb_gdb_py_support
            sil exe s:py . ' ' . s:gdb.var . '.remove_all_signs()'
        endif
    catch
    endtry
    let s:src_buf = -1
    let s:src_bufwin = -1
    let s:sign_file = ''
    let s:sign_line = -1
endfunction

" Delete buffers opened by ConqueGdb
function! conque_gdb#delete_opened_buffers()
    for buf in keys(s:opened_buffers)
        try
            sil exe 'bdelete ' . buf
        catch
        endtry
    endfor
    let s:opened_buffers = {}
endfunction

" Called on BufWinEnter to find out when the user opens a new buffer in the
" source window. Use this window for source code when break points are hit.
function! s:buf_win_enter()
    if winnr() == s:src_bufwin
        if bufwinnr(s:src_buf) != -1
            let s:src_bufwin = bufwinnr(s:src_buf)
        else
            let s:src_buf = bufnr("%")
        endif
    endif
endfunction

" Called on BufReadPost.
" Place sign indicating where there are break points in the newly opened file
" if necessary. Maybe the sign indicating where the execution has stopped
" should be placed in this file also.
function! s:buf_read_post()
    let l:sign_bufname = bufname(s:sign_file)
    if l:sign_bufname != "" && bufnr(l:sign_bufname) == bufnr("%")
        call conque_gdb#update_pointer(s:sign_file, s:sign_line)
    endif
    if g:conque_gdb_gdb_py_support
        sil exe s:py . ' ' . s:gdb.var . '.place_file_breakpoints("' . s:escape_to_py_file(expand('%:p')) . '")'
    endif
endfunction

" Called after new conque terminals start up
function! conque_gdb#after_startup(term)
    if s:is_gdb_startup
        " The gdb terminal has started up
        augroup conque_gdb_augroup
        autocmd!
        autocmd conque_gdb_augroup BufUnload <buffer> call s:restore()
        autocmd conque_gdb_augroup BufWinEnter * call s:buf_win_enter()
        autocmd conque_gdb_augroup BufReadPost * call s:buf_read_post()
        augroup END
    endif
endfunction

" Called when the programs inside conque terminals terminate
function! conque_gdb#after_close(term)
    if a:term.idx == s:gdb.idx
        call s:restore()
    endif
endfunction

" Function to load the python files and setup the script.
" This must be done before calling any other function in this script.
function! conque_gdb#load_python()
    if conque_term#dependency_check(0)
        let s:py = conque_term#get_py()
        if has('unix')
            let s:platform = 'unix'
            let s:term_object = 'ConqueGdb()'
            exe s:py . "file " . s:SCRIPT_DIR . "conque_gdb.py"
        else
            let s:platform = 'win'
            let s:term_object = 'ConqueSoleGdb()'
            exe s:py . "file " . s:SCRIPT_DIR . "conque_sole_gdb.py"
        endif
    endif
    let s:gdb_command = s:get_gdb_command()
endfunction

call conque_term#register_function('after_startup', 'conque_gdb#after_startup')
call conque_term#register_function('after_close', 'conque_gdb#after_close')
