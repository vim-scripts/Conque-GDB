import re, collections

# Marks that a breakpoint has been hit
GDB_BREAK_MARK = '\x1a\x1a'

# Marks that a program opened by gdb has terminated
GDB_EXIT_MARK = '\x1a\x19'

# Marks a prompt has started and stopped
GDB_PROMPT_MARK = '\x1a\x18'

GDB_BREAK_REGEX = re.compile('.*' + GDB_BREAK_MARK + '.*')

GDB_EXIT_REGEX = re.compile('.*' + GDB_EXIT_MARK + '.*')

GDB_PROMPT_REGEX = re.compile('.*' + GDB_PROMPT_MARK + '.*')

GET_BPS_REGEX = re.compile('(bkpt\s*?\=\s*?\{.*?(?:["].*?["])+?\s*?\]?\s*?\}(?!\s*?,\s*?\{).*?)', re.I)

GET_ATTR_STR = '\s*?\=\s*?["](.*?)["].*?'

ATTR_LINE_REGEX = re.compile('(line' + GET_ATTR_STR + ')', re.I)
ATTR_FILE_REGEX = re.compile('(fullname' + GET_ATTR_STR + ')', re.I)
ATTR_NUM_REGEX = re.compile('(number' + GET_ATTR_STR + ')', re.I)
ATTR_ENABLE_REGEX = re.compile('(enabled' + GET_ATTR_STR + ')', re.I)
ATTR_TYPE_REGEX = re.compile('(type' + GET_ATTR_STR + ')', re.I)

IS_BREAKPOINT_REGEX = re.compile('.*breakpoint.*', re.I)

class RegisteredBreakpoint:
    def __init__(self, fname, line, enable):
        self.filename = fname
        self.lineno = line
        self.enabled = enable

    def __str__(self):
        return self.filename + ':' + self.lineno + ',' + self.enabled

class RegisteredBpDict(collections.MutableMapping):
    def __init__(self):
        self.r_breaks = dict()
        self.lookups = dict()

    def lookup(self, filename, line):
        if filename in self.lookups:
            if line in self.lookups[filename]:
                return self.lookups[filename][line]
        return []

    def get_lookups(self):
        return self.lookups

    def get_equal_breakpoints(self, bp):
        return self.lookups[bp.filename][bp.lineno]

    def get_file_breakpoints(self, filename):
        if filename in self.lookups:
            return self.lookups[filename]
        return dict()

    def __getitem__(self, key):
        return self.r_breaks[self.__keytransform__(key)]

    def __setitem__(self, key, r_bp):
        if r_bp.filename in self.lookups:
            if r_bp.lineno in self.lookups[r_bp.filename]:
                self.lookups[r_bp.filename][r_bp.lineno].append(r_bp)
            else:
                self.lookups[r_bp.filename][r_bp.lineno] = [r_bp]
        else:
            self.lookups[r_bp.filename] = {r_bp.lineno : [r_bp]}
        self.r_breaks[self.__keytransform__(key)] = r_bp

    def __delitem__(self, key):
        del self.r_breaks[self.__keytransform__(key)]

    def __iter__(self):
        return iter(self.r_breaks)

    def __len__(self):
        return len(self.r_breaks)

    def __keytransform__(self, key):
        return key

