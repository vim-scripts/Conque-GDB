import re
import os

# Marks that a breakpoint has been hit
GDB_BREAK_MARK_SOLE = 0x2192

# Marks end of breakpoint output from gdb
GDB_BREAK_END_REGEX = re.compile('^\(gdb\)\s*')

class ConqueSoleGdb(ConqueSole):
    """
    Windows specific implementation of the ConqueSole class needed by the Conque GDB terminal.
    """

    # File name and line number of next break point
    breakpoint = None
    
    # Indicates whether a breakpoint is currently being constructed
    is_building_bp = False

    # Specifies whether we have lost a break point, and we must wait for it to appear again
    # -1 if we are not waiting, otherwise contains the line number of the break point we wait for
    waiting_for_bp = -1

    # Line number of the most recent breakpoint hit
    last_bp_line = -1

    # Line number of the current breakpoint being processed
    curr_bp_line = -1 

    def is_breakpoint(self, text):
        return ord(text[0]) == GDB_BREAK_MARK_SOLE and ord(text[1]) == GDB_BREAK_MARK_SOLE

    def append_breakpoint(self, text):
        """
        Append text to the break point being created currently or finalize the breakpoint
        """

        if GDB_BREAK_END_REGEX.match(text):
            self.finalize_breakpoint()
        else:
            self.breakpoint += text
            text = ' ' * len(text)
        return text

    def start_breakpoint(self, text, line):
        """
        Indicate a new breakpoint is being processed
        """

        self.is_building_bp = True
        self.curr_bp_line = line
        self.breakpoint = text[2:]
        return ' ' * len(text)

    def finalize_breakpoint(self):
        """
        Extract file name and line number from a gdb break point.
        And send it to the conque gdb vim script.
        """

        self.is_building_bp = False
        if (self.curr_bp_line > self.last_bp_line and not self.waiting_for_bp != -1) or \
                self.curr_bp_line == self.waiting_for_bp:
            self.last_bp_line = self.curr_bp_line
            self.waiting_for_bp = -1
            sp = self.breakpoint.rsplit(':', 4)
            if os.path.isfile(sp[0]):
                vim.command("call conque_gdb#breakpoint('%s','%s')" % (sp[0], sp[1]))
            else:
                self.waiting_for_bp = self.curr_bp_line

    def plain_text(self, line_nr, text, attributes, stats):
        """
        Append plain text to a gdb break point or the vim buffer.
        """

        if self.is_breakpoint(text):
            text = self.start_breakpoint(text, line_nr)
        elif self.is_building_bp:
            text = self.append_breakpoint(text)
        super(ConqueSoleGdb, self).plain_text(line_nr, text, attributes, stats)
