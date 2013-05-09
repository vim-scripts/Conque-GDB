set confirm off

set prompt (gdb) 
define set prompt
  echo set prompt is not supported with ConqueGdb when GDB doesn't have python support\n
end

define set annotate
  echo set annotate is not supported by ConqueGdb\n
end

define layout
  echo layout command is not supported by ConqueGdb\n
end

define tui
  echo tui command is not supported by ConqueGdb\n
end

set confirm on
