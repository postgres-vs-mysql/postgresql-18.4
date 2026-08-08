#!/usr/bin/env python3
import sys
import re
import os

def fix_dbug_alignment(filepath):
    with open(filepath, 'r') as f:
        lines = f.readlines()
    
    modified = False
    i = 0
    
    while i < len(lines):
        line = lines[i]
        
        # 找到 DBUG_PRINT 行
        if re.match(r'^\s*DBUG_PRINT\s*\(', line):
            current_indent = re.match(r'^\s*', line).group()
            
            # 向下查找同级的语句（如 return, break, continue 等）
            target_indent = None
            for j in range(i + 1, min(i + 5, len(lines))):
                next_line = lines[j].strip()
                if not next_line:
                    continue
                # 找到同级的 return/break/continue/赋值语句
                if re.match(r'(return|break|continue|[_a-zA-Z][_a-zA-Z0-9]*\s*=)', next_line):
                    target_indent = re.match(r'^\s*', lines[j]).group()
                    break
            
            # 如果向下没找到，向上查找
            if target_indent is None:
                for j in range(i - 1, max(i - 5, -1), -1):
                    prev_line = lines[j].strip()
                    if not prev_line:
                        continue
                    if re.match(r'(return|break|continue|[_a-zA-Z][_a-zA-Z0-9]*\s*=)', prev_line):
                        target_indent = re.match(r'^\s*', lines[j]).group()
                        break
            
            # 如果找到目标缩进，且与当前不同
            if target_indent and target_indent != current_indent:
                lines[i] = target_indent + line.lstrip()
                modified = True
                print(f"  {filepath}:{i+1} 缩进已对齐: '{current_indent}' -> '{target_indent}'")
        
        i += 1
    
    if modified:
        with open(filepath, 'w') as f:
            f.writelines(lines)
        return True
    return False

# 处理所有文件
for root, dirs, files in os.walk('.'):
    for file in files:
        if file.endswith(('.c', '.h')):
            filepath = os.path.join(root, file)
            if fix_dbug_alignment(filepath):
                print(f"✓ 已处理: {filepath}")
