
" Option to specify whether to enable ConqueGdb
if !exists('g:ConqueGdb_Disable')
    let g:ConqueGdb_Disable = 0
endif

if exists('g:plugin_conque_gdb_loaded') || g:ConqueGdb_Disable
    finish
endif
let g:plugin_conque_gdb_loaded = 1

" Options how to split GDB window when opening new source file
let g:conque_gdb_src_splits = {'below': 'belowright split', 'above': 'aboveleft split', 'right': 'belowright vsplit', 'left': 'leftabove vsplit'}

let g:conque_gdb_default_split = g:conque_gdb_src_splits['above']

if !exists('g:ConqueGdb_SrcSplit')
    let g:ConqueGdb_SrcSplit = 'above'
elseif !has_key(g:conque_gdb_src_splits, g:ConqueGdb_SrcSplit)
    let g:ConqueGdb_SrcSplit = 'above'
    echohl WarningMsg
    echomsg "ConqueGdb: Warning the g:ConqueGdb_SrcSplit option is invalid"
    echomsg "           valid options are: 'below', 'above', 'right' or 'left'"
    echomsg ""
    echohl None
endif

" Option to define path to gdb executable
if !exists('g:ConqueGdb_GdbExe')
    let g:ConqueGdb_GdbExe = ''
endif

" Option to choose leader key to execute gdb commands.
if !exists('g:ConqueGdb_Leader')
    let g:ConqueGdb_Leader = '<Leader>'
endif

" Load python scripts now
call conque_gdb#load_python()

" Keyboard mappings
if g:conque_gdb_gdb_py_support
    if !exists('g:ConqueGdb_ToggleBreak')
        let g:ConqueGdb_ToggleBreak = g:ConqueGdb_Leader . 'b'
    endif
else
    if !exists('g:ConqueGdb_SetBreak')
        let g:ConqueGdb_SetBreak = g:ConqueGdb_Leader . 'b'
    endif
    if !exists('g:ConqueGdb_DeleteBreak')
        let g:ConqueGdb_DeleteBreak = g:ConqueGdb_Leader . 'd'
    endif
endif
if !exists('g:ConqueGdb_Continue')
    let g:ConqueGdb_Continue = g:ConqueGdb_Leader . 'c'
endif
if !exists('g:ConqueGdb_Run')
    let g:ConqueGdb_Run = g:ConqueGdb_Leader . 'r'
endif
if !exists('g:ConqueGdb_Next')
    let g:ConqueGdb_Next = g:ConqueGdb_Leader . 'n'
endif
if !exists('g:ConqueGdb_Step')
    let g:ConqueGdb_Step = g:ConqueGdb_Leader . 's'
endif
if !exists('g:ConqueGdb_Print')
    let g:ConqueGdb_Print = g:ConqueGdb_Leader . 'p'
endif
if !exists('g:ConqueGdb_Finish')
    let g:ConqueGdb_Finish = g:ConqueGdb_Leader . 'f'
endif
if !exists('g:ConqueGdb_Backtrace')
    let g:ConqueGdb_Backtrace = g:ConqueGdb_Leader . 't'
endif

" Commands to open conque gdb
command! -nargs=* -complete=file ConqueGdb call conque_gdb#open(<q-args>, [
        \ get(g:conque_gdb_src_splits, g:ConqueGdb_SrcSplit, g:conque_gdb_default_split),
        \ 'buffer ' . bufnr("%"),
        \ 'wincmd w'])
command! -nargs=* -complete=file ConqueGdbSplit call conque_gdb#open(<q-args>, [
        \ 'rightbelow split'])
command! -nargs=* -complete=file ConqueGdbVSplit call conque_gdb#open(<q-args>, [
        \ 'rightbelow vsplit'])
command! -nargs=* -complete=file ConqueGdbTab call conque_gdb#open(<q-args>, [
        \ 'tabnew',
        \ get(g:conque_gdb_src_splits, g:ConqueGdb_SrcSplit, g:conque_gdb_default_split),
        \ 'buffer ' . bufnr("%"),
        \ 'wincmd w'])

" Command to delete the buffers ConqueGdb has opened
command! -nargs=0 ConqueGdbBDelete call conque_gdb#delete_opened_buffers()

" Command to write a command to the gdb tertminal
command! -nargs=* ConqueGdbCommand call conque_gdb#command(<q-args>)

if g:conque_gdb_gdb_py_support
    exe 'nnoremap <silent> ' . g:ConqueGdb_ToggleBreak . ' :call conque_gdb#toggle_breakpoint(expand("%:p"), line("."))<CR>'
else
    exe 'nnoremap <silent> ' . g:ConqueGdb_SetBreak . ' :call conque_gdb#command("break " . expand("%:p") . ":" . line("."))<CR>'
    exe 'nnoremap <silent> ' . g:ConqueGdb_DeleteBreak . ' :call conque_gdb#command("clear " . expand("%:p") . ":" . line("."))<CR>'
endif
exe 'nnoremap <silent> ' . g:ConqueGdb_Continue . ' :call conque_gdb#command("continue")<CR>'
exe 'nnoremap <silent> ' . g:ConqueGdb_Run . ' :call conque_gdb#command("run")<CR>'
exe 'nnoremap <silent> ' . g:ConqueGdb_Next . ' :call conque_gdb#command("next")<CR>'
exe 'nnoremap <silent> ' . g:ConqueGdb_Step . ' :call conque_gdb#command("step")<CR>'
exe 'nnoremap <silent> ' . g:ConqueGdb_Finish . ' :call conque_gdb#command("finish")<CR>'
exe 'nnoremap <silent> ' . g:ConqueGdb_Backtrace . ' :call conque_gdb#command("backtrace")<CR>'
exe 'nnoremap <silent> ' . g:ConqueGdb_Print . ' :call conque_gdb#print_word(expand("<cword>"))<CR>'
