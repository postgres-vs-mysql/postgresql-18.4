# 保存脚本
cat > /tmp/fix_dbug.py << 'EOF'
#!/usr/bin/env python3
import sys, re, os

def get_indent(line):
    m = re.match(r'^\s*', line)
    return m.group() if m else ''

def is_code_line(line):
    s = line.strip()
    if not s or s.startswith('//') or s.startswith('/*') or s.startswith('*') or s.startswith('#'):
        return False
    return True

def is_dbug_line(line):
    return 'DBUG_' in line and not line.strip().startswith('//')

def find_nearest(lines, start, direction):
    step = 1 if direction > 0 else -1
    for i in range(start + step, -1 if direction < 0 else len(lines), step):
        line = lines[i]
        if is_code_line(line) and not is_dbug_line(line):
            s = line.strip()
            if s not in ['{', '}', '};', ');']:
                return get_indent(line)
    return None

def fix_file(fname):
    with open(fname, 'r') as f:
        lines = f.readlines()
    changed = False
    for i, line in enumerate(lines):
        if is_dbug_line(line):
            cur = get_indent(line)
            target = find_nearest(lines, i, 1) or find_nearest(lines, i, -1)
            if target and target != cur:
                lines[i] = target + line.lstrip()
                changed = True
                print(f"  {fname}:{i+1}")
    if changed:
        with open(fname, 'w') as f:
            f.writelines(lines)
    return changed

if __name__ == '__main__':
    files = sys.argv[1:] if len(sys.argv) > 1 else []
    if not files:
        for root, dirs, fnames in os.walk('.'):
            for f in fnames:
                if f.endswith(('.c', '.h', '.cc', '.cpp', '.hpp')):
                    files.append(os.path.join(root, f))
    for f in files:
        if os.path.isfile(f) and fix_file(f):
            print(f"✓ {f}")
EOF

# 运行脚本
python3 /tmp/fix_dbug.py
