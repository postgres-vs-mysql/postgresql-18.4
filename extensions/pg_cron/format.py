find . -type f \( -name "*.c" -o -name "*.h" \) -exec python3 << 'EOF' {} \;
import sys, re

def fix_file(fname):
    with open(fname, 'r') as f:
        lines = f.readlines()
    
    new_lines = []
    i = 0
    while i < len(lines):
        line = lines[i]
        # 检查是否是 DBUG_PRINT 行
        m = re.match(r'^(\s*)(DBUG_PRINT\s*\(.*)$', line)
        if m:
            old_indent, content = m.groups()
            # 找下一个非空、非DBUG_开头的行
            target_indent = None
            for j in range(i+1, len(lines)):
                nl = lines[j].strip()
                if nl and not nl.startswith('DBUG_'):
                    target_indent = re.match(r'^\s*', lines[j]).group()
                    break
            if target_indent and target_indent != old_indent:
                line = target_indent + content
        new_lines.append(line)
        i += 1
    
    with open(fname, 'w') as f:
        f.writelines(new_lines)

for fname in sys.argv[1:]:
    fix_file(fname)
EOF