class ConqueGdb(Conque):
    """
    Unix specific implementation of the Conque class needed by the Conque GDB terminal.
    """
    # File name and linenumber of next break point
    breakpoint = None

    # Indicates whether a program opened by gdb has terminated
    inferior_exit = False

    # Internal string before the gdb prompt
    prompt = None

    # True if we are adding to the prompt string
    is_prompt = False

    # Breakpoints which have been registered to exist
    registered_breakpoints = RegisteredBpDict()

    # Mapping from linenumber + filename to a tuple containing the id of the sign 
    # placed there and whether the breakpoint is enebled ('y') or disabled ('n')
    lookup_sign_ids = dict()

    # Id number of the next sign to place. Start from 15607 FTW!
    next_sign_id = 15607

    def plain_text(self, input):
        """
        Append plain text to a gdb break point or the vim buffer.
        """
        if self.breakpoint != None:
            self.append_breakpoint(input)
        elif GDB_BREAK_REGEX.match(input):
            self.begin_breakpoint()
            self.plain_text(input.split(GDB_BREAK_MARK, 1)[1])
        elif GDB_EXIT_REGEX.match(input):
            self.handle_inferior_exit()
            self.plain_text(input.split(GDB_EXIT_MARK, 1)[1])
        elif GDB_PROMPT_REGEX.match(input):
            sp = input.split(GDB_PROMPT_MARK)
            if sp[0] != '':
                self.plain_text(sp[0])
                self.ctl_nl()
            self.toggle_prompt()
            self.plain_text(sp[1])
        elif self.prompt != None:
            self.append_prompt(input)
        else:
            super(ConqueGdb, self).plain_text(input)

    def ctl_nl(self):
        """
        Append new line to vim buffer or finalize a break point.
        """
        if self.breakpoint != None:
            self.finalize_breakpoint()
        elif self.is_prompt:
            self.is_prompt = False
        elif self.inferior_exit:
            self.finalize_inferior_exit()
        else:
            super(ConqueGdb, self).ctl_nl()

    def toggle_prompt(self):
        self.is_prompt = True
        if (self.prompt == None):
            self.prompt = ''
        else:
            self.finalize_prompt()
            self.prompt = None

    def append_prompt(self, string):
        self.is_prompt = True
        self.prompt += string

    def bp_to_look_key(self, bp):
        return bp.filename + "\n" + bp.lineno

    def look_key_split(self, look_key):
        return look_key.split("\n")

    def look_key_filename(self, look_key):
        return look_key.split("\n")[0]

    def get_bp_attribute(self, bp, regex):
        return regex.findall(bp)[0][1].strip()

    def convert_to_vim_file(self, filename):
        return filename.replace("'", "\n").replace("\\\\", "\\")

    def place_sign(self, breakpoints, line):
        enabled = 'n'
        for bp in breakpoints:
            if bp.enabled == 'y':
                enabled = 'y'
                break

        old = self.lookup_sign_ids.get(line)
        if old:
            vim.command("call conque_gdb#remove_breakpoint_sign('%d','%s')" % (old[0], self.convert_to_vim_file(bp.filename)))
        self.lookup_sign_ids[line] = (self.next_sign_id, enabled)
        bp = breakpoints[0]
        vim.command("call conque_gdb#set_breakpoint_sign('%d','%s','%s','%s')" % (self.next_sign_id, self.convert_to_vim_file(bp.filename), bp.lineno, enabled))
        self.next_sign_id += 1

    def remove_sign(self, id, line):
        fname = self.look_key_filename(line)
        vim.command("call conque_gdb#remove_breakpoint_sign('%d','%s')" % (id, self.convert_to_vim_file(fname)))

    def unplace_sign(self, line):
        id = self.lookup_sign_ids[line][0]
        self.remove_sign(id, line)
        del self.lookup_sign_ids[line]

    def reset_registered_breakpoints(self):
        new_breakpoints = RegisteredBpDict()
        changed_lines = set()
        
        bps = GET_BPS_REGEX.findall(self.prompt.replace('\\"', '\\x1a'))
        for bp in bps:
            try:
                num = self.get_bp_attribute(bp, ATTR_NUM_REGEX)
                enable = self.get_bp_attribute(bp, ATTR_ENABLE_REGEX)
                if num in self.registered_breakpoints.keys():
                    if enable == self.registered_breakpoints[num].enabled:
                        new_breakpoints[num] = self.registered_breakpoints[num]
                        del self.registered_breakpoints[num]
                    else:
                        breakpoint = self.registered_breakpoints[num]
                        del self.registered_breakpoints[num]
                        breakpoint.enabled = enable
                        new_breakpoints[num] = breakpoint
                        changed_lines.add(self.bp_to_look_key(breakpoint))
                else:
                    type = self.get_bp_attribute(bp, ATTR_TYPE_REGEX)
                    if not IS_BREAKPOINT_REGEX.match(type):
                        continue
                    fname = self.get_bp_attribute(bp, ATTR_FILE_REGEX).replace('\\x1a', '"')
                    line = self.get_bp_attribute(bp, ATTR_LINE_REGEX)
                    breakpoint = RegisteredBreakpoint(fname, line, enable)
                    new_breakpoints[num] = breakpoint
                    changed_lines.add(self.bp_to_look_key(breakpoint))
            except:
                pass
        for breakpoint in self.registered_breakpoints.values():
            changed_lines.add(self.bp_to_look_key(breakpoint))

        self.registered_breakpoints = new_breakpoints
        return changed_lines

    def apply_breakpoint_changes(self, changed_lines):
        for line in changed_lines:
            (fname, lineno) = self.look_key_split(line)
            equal_bps = self.registered_breakpoints.lookup(fname, lineno)
            if len(equal_bps) == 0:
                self.unplace_sign(line)
            elif line in self.lookup_sign_ids:
                (old_id, old_enabled) = self.lookup_sign_ids[line]
                self.place_sign(equal_bps, line)
                self.remove_sign(old_id, line)
            else:
                self.place_sign(equal_bps, line)

    def finalize_prompt(self):
        changed_lines = self.reset_registered_breakpoints()
        self.apply_breakpoint_changes(changed_lines)
        
    def place_file_breakpoints(self, filename):
        files_dict = self.registered_breakpoints.get_lookups()
        bp_dict = self.registered_breakpoints.get_file_breakpoints(filename)
        for bps in bp_dict.values():
            self.place_sign(bps, self.bp_to_look_key(bps[0]))

    def remove_all_signs(self):
        files_dict = self.registered_breakpoints.get_lookups()
        for bp_dict in files_dict.values():
            for bps in bp_dict.values():
                self.unplace_sign(self.bp_to_look_key(bps[0]))

    def vim_toggle_breakpoint(self, filename, line):
        bps = self.registered_breakpoints.lookup(filename, line)
        if len(bps) == 0:
            vim.command('let l:command = "break "')

    def begin_breakpoint(self):
        self.breakpoint = ''

    def append_breakpoint(self, string):
        self.breakpoint += string

    def handle_inferior_exit(self):
        """
        Handle termination of process running in gdb.
        """
        self.inferior_exit = True
        # Remove break point sign pointer from vim (if any)
        vim.command('call conque_gdb#remove_prev_pointer()')

    def finalize_breakpoint(self):
        """
        Extract file name and line number from a gdb break point.
        And send it to the conque gdb vim script.
        """
        sp = self.breakpoint.rsplit(':', 4)
        self.breakpoint = None
        vim.command("call conque_gdb#breakpoint('%s','%s')" % (self.convert_to_vim_file(sp[0]), sp[1]))

    def finalize_inferior_exit(self):
        self.inferior_exit = False
