#!/usr/bin/env python3
import sys
import re
import os

def fix_dbug_indent(filepath):
    with open(filepath, 'r') as f:
        lines = f.readlines()
    
    modified = False
    i = 0
    
    while i < len(lines):
        line = lines[i]
        
        # 找到 DBUG_PRINT 行
        if re.match(r'^\s*DBUG_PRINT\s*\(', line):
            # 获取当前 DBUG_PRINT 的缩进
            current_indent = re.match(r'^\s*', line).group()
            current_len = len(current_indent)
            
            # 向上查找最近的花括号控制语句（if, else, for, while 等）
            target_indent = None
            for j in range(i-1, -1, -1):
                prev = lines[j]
                # 跳过空行和注释
                if not prev.strip() or prev.strip().startswith('//'):
                    continue
                
                # 查找 if, else if, else, for, while 等
                if re.search(r'\b(if|else|for|while)\s*\(', prev):
                    # 提取该语句的缩进
                    stmt_indent = re.match(r'^\s*', prev).group()
                    # DBUG_PRINT 应该比该语句多一级缩进（2空格）
                    target_indent = stmt_indent + '  '
                    break
                
                # 如果遇到花括号，说明到了代码块边界
                if '{' in prev and not re.search(r'DBUG_PRINT', prev):
                    # 使用花括号所在行的缩进 + 2空格
                    brace_indent = re.match(r'^\s*', prev).group()
                    target_indent = brace_indent + '  '
                    break
            
            # 如果找到了目标缩进，且与当前不同
            if target_indent and target_indent != current_indent:
                lines[i] = target_indent + line.lstrip()
                modified = True
                print(f"  {filepath}:{i+1} 缩进已修正: '{current_indent}' -> '{target_indent}'")
        
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
            if fix_dbug_indent(filepath):
                print(f"✓ 已处理: {filepath}")
