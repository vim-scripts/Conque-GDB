import gdb, os, signal

def exit_handler(event):
    """
    Print '\x1a\x19' to gdb buffer to indicate a process has terminated.
    """
    print('\x1a\x19')

def prompt_hook(prompt):
    print('\x1a\x18')
    gdb.execute('interp mi "-break-list"')
    print('\x1a\x18')

gdb.events.exited.connect(exit_handler)
gdb.prompt_hook = prompt_hook

gdb.execute('source ' + os.path.dirname(os.path.abspath(__file__)) + '/conque_gdb.gdb', False, True)
